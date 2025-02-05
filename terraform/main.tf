provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_client_config" "provider" {}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.mlops_gke_cluster.endpoint}"
  token                  = data.google_client_config.provider.access_token
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
  project = var.project_id

  for_each = toset([
    "roles/owner",
    "roles/editor",
    "roles/serviceusage.serviceUsageAdmin",
    "roles/compute.securityAdmin",
    "roles/cloudkms.admin",
    "roles/container.admin",
    "roles/container.clusterAdmin",
    "roles/container.nodeServiceAccount",
    "roles/cloudbuild.builds.editor",
    "roles/cloudbuild.builds.builder",
    "roles/cloudbuild.builds.viewer",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/resourcemanager.projectIamAdmin",
    "roles/container.developer",
    "roles/storage.admin",
    "roles/storage.objectViewer",
    "roles/storage.objectAdmin",
    "roles/secretmanager.secretAccessor",
    "roles/cloudsql.client",
    "roles/cloudsql.admin",
  ])
  role = each.key

  member = "serviceAccount:${google_service_account.mlops_service_account.email}"

  depends_on = [google_service_account.mlops_service_account]
}

resource "google_service_account_iam_member" "allow_impersonation" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/cloud-build-editor@ml-mentalhealth.iam.gserviceaccount.com"
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "user:${var.email}"
}

# Create Service Account
resource "google_service_account" "docker_auth" {
  account_id   = "docker-auth-sa"
  display_name = "Docker Authentication Service Account"
}

# Create Service Account Key
resource "google_service_account_key" "docker_auth_key" {
  service_account_id = google_service_account.docker_auth.id
  public_key_type    = "TYPE_X509_PEM_FILE"
}

# Grant Permissions for Service Account
resource "google_project_iam_member" "artifact_registry_access" {
  project = var.project_id

  for_each = toset([
    "roles/artifactregistry.writer",
    "roles/artifactregistry.reader",
  ])
  role = each.key

  member = "serviceAccount:service-${var.project_number}@gcf-admin-robot.iam.gserviceaccount.com"

  depends_on = [google_service_account.mlops_service_account]
}

/*
  Login to Docker Registry for the mlop_app deployment in GKE cluster -
  Pushes the image to GCR then pulls it in the GKE cluster
*/
resource "null_resource" "docker_auth" {
  provisioner "local-exec" {
    command = "echo '${base64decode(google_service_account_key.docker_auth_key.private_key)}' | docker login -u _json_key --password-stdin https://gcr.io"
  }
}

# -----------------------------------
# Secret Manager for GitHub Token
# -----------------------------------

resource "google_secret_manager_secret" "github_token" {
  secret_id = "github-token" # Name of the secret in Secret Manager
  replication {
    auto {}
  }
}

# Add a version to the secret (store the actual token value)
resource "google_secret_manager_secret_version" "github_token" {
  secret      = google_secret_manager_secret.github_token.id
  secret_data = var.github_token # Your GitHub token (mark as sensitive)
}

/*
  The service account serviceAccount:service-416879185829@g* is somehow
  expected by cloud build, we need to create it and give it the necessary
  permissions for the github connection to work.
*/
resource "google_secret_manager_secret_iam_member" "github_token_accessor" {
  secret_id = "github-token"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:service-416879185829@gcp-sa-cloudbuild.iam.gserviceaccount.com"

  depends_on = [ google_project_service.compute ]
}

resource "google_project_iam_member" "cloudbuild_secret_access" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:cloud-build-editor@ml-mentalhealth.iam.gserviceaccount.com"
}

