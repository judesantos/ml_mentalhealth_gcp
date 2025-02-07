from kfp.dsl import component


@component(
    base_image='python:3.12',
    packages_to_install=['google-cloud-aiplatform'],
)
def deploy_model(
    project_id: str,
    region: str,
    container_image_uri: str,
    endpoint_name: str,
) -> bool:
    """
    Deploy the trained model to Vertex AI.

    Args:
        - project_id: str, the project id
        - region: str, the region
        - container_image_uri: str, the container image URI
        - endpoint_name: str, the endpoint name

    Returns:
        - bool: True if the model is successfully deployed, False otherwise
    """

    import logging
    from google.cloud import aiplatform

    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)

    try:
        aiplatform.init(
            project=project_id,
            location=region,
        )

        # Upload model
        model = aiplatform.Model.upload(
            display_name='xgboost-middleware',
            container_image_uri=container_image_uri,
        )

        # Create or get endpoint
        endpoints = aiplatform.Endpoint.list(
            filter=f'display_name={endpoint_name}')
        if endpoints:
            endpoint = endpoints[0]
        else:
            endpoint = aiplatform.Endpoint.create(display_name=endpoint_name)

        # Deploy the model
        model.deploy(
            endpoint=endpoint,
            deployed_model_display_name='custom-prediction-deployment',
            machine_type='n1-standard-4',
        )
    except Exception as e:
        logger.error(f'Failed to deploy the model: {e}')
        return False

    return True
