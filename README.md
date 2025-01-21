# ML Mental Health Modeling Pipeline on GCP Vertex AI Orchestrated with Terraform

This project implements the ML Mental Health Modeling Pipeline on Google Cloud Platform (GCP), utilizing Vertex AI for model development and deployment, and Terraform for seamless infrastructure provisioning and management.


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
    git clone https://github.com/judesantos/ml_mentalhealth_gcp
    cd ml_mentalhealth_gcp
```

### 2. Set Up Terraform Variables
Create a terraform.tfvars file to specify your variables (replace placeholders with actual values):
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
7. Clean Up (Optional)
To remove the deployed infrastructure:
```
    terraform destroy
```

## Project Structure
```
    ├── README.md
    ├── .gitignore                  # Git ignore file
    ├── cloud_functions             # The cloud services pipeline operations
    │   ├── deploy_model
    │   │   ├── main.py             # Deploy model to an vertex endpoint
    │   │   └── requirements.txt
    │   ├── register_model
    │   │   ├── main.py             # Transfer trained model to the model registry
    │   │   └── requirements.txt
    │   └── trigger_pipeline
    │       ├── main.py             # Start the pipeline process
    │       └── requirements.txt
    ├── pipelines
    │   ├── components
    │   │   ├── preprocess.py       # Dataset preprocessing
    │   │   ├── train.py            # Model trainingj
    │   │   └── evaluate.py         # Evaluate the model
    │   └── pipeline.py             # The ML model pipeline
    └── terraform
        ├── main.tf                 # Main Terraform configuration
        ├── variables.tf            # Input variables
        ├── pipeline.json.tfvars    # Variable definitions (ignored in .gitignore)
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