resource "google_secret_manager_secret_iam_member" "cloudbuild_secret_access" {
  secret_id = google_secret_manager_secret.github_token.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:service-${var.project_number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
}

# -----------------------------------
# Enable Required Services
# -----------------------------------

resource "google_project_service" "iam" {
  service = "iam.googleapis.com"
  project = var.project_id
}

resource "google_project_service" "serviceusage" {
  project                    = var.project_id
  service                    = "serviceusage.googleapis.com"
  disable_dependent_services = true
  disable_on_destroy         = true
}

resource "google_project_service" "compute" {
  project                    = var.project_id
  service                    = "compute.googleapis.com"
  disable_dependent_services = true
  disable_on_destroy         = true

  depends_on = [google_project_service.serviceusage]
}

resource "google_project_service" "notebooks" {
  project                    = var.project_id
  service                    = "notebooks.googleapis.com"
  disable_dependent_services = true
  disable_on_destroy         = true
  depends_on                 = [google_project_service.compute]
}

resource "google_project_service" "cloudfunctions" {
  project                    = var.project_id
  service                    = "cloudfunctions.googleapis.com"
  disable_dependent_services = true
  disable_on_destroy         = true
}

resource "google_project_service" "pubsub" {
  project                    = var.project_id
  service                    = "pubsub.googleapis.com"
  disable_dependent_services = true
  disable_on_destroy         = true
  depends_on                 = [google_project_service.cloudfunctions]
}

resource "google_project_service" "bigquery" {
  project                    = var.project_id
  service                    = "bigquery.googleapis.com"
  disable_dependent_services = true
  disable_on_destroy         = true
}

resource "google_project_service" "bigquerystorage" {
  project                    = var.project_id
  service                    = "bigquerystorage.googleapis.com"
  disable_dependent_services = true
  disable_on_destroy         = true
  depends_on                 = [google_project_service.bigquery]
}

resource "google_project_service" "servicemanagement" {
  project                    = var.project_id
  service                    = "servicemanagement.googleapis.com"
  disable_dependent_services = true
  disable_on_destroy         = true
}

resource "google_project_service" "cloudapis" {
  project                    = var.project_id
  service                    = "cloudapis.googleapis.com"
  disable_dependent_services = true
  disable_on_destroy         = true

  depends_on = [
    google_project_service.compute,
    google_project_service.bigquery,
    google_project_service.serviceusage,
    google_project_service.servicemanagement
  ]
}

resource "google_project_service" "enabled_services" {
  project                    = var.project_id
  disable_dependent_services = true
  disable_on_destroy         = true

  for_each = toset([
    "containerregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "aiplatform.googleapis.com",
    "container.googleapis.com",
    "dataflow.googleapis.com",
    "artifactregistry.googleapis.com",
    "aiplatform.googleapis.com",
    "file.googleapis.com",
  ])
  service = each.key

  depends_on = [
    google_project_service.iam,
    google_project_service.notebooks,
    google_project_service.pubsub,
    google_project_service.bigquerystorage,
    google_project_service.cloudapis
  ]
}

# -----------------------------------
# VPC and Subnets
# -----------------------------------

resource "google_compute_network" "mlops_vpc_network" {
  name                    = "mlops-vpc-network"
  project                 = var.project_id
  auto_create_subnetworks = false

  depends_on = [
    google_project_service.compute
  ]
}

resource "google_compute_subnetwork" "public_subnet" {
  name          = "mlops-public-subnet"
  region        = var.region
  network       = google_compute_network.mlops_vpc_network.id
  ip_cidr_range = "10.0.1.0/24"

}

resource "google_compute_subnetwork" "private_subnet" {
  name    = "mlops-private-subnet"
  region  = var.region
  network = google_compute_network.mlops_vpc_network.id

  ip_cidr_range            = "10.0.2.0/24"
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods-range"
    ip_cidr_range = "10.20.0.0/20" # Allocates IPs for GKE Pods
  }

  secondary_ip_range {
    range_name    = "services-range"
    ip_cidr_range = "10.20.16.0/20" # Allocates IPs for GKE Services
  }
}

# -----------------------------------
# NAT Router
# -----------------------------------

resource "google_compute_router" "nat_router" {
  name    = "mlops-nat-router"
  network = google_compute_network.mlops_vpc_network.name
  region  = var.region
}

resource "google_compute_router_nat" "nat_config" {
  name                               = "mlops-nat-config"
  router                             = google_compute_router.nat_router.name
  region                             = google_compute_router.nat_router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# -----------------------------------
# Firewall Rules
# -----------------------------------

resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal"
  network = google_compute_network.mlops_vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"] # all ports inside the vpc
  }

  source_ranges = ["10.0.0.0/16"] # Internal network
}

