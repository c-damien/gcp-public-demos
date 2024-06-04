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
#               Data beans - from beans to screams 
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

## Create bq connection
## This creates a cloud resource connection.
## Note: The cloud resource nested object has only one output only field - serviceAccountId.
resource "google_bigquery_connection" "connection" {
    connection_id = "data_beans_connection"
    location = "${var.region}"
    friendly_name = "data beans connection"
   description   = "Connect to Vertex AI & GCS "
    cloud_resource {}
}

## Create gcs bucket
#https://cloud.google.com/storage/docs/terraform-create-bucket-upload-object
resource "google_storage_bucket" "data_beans_bucket" {
 name          = "data_beans_${data.google_project.project.number}" 
 location      = "${var.region}"
 storage_class = "STANDARD"
 force_destroy               = true
 uniform_bucket_level_access = true
}

## Create sub folders - visual inspection
resource "google_storage_bucket_object" "visual_inspection_folder" {
  name          = "visual_inspection/"
  content       = "Not really a directory, but it's empty."
  bucket        = "${google_storage_bucket.data_beans_bucket.name}"
}
## Create sub folders - roaster_sensor
resource "google_storage_bucket_object" "roaster_folder" {
  name          = "roaster/"
  content       = "Not really a directory, but it's empty."
  bucket        = "${google_storage_bucket.data_beans_bucket.name}"
}

##Create sub folders - weather
resource "google_storage_bucket_object" "weather_folder" {
  name          = "weather/"
  content       = "Not really a directory, but it's empty."
  bucket        = "${google_storage_bucket.data_beans_bucket.name}"
}


##Create sub folders - claims
resource "google_storage_bucket_object" "claims_folder" {
  name          = "claims/"
  content       = "Not really a directory, but it's empty."
  bucket        = "${google_storage_bucket.data_beans_bucket.name}"
}

##Create sub folders - orders
resource "google_storage_bucket_object" "orders_folder" {
  name          = "orders/"
  content       = "Not really a directory, but it's empty."
  bucket        = "${google_storage_bucket.data_beans_bucket.name}"
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
resource "google_storage_bucket_iam_member" "data_beans_perms" {
  bucket = "${google_storage_bucket.data_beans_bucket.name}"
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_bigquery_connection.connection.cloud_resource[0].service_account_id}"
  depends_on = [google_storage_bucket.data_beans_bucket]
}

## Ser permission on Vertex.AI
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
      gsutil cp -r gcp-public-demos/data-beans/assets/roaster_sensor/* gs://data_beans_${data.google_project.project.number}/roaster
      gsutil cp -r gcp-public-demos/data-beans/assets/visual_inspection/* gs://data_beans_${data.google_project.project.number}/visual_inspection
      gsutil cp -r gcp-public-demos/data-beans/assets/weather/* gs://data_beans_${data.google_project.project.number}/weather
      gsutil cp -r gcp-public-demos/data-beans/assets/claims/* gs://data_beans_${data.google_project.project.number}/claims
      gsutil cp -r gcp-public-demos/data-beans/assets/orders/* gs://data_beans_${data.google_project.project.number}/orders
      EOT
  }
  depends_on = [
    time_sleep.default, 
    google_storage_bucket_iam_member.data_beans_perms,
    google_project_iam_member.bucket,
    null_resource.get_from_github,
    google_storage_bucket_object.visual_inspection_folder,
    google_storage_bucket_object.roaster_folder,
    google_storage_bucket_object.claims_folder,
    google_storage_bucket_object.orders_folder,
    google_storage_bucket_object.weather_folder
  ]
}

###Cleanup
#resource "null_resource" "cleanup" {
#  provisioner "local-exec" {
#   command = "rm -r gcp-public-demos/data-beans/assets/roaster_sensor"
#    }
#  depends_on = [null_resource.upload]
#}

## Create dataset data_beams
resource "google_bigquery_dataset" "data_beans" {
  dataset_id                      = "data_beans"
  description                     = "Data Beans Demo"
  default_partition_expiration_ms = 2592000000  # 30 days
  default_table_expiration_ms     = 31536000000 # 365 days
  location                        = "${var.region}"
  max_time_travel_hours           = 96 # 4 days
}

## Create Native table - claims
resource "google_bigquery_table" "claims" {
   dataset_id          = google_bigquery_dataset.data_beans.dataset_id
   table_id            = "claims"
   deletion_protection = false
   labels = {
     env = "default"
   }
   #external_data_configuration {
   #  autodetect = true
   #  source_uris =["gs://data_beans_${data.google_project.project.number}/claims/databeans_claims.csv"]
   #  source_format = "CSV"
   
   # csv_options{
   #   quote = ""
   #   skip_leading_rows = 1
   #   field_delimiter       = ","
   #   allow_quoted_newlines = "false"
   #   allow_jagged_rows     = "false"
   # }
   #}
   depends_on = [null_resource.upload]
 }

##load claim data into native table
resource "null_resource" "load_claim_data" {
  provisioner "local-exec" {
    command =  "bq --location=${var.region} load --autodetect --skip_leading_rows=1 --source_format=CSV ${google_bigquery_dataset.data_beans.dataset_id} gs://data_beans_${data.google_project.project.number}/claims/databeans_claims.csv"
  }
  depends_on = [google_bigquery_table.claims]
}

## Create external table - orders
resource "google_bigquery_table" "orders" {
   dataset_id          = google_bigquery_dataset.data_beans.dataset_id
   table_id            = "orders"
   deletion_protection = false
   labels = {
     env = "default"
   }
   external_data_configuration {
     autodetect = true
     source_uris =["gs://data_beans_${data.google_project.project.number}/orders/databeans_orders.csv"]
     source_format = "CSV"
   
   csv_options{
      quote = ""
      skip_leading_rows = 1
      field_delimiter       = ","
      allow_quoted_newlines = "false"
      allow_jagged_rows     = "false"
    }
    }
   depends_on = [google_project_iam_member.bucket, null_resource.upload]
 }



## Create bigLake table - roaster
resource "google_bigquery_table" "roaster" {
  dataset_id = google_bigquery_dataset.data_beans.dataset_id
  table_id   = "roaster"

  external_data_configuration {
    autodetect    = true
    source_format = "NEWLINE_DELIMITED_JSON"
    connection_id = google_bigquery_connection.connection.name
    source_uris   = ["gs://${google_storage_bucket.data_beans_bucket.name}/roaster/*.json"]
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
  dataset_id          = google_bigquery_dataset.data_beans.dataset_id
  external_data_configuration {
    connection_id = google_bigquery_connection.connection.name
    autodetect    = true
    object_metadata = "SIMPLE"
    source_uris = [
      "gs://${google_storage_bucket.data_beans_bucket.name}/visual_inspection/*.png",
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