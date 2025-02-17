from kfp.dsl import component, Input, Artifact


@component(
    base_image='python:3.12',
    packages_to_install=['google-cloud-aiplatform'],
)
def deploy_model(
    project_id: str,
    region: str,
    endpoint_name: str,
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

    logging.basicConfig(level=logging.INFO, force=True)
    logger = logging.getLogger(__name__)

    logger.info(f'Deploying model to Vertex AI endpoint')

    # Initialize the Vertex AI client
    aiplatform.init(
        project=project_id,
        location=region,
    )

    logger.info(f'Getting the Endpoint object from {endpoint_name}')

    endpoint = aiplatform.Endpoint(
        endpoint_name=f'projects/{project_id}/locations/{region}/endpoints/{endpoint_name}'
    )

    logger.info(f'Endpoint object found {endpoint}')

    # Load the model

    logger.info(f'Loading model from {model_resource.uri}')

    model = aiplatform.Model(model_resource.uri)

    logger.info(f'Deploying model to Vertex AI endpoint: {endpoint}.')

    # Deploy the model
    model.deploy(
        endpoint=endpoint,
        machine_type='n1-standard-4',
        min_replica_count=1,
        max_replica_count=2,
        enable_access_logging=True,
        disable_container_logging=False,
        deploy_request_timeout=60,
    )

    logger.info(f'Model deployed to Vertex AI endpoint: {endpoint}.')

    return True
