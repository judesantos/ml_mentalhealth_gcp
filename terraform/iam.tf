
# -----------------------------------
# IAM Permissions
# -----------------------------------

/*
Member permissions for the MLOps service account
*/
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
    "roles/cloudfunctions.invoker",
    "roles/bigquery.dataViewer",
    "roles/bigquery.jobUser",
    "roles/bigquery.dataEditor"
  ])
  role = each.key

  member = "serviceAccount:${google_service_account.mlops_service_account.email}"

  depends_on = [google_service_account.mlops_service_account]
}

/*
  Artifact Registry permissions for the MLOps service account
  Requires artifactregistry account memership
*/
resource "google_project_iam_binding" "artifact_registry_access" {
  project = var.project_id

  for_each = toset([
    "roles/artifactregistry.writer",
    "roles/artifactregistry.reader",
  ])
  role = each.key

  members = [
    "serviceAccount:service-${var.project_number}@gcf-admin-robot.iam.gserviceaccount.com",
    "serviceAccount:${var.project_number}@cloudservices.gserviceaccount.com",
  ]
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

  depends_on = [google_project_service.enabled_services["compute.googleapis.com"]]
}

/*
  Cloubuild service account member access
*/
resource "google_project_iam_member" "cloudbuild_secret_access" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:cloud-build-editor@ml-mentalhealth.iam.gserviceaccount.com"
}

/*
  Cloubuild secret manager access
*/
resource "google_secret_manager_secret_iam_member" "cloudbuild_secret_access" {
  secret_id = google_secret_manager_secret.github_token.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:service-${var.project_number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "cloudfunctions_service_account" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${var.project_id}@appspot.gserviceaccount.com"
}

# Public access to the cloud function trigger_pipeline
resource "google_cloudfunctions_function_iam_member" "invoker" {
  project        = google_cloudfunctions_function.trigger_pipeline.project
  region         = google_cloudfunctions_function.trigger_pipeline.region
  cloud_function = google_cloudfunctions_function.trigger_pipeline.name

  role   = "roles/cloudfunctions.invoker"
  member = "allUsers"
}