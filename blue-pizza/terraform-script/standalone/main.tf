####################################################################################
# Copyright 2024 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     https://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
####################################################################################


####################################################################################
# Main script used to provision the different asset used in the following demo:
#               Blue Pizza -  The dough was not rising to the occasion 
#
# Author: Damien Contreras cdamien@google.com
####################################################################################

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google-beta"
      version = ">= 4.52, < 6"
    }
  }
}

#get default parameters:
data "google_client_config" "default" {
}

variable "region" {
  type = string
  default = "us-central1"
}

#provider "google" {
#  project = "${data.google_project.project.id}"
#  region  = "us-central1"
#  zone    = "us-central1-c"
#}

#Provisioning

## get Google Cloud project
data "google_project" "project" {}

#wait 7mins
resource "time_sleep" "default" {
  create_duration = "7m"
  depends_on = [google_project_iam_member.bucket]
}

###activate vertex API
resource "google_project_service" "google-cloud-apis" {
  project = data.google_project.project.project_id 
  for_each = toset([
    "aiplatform.googleapis.com",
    "servicenetworking.googleapis.com",
    "compute.googleapis.com",
    "embeddedassistant.googleapis.com"
  ])
  disable_dependent_services = true
  disable_on_destroy         = true
  service                    = each.key
}

## Create bq connection
## This creates a cloud resource connection.
## Note: The cloud resource nested object has only one output only field - serviceAccountId.
resource "google_bigquery_connection" "connection" {
    connection_id = "blue_pizza_connection"
    location = "${var.region}"
    friendly_name = "Blue Pizza connection"
   description   = "Connect to Vertex AI & GCS "
    cloud_resource {}
}

## Create gcs bucket
#https://cloud.google.com/storage/docs/terraform-create-bucket-upload-object
resource "google_storage_bucket" "blue_pizza_bucket" {
 name          = "blue_pizza_${data.google_project.project.number}" 
 location      = "${var.region}"
 storage_class = "STANDARD"
 force_destroy               = true
 uniform_bucket_level_access = true
}

## Create sub folders - visual inspection
resource "google_storage_bucket_object" "visual_inspection_folder" {
  name          = "visual_inspection/"
  content       = "Not really a directory, but it's empty."
  bucket        = "${google_storage_bucket.blue_pizza_bucket.name}"
}
## Create sub folders - oven_sensor
resource "google_storage_bucket_object" "oven_folder" {
  name          = "oven/"
  content       = "Not really a directory, but it's empty."
  bucket        = "${google_storage_bucket.blue_pizza_bucket.name}"
}

##Create sub folders - weather
resource "google_storage_bucket_object" "weather_folder" {
  name          = "weather/"
  content       = "Not really a directory, but it's empty."
  bucket        = "${google_storage_bucket.blue_pizza_bucket.name}"
}

##Create sub folders - claims
resource "google_storage_bucket_object" "claims_folder" {
  name          = "claims/"
  content       = "Not really a directory, but it's empty."
  bucket        = "${google_storage_bucket.blue_pizza_bucket.name}"
}


#Permissions

##permissions
# This grants the previous connection IAM role access to the bucket.
resource "google_project_iam_member" "bucket" {
  role    = "roles/storage.admin"
  project = data.google_project.project.project_id
  member  = "serviceAccount:${google_bigquery_connection.connection.cloud_resource[0].service_account_id}"
  depends_on = [ 
     google_bigquery_connection.connection
     ]
}

## Set permissions on gcs
resource "google_storage_bucket_iam_member" "blue_pizza_perms" {
  bucket = "${google_storage_bucket.blue_pizza_bucket.name}"
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_bigquery_connection.connection.cloud_resource[0].service_account_id}"
  depends_on = [google_storage_bucket.blue_pizza_bucket]
}

## Set permission on Vertex.AI
resource "google_project_iam_binding" "project" {
  project = "${data.google_project.project.id}"
  role    = "roles/aiplatform.user"
  members = [
    "serviceAccount:${google_bigquery_connection.connection.cloud_resource[0].service_account_id}",
  ]
}

## copy files from github

###download from github
resource "null_resource" "get_from_github" {
  provisioner "local-exec" {
    command =  "git clone https://github.com/c-damien/gcp-public-demos"
  }

}

