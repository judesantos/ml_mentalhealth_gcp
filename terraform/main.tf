
# -----------------------------------------------------
#
# Startup Scripts - Executes on "terraform apply"
#
# -----------------------------------------------------

/*
  Vertex AI Pipeline setup Script.check.
  --------------------------------------

  Build pipeline.json
  Pipeline will include preprocessing (feature store integration), training,
  evaluation, model registration, and deployment steps
*/
resource "null_resource" "generate_pipeline_json" {
  provisioner "local-exec" {
    command     = "python3 ../pipelines/pipeline.py"
    working_dir = "${path.module}/../pipelines/"
  }
}

/*
  The Mental Health Web Application Deployment Authentication Script.
  -------------------------------------------------------------------

  Login to Docker Registry for the mlop_app deployment in the artifact registry.
  This is required to push/pull the Docker image:
    - From cloud build to the artifact registry,
        in (null_resource.mlops_app_docker_build)
    - From the artifact registry to the kubernetes cluster (GKE),
        in (kubernetes_deployment.mlops_app)
*/
resource "null_resource" "docker_auth" {
  provisioner "local-exec" {
    command = "echo '${base64decode(google_service_account_key.docker_auth_key.private_key)}' | docker login -u _json_key --password-stdin https://gcr.io"
  }
}

/*
  The Mental Health Web Application Kubernetes Deployment Script.
  ---------------------------------------------------------------

  Runs on terraform apply: Build and deploy the app docker image given a
    github repository tag number. See (var.image_tag).
  Conditions:
    Check if a variable tag value is provided;
    Check if the image for the given tag does not already exist in GCR
  NOTE: This may conflict with the GitHub trigger, 'mlops_app_github_trigger'.
        Use only when retrying a failed deployment, or when the VPC is
        created for the first time and a tag is provided in the variables.

  FOR DEVELOPEMENT PURPOSES ONLY.
*/
resource "null_resource" "mlops_app_docker_build" {
  provisioner "local-exec" {
    command     = <<EOT
      #!/bin/bash
      set -e
      # Set the image ID according to GCP artifact registry format
      IMAGE_ID=${var.region}-docker.pkg.dev/${var.project_id}/mlops-repo/mlops-app:${var.image_tag}
      rm -rf repo # Remove the repo if it exists

      # Clone the GitHub repository with the given tag
      git clone --branch ${var.image_tag} --depth 1 ${google_cloudbuildv2_repository.mlops_app_repo.remote_uri} repo

      # Get the absolute path of the .env file and cert folder
      ENV_FILE_PATH=$(realpath "${var.env_file}")
      CERT_FOLDER_PATH=$(realpath "${var.cert}")

      # Copy the .env file from the local system to the cloned repository
      if [ -f "$ENV_FILE_PATH" ]; then
        cp "$ENV_FILE_PATH" ./repo/.env
      else
        echo "Error: .env file not found at $ENV_FILE_PATH"
        exit 1
      fi

      # Copy the cert folder if it exists
      if [ -d "$CERT_FOLDER_PATH" ]; then
        cp -r "$CERT_FOLDER_PATH" ./repo/certs
      else
        echo "Error: cert folder not found at $CERT_FOLDER_PATH"
        exit 1
      fi

      # Go to the docker build directory
      cd repo

      # Clean up the Docker builder cache
      docker builder prune --all

      # Build the Docker image according to GCP platform specifications
      DOCKER_BUILDKIT=1 docker build --platform=linux/amd64 -t $IMAGE_ID .

      # Push the Docker image to GCR
      docker push $IMAGE_ID

      # Clean up
      rm -rf repo

    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}