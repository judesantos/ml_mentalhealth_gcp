from kfp.dsl import component, Input, Artifact


@component(
    base_image='python:3.12',
    packages_to_install=['google-cloud-aiplatform'],
)
def deploy_model(
    project_id: str,
    region: str,
    model_resource: Input[Artifact],
) -> bool:
    """
    Deploy the trained model to Vertex AI.

    Args:
        - project_id: str, the project id
        - region: str, the region
        - model_resource: Input[Artifact], the model resource

    Returns:
        - bool: True if the model is successfully deployed, False otherwise
    """

    import logging
    from google.cloud import aiplatform

    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)

    logger.info(f'Deploying model to Vertex AI endpoint')

    # Initialize the Vertex AI client
    aiplatform.init(
        project=project_id,
        location=region,
    )

    logger.info(f'Loading model from {model_resource.uri}')

    # Load the model
    model = aiplatform.Model(model_resource.uri)

    logger.info(f'Deploying model to Vertex AI endpoint...')

    # Deploy the model
    endpoint = model.deploy(
        machine_type='n1-standard-4',
        min_replica_count=1,
        max_replica_count=1,
    )

    logger.info(f'Model deployed to Vertex AI endpoint: {endpoint}.')

    return True
