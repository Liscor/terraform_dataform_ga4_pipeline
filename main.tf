terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "4.70.0"
    }
    google-beta = {
      source = "hashicorp/google-beta"
      version = "4.70.0"
    }
  }
}

provider "google" {
  credentials = file(var.service_account_file)
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  credentials = file(var.service_account_file)
  project = var.project_id
  region  = var.region
}

# Activate the needed apis
resource "google_project_service" "iam_api" {
  service = "iam.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "eventarc_api" {
  service = "eventarc.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "dataform_api" {
  service = "dataform.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "workflows_api" {
  service = "workflows.googleapis.com"
  disable_on_destroy = false
}
resource "google_project_service" "workflowexec_api" {
  service = "workflowexecutions.googleapis.com"
  disable_on_destroy = false
  depends_on = [ google_project_service.workflows_api ]
}
resource "google_project_service" "pub_sub_api" {
  service = "pubsub.googleapis.com"
  disable_on_destroy = false
}

#Alerts
resource "google_project_service" "monitoring_api" {
  service = "monitoring.googleapis.com"
  disable_on_destroy = false
}

#For Log bucket
resource "google_project_service" "logging_api" {
  service = "logging.googleapis.com"
  disable_on_destroy = false
}

# Grants access to the project number and other gcp meta data fields
data "google_project" "project" {
  project_id =  var.project_id
}

# Create dataform repository 
resource "google_dataform_repository" "create_respository" {
  provider = google-beta
  name = var.dataform_respository_name

  depends_on = [ google_project_service.dataform_api ]
  /*git_remote_settings {
      url = google_sourcerepo_repository.git_repository.url
      default_branch = "main"
      authentication_token_secret_version = google_secret_manager_secret_version.secret_version.id
  }
  workspace_compilation_overrides {
    default_database = "database"
    schema_suffix = "_suffix"
    table_prefix = "prefix_"
  }*/
}

# Bind the needed roles to the dataform standard service account
resource "google_project_iam_member" "project" {
  for_each = toset([
    "roles/bigquery.dataEditor", 
    "roles/bigquery.jobUser", 
    "roles/secretmanager.secretAccessor"
    ])
  project = var.project_id
  role = each.value
  member = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-dataform.iam.gserviceaccount.com"
  depends_on = [ google_dataform_repository.create_respository ]
}

# Pub/sub topic for our log sink
resource "google_pubsub_topic" "ga4_export_complete" {
  name    = var.pub_sub_topic_name
  project = var.project_id
  depends_on = [ google_project_service.pub_sub_api ]
}

# Log sink which listens for ga4 raw data imports by google 
resource "google_logging_project_sink" "ga4_raw_data_export" {
  name        = "ga4_raw_data_export"
  destination = "pubsub.googleapis.com/projects/${var.project_id}/topics/${var.pub_sub_topic_name}"
  filter = var.ga4_log_filter
  depends_on = [ google_pubsub_topic.ga4_export_complete, google_project_service.logging_api ]
}

#Grant pub/sub standard service account access to serviceAccountTokenCreator
resource "google_project_iam_binding" "project_binding_pubsub" {
  provider = google-beta
  project  = var.project_id
  role     = "roles/iam.serviceAccountTokenCreator"
  members = ["serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"]
  depends_on = [ google_project_service.pub_sub_api ]
}

# Create a service account for Eventarc trigger and Workflows
resource "google_service_account" "eventarc_workflows_service_account" {
  provider     = google-beta
  account_id   = "eventarc-workflows-sa"
  display_name = "Eventarc Workflows Service Account"
  depends_on = [ google_project_service.iam_api ]
}

# Grant the logWriter role to the service account
resource "google_project_iam_binding" "project_binding_eventarc" {
  provider = google-beta
  project  = data.google_project.project.id
  role     = "roles/logging.logWriter"
  members = ["serviceAccount:${google_service_account.eventarc_workflows_service_account.email}"]
  depends_on = [google_service_account.eventarc_workflows_service_account]
}