resource "google_compute_firewall" "allow_external" {
  name    = "allow-external"
  network = google_compute_network.mlops_vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  source_ranges = ["0.0.0.0/0"]
  direction     = "INGRESS"

  priority = 1000 # Lower number the higher the priority
}

# Office network access to the Kubernetes API
resource "google_compute_firewall" "allow_k8s_api" {
  name    = "allow-k8s-api"
  network = google_compute_network.mlops_vpc_network.name

  direction = "INGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  #target_tags   = ["private-subnet"]
  source_ranges = ["192.168.1.0/24"] # Allow the office network
  description   = "Allow Kubernetes API access from office network"
}

# This rule allows egress traffic from GKE to the internet on port 443
resource "google_compute_firewall" "allow_egress_to_api" {
  name    = "allow-egress-to-api"
  network = google_compute_network.mlops_vpc_network.name

  direction = "EGRESS"
  priority  = 1000

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
  destination_ranges = ["0.0.0.0/0"] # Allow egress to any destination
}

# This rule allows HTTPS traffic from the Load Balancer to the GKE pods
resource "google_compute_firewall" "allow_lb_to_gke" {
  name        = "allow-lb-to-gke"
  description = "Allow HTTPS traffic from Load Balancer to GKE"

  direction = "INGRESS"
  priority  = 900 # Higher priority than default rules
  network   = google_compute_network.mlops_vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["443"] # Allow HTTPS traffic to GKE pods
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"] # GCP Load Balancer IP ranges
  # Allow ingress to all GKE nodes in the VPC
  destination_ranges = [
    "10.0.2.0/24",  # GKE Subnet (private subnet)
    "10.20.0.0/20", # GKE Pods CIDR
    "10.20.16.0/20" # GKE Services CIDR
  ]
}

# -----------------------------------
# Cloud Armor Security Policy
# -----------------------------------

# Public load balancer protection.
resource "google_compute_security_policy" "cloud_armor" {
  project = var.project_id

  name        = "cloud-armor"
  description = "Cloud Armor security policy"

  # Security policy - blocks traffic from specific countries
  rule {
    action   = "deny(403)"
    priority = 1000
    match {
      expr {
        expression = "origin.region_code == 'CN' || origin.region_code == 'RU'"
      }
    }
    description = "Block traffic from listed countries"
  }

  # Security policy - blocks common OWASP threats:
  #   XSS, SQLi, and other web based attacks
  #rule {
  #  action   = "deny(403)"
  #  priority = 500
  #  match {
  #    expr {
  #      expression = "evaluatePreconfiguredWaf(\"owasp-crs-v030001-high\")"
  #    }
  #  }
  #  description = "Block common OWASP threats"
  #}

  # Security policy - prevent DDoS attacks
  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable = true
    }
  }

  # Default allow rule for all other traffic
  rule {
    action   = "allow"
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow rule"
  }

  depends_on = [
    google_project_iam_member.mlops_permissions,
    google_project_service.compute,
  ]
}

# -----------------------------------
# Load Balancer
# -----------------------------------

# Public subnet load balancer - The gateway to the VPC private subnet
resource "google_compute_url_map" "url_map" {
  name = "multi-backend-url-map"

  default_service = google_compute_backend_service.mlops_app_backend.self_link

  host_rule {
    hosts        = ["*"] # Match all hosts, or specify a specific host like "example.com"
    path_matcher = "mlops-app"
  }

  path_matcher {
    name            = "mlops-app"
    default_service = google_compute_backend_service.mlops_app_backend.self_link

    # Separate path rules for different services
    path_rule {
      paths   = ["/*"]
      service = google_compute_backend_service.mlops_app_backend.self_link
    }
    # TODO: Add vertex AI endpoint path rules here
  }
}

# Load balancer public IP address for incoming traffic
resource "google_compute_global_address" "default" {
  name         = "mlops-global-ip"
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
  depends_on   = [google_project_service.enabled_services]
}

# TODO: Looks like this is not used. Remove if not needed
# Load balancer private IP address for internal traffic
resource "google_compute_address" "load_balancer_ip" {
  name         = "load-balancer-ip"
  project      = var.project_id
  region       = var.region
  address_type = "INTERNAL"
  subnetwork   = google_compute_subnetwork.public_subnet.name
}

