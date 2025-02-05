
# -----------------------------------
# VPC and Subnets
# -----------------------------------

resource "google_compute_network" "mlops_vpc_network" {
  name                    = "mlops-vpc-network"
  project                 = var.project_id
  auto_create_subnetworks = false

  depends_on = [
    google_project_service.compute
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
    google_project_iam_member.mlops_permissions,
    google_project_service.compute,
  ]
}

# -----------------------------------
# Load Balancer
# -----------------------------------

# Public subnet load balancer - The gateway to the VPC private subnet
resource "google_compute_url_map" "url_map" {
  name = "multi-backend-url-map"

  default_service = google_compute_backend_service.mlops_app_backend.self_link

  host_rule {
    hosts        = ["*"] # Match all hosts, or specify a specific host like "example.com"
    path_matcher = "mlops-app"
  }

  path_matcher {
    name            = "mlops-app"
    default_service = google_compute_backend_service.mlops_app_backend.self_link

    # Separate path rules for different services
    path_rule {
      paths   = ["/*"]
      service = google_compute_backend_service.mlops_app_backend.self_link
    }
    # TODO: Add vertex AI endpoint path rules here
  }
}

# Load balancer public IP address for incoming traffic
resource "google_compute_global_address" "default" {
  name         = "mlops-global-ip"
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
  depends_on   = [google_project_service.enabled_services]
}

# TODO: Looks like this is not used. Remove if not needed
# Load balancer private IP address for internal traffic
resource "google_compute_address" "load_balancer_ip" {
  name         = "load-balancer-ip"
  project      = var.project_id
  region       = var.region
  address_type = "INTERNAL"
  subnetwork   = google_compute_subnetwork.public_subnet.name
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

  depends_on = [ google_project_service.compute ]
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