###upload to gcs
resource "null_resource" "upload" {
  provisioner "local-exec" {
    #working_dir = "${path.module}"
    command = <<-EOT
      gsutil cp -r gcp-public-demos/blue-pizza/assets/oven/* gs://blue_pizza_${data.google_project.project.number}/oven
      gsutil cp -r gcp-public-demos/blue-pizza/assets/visual_inspection/* gs://blue_pizza_${data.google_project.project.number}/visual_inspection
      gsutil cp -r gcp-public-demos/blue-pizza/assets/weather/* gs://blue_pizza_${data.google_project.project.number}/weather
      gsutil cp -r gcp-public-demos/blue-pizza/assets/claims/* gs://blue_pizza_${data.google_project.project.number}/claims
      EOT
  }
  depends_on = [
    time_sleep.default, 
    google_storage_bucket_iam_member.blue_pizza_perms,
    google_project_iam_member.bucket,
    null_resource.get_from_github,
    google_storage_bucket_object.visual_inspection_folder,
    google_storage_bucket_object.oven_folder,
    google_storage_bucket_object.claims_folder,
    google_storage_bucket_object.weather_folder
  ]
}

## Create dataset data_beams
resource "google_bigquery_dataset" "blue_pizza" {
  dataset_id                      = "blue_pizza"
  description                     = "Blue pizza Demo"
  default_partition_expiration_ms = 2592000000  # 30 days
  default_table_expiration_ms     = 31536000000 # 365 days
  location                        = "${var.region}"
  max_time_travel_hours           = 96 # 4 days
}

## Create Native table - claims
resource "google_bigquery_table" "claims" {
   dataset_id          = google_bigquery_dataset.blue_pizza.dataset_id
   table_id            = "claims"
   deletion_protection = false
   labels = {
     env = "default"
   }
   depends_on = [null_resource.upload]
 }

##load claim data into native table
resource "null_resource" "load_claim_data" {
  provisioner "local-exec" {
    command =  "bq --location=${var.region} load --autodetect --skip_leading_rows=1 --source_format=CSV ${google_bigquery_dataset.blue_pizza.dataset_id}.claims gs://blue_pizza_${data.google_project.project.number}/claims/claims.csv"
  }
  depends_on = [google_bigquery_table.claims]
}



## Create bigLake table - oven
resource "google_bigquery_table" "oven" {
  dataset_id = google_bigquery_dataset.blue_pizza.dataset_id
  table_id   = "oven"

  external_data_configuration {
    autodetect    = true
    source_format = "NEWLINE_DELIMITED_JSON"
    connection_id = google_bigquery_connection.connection.name
    source_uris   = ["gs://${google_storage_bucket.blue_pizza_bucket.name}/oven/*.json"]
    metadata_cache_mode = "AUTOMATIC"
  }

  # This sets the maximum staleness of the metadata cache to 10 hours.
  max_staleness = "0-0 0 10:0:0"

  deletion_protection = false

  depends_on = [
  time_sleep.default, 
  google_project_iam_member.bucket,
  null_resource.upload
  ]
}


## Create bigLake table - weather
resource "google_bigquery_table" "weather" {
  dataset_id = google_bigquery_dataset.blue_pizza.dataset_id
  table_id   = "weather"

  external_data_configuration {
    autodetect    = true
    source_format = "NEWLINE_DELIMITED_JSON"
    connection_id = google_bigquery_connection.connection.name
    source_uris   = ["gs://${google_storage_bucket.blue_pizza_bucket.name}/weather/*.json"]
    metadata_cache_mode = "AUTOMATIC"
  }

  # This sets the maximum staleness of the metadata cache to 10 hours.
  max_staleness = "0-0 0 10:0:0"

  deletion_protection = false

  depends_on = [
  time_sleep.default, 
  google_project_iam_member.bucket,
  null_resource.upload
  ]
}

## Create biglake object table - visual inspection
resource "google_bigquery_table" "visual_inspection" {
  deletion_protection = false
  table_id            = "visual_inspection"
  dataset_id          = google_bigquery_dataset.blue_pizza.dataset_id
  external_data_configuration {
    connection_id = google_bigquery_connection.connection.name
    autodetect    = true
    object_metadata = "SIMPLE"
    source_uris = [
      "gs://${google_storage_bucket.blue_pizza_bucket.name}/visual_inspection/*.png",
    ]

    metadata_cache_mode = "MANUAL"
  }

  # This ensures that the connection can access the bucket
  # before Terraform creates a table.
  depends_on = [
    google_project_iam_member.bucket,
    null_resource.upload
  ]
}