# Grant the workflows.invoker role to the service account
resource "google_project_iam_binding" "project_binding_workflows" {
  provider = google-beta
  project  = data.google_project.project.id
  role     = "roles/workflows.invoker"
  members = ["serviceAccount:${google_service_account.eventarc_workflows_service_account.email}"]
  depends_on = [google_service_account.eventarc_workflows_service_account]
}

resource "google_project_iam_binding" "project_binding_dataform" {
  provider = google-beta
  project  = data.google_project.project.id
  role     = "roles/dataform.serviceAgent"
  members = ["serviceAccount:${google_service_account.eventarc_workflows_service_account.email}"]
  depends_on = [google_service_account.eventarc_workflows_service_account]
}

# We create a workflow which will be used to execute dataform 
resource "google_workflows_workflow" "execute_dataform_ga4" {
  name            = "execute_dataform_ga4"
  service_account = google_service_account.eventarc_workflows_service_account.email
  source_contents = templatefile("workflow.tftpl", {project_id = var.project_id, region = var.region, dataform_respository_name = var.dataform_respository_name})
  depends_on = [ google_project_service.workflows_api,
  google_service_account.eventarc_workflows_service_account ]
}

# We create an event arc pub/sub trigger for the dataform workflow
resource "google_eventarc_trigger" "ga4_data_updated" {
  name        = "ga4-data-updated"
  location    = var.region
  matching_criteria {
    attribute = "type"
    value = "google.cloud.pubsub.topic.v1.messagePublished"
  }
  transport {
    pubsub {
      topic = "projects/${var.project_id}/topics/ga4_export_complete"
    }
  }
  destination {
    workflow = "projects/${var.project_id}/locations/${var.region}/workflows/execute_dataform_ga4"
  }
  service_account = google_service_account.eventarc_workflows_service_account.email
  depends_on = [ google_project_service.eventarc_api, google_workflows_workflow.execute_dataform_ga4 ]
}

# Saving errors longer than the standard 30 days
resource "google_logging_project_bucket_config" "dataform_error_bucket" {
    project    = var.project_id
    location  = var.region
    retention_days = var.log_bucket_retention_period
    bucket_id = "dataform_error_bucket"
    depends_on = [ google_project_service.logging_api ]
}

resource "google_logging_project_sink" "dataform_execution_errors" {
  name        = "dataform_execution_errors"
  destination = "logging.googleapis.com/${google_logging_project_bucket_config.dataform_error_bucket.name}"
  filter = var.error_log_filter
  depends_on = [ google_logging_project_bucket_config.dataform_error_bucket ]
}

resource "google_monitoring_notification_channel" "notification_channel" {
  display_name = "${var.notification_user.name}"
  type         = "email"
  labels = {
    email_address = var.notification_user.email
  }
  force_delete = false
  depends_on = [ google_project_service.monitoring_api ]
}
## Create a log alert_policy for workflow and dataform errors
resource "google_monitoring_alert_policy" "alert_policy" {
  display_name = "Dataform/Workflow Errors"
  combiner     = "OR"
  documentation {
    content = <<EOT
    GA4 Dataform / Workflow Errors
    There was an error while running the GA4 Dataform pipeline in gcp-project "${var.project_id}".
    One or more of the following conditions were found:

    - The Workflow failed and did not successfully complete
    - The Dataform repository was not compiled successfully
    - Assertions within the Dataform repository failed 

    Check the logs in ${google_logging_project_bucket_config.dataform_error_bucket.name} for more information.
    EOT
    mime_type = "text/markdown"
  }
  conditions {
    display_name = "Dataform/Workflow Errors"
    condition_matched_log {
      filter =  var.error_log_filter
    }
  }
  alert_strategy {
    notification_rate_limit {
      period = "300s"
    }  
  }
  notification_channels = [google_monitoring_notification_channel.notification_channel.id]
  depends_on = [ google_logging_project_sink.dataform_execution_errors, google_monitoring_notification_channel.notification_channel ]
}