
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

  depends_on = [google_project_service.compute]
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
