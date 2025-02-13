# ML Mental Health Modeling Pipeline on GCP Vertex AI Orchestrated with Terraform

This project implements the ML Mental Health Modeling Pipeline on Google Cloud Platform (GCP), utilizing Vertex AI for model development and deployment, and Terraform for seamless infrastructure provisioning and management.


## Prerequisites

For the developer:
    Requires basic understanding of computer networks:
        network security(Firewalls, common network vulnerability concepts and mitigation),
        network infrastructures (load balancer, vpn, subnetworks, ipblocks, , IAM, etc..)
        network/cloud storage, Db, cloud db
    Some experience in cloud services (AWS, GCP, Azure, etc..):
        Infrastructure setup, configuration,
        kubernetes, docker: configuration, deployment
    Terraform basics, configuration, troubleshooting.

Before deploying this project, ensure the following:

**NOTE:** This project was developed on a **MacBook Pro M2** running macOS.

1. **Google Cloud Platform**:
   - A GCP account with billing enabled.
   - Required IAM roles for Terraform:
     - `Owner` or `Editor` role.
     - `Storage Admin`, `Compute Admin`, `Vertex AI Admin` roles (depending on services used).

2. **Local Environment**:
   - Python => 3.12
   - Miniconda
   - Install [Terraform](https://www.terraform.io/downloads.html).
   - Install the [Google Cloud SDK](https://cloud.google.com/sdk/docs/install).
   - Authenticate to GCP using:
     ```
        # Terraform GCP access
        gcloud auth application-default login
        # gcloud cli commands
        gcloud auth login
     ```

3. **Configuration**:
   - Set the GCP project ID:
     ```bash
        gcloud config set project [PROJECT_ID]
     ```
   - Create a service account key file with the required permissions and download it as `credentials.json`.

4. **Terraform Backend**:
   - Ensure a GCS bucket exists for storing the Terraform state.

## Deployment Steps

Follow these steps to deploy the infrastructure:

### 1. Clone the Repository, setup Python environment

Clone the repository containing the Terraform project:
```
    git clone https://github.com/judesantos/ml_mentalhealth_gcp
    cd ml_mentalhealth_gcp

```

We need a Python environment with all the required packages to
build Python artifacts that is then uploaded to GCP.

Setup Python environment 'ml_gcp', run:
```
    # Creates a python environment named 'ml_gcp'
    conda env create -f environment.yml
    # Switch to 'ml_gcp'
    conda activate ml_gcp
```

### 2. Set Up Terraform Variables
Create a terraform.tfvars file to specify your variables (replace placeholders with actual values):
NOTE: The cloned repo path in ./terraform should contain an example file 'terraform.tfvars.development'.
      You may copy it and rename to terraform.tfvars, fill out values.
```
    project_id = "gcp-project-id"
    region     = "region"
```
Alternatively, you can pass variables during execution or use environment variables.

### 3. Initialize Terraform
Initialize Terraform to download the required provider plugins and set up the backend:
```
    terraform init
    terraform apply -var-file=terraform/pipeline.json.tfvars
```

### 4. Plan the Deployment
Generate and review the execution plan to verify the resources that will be created:
```
    terraform plan
```

### 5. Apply the Deployment
Deploy the resources on GCP:
```
    terraform apply
```
Confirm the prompt with yes to proceed.

### 6. Verify Deployment
Once the deployment completes:

Check the GCP Console to verify the resources.
Ensure all services are running as expected.

### 7. Get outputs

The result of the operation (terraform apply) will be stored as resources
that can be viewed later on.

You can retrieve the terraform outputs to generate a report.

```
    terraform output -json > pipeline_report.json
```

### 8. Clean Up (Optional)
To remove the deployed infrastructure:
```
    terraform destroy
```

## Project Structure
```
    ├── README.md
    ├── cloud_functions
    │   ├── retraining_notification
    │   │   ├── main.py
    │   │   └── requirements.txt
    │   ├── trigger_pipeline
    │   │   ├── main.py
    │   │   └── requirements.txt
    │   └── vertex_ai_notification
    │       ├── main.py
    │       └── requirements.txt
    ├── environment.yml
    ├── pipelines
    │   ├── components
    │   │   ├── build.py
    │   │   ├── deploy.py
    │   │   ├── evaluate.py
    │   │   ├── preprocess.py
    │   │   ├── register.py
    │   │   └── train.py
    │   └── pipeline.py
    └── terraform
        ├── graph.png
        ├── main.tf
        ├── output.tf
        ├── terraform.tfvars
        ├── variables.tf
        └── versions.tf

```

## Notes

###  Manually trigger the pipeline
   To start the service for the first time, or to restart the pipeline if needed, use the following command:
```
    terraform apply -var-file=terraform/pipeline.json.tfvars
```

## Troubleshooting
If Terraform fails to authenticate, verify your GCP credentials:
```
    gcloud auth application-default login
```

Ensure the service account has the necessary permissions.
Check logs for specific errors using:
```
    terraform show
```

### Update mlops_app image
Triggers the creation of a new image and pushes to the artifact registry.
Any changes in the terraform configuration will also be updated.
```
terraform apply -replace=null_resource.mlops_app_docker_build
```