/*
  Custom domain SSL certificate - Why we need a global forwarding rule:
  - The public-facing load balancer must terminate HTTPS connections.
  - GCP Load Balancers do not automatically generate SSL certificates
      (unless using a Managed SSL Certificate, i.e.: Using google domains).
  - Using our own custom domain and TLS certificate,
      we provide our own SSL certificate.
*/
resource "google_compute_ssl_certificate" "ml_ops_ssl_certificate" {
  name        = "mlops-ssl-certificate"
  private_key = file("../certs/app_private_key.pem")
  certificate = file("../certs/app_certificate.pem")

  depends_on = [ google_project_service.compute ]
}

/*
  The Global Load Balancer uses a proxy to handle HTTPS traffic.
  The proxy terminates HTTPS connections (decrypts SSL) before forwarding
  traffic to backend services (GKE, Vertex AI, etc.).
  It links the SSL certificate and the URL map (which defines how traffic
  is routed to backends).
  Without this, the load balancer would not be able to serve HTTPS traffic.
*/
resource "google_compute_target_https_proxy" "https_proxy" {
  name             = "https-proxy"
  url_map          = google_compute_url_map.url_map.self_link
  ssl_certificates = [google_compute_ssl_certificate.ml_ops_ssl_certificate.self_link]
}

/*
  This is what actually assigns the public IP to the Load Balancer.
  It listens for incoming traffic on port 443 (HTTPS).
  It forwards traffic to the HTTPS proxy (google_compute_target_https_proxy).
  Without this, the load balancer can not receive external requests.
*/
resource "google_compute_global_forwarding_rule" "https_forwarding_rule" {
  name        = "https-forwarding-rule"
  port_range  = "443"
  ip_protocol = "TCP"

  target     = google_compute_target_https_proxy.https_proxy.self_link
  ip_address = google_compute_global_address.default.address
}

# -----------------------------------
# GKE Deployment Cluster
# -----------------------------------

# The GKE cluster
resource "google_container_cluster" "mlops_gke_cluster" {
  name     = "mlops-gke-cluster"
  project  = var.project_id
  location = var.region # zonal cluster - create one node only

  enable_autopilot    = true
  deletion_protection = false
  networking_mode     = "VPC_NATIVE" # Ensure GKE is in the private subnetwork

  initial_node_count = 1 # Free tier setting
  network            = google_compute_network.mlops_vpc_network.id
  subnetwork         = google_compute_subnetwork.private_subnet.id

  lifecycle {
    ignore_changes = [
      node_locations,     # Ignore changes to the node_locations block
      addons_config,      # Ignore changes to the addons_config block
      node_config,        # Ignore changes to the node_config block
      initial_node_count, # Ignore changes to the initial_node_count block
      network,            # Ignore changes to the network block
      subnetwork,         # Ignore changes to the subnetwork block
    ]
  }
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods-range"
    services_secondary_range_name = "services-range"
  }

  private_cluster_config { # Ensures the cluster is private
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  addons_config {
    http_load_balancing {
      disabled = false # Enable HTTP load balancing for frontend
    }
  }
  node_config {
    service_account = google_service_account.mlops_service_account.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  depends_on = [ google_project_service.enabled_services["container.googleapis.com"] ]
}

# --------------------------------------
# Automate application deployment
#
# The following entries will be resources to build and deploy the Mental Health
# MLOps Flask application.
# Aside from creating a docker image for the app, the deployment also updates
# the destination instance in a GKE cluster that serves the public domain.
# --------------------------------------

/*
  We need a repository to store the Docker image
  Note: GCR (Container Registry) is now called Artifact Registry
*/
resource "google_artifact_registry_repository" "mlops_repo" {
  provider      = google
  project       = var.project_id
  location      = var.region
  repository_id = "mlops-repo"
  description   = "MLOps Docker Repository"
  format        = "DOCKER"

  depends_on = [google_project_service.enabled_services["artifactregistry.googleapis.com"]]
}

# Create a Gen2 connection to GitHub
resource "google_cloudbuildv2_connection" "github_connection" {
  location = var.region # Must be regional (e.g., "us-central1")
  name     = "github-connection"

  github_config {
    app_installation_id = var.github_app_id
    authorizer_credential {
      oauth_token_secret_version = google_secret_manager_secret_version.github_token.id
    }
  }

  lifecycle {
    ignore_changes = all
  }

  depends_on = [
    google_project_service.enabled_services["cloudbuild.googleapis.com"],
    google_secret_manager_secret_version.github_token,
    google_project_iam_member.mlops_permissions,
    google_secret_manager_secret_iam_member.cloudbuild_secret_access,
  ]
}

# Link a GitHub repository to the connection
resource "google_cloudbuildv2_repository" "mlops_app_repo" {
  name              = "mlops-app-repo"
  location          = "us-central1"
  parent_connection = google_cloudbuildv2_connection.github_connection.id
  remote_uri        = "https://github.com/${var.github_user}/${var.github_repo}.git"

  lifecycle {
    ignore_changes = all
  }
}

# Generate the script to fetch the latest git tag
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
  program    = ["bash", local_file.get_latest_tag_script.filename, var.github_user, var.github_repo]
  depends_on = [local_file.get_latest_tag_script]
}
# Use the fetched tag reference
locals {
  tag_ref = data.external.latest_tag.result.result # e.g., "refs/tags/v0.1.1"
}

