"""
DEVELOPMENT SCRIPT ONLY

The process of compiling the pipeline into a JSON file, uploading it to GCS,
and triggering the pipeline job is automated in the Cloud Functions deployment
script.

This script is used to test the pipeline locally before deploying it.

Steps:
    1. Define the service account, project ID, and region
    2. Create a pipeline job using the Vertex AI Python client library
    3. Run the pipeline job
    4. Retrieve error details, if any
    5. Print the final pipeline status
    6. Show a link to view detailed logs in the GCP Console
"""

from google.cloud import aiplatform
import pipeline as pipeline

# Define the pipeline parameters

SA = 'mlops-service-account@ml-mentalhealth.iam.gserviceaccount.com'
PROJECT_ID = 'ml-mentalhealth'
REGION = 'us-central1'
BUCKET_NAME = 'mlops-gcs-bucket/pipelines/data/'
FEATURESTORE_ID = 'mlops_feature_store'
ENTITY_TYPE_ID = 'cdc_training'
ENDPOINT_NAME = 'mlops-endpoint'
CONTAINER_IMAGE_URI = f'us-central1-docker.pkg.dev/ml-mentalhealth/mlops-repo/{ENDPOINT_NAME}:v0.1.9'

# Create the pipeline job

job = aiplatform.PipelineJob(
    enable_caching=False,
    failure_policy='fast',
    display_name='mental-health-pipeline',
    template_path='pipeline.json',
    pipeline_root=f'gs://mlops-gcs-bucket/pipelines',
    parameter_values={
        'project_id': PROJECT_ID,
        'region': REGION,
        'bucket_name': BUCKET_NAME,
        'featurestore_id': FEATURESTORE_ID,
        'entity_type_id': ENTITY_TYPE_ID,
        'container_image_uri': CONTAINER_IMAGE_URI,
        'endpoint_name': ENDPOINT_NAME
    },
)

# Run the pipeline job

job.run(service_account=SA)

# Retrieve error details

errors = job.gca_resource.error
if len(errors.message) > 0:
    print(f'Error message: {errors.message}')
    print(f'Error details: {errors.details}')

print(f'Final Pipeline Status: {job.state}')
print(f'View detailed logs in GCP Console: {job.resource_name}')
