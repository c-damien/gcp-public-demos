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
#               Data Security Workshop - demo
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

## get Google Cloud project
data "google_project" "project" {}

variable "region" {
  type = string
  default = "us-central1"
}

###activate API services
resource "google_project_service" "google-cloud-apis" {
  project = data.google_project.project.project_id 
  for_each = toset([
    "datacatalog.googleapis.com"
    "dataplex.googleapis.com",
    "bigqueryconnection.googleapis.com",
    "aiplatform.googleapis.com",
    "servicenetworking.googleapis.com",
    "compute.googleapis.com",
    "embeddedassistant.googleapis.com"
  ])
  disable_dependent_services = true
  disable_on_destroy         = true
  service                    = each.key
}

//-------GCS bucket

## Create gcs bucket
#https://cloud.google.com/storage/docs/terraform-create-bucket-upload-object
resource "google_storage_bucket" "workshop_bucket" {
 name          = "workshop_${data.google_project.project.number}" 
 location      = "${var.region}"
 storage_class = "STANDARD"
 force_destroy               = true
 uniform_bucket_level_access = true
}

###Install
resource "null_resource" "install_package" {
  provisioner "local-exec" {
    command = <<-EOT
        curl -O https://github.com/Teradata/kylo/blob/master/samples/sample-data/parquet/userdata1.parquet
      EOT
  }
}

##Create sub folders - parquet 
resource "google_storage_bucket_object" "workshop_folder" {
  name          = "userdata1.parquet"
  source        = "${path.module}/userdata1.parquet"
  bucket        = "${google_storage_bucket.workshop_bucket.name}"
  depends_on = [
  google_storage_bucket.workshop_bucket,
  null_resource.install_package
  ]
}

//------Bigquery

## Create dataset workshop
resource "google_bigquery_dataset" "workshop-dset" {
  dataset_id                      = "workshop"
  description                     = "Workshop"
  location                        = "${var.region}"
  max_time_travel_hours           = 96 # 4 days
}

//--------copy table
# BigQuery job to perform the copy operation
resource "google_bigquery_job" "copy_job_user" {
  job_id   = "copy-public-table-job-user" 
  project  = data.google_project.project.project_id

  copy {
    source_tables {
      project_id = "bigquery-public-data"
      dataset_id = "thelook_ecommerce"
      table_id   = "users"
    }
    destination_table {
      project_id = data.google_project.project.project_id 
      dataset_id = google_bigquery_dataset.workshop-dset.dataset_id
      table_id   = "users"
    }

     }

  # Wait for the copy job to complete before proceeding
  depends_on = [google_bigquery_dataset.workshop-dset] 
}

resource "google_bigquery_job" "copy_job_order_items" {
  job_id   = "copy-public-table-job-order_items" 
  project  = data.google_project.project.project_id

  copy {
    source_tables {
      project_id = "bigquery-public-data"
      dataset_id = "thelook_ecommerce"
      table_id   = "order_items"
    }
    destination_table {
      project_id = data.google_project.project.project_id 
      dataset_id = google_bigquery_dataset.workshop-dset.dataset_id
      table_id   = "order_items"
    }

     }

  # Wait for the copy job to complete before proceeding
  depends_on = [google_bigquery_dataset.workshop-dset] 
}

resource "google_bigquery_job" "copy_job_products" {
  job_id   = "copy-public-table-job-products" 
  project  = data.google_project.project.project_id

  copy {
    source_tables {
      project_id = "bigquery-public-data"
      dataset_id = "thelook_ecommerce"
      table_id   = "products"
    }
    destination_table {
      project_id = data.google_project.project.project_id 
      dataset_id = google_bigquery_dataset.workshop-dset.dataset_id
      table_id   = "products"
    }

     }

  # Wait for the copy job to complete before proceeding
  depends_on = [google_bigquery_dataset.workshop-dset] 
}

//--------datalake creation
resource "google_dataplex_lake" "analytics_lake" {
  name        = "analytics"
  location    = "us-central1"
  description = "Data lake for analytics"
  #metastore {
  #  service = "YOUR_METASTORE_SERVICE"   // Example: "projects/YOUR_PROJECT_ID/locations/YOUR_LOCATION/services/YOUR_HIVE_METASTORE_SERVICE"
  #}
  depends_on = [google_project_service.google-cloud-apis] 
}

resource "google_dataplex_zone" "landing_zone" {
  name        = "landing"
  lake        = google_dataplex_lake.analytics_lake.name
  location    = google_dataplex_lake.analytics_lake.location
  description = "Landing Zone for raw data ingestion"
  type        = "RAW"
  discovery_spec {
    enabled = false
  }
  resource_spec {
    location_type = "SINGLE_REGION"
  }
}

resource "google_dataplex_zone" "staging_zone" {
  name        = "staging"
  lake        = google_dataplex_lake.analytics_lake.name
  location    = google_dataplex_lake.analytics_lake.location
  description = "Staging Zone for data transformation and cleaning"
  type        = "CURATED"
  discovery_spec {
    enabled = false
  }
  resource_spec {
    location_type = "SINGLE_REGION"
  }
}

//--------create policy tag
resource "google_data_catalog_policy_tag" "workshop_policy_tag" {
  taxonomy = google_data_catalog_taxonomy.workshop_taxonomy.id
  display_name = "High security"
  description = "A policy tag associated with high security items"
}

resource "google_data_catalog_taxonomy" "workshop_taxonomy" {
  display_name =  "workshop_taxonomy"
  region = "us-central1"
  description = "A collection of policy tags"
  activated_policy_types = ["FINE_GRAINED_ACCESS_CONTROL"]
}

resource "google_data_catalog_policy_tag_iam_binding" "binding" {
  policy_tag = google_data_catalog_policy_tag.workshop_policy_tag.name
  role = "roles/viewer"
  members = [
    "user:cdamien@google.com",
  ]
}

//--------create a template
resource "google_data_catalog_tag_template" "workshop_tag_template" {
  tag_template_id = "workshop_template"
  region = "us-central1"
  display_name = "Workshop Tag Template"

  fields {
    field_id = "data_source"
    display_name = "Source of data asset"
    type {
      primitive_type = "STRING"
    }
    is_required = true
  }

  fields {
    field_id = "num_rows"
    display_name = "Number of rows in the data asset"
    type {
      primitive_type = "DOUBLE"
    }
  }

  fields {
    field_id = "pii_type"
    display_name = "PII type"
    type {
      enum_type {
        allowed_values {
          display_name = "FULLNAME"
        }
        allowed_values {
          display_name = "SOCIAL SECURITY NUMBER"
        }
        allowed_values {
          display_name = "NONE"
        }
      }
    }
  }

  force_delete = "false"
}




