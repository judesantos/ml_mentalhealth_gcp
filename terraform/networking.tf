
# -----------------------------------
# VPC and Subnets
# -----------------------------------

resource "google_compute_network" "mlops_vpc_network" {
  name                    = "mlops-vpc-network"
  project                 = var.project_id
  auto_create_subnetworks = false

  depends_on = [
    google_project_service.enabled_services["compute.googleapis.com"]
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
    google_project_service.enabled_services["compute.googleapis.com"],
    google_project_iam_member.mlops_permissions,
  ]
}

# -----------------------------------
# Load Balancer
# -----------------------------------

# Public subnet load balancer - The gateway to the VPC private subnet
resource "google_compute_url_map" "url_map" {
  name = "multi-backend-url-map"

  # Reply with a 404 error if no path is matched
  default_service = google_compute_backend_service.error_backend.id

  host_rule {
    hosts        = ["*"] # Match all hosts, or specify a specific host like "example.com"
    path_matcher = "mlops-app"
  }

  path_matcher {
    name            = "mlops-app"
    default_service = google_compute_backend_service.error_backend.id

    # Separate path rules for different services
    path_rule {
      paths   = ["/app/*"]
      service = google_compute_backend_service.mlops_app_backend.id
    }
    path_rule {
      paths   = ["/vertexai/*"]
      service = google_compute_backend_service.vertexai_backend.id
    }
  }

  depends_on = [google_project_service.enabled_services["compute.googleapis.com"]]
}

# 404 error backend service for unmatched paths
resource "google_compute_backend_service" "error_backend" {
  name                  = "error-backend"
  load_balancing_scheme = "EXTERNAL"
  protocol              = "HTTP"
  health_checks         = [google_compute_health_check.error_check.id]
}

resource "google_compute_health_check" "error_check" {
  name = "error-health-check"
  http_health_check {
    port = 9999 # Fake port that doesn't respond
  }
}

# Load balancer public IP address for incoming traffic
resource "google_compute_global_address" "default" {
  name         = "mlops-global-ip"
  address_type = "EXTERNAL"
  ip_version   = "IPV4"

  depends_on = [google_project_service.enabled_services]
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

  depends_on = [google_project_service.enabled_services["compute.googleapis.com"]]
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
# Kubernetes Endpoint Group
# -----------------------------------

locals {
  # Parse the NEG annotations and use to establish the network endpoint group
  # for the load balancer
  neg_annotations = jsondecode(
    lookup(
      data.kubernetes_service.mlops_app_service.metadata[0].annotations != null ? data.kubernetes_service.mlops_app_service.metadata[0].annotations : {},
      "cloud.google.com/neg-status",
      "{}"
    )
  )
}

# Load balancer backend service for the compute network endpoint group
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

# -----------------------------------
# Vertex AI enpoint group
# -----------------------------------

# Network endpoint group for Vertex AI - region and service specific only
# TODO: Make more inclusive for other regions and services
resource "google_compute_region_network_endpoint_group" "vertexai_neg" {
  name                  = "vertexai-neg"
  region                = var.region
  network_endpoint_type = "SERVERLESS"
  cloud_function {
    function = google_cloudfunctions_function.trigger_pipeline.name
  }
}

resource "google_compute_backend_service" "vertexai_backend" {
  name                            = "trigger-pipeline-backend"
  description                     = "Backend for Vertex AI service"
  protocol                        = "HTTPS"
  load_balancing_scheme           = "EXTERNAL"
  timeout_sec                     = 30
  connection_draining_timeout_sec = 0

  backend {
    group = google_compute_region_network_endpoint_group.vertexai_neg.id
  }

  # Attach Cloud Armor
  security_policy = google_compute_security_policy.cloud_armor.id
}
