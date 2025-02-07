
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

/*
  Listen to github for new tags, build and deploy the app with the new tag
*/
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


