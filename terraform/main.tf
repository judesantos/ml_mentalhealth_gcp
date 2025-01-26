provider "google" {
  project = var.project_id
  region  = var.region
}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.mlops_gke_cluster.endpoint}"
  client_certificate     = base64decode(google_container_cluster.mlops_gke_cluster.master_auth[0].client_certificate)
  client_key             = base64decode(google_container_cluster.mlops_gke_cluster.master_auth[0].client_key)
  cluster_ca_certificate = base64decode(google_container_cluster.mlops_gke_cluster.master_auth[0].cluster_ca_certificate)
}

# -----------------------------------
# IAM Permissions
# -----------------------------------

resource "google_service_account" "mlops_service_account" {
  account_id   = "mlops-service-account"
  display_name = "MLOps Service Account"
}

resource "google_project_iam_member" "mlops_permissions" {
  for_each = toset([
    "roles/owner",
    "roles/editor",
    "roles/serviceusage.serviceUsageAdmin",
    "roles/cloudkms.admin",
    "roles/container.admin",
    "roles/container.clusterAdmin",
    "roles/container.nodeServiceAccount",
    "roles/cloudbuild.builds.editor",
    "roles/cloudbuild.builds.builder",
    "roles/artifactregistry.writer",
    "roles/resourcemanager.projectIamAdmin",
    "roles/container.developer",
    "roles/storage.admin",
    "roles/secretmanager.secretAccessor",
  ])
  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.mlops_service_account.email}"
  depends_on = [google_service_account.mlops_service_account]
}

resource "google_service_account_iam_member" "allow_impersonation" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/cloud-build-editor@ml-mentalhealth.iam.gserviceaccount.com"
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "user:${var.email}"
}

# The service account serviceAccount:service-416879185829@g* is somehow
# expected by cloud build, we need to create it and give it the necessary
# permissions for the github connection to work.
resource "google_secret_manager_secret_iam_member" "github_token_accessor" {
  secret_id = "github-token" # Replace with your secret's name
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:service-416879185829@gcp-sa-cloudbuild.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "cloudbuild_secret_access" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:cloud-build-editor@ml-mentalhealth.iam.gserviceaccount.com"
}

# -----------------------------------
# Enable Required Services
# -----------------------------------
resource "google_project_service" "iam" {
  service = "iam.googleapis.com"
  project = var.project_id
}

#resource "google_project_service" "enable_kms" {
#  project = var.project_id
#  service = "cloudkms.googleapis.com"
#
#  depends_on = [google_project_service.iam]
#}

resource "google_project_service" "enabled_services" {
  for_each = toset([
    "serviceusage.googleapis.com",
    "servicemanagement.googleapis.com",
    "containerregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "aiplatform.googleapis.com",
    "container.googleapis.com",
    "dataflow.googleapis.com",
    "compute.googleapis.com",
    "artifactregistry.googleapis.com",
    #"cloudresourcemanager.googleapis.com",
    "bigquery.googleapis.com",
    "aiplatform.googleapis.com",
    "pubsub.googleapis.com",
    "file.googleapis.com",
  ])

  service = each.key
  depends_on = [google_project_service.iam]
}

# -----------------------------------
# VPC and Subnets
# -----------------------------------
resource "google_compute_network" "vpc_network" {
  name = "mlops-vpc-network"
}

resource "google_compute_subnetwork" "public_subnet" {
  name          = "mlops-public-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc_network.id

  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_10_MIN" # Options: INTERVAL_5_SEC, INTERVAL_1_MIN, INTERVAL_10_MIN
    flow_sampling        = 0.5              # Fraction of traffic to sample (0.0 to 1.0)
    metadata             = "INCLUDE_ALL_METADATA" # Options: EXCLUDE_ALL_METADATA, INCLUDE_ALL_METADATA
  }
}

resource "google_compute_subnetwork" "private_subnet" {
  name          = "mlops-private-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.vpc_network.id

  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_10_MIN" # Options: INTERVAL_5_SEC, INTERVAL_1_MIN, INTERVAL_10_MIN
    flow_sampling        = 0.5              # Fraction of traffic to sample (0.0 to 1.0)
    metadata             = "INCLUDE_ALL_METADATA" # Options: EXCLUDE_ALL_METADATA, INCLUDE_ALL_METADATA
  }

  secondary_ip_range {
    range_name    = "pods-range"
    ip_cidr_range = "10.1.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services-range"
    ip_cidr_range = "10.2.0.0/20"
  }
}

