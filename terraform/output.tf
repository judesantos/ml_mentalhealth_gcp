output "vpc_network_name" {
  description = "The name of the VPC network."
  value       = google_compute_network.mlops_vpc_network.name
}

output "public_subnet_cidr" {
  description = "The CIDR range of the public subnet."
  value       = google_compute_subnetwork.public_subnet.ip_cidr_range
}

output "private_subnet_cidr" {
  description = "The CIDR range of the private subnet."
  value       = google_compute_subnetwork.private_subnet.ip_cidr_range
}

output "preprocessing_bucket_name" {
  description = "The name of the preprocessing bucket."
  value       = google_storage_bucket.mlops_gcs_bucket.name
}

output "mlops_gke_cluster" {
  description = "The name of the GKE cluster."
  value       = google_container_cluster.mlops_gke_cluster.name
}

output "feature_store_name" {
  description = "The name of the Vertex AI Feature Store."
  value       = google_vertex_ai_featurestore.mlops_feature_store.name
}

output "vertex_endpoint_name" {
  description = "The name of the Vertex AI endpoint."
  value       = google_vertex_ai_endpoint.endpoint.display_name
}

#output "load_balancer_ip" {
#  description = "The external IP address of the load balancer."
#  value       = google_compute_address.load_balancer_ip.address
#}

output "alert_policy_name" {
  description = "The name of the alert policy for Vertex AI monitoring."
  value       = google_monitoring_alert_policy.mlops_alert_policy.display_name
}

#output "trigger_pipeline_function_url" {
#  description = "The HTTP trigger URL for the Cloud Function that triggers the Vertex AI pipeline."
#  value       = google_cloudfunctions_function.trigger_pipeline.https_trigger_url
#}

output "pipeline_url" {
  value       = "https://console.cloud.google.com/vertex-ai/pipelines?project=${var.project_id}"
  description = "URL to view the deployed Vertex AI pipeline"
}

output "public_endpoint" {
  value = try(
    kubernetes_service.mlops_app_service, #.status[0].load_balancer[0].ingress[0].ip,
    "Not available yet"
  )
  description = "The public endpoint of the application."
}

output "instance_group_urls" {
  value = google_container_cluster.mlops_gke_cluster.node_pool[0].instance_group_urls
}

# Use the cluster attributes directly
output "cluster_name" {
  value = google_container_cluster.mlops_gke_cluster.name
}

output "service_account_email" {
  description = "Service account email for Docker authentication"
  value       = google_service_account.docker_auth.email
}

output "docker_key_file" {
  description = "The private key for Docker authentication"
  value       = google_service_account_key.docker_auth_key.private_key
  sensitive   = true
}

output "available_zones" {
  value = data.google_compute_zones.available_zones.names
}

output "database_url" {
  value     = kubernetes_secret.mlops_app_secret.data["DATABASE_URL"]
  sensitive = true
}