# Listen to github for new tags, build and deploy the app with the new tag
resource "google_cloudbuild_trigger" "mlops_app_github_trigger" {
  name        = "mlops-app-github-trigger"
  location    = var.region
  description = "Trigger for MLOps deployment from GitHub - listen for new tags"

  # Gen2-specific configuration
  source_to_build {
    uri       = google_cloudbuildv2_repository.mlops_app_repo.id
    ref       = local.tag_ref # Latest tag (e.g., v0.1.1)
    repo_type = "GITHUB"
  }

  # Substitutions block for manual triggers
  substitutions = {
    _IMAGE_TAG = replace(local.tag_ref, "refs/tags/", "")
  }

  approval_config {
    # Explicitly disable approvals if not used
    approval_required = false
  }

  # Build configuration (inline steps)
  build {
    options {
      #logging = "CLOUD_LOGGING_ONLY"
      substitution_option = "ALLOW_LOOSE"  # Allow substitutions like ${_IMAGE_TAG}
      machine_type        = "N1_HIGHCPU_8" # Same as Gen1
    }
    # Add logs bucket to store build logs
    logs_bucket = "gs://mlops-gcs-bucket/cloud-build-logs/"

    # Step 1: Build Docker image
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "build",
        "-t", "${var.region}-docker.pkg.dev/${var.project_id}/mlops-repo/mlops-app:$${_IMAGE_TAG}", # Use Artifact Registry format
        "--build-arg", "ENV=prod",
        "."
      ]
      wait_for = ["-"] # Wait for the build step to finish
    }
    # Step 2: Push Docker image to GCR
    step {
      name     = "gcr.io/cloud-builders/docker"
      args     = ["push", "${var.region}-docker.pkg.dev/${var.project_id}/mlops-repo/mlops-app:$${_IMAGE_TAG}"]
      wait_for = ["-"] # Wait for the build step to finish
    }
    # Step 3: Update Kubernetes deployment
    step {
      name = "gcr.io/cloud-builders/kubectl"
      args = [
        "set", "image",
        "deployment/mlops-app-serving",
        "mlops-app=${var.region}-docker.pkg.dev/${var.project_id}/mlops-repo/mlops-app:$${_IMAGE_TAG}"
      ]
      env = [
        "CLOUDSDK_COMPUTE_ZONE=${google_container_cluster.mlops_gke_cluster.location}",
        "CLOUDSDK_CONTAINER_CLUSTER=${google_container_cluster.mlops_gke_cluster.name}"
      ]
      wait_for = ["-"] # Wait for the push step to succeed
    }
    # Images to publish
    images = ["${var.region}-docker.pkg.dev/${var.project_id}/mlops-repo/mlops-app:$${_IMAGE_TAG}"]
  }

  # Service account for kubectl (if needed)
  service_account = google_service_account.mlops_service_account.id
}

