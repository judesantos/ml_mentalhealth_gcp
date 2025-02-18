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

    # List existing endpoints
    endpoints = aiplatform.Endpoint.list(
        filter=f'display_name="{endpoint_name}"')

    if endpoints:
        endpoint = endpoints[0]  # Use the first matching endpoint
        logger.info(f'Found existing endpoint: {endpoint.resource_name}')
    else:
        # If endpoint does not exist, create a new one
        logger.info('No existing endpoint found. Creating a new one...')
        endpoint = aiplatform.Endpoint.create(display_name=endpoint_name)
        logger.info(f'Created new endpoint: {endpoint.resource_name}')

    # Load the model

    logger.info(f'Loading model from {model_resource.uri}')

    model = aiplatform.Model(model_resource.uri)

    logger.info(
        f'Deploying model to Vertex AI endpoint: {endpoint.resource_name}.')

    # Deploy the model
    model.deploy(
        endpoint=endpoint,
        machine_type='n1-standard-4',
        min_replica_count=1,
        max_replica_count=2,
        enable_access_logging=True,
        disable_container_logging=False,
        deploy_request_timeout=600,
        traffic_split={'0': 100},
    )

    logger.info(
        f'Model deployed to Vertex AI endpoint: {endpoint.resource_name}.')

    return True
