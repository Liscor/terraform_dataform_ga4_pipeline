variable "project_id" {
  description = "The project ID in which the stack is being deployed"
  type        = string
}

variable "service_account_file" {
  description = "The path to the service account file for deployment"
  type        = string
}

variable "region" {
  description = "The name of the region to deploy within"
  type        = string
}

variable "notification_user" {
  description = "The name and e-mail address used in the notification channel setup"
  type        = object({
    name  = string
    email = string
  })
}

variable "pub_sub_topic_name" {
  description = "The name of the pub sub topic for the log sink"
  type = string  
}

variable "dataform_respository_name" {
  description = "The name of the data form repository"
  type = string
}

variable "dataform_workspace_name" {
  description = "The name of the workspace within the Dataform repository to automize"
  type = string
}

variable "ga4_log_filter" {
  description = "The SQL statement to filter the logs for ga4 raw data imports"
  type = string
}
variable "error_log_filter" {
  description = "The SQL statement to filter the logs for"
  type = string
}
variable "log_bucket_retention_period" {
  description = "The retention period of the log files"
  type = number
}