# -----------------------------------
# Firewall Rules
# -----------------------------------

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

  source_ranges = ["0.0.0.0/24"] # Replace with your allowed IP range
  direction     = "INGRESS"
  target_tags   = ["ssh-access"]

  priority = 1000 # Lower number = higher priority

  #source_ranges = ["0.0.0.0/0"]
}

# -----------------------------------
# Load Balancer
# -----------------------------------

resource "google_compute_address" "load_balancer_ip" {
  name = "load-balancer-ip"
}

resource "google_compute_target_pool" "load_balancer_pool" {
  name = "lb-pool"
}

resource "google_compute_forwarding_rule" "load_balancer_rule" {
  name       = "http-load-balancer"
  region     = var.region
  ip_address = google_compute_address.load_balancer_ip.address
  port_range = "80"
  target     = google_compute_target_pool.load_balancer_pool.self_link
}

# -----------------------------------
# Cloud Armor Security Policy
# -----------------------------------

resource "google_compute_security_policy" "cloud_armor" {
  name = "cloud-armor-policy"
  description = "Cloud Armor security policy"

}

#resource "google_kms_key_ring" "mlops_key_ring" {
#  name     = "mlops-key-ring"
#  location = var.region # Adjust location as necessary
#
#  depends_on = [google_project_service.enable_kms]
#}
#
#resource "google_kms_crypto_key" "mlops_crypto_key" {
#  name            = "mlops-crypto-key"
#  key_ring        = google_kms_key_ring.mlops_key_ring.id
#  purpose         = "ENCRYPT_DECRYPT"
#
#   # Set a key rotation period
#  rotation_period = "2592000s" # 30 days
#
#}

# -----------------------------------
# Cloud Storage (GCS) for Data Storage
# -----------------------------------
resource "google_storage_bucket" "mlops_gcs_bucket" {
  name          = "mlops-gcs-bucket"
  location      = var.region
  force_destroy = true # Destroy all objects when bucket is destroyed

  logging {
    log_bucket = "google_storage_bucket.log_bucket"
    log_object_prefix = "gcs_access_logs"
  }

  storage_class = "STANDARD"
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 29 # Delete objects older than 29 days
    }
  }

  public_access_prevention = "enforced"
  #Enable uniform bucket-level access
  uniform_bucket_level_access = true

  #encryption {
  #  default_kms_key_name = google_kms_crypto_key.mlops_crypto_key.id
  #}
}

# -----------------------------------
# GKE Deployment Cluster (Free Tier)
# -----------------------------------

#resource "google_service_account" "gke_service_account" {
#  account_id   = "gke-security-groups"
#  display_name = "GKE Node Service Account"
#}

resource "google_container_cluster" "mlops_gke_cluster" {
  name     = "mlops-gke-cluster"
  location = var.region
  deletion_protection = false

  initial_node_count = 1  # Free tier setting
  network  = google_compute_network.vpc_network.id
  subnetwork = google_compute_subnetwork.private_subnet.id

  release_channel {
    channel = "REGULAR" # Choose from RAPID, REGULAR, or STABLE
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Enable network policy
  network_policy {
    enabled  = true
    provider = "CALICO" # GKE supports CALICO for network policy
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "10.3.0.0/28"
  }

  # Enable Binary Authorization
  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  #authenticator_groups_config {
  #  security_group = "mlops-service-accounts@ml-mentalhealth.iam.gserviceaccount.com"
  #}

  master_auth {
    client_certificate_config {
      issue_client_certificate = true # Disable client certificate authentication
    }
  }

  node_config {
    machine_type = "e2-small"  # Free tier-eligible
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    service_account = google_service_account.mlops_service_account.email

    workload_metadata_config {
      mode = "GKE_METADATA" # Enable GKE Metadata Server
    }
    # Enable Secure Boot in Shielded Instance Config
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }


  # Add labels to the cluster
  resource_labels = {
    environment = "production"
    team         = "devops"
    project      = var.project_id
  }

  # Enable Master Authorized Networks
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "192.168.1.0/24" # Replace with your trusted network
      display_name = "Office Network"
    }
  }
  # Enable Alias IP ranges
  ip_allocation_policy {
    cluster_secondary_range_name = "pods-range"    # Name of the secondary range for Pods
    services_secondary_range_name = "services-range" # Name of the secondary range for Services
  }

}

