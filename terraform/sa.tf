
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

resource "google_service_account" "gcf_admin_robot" {
  account_id   = "gcf-admin-robot"
  display_name = "GCF Admin Robot"
  project      = var.project_id
}

# -----------------------------------
# Enable Required Services
# -----------------------------------

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

}

resource "google_project_service" "notebooks" {
  project                    = var.project_id
  service                    = "notebooks.googleapis.com"
  disable_dependent_services = true
  disable_on_destroy         = true
  depends_on                 = [google_project_service.compute]
}

resource "google_project_service" "cloudfunctions" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "aiplatform.googleapis.com",
    "run.googleapis.com",
    "iam.googleapis.com"
  ])
  project = var.project_id
  service = each.key

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

/*
  Enable the required services for kubernetes
*/
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

