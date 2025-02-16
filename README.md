
# ML Mental Health Modeling Pipeline on GCP Vertex AI, Orchestrated with Terraform

This project implements a **Machine Learning (ML) Mental Health Modeling Pipeline** on **Google Cloud Platform (GCP)**, leveraging **Vertex AI** for model development and deployment, and **Terraform** for infrastructure provisioning and management. The pipeline is fully automated, enabling infrastructure-as-code (IaC) practices for scalability and reproducibility.

---

## Table of Contents

- [Project Overview](#Overview)
- [Datascience Approach](#Datascience-Approach)
- [Model Development](#model-development)
- [MLOps-&-Deployment](#MLops-&-Deployment)
- [CI/CD Pipeline](#cicd-pipeline)
- [Prerequisites](#Prerequisites)
- [Project Structure](#Project-Structure)
- [Getting Started](#getting-started)
- [Contributing](#contributing)
- [License](#license)


---


## Overview

This project automates end-to-end machine learning workflows using GCP, Vertex AI, and Terraform.

The project is designed to predict mental health conditions and can be repurosed for other domains like finance and customer analytics.

Below is an overview of the infrastructure and model training pipeline.

Application:

<p align="center">
  <img src="images/app.png" width=600 />
</p>

Architecure:

<p align="center">
  <img src="images/architecture.png" width=600 "/>
</p>

### Key Features:
- **Automated Infrastructure**: Terraform manages cloud resources dynamically.
- **Scalable ML Pipeline**: Vertex AI handles model training, evaluation, and deployment.
- **Continuous Learning**: Models are retrained automatically as new data becomes available.
- **Web Application**: A user-friendly interface for mental health predictions and insights.

---

### Current Implementation: Mental Health Prediction

Mental health issues are widespread and complex, yet timely and personalized support remains limited. This implementation focuses on predicting mental health conditions using ML models trained on large-scale mental health survey data. The system provides insights for early intervention, helping healthcare providers, policymakers, and individuals proactively address mental health needs.

### Key Beneficiaries:
- **Healthcare Providers**: Prioritize care, optimize resources, and improve patient outcomes.
- **Businesses & HR Teams**: Identify mental health risks among employees to enhance workplace well-being.
- **Policy & Government Agencies**: Use aggregated insights for public health planning and resource allocation.
- **Research & Academia**: Leverage the model framework for further analysis in mental health and beyond.

---

### Dataset & Data Pipeline

The ML pipeline is built on a continuously evolving dataset framework that integrates new and diverse data sources over time.

- **Current Dataset**: The model is trained on the **CDC’s Behavioral Risk Factor Surveillance System (BRFSS)**, offering insights into mental health trends across the United States.
- **Future Iterations**: The system is designed to incorporate additional data sources, including real-time survey data, anonymized user responses, and external research datasets.

---

## Datascience Approach

### Feature Engineering
- Key mental health indicators, lifestyle behaviors, and healthcare access patterns are extracted and transformed into meaningful features.
- Techniques include **categorizing complex responses**, combining related questions, and refining features for improved interpretability.

### Predictive Modeling
- **Classification algorithms** are employed to predict mental health outcomes.
- The pipeline begins with **logistic regression** as a baseline, followed by **neural networks, stacked models, and advanced classification techniques** to improve accuracy and robustness.

### Application Development
- A **web-based application** enables users to input predefined survey responses based on the model's most predictive features.
- The app provides **personalized insights** and **mental health recommendations**, ensuring accessibility on both desktop and mobile platforms.

---

## MLOps & Deployment

The deployment pipeline follows **MLOps best practices** to ensure:
- **Scalability & Reliability**: Cloud-based deployment on **Google Cloud Platform (GCP)** using **Vertex AI**.
- **Continuous Learning**: Automated monitoring, evaluation, and retraining of models to adapt to new data.
- **Infrastructure as Code (IaC)**: Terraform is used to **provision and manage** all cloud resources dynamically.

---

## Prerequisites

### Developer Requirements
- **Basic understanding of computer networks**:
  - Network security (Firewalls, common vulnerabilities, and mitigation).
  - Network infrastructures (Load balancers, VPNs, subnetworks, IP blocks, IAM, etc.).
  - Network/cloud storage, databases, and cloud databases.
- **Experience with cloud services** (AWS, GCP, Azure, etc.):
  - Infrastructure setup and configuration.
  - Kubernetes and Docker: Configuration and deployment.
- **Terraform basics**: [Learn Terraform with HashiCorp](https://developer.hashicorp.com/terraform/tutorials)

### Developer Environment
**Note**: This project was developed on a **MacBook Pro M2** running macOS.

Before deploying, ensure the following:

1. **Google Cloud Platform**:
   - A GCP account with billing enabled.
   - Required IAM roles for Terraform:
     - `Owner` or `Editor` role.
     - `Storage Admin`, `Compute Admin`, `Vertex AI Admin` roles (depending on services used).

2. **Local Environment**:
   - Python => 3.12
   - Docker (Docker Desktop on MacOs)
   - Miniconda
   - Install [Terraform](https://www.terraform.io/downloads.html).
   - Install the [Google Cloud SDK](https://cloud.google.com/sdk/docs/install).
   - Authenticate to GCP using:
     ```bash
     # Terraform GCP access
     gcloud auth application-default login
     # gcloud CLI commands
     gcloud auth login
     ```

3. **Configuration**:
   - Set the GCP project ID:
     ```bash
     gcloud config set project [PROJECT_ID]
     ```
   - Create a service account key file with the required permissions and download it as `credentials.json`.

4. **Access to the Mental Health Application GitHub Repo**:
   - [ML Mental Health](https://github.com/judesantos/ml_mentalhealth_app) Application Repository
   - Add Cloud Build app to your GitHub account. [See Google Cloud Documentation](https://cloud.google.com/build/docs/automating-builds/github/connect-repo-github).
   - Create a Personal Access Token from your GitHub account.

5. **Terraform Backend**:
   - Ensure a GCS bucket exists for storing the Terraform state.

---

## Project Structure
```
├── .env.development                  # Environment variables for development
├── .gitignore
├── README.md
├── cloud_functions                   # Serverless functions for MLOps automation
│   ├── retraining_notification       # Alerts when retraining is triggered
│   │   ├── main.py
│   │   └── requirements.txt
│   ├── trigger_pipeline              # Starts the ML pipeline on Vertex AI
│   │   ├── main.py                   # Trigger function
│   │   ├── requirements.txt          # Required packages
│   └── vertex_ai_notification        # Handles notifications for Vertex AI events
│       ├── main.py                   # Notification function
│       └── requirements.txt          # Required packages
├── data
│   └── llcp_2022_2023_cleaned.csv    # Base dataset for training and inference
├── docker
│   └── vertexai-middleware           # Dockerfile and scripts for Vertex AI middleware (custom container)
│       ├── Dockerfile                # Dockerfile for the middleware and application startup
│       ├── build.sh                  # Build script for the Docker image
│       ├── ml_inference_data.py      # Data preprocessing script
│       └── predictor.py              # Router for the application implements /predict
├── environment.yml                   # Python environment packages required for this project
├── images
│   ├── dataflow.png
│   ├── mlops.png
│   └── platform.png
├── pipelines                         # Vertex AI pipeline definition
│   ├── components
│   │   ├── deploy.py                 # Component for model deployment
│   │   ├── evaluate.py               # Component for model evaluation
│   │   ├── preprocess.py             # Component for data preprocessing
│   │   ├── register.py               # Component for model registration
│   │   └── train.py                  # Component for model training
│   ├── pipeline.py                   # Pipeline - Defines the workflow
│   └── trigger_pipeline.py           # Manually trigger the pipeline (for testing)
└── terraform                         # Terraform configuration for GCP resources
    ├── app.tf                        # MLops application deployment
    ├── database.tf                   # Database setup
    ├── gcr.tf                        # Artifact (GCR) Registry setup
    ├── gcs.tf                        # GCS bucket setup
    ├── gke.tf                        # GKE cluster setup
    ├── iam.tf                        # IAM roles and permissions
    ├── kubernetes.tf                 # (GKE) Kubernetes resources
    ├── networking.tf                 # Networking setup
    ├── output.tf                     # Outputs from Terraform
    ├── provider.tf                   # Provider configuration
    ├── sa.tf                         # Service accounts
    ├── setup.tf                      # Setup scripts (Docker build, data upload, pipeline trigger)
    ├── terraform.tfvars.development  # Development environment variables
    ├── variables.tf                  # Variable declarations
    ├── versions.tf                   # Provider versions
    └── vertex_ai.tf                  # Vertex AI resources
```
---

## Getting Started

Follow these steps to deploy the infrastructure:

### 1. Clone the Repository and Set Up Python Environment
Clone the repository and set up the Python environment:
```bash
git clone https://github.com/judesantos/ml_mentalhealth_gcp
cd ml_mentalhealth_gcp

# Create and activate the Python environment
conda env create -f environment.yml
conda activate ml_gcp
```

### 2. Set Up Terraform Variables
Create a `terraform.tfvars` file to specify your variables (replace placeholders with actual values):
```bash
project_id = "gcp-project-id"
region     = "region"
...
```

### 3. Initialize Terraform
Initialize Terraform to download the required provider plugins and set up the backend:
```bash
cd terraform

terraform init
```

### 4. Plan the Deployment
Generate and review the execution plan to verify the resources that will be created:
```bash
terraform plan
```

### 5. Apply the Deployment
Deploy the resources on GCP:
```bash
terraform apply
```
Confirm the prompt with `yes` to proceed.

### 6. Verify Deployment
Once the deployment completes:
- Check the GCP Console to verify the resources.
- Ensure all services are running as expected.

### 7. Retrieve Outputs
Retrieve the Terraform outputs to generate a report:
```bash
terraform output -json > pipeline_report.json
```

### 8. Clean Up (Optional)
To tear down the deployed infrastructure:
```bash
terraform destroy
```
Go to cloud console and delete/disable resources and services if not so:
- Cloud SQL             # Application Authentication
- BigQuery              # Vertex AI Feature Store
- VPC Network           # VPC
- Vertex AI             # Feature store, Model Registry, Pipelines
- GCS                   # Cloud Buckets
- GKE                   # Kubernetes Cluster
- Artifacts Registry    # Atifact Registry (AKA: GCR)

---



## Notes

### Troubleshooting
- If Terraform fails to authenticate, verify your GCP credentials:
  ```bash
  gcloud auth application-default login
  ```
- Ensure the service account has the necessary permissions.
- Check logs for specific errors using:
  ```bash
  terraform show
  ```

### Create/Update Docker Container Images
- **MLOps App**:
  ```bash
  terraform apply -replace="null_resource.mlops_app_docker_build"
  ```
- **Vertex AI Model Endpoint Custom Container**:
  ```bash
  terraform apply -replace="null_resource.vertexai_endpoint_middleware"
  ```

---

## Contributing
Contributions are welcome! Please follow these steps:

Fork the repository.
Create a new branch (feature/your-feature).
Commit your changes.
Push to the branch.
Open a Pull Request.

## License
This project is licensed under the MIT License. See the [LICENSE](./LICENSE) file for details.


