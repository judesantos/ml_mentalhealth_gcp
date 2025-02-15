
# -----------------------------------
# PgSQL Database
# -----------------------------------

resource "google_compute_global_address" "private_ip_alloc" {
  name          = "private-ip-alloc"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  network       = google_compute_network.mlops_vpc_network.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.mlops_vpc_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_alloc.name]

  lifecycle {
    #ignore_changes = all
    prevent_destroy = false
  }

  depends_on = [
    google_compute_global_address.private_ip_alloc,
  ]
}

# Create Cloud SQL PostgreSQL Instance
resource "google_sql_database_instance" "pg_instance" {
  name                = "pg-instance"
  database_version    = "POSTGRES_14"
  region              = var.region
  deletion_protection = false

  settings {
    tier            = "db-f1-micro" # Adjust as needed
    disk_size       = 10
    disk_autoresize = false

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.mlops_vpc_network.id
    }

    backup_configuration {
      enabled = false
    }
  }

  lifecycle {
    #ignore_changes = all
    prevent_destroy = false
  }

  depends_on = [
    google_service_networking_connection.private_vpc_connection,
  ]
}

# Create PostgreSQL Database
resource "google_sql_database" "pg_database" {
  name     = "pg-database"
  project = var.project_id

  instance = google_sql_database_instance.pg_instance.name

  depends_on = [
    google_sql_user.pg_user,
    google_service_networking_connection.private_vpc_connection,
  ]
}

# Create PostgreSQL User (Secure via Secret Manager)
resource "google_sql_user" "pg_user" {
  name     = var.pgsql_user
  project = var.project_id

  instance = google_sql_database_instance.pg_instance.name
  password = var.pgsql_password # Store in Secret Manager instead

  depends_on = [google_project_service.enabled_services]
}

# Create the SQL DB instance
data "google_sql_database_instance" "pg_instance" {
  name = google_sql_database_instance.pg_instance.name
  project = var.project_id

  depends_on = [
    google_sql_user.pg_user
  ]
}

# Provide the database URL as a secret
resource "kubernetes_secret" "mlops_app_secret" {
  metadata {
    name      = "mlops-app-secret"
    namespace = kubernetes_namespace.mlops_app_namespace.metadata[0].name
  }
  data = {
    DATABASE_URL = "postgresql://${var.pgsql_user}:${var.pgsql_password}@${data.google_sql_database_instance.pg_instance.private_ip_address}:5432/pg-database"
  }

  depends_on = [ google_sql_database.pg_database ]
}