# Create a Node Pool for the GKE Cluster
resource "google_container_node_pool" "primary_nodes" {
  name       = "primary-node-pool"
  cluster    = google_container_cluster.mlops_gke_cluster.name
  location   = google_container_cluster.mlops_gke_cluster.location
  initial_node_count = 1

  autoscaling {
    min_node_count = 1
    max_node_count = 1
  }

  node_config {
    machine_type = "e2-medium"
    disk_size_gb = 50
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
  depends_on = [google_service_account.mlops_service_account ]
}


# ------------------------------------
# Build pipeline.json
# Pipeline will include preprocessing (feature store integration), training,
# evaluation, model registration, and deployment steps
# ------------------------------------

resource "null_resource" "generate_pipeline_json" {

  provisioner "local-exec" {
    command = "python3 ../pipelines/pipeline.py"
    working_dir = "${path.module}/../pipelines/"
  }

}

resource "local_file" "pipeline_json" {
  content  = <<EOT
  {
    "key": "value"
  }
  EOT
  filename = "../pipelines/pipeline.json"
}

# ------------------------------------
# Shared Data Storage for Pipeline
# ------------------------------------
resource "google_storage_bucket_object" "pipeline_json" {
  name   = "pipeline.json"
  bucket = google_storage_bucket.mlops_gcs_bucket.name
  source = local_file.pipeline_json.filename

  depends_on = [null_resource.generate_pipeline_json]

}

# --------------------------------------
# CI/CD Pipeline - Automate application deployment
#
# This will be the CI/CD inititiator to build and deploy the Mental Health
# MLOps Flask application. The destination instance will be in a GKE cluster
# that is exposed to the public domain.
# --------------------------------------

# Add a version to the secret (store the actual token value)
resource "google_secret_manager_secret_version" "github_token" {
  secret      = google_secret_manager_secret.github_token.id
  secret_data = var.github_token  # Your GitHub token (mark as sensitive)
}

resource "google_secret_manager_secret" "github_token" {
  secret_id = "github-token"  # Name of the secret in Secret Manager
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_iam_member" "cloudbuild_secret_access" {
  secret_id = google_secret_manager_secret.github_token.id

  role   = "roles/secretmanager.secretAccessor"
  #member = "serviceAccount:cloud-build-editor@ml-mentalhealth.iam.gserviceaccount.com"
  member    = "serviceAccount:service-${var.project_number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
}

# Create a Gen2 connection to GitHub
resource "google_cloudbuildv2_connection" "github_connection" {
  location = var.region  # Must be regional (e.g., "us-central1")
  name     = "github-connection"
  github_config {
    app_installation_id = var.github_app_id
    authorizer_credential {
      oauth_token_secret_version = google_secret_manager_secret_version.github_token.id
    }
  }

  depends_on = [
    google_project_iam_member.mlops_permissions,
    google_secret_manager_secret_iam_member.cloudbuild_secret_access,
    google_secret_manager_secret_version.github_token
  ]
}

# Link a GitHub repository to the connection
resource "google_cloudbuildv2_repository" "ci_cd_repo" {
  name             = "ci-cd-repo"
  location         = "us-central1"
  parent_connection = google_cloudbuildv2_connection.github_connection.id
  remote_uri       = "https://github.com/${var.github_user}/${var.github_repo}.git"
}

# Generate the script to fetch the latest tag
resource "local_file" "get_latest_tag_script" {
  filename = "${path.module}/get_latest_tag.sh"
  content  = <<-EOT
    #!/bin/bash
    # Fetch and sort tags by semantic version, then return the latest
    LATEST_TAG=$(git ls-remote --tags --sort="v:refname" "https://github.com/$1/$2.git" \\
      | awk -F/ '{print \$3}' \\
      | grep -v '{}' \\
      | tail -n1)
    # Output as JSON (required for Terraform external data source)
    echo "{\"result\":\"$LATEST_TAG\"}"
  EOT
  # Set executable permissions (Unix/Linux)
  file_permission = "0755"
}

# Execute the script to get the latest tag
data "external" "latest_tag" {
  program = ["bash", local_file.get_latest_tag_script.filename, var.github_user, var.github_repo]
  depends_on = [local_file.get_latest_tag_script]
}
# Use the fetched tag reference
locals {
  tag_ref = data.external.latest_tag.result.result # e.g., "refs/tags/v0.1.1"
}

resource "google_cloudbuild_trigger" "ci_cd_pipeline" {
  name        = "ci-cd-deployment"
  location    =  var.region
  description = "CI/CD (Gen2) trigger for MLOps deployment from GitHub - with manual trigger support"

  # Gen2-specific configuration
  source_to_build {
    uri       = "https://github.com/${var.github_user}/${var.github_repo}"
    ref       = local.tag_ref # Latest tag (e.g., v0.1.1)
    repo_type = "GITHUB"
  }

  # Substitutions block for manual triggers
  substitutions = {
    _PROJECT_ID = var.project_id
    _IMAGE_TAG  = replace(local.tag_ref, "refs/tags/", "")
  }

  approval_config {
    # Explicitly disable approvals if not used
    approval_required = false
  }

  # Build configuration (inline steps)
  build {
    options {
      substitution_option = "ALLOW_LOOSE"  # Allow substitutions like ${_IMAGE_TAG}
      machine_type        = "N1_HIGHCPU_8" # Same as Gen1
    }

    # Step 1: Build Docker image
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "build",
        "-t", "gcr.io/${var.project_id}/mlops-app:$${_IMAGE_TAG}", # Use substitution
        "--build-arg", "ENV=prod",
        "."
      ]
    }

    # Step 2: Push Docker image to GCR
    step {
      name = "gcr.io/cloud-builders/docker"
      args = ["push", "gcr.io/${var.project_id}/mlops-app:$${_IMAGE_TAG}"]
    }

    # Step 3: Update Kubernetes deployment
    step {
      name = "gcr.io/cloud-builders/kubectl"
      args = [
        "set", "image",
        "deployment/mlops-model-serving",
        "mlops-model=gcr.io/${var.project_id}/mlops-app:$${_IMAGE_TAG}"
      ]
      env  = [
        "CLOUDSDK_COMPUTE_ZONE=${google_container_cluster.mlops_gke_cluster.location}",
        "CLOUDSDK_CONTAINER_CLUSTER=${google_container_cluster.mlops_gke_cluster.name}"
      ]
    }

    # Images to publish
    images = ["gcr.io/${var.project_id}/mlops-app:$${_IMAGE_TAG}"]
  }

  # Service account for kubectl (if needed)
  service_account = google_service_account.mlops_service_account.id

}

