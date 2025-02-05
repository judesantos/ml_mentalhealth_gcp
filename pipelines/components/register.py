"""
This component contains code to register a trained model in Vertex AI
Model Registry.

Implement the `register_model` function using kfp.dsl.component
implementation which abstracts away the virtual machine environment
where the component runs.

"""

from kfp.dsl import component, Input, Artifact
from google.cloud import aiplatform


@component(
    base_image="python:3.12",
    packages_to_install=["google-cloud-aiplatform"],
)
def register_model(
    container_image_uri: str,
    project_id: str,
    region: str,
    display_name: str,
) -> str:
    """
    Register a trained model in Vertex AI Model Registry.

    Uses the Vertex AI Python client library to upload the model artifact
    into the Model Registry.

    Args:
        - model_path: Artifact of the model to register
        - project_id: str, the project id
        - region: str, the region
        - display_name: str, the display name of the model
    """

    aiplatform.init(project=project_id, location=region)

    # Register the model in Vertex AI Model Registry
    model = aiplatform.Model.upload(
        display_name=display_name,
        artifact_uri=None,
        serving_container_image_uri=container_image_uri,
    )
    return model.resource_name
