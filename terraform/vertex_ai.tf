
# -----------------------------------
# Vertex AI Pipelines
# -----------------------------------

/*
  An executable function is needed to trigger the Vertex AI pipeline.
  Here we use python trigger hosted in a Cloud Function.
  First we need to get this function trigger uploaded to a
  Cloud Storage bucket so that the trigger 'trigger_pipeline' can reach
  it and run the program.

  Steps:
  1. Zip the function source files from the project directory
      on the development machine. The source files are located in
      cloud_functions/trigger_pipeline in the project directory.
*/
resource "archive_file" "trigger_pipeline_zip" {
  type        = "zip"
  source_dir  = "../cloud_functions/trigger_pipeline"
  output_path = "../cloud_functions/trigger_pipeline/trigger_pipeline.zip"
}

# 2. Upload the zip file to the Cloud Storage bucket
resource "google_storage_bucket_object" "trigger_pipeline_zip" {
  name   = "functions/trigger_pipeline.zip"
  bucket = google_storage_bucket.mlops_gcs_bucket.name
  source = archive_file.trigger_pipeline_zip.output_path
}

/*
  3. Create the Cloud Function to trigger the Vertex AI pipeline
  Workaround for the not supported (by TF) google_vertex_ai_pipeline"
*/
resource "google_cloudfunctions_function" "trigger_pipeline" {
  name                  = "trigger-vertex-pipeline"
  runtime               = "python312"
  entry_point           = "trigger_pipeline" # The executable function to run
  source_archive_bucket = google_storage_bucket.mlops_gcs_bucket.name
  source_archive_object = google_storage_bucket_object.trigger_pipeline_zip.name
  trigger_http          = true
  available_memory_mb   = 1024
  environment_variables = {
    PROJECT_ID = var.project_id
    REGION     = var.region
    # Set the bucket destination for the executable pipeline trigger
    # python file.
    BUCKET_NAME = google_storage_bucket.mlops_gcs_bucket.name
  }
  ingress_settings = "ALLOW_INTERNAL_AND_GCLB" # debug option: ALLOW_ALL

  # Executes uploading the dependencies for the Cloud Function
  depends_on = [
    google_project_service.enabled_services["cloudbuild.googleapis.com"],
    google_project_iam_member.artifact_registry_access,
    google_project_service.cloudfunctions,
    google_storage_bucket_object.trigger_pipeline_zip
  ]
}

# -----------------------------------
# Vertex AI Feature Store
# -----------------------------------

resource "google_vertex_ai_featurestore" "mlops_feature_store" {
  name   = "mlops_feature_store"
  region = var.region

  lifecycle {
    ignore_changes = all
  }

  depends_on = [google_project_service.enabled_services["aiplatform.googleapis.com"]]
}

# Table schema for the data entity
variable "mlops__data_features" {
  type = list(object({
    name = string
    type = string
    mode = string
  }))
  default = [
    { "name" : "poorhlth", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "physhlth", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "genhlth", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "diffwalk", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "diffalon", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "checkup1", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "diffdres", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "addepev3", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "acedeprs", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "sdlonely", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "lsatisfy", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "emtsuprt", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "decide", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "cdsocia1", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "cddiscu1", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "cimemlo1", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "smokday2", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "alcday4", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "marijan1", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "exeroft1", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "usenow3", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "firearm5", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "income3", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "educa", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "employ1", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "sex", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "marital", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "adult", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "rrclass3", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "qstlang", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "_state", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "veteran3", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "medcost1", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "sdhbills", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "sdhemply", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "sdhfood1", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "sdhstre1", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "sdhutils", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "sdhtrnsp", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "cdhous1", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "foodstmp", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "pregnant", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "asthnow", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "havarth4", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "chcscnc1", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "chcocnc1", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "diabete4", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "chccopd3", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "cholchk3", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "bpmeds1", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "bphigh6", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "cvdstrk3", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "cvdcrhd4", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "chckdny2", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "cholmed3", "type" : "INTEGER", "mode" : "REQUIRED" },
    { "name" : "_ment14d", "type" : "INTEGER", "mode" : "REQUIRED" }
  ]
}

/*
  Define 2 entities for the feature store:
    One for training data, and one for inference data
*/

# 1. Training Data Entity using the Vertex AI Feature Store schema
resource "google_vertex_ai_featurestore_entitytype" "training_data" {
  name        = "training_data"
  description = "Entity for training data"

  featurestore = google_vertex_ai_featurestore.mlops_feature_store.id

  depends_on = [google_vertex_ai_featurestore.mlops_feature_store]
}

# Historical Features
resource "google_vertex_ai_featurestore_entitytype_feature" "historical_features" {
  for_each   = { for feature in var.mlops__data_features : feature.name => feature }
  entitytype = google_vertex_ai_featurestore_entitytype.training_data.id
  value_type = each.value.type == "INTEGER" ? "INT64" : each.value.type
  name       = each.value.name

  depends_on = [
    google_container_cluster.mlops_gke_cluster,
    google_vertex_ai_featurestore_entitytype.training_data
  ]
}

# 2. Inference Data Entity - using the BigQuery table schema

/*
  Define the feature store schema for the Mental Health inference dataset.
  The schema is defined in the BigQuery table 'mental_health_features'.

  NOTE: We decided to use the BigQuery table as the source of truth for the
    feature store schema because it is easier to manage for future
      updates and ingestion.

  The schema is used to create the feature store entity type.

  Google cloud manages the linkage between the BigQuery table and the
    feature store, so no need to link them manually - we just need to
    provide the schema to the feature store client instance.
*/

# Define the bigquery table for the feature store
resource "google_bigquery_dataset" "featurestore_dataset" {
  dataset_id = "vertex_ai_featurestore"
  project    = var.project_id
  location   = var.region
  depends_on = [google_project_service.bigquery]
}

resource "google_bigquery_table" "inference" {

  table_id = "inference_data"
  project  = var.project_id

  dataset_id = google_bigquery_dataset.featurestore_dataset.dataset_id

  schema = jsonencode(
    concat(
      [{ "name" : "id", "type" : "INTEGER", "mode" : "REQUIRED" }],
      [for item in var.mlops__data_features : { "name" : item.name, "type" : item.type, "mode" : item.mode }]
    )
  )

  deletion_protection = false
  depends_on = [
    google_container_cluster.mlops_gke_cluster,
    google_bigquery_dataset.featurestore_dataset
  ]
}

# -----------------------------------
# Vertex AI Endpoint
# -----------------------------------

resource "google_vertex_ai_endpoint" "endpoint" {
  name         = "mlops-endpoint"
  display_name = "mlops-endpoint"
  location     = var.region

  lifecycle {
    ignore_changes = all
  }

  depends_on = [google_project_service.enabled_services["aiplatform.googleapis.com"]]
}

# -----------------------------------
# Vertex AI Monitoring
# -----------------------------------

resource "google_monitoring_notification_channel" "email_channel" {
  display_name = "Email Notifications"
  type         = "email"
  labels = {
    email_address = var.email
  }
}

resource "google_monitoring_alert_policy" "mlops_alert_policy" {
  display_name = "Vertex AI Monitoring Alert Policy"
  combiner     = "OR"

  conditions {
    display_name = "High CPU Utilization"
    condition_threshold {
      filter          = "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8
      duration        = "300s" # 5 minutes

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = [
    google_monitoring_notification_channel.email_channel.id
  ]

  user_labels = {
    environment = "production"
    type        = "generic_alert"
  }
}