# -----------------------------------
# Vertex AI Pipelines
# -----------------------------------

# An executable function is needed to trigger the Vertex AI pipeline.
# Here we use python trigger hosted in a Cloud Function.
# First we need to get this function trigger uploaded to a
# Cloud Storage bucket so the trigger 'trigger_pipeline' can reach
# it and run the program.
# Steps:

# 1. Zip the function source files from the project directory
#    on the development machine. The source files are located in
#    cloud_functions/trigger_pipeline in the project directory.
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

# 3. Create the Cloud Function to trigger the Vertex AI pipeline
#resource "google_vertex_ai_pipeline" "pipeline" {
#  display_name = "mlops-pipeline"
#  template_uri = "gs://path-to-your-pipeline-template"
#}
# Workaround for the not supported (by TF) google_vertex_ai_pipeline"
resource "google_cloudfunctions_function" "trigger_pipeline" {
  name        = "trigger-vertex-pipeline"
  runtime     = "python312"
  entry_point = "trigger_pipeline" # The executable function to run
  source_archive_bucket = google_storage_bucket.mlops_gcs_bucket.name
  source_archive_object = google_storage_bucket_object.trigger_pipeline_zip.name
  trigger_http          = true
  available_memory_mb   = 256
  environment_variables = {
    PROJECT_ID = var.project_id
    REGION     = var.region
    # Set the bucket destination for the executable pipeline trigger
    # python file.
    BUCKET_NAME = google_storage_bucket.mlops_gcs_bucket.name
  }
  ingress_settings = "ALLOW_INTERNAL_AND_GCLB" # Restrict ingress settings

  # Executes uploading the dependencies for the Cloud Function
  depends_on = [google_storage_bucket_object.trigger_pipeline_zip]
}

# -----------------------------------
# Vertex AI Model Registry
# -----------------------------------
#resource "google_vertex_ai_model" "mlops_model_registry" {
#  display_name = "mlops-registered-model"
#  container_spec {
#    image_uri = "gcr.io/path-to-your-prediction-image"
#  }
#}
#resource "google_vertex_ai_model" "model" {
#  display_name = "vertex-trained-model"
#  region       = var.region
#  labels = {
#    environment = "prod"
#  }
#  artifact_uri = google_filestore_instance.filestore.file_shares[0].name
#}
# Workaround for the not supported google_vertex_ai_model"
#resource "google_cloudfunctions_function" "register_model" {
#  name        = "register-vertex-model"
#  runtime     = "python310"
#  entry_point = "register_model"
#  source_archive_bucket = google_storage_bucket.data_storage.name
#  source_archive_object = "functions/register_model.zip"
#  trigger_http          = true
#  available_memory_mb   = 256
#  environment_variables = {
#    PROJECT_ID = var.project_id
#    REGION     = var.region
#  }
#}

# -----------------------------------
# Vertex AI Feature Store
# -----------------------------------
resource "google_vertex_ai_featurestore" "mlops_feature_store" {
  name    = "mlops_feature_store"
  region  = var.region

  depends_on = [google_project_service.enabled_services["aiplatform.googleapis.com"]]
}

