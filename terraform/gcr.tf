
# ------------------------------------------------
# Google Artifact Registry (GCR) for Docker Images
# ------------------------------------------------

resource "google_artifact_registry_repository" "mlops_repo" {
  provider      = google
  project       = var.project_id
  location      = var.region
  repository_id = "mlops-repo"
  description   = "MLOps Docker Repository"
  format        = "DOCKER"

  lifecycle {
    prevent_destroy = false
  }

  depends_on = [google_project_service.enabled_services["artifactregistry.googleapis.com"]]
}
