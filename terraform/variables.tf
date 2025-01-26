variable "project_id" {
  description = "Google Cloud Project ID"
  type        = string
}

variable "project_number" {
  description = "Google Cloud Project ID"
  type        = number
}

variable "region" {
  description = "Google Cloud region"
  type        = string
  default     = "us-central1"
}

variable "github_user" {
  description = "GitHub username"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string

}

variable "github_app_id" {
  description = "GitHub App Installation ID"
  type        = number
}

variable "github_token" {
  description = "GitHub Access Token"
  type        = string
  sensitive  = true
}

variable "docker_image_tag" {
  description = "Docker image tag"
  type        = string
  default     = "latest"
}

variable "email" {
  description = "Email address"
  type        = string
}