# -----------------------------------
# Vertex AI Endpoint
# -----------------------------------
resource "google_vertex_ai_endpoint" "endpoint" {
  name         = "mlops-endpoint"
  display_name = "mlops-endpoint"
  location     = var.region

  depends_on = [google_project_service.enabled_services["aiplatform.googleapis.com"]]
}

#resource "google_vertex_ai_model_deployment" "deployment" {
#  endpoint_id = google_vertex_ai_endpoint.endpoint.id
#  model_id    = google_vertex_ai_model.model.id
#  traffic_split = {
#    "0" = 100
#  }
#}
# Workaround for the not supported google_vertex_ai_model_deployment"
#resource "google_cloudfunctions_function" "deploy_model" {
#  name        = "deploy-vertex-model"
#  runtime     = "python310"
#  entry_point = "deploy_model"
#  source_archive_bucket = google_storage_bucket.data_storage.name
#  source_archive_object = "functions/deploy_model.zip"
#  trigger_http          = true
#  available_memory_mb   = 256
#  environment_variables = {
#    PROJECT_ID = var.project_id
#    REGION     = var.region
#  }
#}

# Poor man's load balancer
#resource "kubernetes_namespace" "mlops_model_namespace" {
#  metadata {
#    name = "mlops-model-namespace"
#  }
#
#  depends_on = [google_container_cluster.mlops_gke_cluster]
#}
#
## Kubernetes Service
#resource "kubernetes_service" "mlops_model_service" {
#  metadata {
#    name      = "mlops-model-service"
#    namespace = kubernetes_namespace.mlops_model_namespace.metadata[0].name
#  }
#  spec {
#    selector = {
#      app = "mlops-model"
#    }
#    type = "LoadBalancer"
#    #type = "NodePort"
#    port {
#      port        = 80
#      target_port = 8080
#      node_port   = 30001
#    }
#  }
#}

# -----------------------------------
# Pub/Sub for Alerts
# -----------------------------------


#resource "google_pubsub_topic" "alerts_topic" {
#  name = "mlops-alerts"
#  #kms_key_name = google_kms_crypto_key.mlops_crypto_key.id
#}

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

#resource "google_vertex_ai_model_monitoring_job" "monitoring_job" {
#  display_name = "mlops-monitoring-job"
#  endpoint     = google_vertex_ai_endpoint.endpoint.id
#}
# Wrorkaround for the not supported google_vertex_ai_model_monitoring_job"
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
        alignment_period    = "60s"
        per_series_aligner  = "ALIGN_MEAN"
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

  ## Prediction latency condition
  #  conditions {
  #  display_name = "Prediction Latency"
  #  condition_threshold {
  #    filter          = "resource.type=\"aiplatform.googleapis.com/Endpoint\" AND metric.type=\"aiplatform.googleapis.com/endpoint/prediction_latency\""
  #    comparison      = "COMPARISON_GT"
  #    threshold_value = 1000
  #    duration        = "60s"

  #    aggregations {
  #      alignment_period    = "60s"
  #      per_series_aligner  = "ALIGN_MEAN"
  #    }
  #  }
  #}

  ## Prediction errors condition
  #conditions {
  #  display_name    = "Prediction Errors"
  #  condition_threshold {
  #    filter          = "resource.type=\"aiplatform.googleapis.com/Model\" AND metric.type=\"cloudml.googleapis.com/endpoint/prediction_error_count\""
  #    comparison      = "COMPARISON_GT"
  #    threshold_value = 50
  #    duration        = "60s"
  #  }
  #}

  ## Drift monitoring condition (example using threshold violations)
  #conditions {
  #  display_name    = "Data Drift Violations"
  #  condition_threshold {
  #    filter          = "resource.type=\"aiplatform.googleapis.com/Model\" AND metric.type=\"cloudml.googleapis.com/endpoint/deployed_model/distance_threshold_violations\""
  #    comparison      = "COMPARISON_GT"
  #    threshold_value = 10
  #    duration        = "300s"
  #  }
  #}

  ## Feature attribution drift condition
  #conditions {
  #  display_name    = "Feature Attribution Drift"
  #  condition_threshold {
  #    filter          = "resource.type=\"aiplatform.googleapis.com/Model\" AND metric.type=\"cloudml.googleapis.com/endpoint/deployed_model/feature_attribution_score_drift\""
  #    comparison      = "COMPARISON_GT"
  #    threshold_value = 0.1
  #    duration        = "300s"
  #  }
  #}
}


