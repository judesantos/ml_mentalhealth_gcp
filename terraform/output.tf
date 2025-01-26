#output "service_account_email" {
#  description = "The email of the Vertex AI service account."
#  value       = google_service_account.vertex_service_account.email
#}

output "vpc_network_name" {
  description = "The name of the VPC network."
  value       = google_compute_network.vpc_network.name
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

output "endpoint_name" {
  description = "The name of the Vertex AI endpoint."
  value       = google_vertex_ai_endpoint.endpoint.display_name
}

output "ci_cd_trigger_name" {
  description = "The name of the Vertex AI endpoint."
  value       = google_cloudbuild_trigger.ci_cd_pipeline.name
}

output "load_balancer_ip" {
  description = "The external IP address of the load balancer."
  value       = google_compute_address.load_balancer_ip.address
}

output "alert_policy_name" {
  description = "The name of the alert policy for Vertex AI monitoring."
  value       = google_monitoring_alert_policy.mlops_alert_policy.display_name
}

output "trigger_pipeline_function_url" {
  description = "The HTTP trigger URL for the Cloud Function that triggers the Vertex AI pipeline."
  value       = google_cloudfunctions_function.trigger_pipeline.https_trigger_url
}

#output "register_model_function_url" {
#  description = "The HTTP trigger URL for the Cloud Function that registers the Vertex AI model."
#  value       = google_cloudfunctions_function.register_model.https_trigger_url
#}

#output "deploy_model_function_url" {
#  description = "The HTTP trigger URL for the Cloud Function that deploys the Vertex AI model."
#  value       = google_cloudfunctions_function.deploy_model.https_trigger_url
#}

output "pipeline_url" {
  value = "https://console.cloud.google.com/vertex-ai/pipelines?project=${var.project_id}"
  description = "URL to view the deployed Vertex AI pipeline"
}
