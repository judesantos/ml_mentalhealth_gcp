# ML Mental Health on GCP Vertex AI

This project implements the Mental Health Evaluation service on
Google Cloud Platform (GCP), leveraging Vertex AI and managed through
Terraform for infrastructure provisioning.



To Deploy:


1. Initialize the project

```
    terraform init
    terraform apply -var-file=terraform/pipeline.json.tfvars
```

2. Manually trigger the pipeline (Note: This is automated using pub/sub in production)

```
    curl -X POST https://REGION-PROJECT_ID.cloudfunctions.net/trigger_pipeline
```


# Mental Health Evaluation Service Deployment on GCP and Vertex AI

This project implements the Mental Health Evaluation service on
Google Cloud Platform (GCP), leveraging Vertex AI and managed through
Terraform for infrastructure provisioning.

## Prerequisites

Before deploying this project, ensure the following:

1. **Google Cloud Platform**:
   - A GCP account with billing enabled.
   - Required IAM roles for Terraform:
     - `Owner` or `Editor` role.
     - `Storage Admin`, `Compute Admin`, `Vertex AI Admin` roles (depending on services used).

2. **Local Environment**:
   - Install [Terraform](https://www.terraform.io/downloads.html).
   - Install the [Google Cloud SDK](https://cloud.google.com/sdk/docs/install).
   - Authenticate to GCP using:
     ```
        gcloud auth application-default login
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

### 1. Clone the Repository
Clone the repository containing this Terraform project:
```
    git clone [repository_url]
    cd [project_directory]
```

### 2. Set Up Terraform Variables
Create a terraform.tfvars file to specify your variables (replace placeholders with actual values):
```
    project_id = "your-gcp-project-id"
    region     = "your-region"
    zone       = "your-zone"
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
7. Clean Up (Optional)
To remove the deployed infrastructure:
```
    terraform destroy
```

## Project Structure
```
    ├── main.tf                # Main Terraform configuration
    ├── variables.tf           # Input variables
    ├── outputs.tf             # Outputs
    ├── terraform.tfvars       # Variable definitions (ignored in .gitignore)
    ├── provider.tf            # Provider configuration (e.g., GCP)
    ├── modules/               # Optional reusable Terraform modules
    └── .gitignore             # Git ignore file
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