/*
  Run on terraform apply - Build and deploy the app with a given tag version.
  Conditions:
    Check if a variable tag value is provided;
    Check if the image for the given tag does not already exist in GCR
  NOTE: This may conflict with the GitHub trigger, 'mlops_app_github_trigger'.
        Use only when retrying a failed deployment, or when the VPC is
        created for the first time and a tag is provided in the variables.
*/
resource "null_resource" "mlops_app_docker_build" {
  provisioner "local-exec" {
    command     = <<EOT
      #!/bin/bash
      set -e
      # Set the image ID according to GCP artifact registry format
      IMAGE_ID=${var.region}-docker.pkg.dev/${var.project_id}/mlops-repo/mlops-app:${var.image_tag}
      rm -rf repo # Remove the repo if it exists

      # Clone the GitHub repository with the given tag
      git clone --branch ${var.image_tag} --depth 1 ${google_cloudbuildv2_repository.mlops_app_repo.remote_uri} repo

      # Get the absolute path of the .env file and cert folder
      ENV_FILE_PATH=$(realpath "${var.env_file}")
      CERT_FOLDER_PATH=$(realpath "${var.cert}")

      # Copy the .env file from the local system to the cloned repository
      if [ -f "$ENV_FILE_PATH" ]; then
        cp "$ENV_FILE_PATH" ./repo/.env
      else
        echo "Error: .env file not found at $ENV_FILE_PATH"
        exit 1
      fi

      # Copy the cert folder if it exists
      if [ -d "$CERT_FOLDER_PATH" ]; then
        cp -r "$CERT_FOLDER_PATH" ./repo/certs
      else
        echo "Error: cert folder not found at $CERT_FOLDER_PATH"
        exit 1
      fi

      # Go to the docker build directory
      cd repo

      # Clean up the Docker builder cache
      docker builder prune --all

      # Build the Docker image according to GCP platform specifications
      DOCKER_BUILDKIT=1 docker build --platform=linux/amd64 -t $IMAGE_ID .

      # Push the Docker image to GCR
      docker push $IMAGE_ID

      # Clean up
      rm -rf repo

    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

# -----------------------------------
# Kubernetes Deployment
# -----------------------------------

resource "kubernetes_namespace" "mlops_app_namespace" {
  metadata {
    name = "mlops-app-namespace"
  }

  depends_on = [google_container_cluster.mlops_gke_cluster]
}

resource "kubernetes_service_account" "mlops_k8s_sa" {
  metadata {
    name      = "mlops-k8s-sa"
    namespace = kubernetes_namespace.mlops_app_namespace.metadata[0].name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.mlops_service_account.email
    }
  }

  depends_on = [google_service_account.mlops_service_account]
}

/*
  Resolves Issue: Workload Identity Not Applied (Empty IAM Policy)
  Requres the specific role to be assigned to the service account used
  specifically for GKE clusters.
 */
resource "google_service_account_iam_binding" "mlops_workload_identity" {
  service_account_id = google_service_account.mlops_service_account.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[mlops-app-namespace/mlops-k8s-sa]"
  ]
}

# The GKE cluster metadata
data "google_container_cluster" "mlops_gke_cluster" {
  name     = google_container_cluster.mlops_gke_cluster.name
  location = google_container_cluster.mlops_gke_cluster.location
  project  = google_container_cluster.mlops_gke_cluster.project

  depends_on = [google_container_cluster.mlops_gke_cluster]
}

data "google_compute_zones" "available_zones" {
  project = var.project_id
  region  = data.google_container_cluster.mlops_gke_cluster.location

  depends_on = [google_project_service.compute]
}

# Kubernetes Frontend Service
resource "kubernetes_service" "mlops_app_service" {
  metadata {
    name      = "mlops-app-service"
    namespace = kubernetes_namespace.mlops_app_namespace.metadata[0].name
    annotations = {
      "cloud.google.com/load-balancer-type" = "External"
    }
  }
  spec {
    selector = {
      app = "mlops-app"
    }
    type = "LoadBalancer"
    port {
      protocol    = "TCP"
      port        = 443 # public
      target_port = 443 # Internal container port
    }
  }
}

