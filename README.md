# ML Mental Health Modeling Pipeline on GCP Vertex AI Orchestrated with Terraform

This project implements the ML Mental Health Modeling Pipeline on Google Cloud Platform (GCP), using Vertex AI for model development and deployment, and Terraform for infrastructure provisioning and management.

This project focuses on predicting mental health conditions using machine learning models deployed on Google Cloud's Vertex AI. Unlike the typical UI-driven approach, this project is fully automated using Terraform, allowing infrastructure to be provisioned and managed as code.

---

## Overview

This project implements a scalable and adaptable machine learning (ML) pipeline designed for predictive modeling across various domains. By leveraging Google Cloud Platform (GCP), Vertex AI, and Terraform, the system automates model development, deployment, and continuous retraining, making it suitable for healthcare, finance, customer behavior analysis, and other data-driven applications.

While the current implementation focuses on mental health prediction, the framework can be easily extended to other business models that require predictive analytics. The infrastructure and MLOps pipeline ensure seamless integration of new data sources, model updates, and cloud-based deployment, providing a flexible and reusable foundation for a variety of use cases.

### Current Implementation: Mental Health Prediction
Mental health issues are widespread and complex, yet timely and personalized support remains limited. Insufficient mental health care has led to legal, financial, and social consequences, with major healthcare providers facing lawsuits and penalties for failing to provide adequate behavioral health services.

This implementation focuses on predicting mental health conditions using ML models trained on large-scale mental health survey data. The system provides insights for early intervention, helping healthcare providers, policymakers, and individuals proactively address mental health needs.

#### Key Beneficiaries & Applications
Healthcare & Mental Health Providers: Prioritize care, optimize resources, and improve patient outcomes.
Businesses & HR Teams: Identify mental health risks among employees to enhance workplace well-being.
Policy & Government Agencies: Use aggregated insights for public health planning and resource allocation.
Research & Academia: Leverage the model framework for further analysis in mental health and beyond.

#### Dataset & Data Pipeline

The ML pipeline is built on a continuously evolving dataset framework that integrates new and diverse data sources over time.

The current mental health model was trained using the CDC’s Behavioral Risk Factor Surveillance System (BRFSS), offering insights into mental health trends across the United States.
Future iterations can incorporate additional sources, including real-time survey data, anonymized user responses, and external research datasets.
The system is designed to automate dataset updates, ensuring the model adapts to new trends and remains relevant.

### Data Science Approach

#### **Feature Engineering**
Key mental health indicators, lifestyle behaviors, and healthcare access patterns are extracted and transformed into meaningful features. This includes **categorizing complex responses**, combining related questions, and refining features for improved interpretability.

#### **Predictive Modeling**
Employs **classification algorithms** to predict mental health outcomes. The modeling pipeline begins with **logistic regression** as a baseline, followed by **neural networks, stacked models, and advanced classification techniques** to improve accuracy and robustness.

#### **Application Development**
A **web-based application** enables users to input predefined survey responses based on the model's most predictive features. The app provides **personalized insights** and **mental health recommendations**, ensuring **accessibility on both desktop and mobile platforms**.

### MLOps & Deployment

The deployment pipeline follows **MLOps best practices** to ensure:
- **Scalability & Reliability**: Cloud-based deployment on **Google Cloud Platform (GCP)** using **Vertex AI**.
- **Continuous Learning**: Automated monitoring, evaluation, and retraining of models to adapt to new data.
- **Infrastructure as Code (IaC)**: Terraform is used to **provision and manage** all cloud resources dynamically.

## Architecture

The **Mental Health Support Services**, **Cloud Platform**, and **MLOps Infrastructure** are designed for seamless integration and scalability. **Architecture diagrams** detailing the full pipeline are provided below:

---


## Prerequisites

### For the developer:

Requires basic understanding of computer networks:
    - network security(Firewalls, common network vulnerability concepts and mitigation),
    - network infrastructures (load balancer, vpn, subnetworks, ipblocks, , IAM, etc..)
    - network/cloud storage, Db, cloud db

Some experience in cloud services (AWS, GCP, Azure, etc..):
    - Infrastructure setup, configuration,
    - kubernetes, docker: configuration, deployment

Terraform basics, configuration, troubleshooting.

### Developer Environment:
**NOTE:** This project was developed on a **MacBook Pro M2** running macOS.

Before deploying this project, ensure the following:

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
├── .env.development
├── .gitignore
├── README.md
├── cloud_functions
│   ├── retraining_notification
│   │   ├── main.py
│   │   └── requirements.txt
│   ├── trigger_pipeline
│   │   ├── main.py
│   │   ├── requirements.txt
│   │   └── trigger_pipeline.zip
│   └── vertex_ai_notification
│       ├── main.py
│       └── requirements.txt
├── data
│   └── llcp_2022_2023_cleaned.csv
├── docker
│   └── vertexai-middleware
│       ├── Dockerfile
│       ├── build.sh
│       ├── ml_inference_data.py
│       └── predictor.py
├── environment.yml
├── pipelines
│   ├── components
│   │   ├── deploy.py
│   │   ├── evaluate.py
│   │   ├── preprocess.py
│   │   ├── register.py
│   │   └── train.py
│   ├── pipeline.py
│   ├── terraform.tfstate
│   └── trigger_pipeline.py
└── terraform
    ├── app.tf
    ├── database.tf
    ├── gclb_cert.pem
    ├── gcr.tf
    ├── gcs.tf
    ├── gke.tf
    ├── iam.tf
    ├── kubernetes.tf
    ├── networking.tf
    ├── output.tf
    ├── provider.tf
    ├── sa.tf
    ├── setup.tf
    ├── terraform.tfvars.development
    ├── variables.tf
    ├── versions.tf
    └── vertex_ai.tf

```

## Notes

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

### Create, Update docker container images

#### Mlops App:

Triggers the creation of a new docker image and pushes to the artifact registry.
Any changes in the terraform configuration will also be updated.
```
terraform apply -replace="null_resource.mlops_app_docker_build"
```

### Vertex AI model enpoint custom container
```
terraform apply -replace="null_resource.vertexai_endpoint_middleware"
```




