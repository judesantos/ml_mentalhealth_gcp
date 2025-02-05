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