data "kubernetes_service" "mlops_app_service" {
  metadata {
    name      = kubernetes_service.mlops_app_service.metadata[0].name
    namespace = kubernetes_namespace.mlops_app_namespace.metadata[0].name
  }
  depends_on = [kubernetes_service.mlops_app_service]
}

locals {
  neg_annotations = jsondecode(
    lookup(
      data.kubernetes_service.mlops_app_service.metadata[0].annotations != null ? data.kubernetes_service.mlops_app_service.metadata[0].annotations : {},
      "cloud.google.com/neg-status",
      "{}"
    )
  )
}

data "google_compute_network_endpoint_group" "neg" {
  for_each = can(jsondecode(lookup(data.kubernetes_service.mlops_app_service.metadata[0].annotations, "cloud.google.com/neg-status", "{}"))["network_endpoint_groups"]["8080"]) ? toset(data.google_compute_zones.available_zones.names) : []
  name     = local.neg_annotations["network_endpoint_groups"]["8080"]
  zone     = each.key
  project  = var.project_id
}

# Kubernetes Backend Deployment specs
resource "google_compute_backend_service" "mlops_app_backend" {
  name                  = "service-a-backend"
  description           = "Backend for kubernetes service"
  protocol              = "HTTPS"
  port_name             = "https"
  load_balancing_scheme = "EXTERNAL"

  dynamic "backend" {
    for_each = data.google_compute_network_endpoint_group.neg
    content {
      group = backend.value.self_link
    }
  }

  # Attach Cloud Armor
  security_policy = google_compute_security_policy.cloud_armor.id
}

# Kubernetes Frontend Deployment specs
resource "kubernetes_deployment" "mlops_app" {
  metadata {
    name      = "mlops-app-serving"
    namespace = kubernetes_namespace.mlops_app_namespace.metadata[0].name
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "mlops-app"
      }
    }
    template {
      metadata {
        labels = {
          app = "mlops-app"
        }
      }
      spec {
        service_account_name = kubernetes_service_account.mlops_k8s_sa.metadata[0].name

        container {
          name  = "mlops-app"
          image = "${var.region}-docker.pkg.dev/${var.project_id}/mlops-repo/mlops-app:${var.image_tag}"
          port {
            container_port = 443
          }
          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }
          env {
            name = "DATABASE_URL"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.mlops_app_secret.metadata[0].name
                key  = "DATABASE_URL"
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    google_sql_database.pg_database,
    null_resource.mlops_app_docker_build,
    kubernetes_service_account.mlops_k8s_sa
  ]
}

/*
  Vertex AI Related Resources follows
*/

# -----------------------------------
# Cloud Storage (GCS) for Data Storage
# -----------------------------------

resource "google_storage_bucket" "mlops_gcs_bucket" {
  name          = "mlops-gcs-bucket"
  location      = var.region
  force_destroy = true # Destroy all objects when bucket is destroyed

  logging {
    log_bucket        = "google_storage_bucket.log_bucket"
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

  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_iam_member" "gcs_uploader" {
  bucket = google_storage_bucket.mlops_gcs_bucket.name
  role   = "roles/storage.objectCreator" # Allows file uploads
  member = "serviceAccount:${google_service_account.mlops_service_account.email}"
}


# GCS Backend Service
resource "google_compute_backend_bucket" "gcs_backend" {
  name        = "gcs-backend-bucket"
  bucket_name = google_storage_bucket.mlops_gcs_bucket.name

  depends_on = [ google_project_service.compute ]
}

/*
  Build pipeline.json
  Pipeline will include preprocessing (feature store integration), training,
  evaluation, model registration, and deployment steps
*/
resource "null_resource" "generate_pipeline_json" {
  provisioner "local-exec" {
    command     = "python3 ../pipelines/pipeline.py"
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
    name  = string
    type  = string
    mode = string
  }))
  default = [
    {"name": "poorhlth", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "physhlth", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "genhlth", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "diffwalk", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "diffalon", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "checkup1", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "diffdres", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "addepev3", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "acedeprs", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "sdlonely", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "lsatisfy", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "emtsuprt", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "decide", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "cdsocia1", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "cddiscu1", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "cimemlo1", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "smokday2", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "alcday4", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "marijan1", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "exeroft1", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "usenow3", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "firearm5", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "income3", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "educa", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "employ1", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "sex", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "marital", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "adult", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "rrclass3", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "qstlang", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "_state", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "veteran3", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "medcost1", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "sdhbills", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "sdhemply", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "sdhfood1", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "sdhstre1", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "sdhutils", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "sdhtrnsp", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "cdhous1", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "foodstmp", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "pregnant", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "asthnow", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "havarth4", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "chcscnc1", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "chcocnc1", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "diabete4", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "chccopd3", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "cholchk3", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "bpmeds1", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "bphigh6", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "cvdstrk3", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "cvdcrhd4", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "chckdny2", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "cholmed3", "type": "INTEGER", "mode": "REQUIRED"},
    {"name": "_ment14d", "type": "INTEGER", "mode": "REQUIRED"}
  ]
}

