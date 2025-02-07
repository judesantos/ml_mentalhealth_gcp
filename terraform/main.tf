
# -----------------------------------------------------
#
# Startup Scripts - Executes on "terraform apply"
#
# -----------------------------------------------------

/*
    Common variables
*/

resource "local_file" "pipeline_json" {
  content  = <<EOT
    {
        "key": "value"
    }
    EOT
  filename = "../pipelines/pipeline.json"
}

# Generate the script to fetch the latest git tag
resource "local_file" "get_latest_tag_script" {
  filename = "${path.module}/get_latest_tag.sh"
  content  = <<-EOT
        #!/bin/bash
        # Fetch and sort tags by semantic version, then return the latest
        LATEST_TAG=$(git ls-remote --tags --sort="v:refname" "https://github.com/$1/$2.git" \\
        | awk -F/ '{print \$3}' \\
        | grep -v '{}' \\
        | tail -n1)
        # Output as JSON (required for Terraform external data source)
        echo "{\"result\":\"$LATEST_TAG\"}"
    EOT
  # Set executable permissions (Unix/Linux)
  file_permission = "0755"
}

# Execute the script to get the latest tag
data "external" "latest_tag" {
  program    = ["bash", local_file.get_latest_tag_script.filename, var.github_user, var.github_repo]
  depends_on = [local_file.get_latest_tag_script]
}

# Use the fetched tag reference
locals {
  tag_ref = data.external.latest_tag.result.result # e.g., "refs/tags/v0.1.1"

  image_tag = replace(local.tag_ref, "refs/tags/", "")

  bucket       = google_storage_bucket.mlops_gcs_bucket.name
  project      = var.project_id
  featurestore = google_vertex_ai_featurestore.mlops_feature_store.id
  entity_type  = google_vertex_ai_featurestore_entitytype.training_data.id

  container_uri = "${var.region}-docker.pkg.dev/${var.project_id}/mlops-repo/${google_vertex_ai_endpoint.endpoint.name}:${local.image_tag}"
  params        = "^#^project_id=${local.project},bucket_name=${local.bucket},featurestore_id=${local.featurestore},entity_type_id=${local.entity_type}"

  spec = "gs://${local.bucket}/pipeline.json"

  depends_on = [data.external.latest_tag]
}

/*
  Vertex AI Pipeline setup Scripts.
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

resource "null_resource" "dataset_ingest" {
  provisioner "local-exec" {
    command     = "gsutil cp ../data/llcp_2022_2023_cleaned.csv gs://${local.bucket}/ml-mentalhealth/"
    working_dir = "${path.module}/../data/"
  }
}

/*
  Trigger the Vertex AI Pipeline.
  --------------------------------------

  Run the pipeline using the generated pipeline.json file.
  The pipeline will include preprocessing (feature store integration), training,
  evaluation, model registration, and deployment steps.
*/
resource "null_resource" "trigger_pipeline" {
  # Use the local-exec provisioner to send the HTTP request
  provisioner "local-exec" {
    command = <<EOT
      curl -X POST ${google_cloudfunctions_function.trigger_pipeline.https_trigger_url} \
        -H "Content-Type: application/json" \
        -d '{
              "parameters": {
                "project": "${var.project_id}",
                "region": "${var.region}",
                "pipeline_name": "build_pipeline",
                "pipeline-spec": "${local.spec}",
                "project_id": "${var.project_id}",
                "bucket_name": "${local.bucket}",
                "featurestore_id": "${local.featurestore}",
                "entity_type_id": "${local.entity_type}",
                "container_image_uri": "${local.container_uri}",
                "endpoint_name": "${google_vertex_ai_endpoint.endpoint.name}"
              }
            }'
    EOT
  }

  # Depend on the Cloud Function being created,
  # pipeline.json being uploaded to the GCS bucket, and
  # the dataset being ingested and resides in the GCS bucket
  depends_on = [
    google_project_service.cloudfunctions,
    google_cloudfunctions_function.trigger_pipeline,
    null_resource.generate_pipeline_json,
    null_resource.dataset_ingest,
  ]
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
