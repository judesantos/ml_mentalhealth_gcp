
# -----------------------------------
# Kubernetes Deployment
# -----------------------------------

resource "kubernetes_namespace" "mlops_app_namespace" {
  metadata {
    name = "mlops-app-namespace"
  }

  depends_on = [google_container_cluster.mlops_gke_cluster]
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

  depends_on = [google_project_service.enabled_services["compute.googleapis.com"]]
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

