provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_project_service" "enabled_services" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "cloudbuild.googleapis.com",
    "bigquery.googleapis.com",
    "vertexai.googleapis.com",
    "pubsub.googleapis.com",
    "file.googleapis.com"
  ])

  service = each.key
}

resource "google_service_account" "vertex_service_account" {
  account_id   = "vertex-sa"
  display_name = "Vertex AI Service Account"
}

resource "google_project_iam_binding" "vertex_sa_roles" {
  project = var.project_id

  role = "roles/editor"
  members = [
    "serviceAccount:${google_service_account.vertex_service_account.email}"
  ]
}

resource "google_project_iam_binding" "vertex_sa_custom_roles" {
  project = var.project_id

  role = "roles/aiplatform.user"
  members = [
    "serviceAccount:${google_service_account.vertex_service_account.email}"
  ]
}

resource "google_project_iam_binding" "compute_network_admin" {
  project = var.project_id

  role = "roles/compute.networkAdmin"
  members = [
    "serviceAccount:${google_service_account.vertex_service_account.email}"
  ]
}

resource "google_compute_network" "vpc_network" {
  name = "vertex-vpc"
}

resource "google_compute_subnetwork" "public_subnet" {
  name          = "vertex-public-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.vpc_network.id
}

resource "google_compute_subnetwork" "private_subnet" {
  name          = "vertex-private-subnet"
  ip_cidr_range = "10.0.2.0/24"
  region        = var.region
  network       = google_compute_network.vpc_network.id
}

resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  source_ranges = ["10.0.0.0/16"]
}

resource "google_compute_firewall" "allow_external" {
  name    = "allow-external"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_global_address" "load_balancer_ip" {
  name = "load-balancer-ip"
}

resource "google_compute_target_pool" "load_balancer_pool" {
  name = "lb-pool"
}

resource "google_compute_forwarding_rule" "load_balancer_rule" {
  name       = "http-load-balancer"
  ip_address = google_compute_global_address.load_balancer_ip.address
  port_range = "80"
  target     = google_compute_target_pool.load_balancer_pool.self_link
}

resource "google_compute_security_policy" "cloud_armor" {
  name = "cloud-armor-policy"
  description = "Cloud Armor security policy"

  rule {
    action = "allow"
    priority = 1000
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["0.0.0.0/0"]
      }
    }
  }
}

resource "google_container_cluster" "gke_cluster" {
  name     = "vertex-deployment-cluster"
  location = var.region
  initial_node_count = 1  # Free tier setting
  network  = google_compute_network.vpc_network.id
  subnetwork = google_compute_subnetwork.private_subnet.id
  node_config {
    machine_type = "e2-small"  # Free tier-eligible
    service_account = google_service_account.vertex_service_account.email
  }
}

# No longer needed as we use google_storage_bucket
# in google_cloudfunctions_function for storage
#resource "google_filestore_instance" "filestore" {
#  name = "vertex-filestore"
#  tier = "BASIC_HDD"  # Free-tier compatible storage
#  file_shares {
#    capacity_gb = 1024
#    name        = "vertex-share"
#  }
#  networks {
#    network = google_compute_network.vpc_network.name
#    modes   = ["MODE_IPV4"]
#  }
#}

resource "google_bigquery_dataset" "bigquery_dataset" {
  dataset_id = "vertex_ai_dataset"
  location   = "US"
}

resource "google_vertex_ai_featurestore" "feature_store" {
  name   = "vertex-feature-store"
  region = var.region
}

#resource "google_vertex_ai_pipeline" "pipeline" {
#  name        = "data-pipeline"
#  display_name = "Data Preprocessing Pipeline"
#  region      = var.region
#  input_data_config {
#    gcs_source {
#      input_uri_prefix = google_compute_network.vpc_network.name
#    }
#  }
#}
resource "google_storage_bucket" "preprocessing_bucket" {
  name     = "${var.project_id}-vertex-preprocesing-bucket"
  location = var.region

  storage_class = "STANDARD"
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 5 # Delete objects older than 5 days
    }
  }
}

# Workaround for the not supported google_vertex_ai_pipeline"
resource "google_cloudfunctions_function" "trigger_pipeline" {
  name        = "trigger-vertex-pipeline"
  runtime     = "python310"
  entry_point = "trigger_pipeline"
  source_archive_bucket = google_storage_bucket.preprocessing_bucket.name
  source_archive_object = "functions/trigger_pipeline.zip"
  trigger_http          = true
  available_memory_mb   = 256
  environment_variables = {
    PROJECT_ID = var.project_id
    REGION     = var.region
  }
}


#resource "google_vertex_ai_model" "model" {
#  display_name = "vertex-trained-model"
#  region       = var.region
#  labels = {
#    environment = "prod"
#  }
#  artifact_uri = google_filestore_instance.filestore.file_shares[0].name
#}
# Workaround for the not supported google_vertex_ai_model"
resource "google_cloudfunctions_function" "register_model" {
  name        = "register-vertex-model"
  runtime     = "python310"
  entry_point = "register_model"
  source_archive_bucket = google_storage_bucket.preprocessing_bucket.name
  source_archive_object = "functions/register_model.zip"
  trigger_http          = true
  available_memory_mb   = 256
  environment_variables = {
    PROJECT_ID = var.project_id
    REGION     = var.region
  }
}

resource "google_vertex_ai_endpoint" "endpoint" {
  name = "vertex-endpoint"
  display_name = "Vertex AI Endpoint"
  location = var.region
}

#resource "google_vertex_ai_model_deployment" "deployment" {
#  endpoint_id = google_vertex_ai_endpoint.endpoint.id
#  model_id    = google_vertex_ai_model.model.id
#  traffic_split = {
#    "0" = 100
#  }
#}
# Workaround for the not supported google_vertex_ai_model_deployment"
resource "google_cloudfunctions_function" "deploy_model" {
  name        = "deploy-vertex-model"
  runtime     = "python310"
  entry_point = "deploy_model"
  source_archive_bucket = google_storage_bucket.preprocessing_bucket.name
  source_archive_object = "functions/deploy_model.zip"
  trigger_http          = true
  available_memory_mb   = 256
  environment_variables = {
    PROJECT_ID = var.project_id
    REGION     = var.region
  }
}

resource "google_monitoring_alert_policy" "alert_policy" {
  display_name = "Vertex AI Monitoring"
  combiner     = "OR"

  # Prediction latency condition
  conditions {
    display_name = "Prediction Latency"
    condition_threshold {
      filter          = "metric.type='cloudml.googleapis.com/endpoint/prediction_latency'"
      comparison      = "COMPARISON_GT"
      threshold_value = 1000
      duration        = "60s"
    }
  }

  # Prediction errors condition
  conditions {
    display_name    = "Prediction Errors"
    condition_threshold {
      filter          = "metric.type='cloudml.googleapis.com/endpoint/prediction_error_count'"
      comparison      = "COMPARISON_GT"
      threshold_value = 50
      duration        = "60s"
    }
  }

  # Drift monitoring condition (example using threshold violations)
  conditions {
    display_name    = "Data Drift Violations"
    condition_threshold {
      filter          = "metric.type='cloudml.googleapis.com/endpoint/deployed_model/distance_threshold_violations'"
      comparison      = "COMPARISON_GT"
      threshold_value = 10
      duration        = "300s"
    }
  }

  # Feature attribution drift condition
  conditions {
    display_name    = "Feature Attribution Drift"
    condition_threshold {
      filter          = "metric.type='cloudml.googleapis.com/endpoint/deployed_model/feature_attribution_score_drift'"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.1
      duration        = "300s"
    }
  }
}
