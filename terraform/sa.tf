
# -----------------------------------
# Service Accounts
# -----------------------------------

# Admin Service Account
resource "google_service_account" "mlops_service_account" {
  account_id   = "mlops-service-account"
  display_name = "MLOps Service Account"
}

# Cloud Build Service Account
resource "google_service_account_iam_member" "allow_impersonation" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/cloud-build-editor@ml-mentalhealth.iam.gserviceaccount.com"
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "user:${var.email}"
}

# Docker Authentication Service Account
resource "google_service_account" "docker_auth" {
  account_id   = "docker-auth-sa"
  display_name = "Docker Authentication Service Account"
}

# Docker Authentication Service Account auth key
resource "google_service_account_key" "docker_auth_key" {
  service_account_id = google_service_account.docker_auth.id
  public_key_type    = "TYPE_X509_PEM_FILE"
}

#  Required SA for kubernetes
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

# -----------------------------------
# Enable Required Services
# -----------------------------------

resource "google_project_service" "enabled_services" {
  project                    = var.project_id
  disable_dependent_services = true
  disable_on_destroy         = true

  for_each = toset([
    "containerregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "container.googleapis.com",
    "dataflow.googleapis.com",
    "artifactregistry.googleapis.com",
    "aiplatform.googleapis.com",
    "file.googleapis.com",
    "cloudapis.googleapis.com",
    "servicemanagement.googleapis.com",
    "bigquerystorage.googleapis.com",
    "bigquery.googleapis.com",
    "pubsub.googleapis.com",
    "notebooks.googleapis.com",
    "compute.googleapis.com",
    "cloudfunctions.googleapis.com",
    "run.googleapis.com",
    "iam.googleapis.com",
    "servicenetworking.googleapis.com",
    "serviceusage.googleapis.com"
  ])
  service = each.key

}

