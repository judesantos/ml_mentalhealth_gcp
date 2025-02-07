
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

  depends_on = [google_project_service.enabled_services["container.googleapis.com"]]
}