/*
  Define 2 entities for the feature store:
    One for training data, and one for inference data
*/

# 1. Training Data Entity using the Vertex AI Feature Store schema
resource "google_vertex_ai_featurestore_entitytype" "training_data" {
  name            = "training_data"
  description     = "Entity for training data"

  featurestore = google_vertex_ai_featurestore.mlops_feature_store.id

  depends_on = [google_vertex_ai_featurestore.mlops_feature_store]
}

# Historical Features
resource "google_vertex_ai_featurestore_entitytype_feature" "historical_features" {
  for_each = { for feature in var.mlops__data_features : feature.name => feature }
  entitytype   = google_vertex_ai_featurestore_entitytype.training_data.id
  value_type   = each.value.type == "INTEGER" ? "INT64" : each.value.type
  name         = each.value.name

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
  dataset_id  = "vertex_ai_featurestore"
  project     = var.project_id
  location    = var.region
  depends_on = [google_project_service.bigquery]
}

resource "google_bigquery_table" "inference" {

  table_id   = "inference_data"
  project    = var.project_id

  dataset_id = google_bigquery_dataset.featurestore_dataset.dataset_id

  schema = jsonencode(
    concat(
      [{ "name": "id", "type": "INTEGER", "mode": "REQUIRED" }],
      [for item in var.mlops__data_features : { "name": item.name, "type": item.type, "mode": item.mode }]
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

# -----------------------------------
# PgSQL Database
# -----------------------------------

resource "google_compute_global_address" "private_ip_alloc" {
  name          = "private-ip-alloc"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  network       = google_compute_network.mlops_vpc_network.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.mlops_vpc_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_alloc.name]

  lifecycle {
    ignore_changes = all
  }

  depends_on = [ google_compute_global_address.private_ip_alloc ]
}

# Create Cloud SQL PostgreSQL Instance
resource "google_sql_database_instance" "pg_instance" {
  name                = "pg-instance"
  database_version    = "POSTGRES_14"
  region              = var.region
  deletion_protection = false

  settings {
    tier            = "db-f1-micro" # Adjust as needed
    disk_size       = 10
    disk_autoresize = false

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.mlops_vpc_network.id
    }

    backup_configuration {
      enabled = false
    }
  }

  depends_on = [google_service_networking_connection.private_vpc_connection]
}

# Create PostgreSQL Database
resource "google_sql_database" "pg_database" {
  name     = "pg-database"
  instance = google_sql_database_instance.pg_instance.name
}

# Create PostgreSQL User (Secure via Secret Manager)
resource "google_sql_user" "pg_user" {
  name     = var.pgsql_user
  instance = google_sql_database_instance.pg_instance.name
  password = var.pgsql_password # Store in Secret Manager instead

  depends_on = [
    google_sql_database.pg_database,
    google_project_service.enabled_services
  ]
}

# Create the SQL DB instance
data "google_sql_database_instance" "pg_instance" {
  name = google_sql_database_instance.pg_instance.name
}

# Provide the database URL as a secret
resource "kubernetes_secret" "mlops_app_secret" {
  metadata {
    name      = "mlops-app-secret"
    namespace = kubernetes_namespace.mlops_app_namespace.metadata[0].name
  }
  data = {
    DATABASE_URL = "postgresql://${var.pgsql_user}:${var.pgsql_password}@${data.google_sql_database_instance.pg_instance.private_ip_address}:5432/pg-database"
  }
}
