"""
This component contains code to register a trained model in Vertex AI
Model Registry.

Implement the `register_model` function using kfp.dsl.component
implementation which abstracts away the virtual machine environment
where the component runs.
"""

from kfp.dsl import component, Input, Output, Artifact


@component(
    base_image='python:3.12',
    packages_to_install=['google-cloud-aiplatform'],
)
def register_model(
    project_id: str,
    region: str,
    display_name: str,
    container_image_uri: str,
    model_artifact: Input[Artifact],
    model_resource: Output[Artifact],
) -> bool:
    """
    Register a trained model in Vertex AI Model Registry.

    Uses the Vertex AI Python client library to upload the model artifact
    into the Model Registry.

    Args:
        - model_path: Artifact of the model to register
        - project_id: str, the project id
        - region: str, the region
        - display_name: str, the display name of the model
        - model_artifact_uri: Input[Artifact], the model artifact URI
        - model: Output[Artifact], the registered model

    Returns:
        - bool: True if the model is successfully registered, False otherwise
    """

    import os
    import logging

    from google.cloud import aiplatform, storage

    logging.basicConfig(level=logging.INFO, force=True)
    logger = logging.getLogger(__name__)

    # Define the destination path in GCS
    bucket_name = 'mlops-gcs-bucket'
    model_dst_path = 'models/xgb-model'
    model_dst_filename = 'model.joblib'

    # Define the source path of the model artifact
    model_src_path = model_artifact.path
    # Extract the filename from the model path
    # model_filename = os.path.basename(model_src_path)

    # Define the GCS path of the destination model artifact
    gcs_model_path = f'{model_dst_path}/{model_dst_filename}'
    model_artifact_uri = f'gs://{bucket_name}/{model_dst_path}'

    # Initialize GCS client
    client = storage.Client(project=project_id)
    # Get the GCS bucket
    bucket = client.bucket(bucket_name)

    logger.info(f'Uploading model from model artifact {model_src_path}...')

    # Upload the model directory to GCS
    blob = bucket.blob(gcs_model_path)
    blob.upload_from_filename(model_src_path)

    logger.info(f'Uploaded model artifact to GCS: {model_artifact_uri}.')
    logger.info(f'Registering model with display name: {display_name}...')

    # Initialize Vertex AI client to register the model

    aiplatform.init(
        project=project_id,
        location=region,
    )

    # Register the model in Vertex AI Model Registry
    # The custom container is provided by the container registry URI
    # The container auto loads the model using the model artifact URI
    # provided through the MODEL_URI environment variable.

    model = aiplatform.Model.upload(
        project=project_id,
        location=region,
        display_name=display_name,
        artifact_uri=model_artifact_uri,
        serving_container_image_uri=container_image_uri
    )

    model_resource.uri = model.resource_name

    logger.info(
        f'Model registered with Vertex AI: {model.resource_name}.')

    return True
