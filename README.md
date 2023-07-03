# Dataform Pipeline for Google Analytics 4

This terraform project will deploy the necessary infrastructure on Google Cloud Platform to automize the
Dataform raw data transformation based on the GA4 BigQuery export.
## Features
- Dynamic data transformation with environment variables. Only query the GA4 table updated by Google to avoid querying data more than once
- Custom error alerting / monitoring with e-mail notifications
- Longer log retention for the Dataform pipeline
- Automatic api activaition and creation of service accounts including nessary roles / rights


## Getting Started
1. Create a new service account for terraform with the primitive role "owner" within the desired GCP project 
2. Create and download the JSON key file for the service account and copy it to the directory of this respository
3. Activate the `cloudresourcemanager.googleapis.com` and `serviceusage.googleapis.com` API within Google Cloud Console
4. Clone this repository and make sure you have installed [Terraform](https://developer.hashicorp.com/terraform/tutorials/gcp-get-started/install-cli).
5. Change the variables inside terraform.tfvars.example to suit your needs and rename the file to terraform.tfvars.
This will be used to configure where the infrastructure will be deployed on and where notifications will be sent to. Don't forget to
replaced the name of the GA4 dataset within the ga4_log_filter variable.
6. Run `terraform init` to initialize the repository and `terraform apply` the infrastructure will be built on GCP

## Included Components
Service accounts will be set up with the necessary roles including the dataform standard service account.
Needed API's will be activated automatically as well.

- Log Sink for GA4 BigQuery export
- Log Bucket to save pipeline erros (Standard 180 days)
- Pub/Sub Topic for Log Sink Destination
- Eventarc Trigger based on Pub/Sub topic
- Worklfow to control the Dataform execution
- Dataform repository
