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
    #BUCKET_NAME = google_storage_bucket.mlops_gcs_bucket.name
    BUCKET_NAME = local.pipelines_bucket
  }
  #ingress_settings = "ALLOW_INTERNAL_AND_GCLB" # debug option: ALLOW_ALL
  ingress_settings = "ALLOW_ALL"

  # Executes uploading the dependencies for the Cloud Function
  depends_on = [
    google_project_service.enabled_services["cloudbuild.googleapis.com"],
    google_project_service.enabled_services["cloudfunctions.googleapis.com"],
    google_project_iam_binding.artifact_registry_access,
    google_storage_bucket_object.trigger_pipeline_zip
  ]
}

# -----------------------------------
# Vertex AI Feature Store
# -----------------------------------

# Table schema for the data entities

variable "mlops_featurestore_features" {
  type = list(object({
    name = string
    type = string
    mode = string
  }))
  default = [
    { "name" : "id", "type" : "STRING", "mode" : "REQUIRED" },
    { "name" : "ts", "type" : "STRING", "mode" : "REQUIRED" },
    { "name" : "poorhlth", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "physhlth", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "genhlth", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "diffwalk", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "diffalon", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "checkup1", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "diffdres", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "addepev3", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "acedeprs", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "sdlonely", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "lsatisfy", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "emtsuprt", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "decide", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "cdsocia1", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "cddiscu1", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "cimemlo1", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "smokday2", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "alcday4", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "marijan1", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "exeroft1", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "usenow3", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "firearm5", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "income3", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "educa", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "employ1", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "sex", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "marital", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "adult", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "rrclass3", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "qstlang", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "state", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "veteran3", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "medcost1", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "sdhbills", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "sdhemply", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "sdhfood1", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "sdhstre1", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "sdhutils", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "sdhtrnsp", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "cdhous1", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "foodstmp", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "pregnant", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "asthnow", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "havarth4", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "chcscnc1", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "chcocnc1", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "diabete4", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "chccopd3", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "cholchk3", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "bpmeds1", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "bphigh6", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "cvdstrk3", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "cvdcrhd4", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "chckdny2", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "cholmed3", "type" : "INT64", "mode" : "REQUIRED" },
    { "name" : "ment14d", "type" : "INT64", "mode" : "REQUIRED" }
  ]
}

# 1. Define the online feature store for the Vertex AI Feature Store
#####################################################################

resource "google_vertex_ai_feature_online_store" "mlops_online_store" {
  name   = "mlops_online_store"
  region = var.region

  bigtable {
    auto_scaling {
      max_node_count = 1
      min_node_count = 1
    }
  }

}

# 2. Define the feature store
#####################################################################

resource "google_vertex_ai_featurestore" "mlops_feature_store" {
  name   = "mlops_feature_store"
  region = var.region

  depends_on = [google_project_service.enabled_services["aiplatform.googleapis.com"]]
}

/*
  Define 2 entities for the feature store:
    One for training data, and one for inference data
*/

# 3. Define data Entities using the Vertex AI Feature Store schema
#####################################################################

# Training Data Entity
resource "google_vertex_ai_featurestore_entitytype" "cdc_training" {
  name        = "cdc_training"
  description = "Entity for training data"

  featurestore = google_vertex_ai_featurestore.mlops_feature_store.id

  depends_on = [google_vertex_ai_featurestore.mlops_feature_store]
}

# Training data entity cdc_training features
resource "google_vertex_ai_featurestore_entitytype_feature" "cdc_training_features" {
  for_each   = { for feature in var.mlops_featurestore_features : feature.name => feature }
  entitytype = google_vertex_ai_featurestore_entitytype.cdc_training.id
  value_type = each.value.type
  name       = each.value.name

  depends_on = [
    google_container_cluster.mlops_gke_cluster,
    google_vertex_ai_featurestore_entitytype.cdc_training
  ]
}

# Inference Data Entity
resource "google_vertex_ai_featurestore_entitytype" "cdc_inference" {
  name        = "cdc_inference"
  description = "Entity for inferential data"

  featurestore = google_vertex_ai_featurestore.mlops_feature_store.id

  depends_on = [google_vertex_ai_featurestore.mlops_feature_store]
}

# Inference data entity cdc_inference Features
resource "google_vertex_ai_featurestore_entitytype_feature" "cdc_inference_features" {
  for_each   = { for feature in var.mlops_featurestore_features : feature.name => feature }
  entitytype = google_vertex_ai_featurestore_entitytype.cdc_inference.id
  value_type = each.value.type
  name       = each.value.name

  depends_on = [
    google_container_cluster.mlops_gke_cluster,
    google_vertex_ai_featurestore_entitytype.cdc_inference
  ]
}

# 4. Setup the bigquery tables for the feature store
#####################################################################

# Create a BigQuery dataset
resource "google_bigquery_dataset" "mlops_feature_store" {
  dataset_id = "mlops_feature_store"
  location   = var.region
}

# Create the BigQuery tables for the feature store

# Training data table
resource "google_bigquery_table" "cdc_training" {
  table_id   = "cdc_training"
  dataset_id = google_bigquery_dataset.mlops_feature_store.dataset_id

  schema = jsonencode([
    for feature in var.mlops_featurestore_features : {
      name        = feature.name
      type        = feature.type
      mode        = feature.mode
    }
  ])

  deletion_protection = false

  depends_on = [google_bigquery_dataset.mlops_feature_store]
}

# Inference data table
resource "google_bigquery_table" "cdc_inference" {
  table_id   = "cdc_inference"
  dataset_id = google_bigquery_dataset.mlops_feature_store.dataset_id

  schema = jsonencode([
    for feature in var.mlops_featurestore_features : {
      name        = feature.name
      type        = feature.type
      mode        = feature.mode
    }
  ])

  deletion_protection = false

  depends_on = [google_bigquery_dataset.mlops_feature_store]
}

# 5. Define the feature views for the feature store
#####################################################################

# Feature view for training data
resource "google_vertex_ai_feature_online_store_featureview" "cdc_training_featureview" {
  name         = "cdc_training_featureview"
  region = var.region

  feature_online_store = google_vertex_ai_feature_online_store.mlops_online_store.name

  big_query_source {
    uri = "bq://${var.project_id}.${google_bigquery_dataset.mlops_feature_store.dataset_id}.${google_bigquery_table.cdc_training.table_id}"
    entity_id_columns = [for entity_id in var.mlops_featurestore_features : entity_id.name]
  }

  sync_config {
    cron = "0 * * * *"
  }

  depends_on = [
    google_bigquery_table.cdc_training,
    google_vertex_ai_feature_online_store.mlops_online_store
  ]
}

# Feature view for inference data
resource "google_vertex_ai_feature_online_store_featureview" "cdc_inference_featureview" {
  name         = "cdc_inference_featureview"
  region = var.region

  feature_online_store = google_vertex_ai_feature_online_store.mlops_online_store.name

  big_query_source {
    uri = "bq://${var.project_id}.${google_bigquery_dataset.mlops_feature_store.dataset_id}.${google_bigquery_table.cdc_inference.table_id}"
    entity_id_columns = [for entity_id in var.mlops_featurestore_features : entity_id.name]
  }

  sync_config {
    cron = "0 * * * *"
  }

  depends_on = [
    google_bigquery_table.cdc_inference,
    google_vertex_ai_feature_online_store.mlops_online_store
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


