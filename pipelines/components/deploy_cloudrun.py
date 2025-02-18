from kfp.dsl import component, Input, Artifact


@component(
    base_image='python:3.12',
    packages_to_install=['google-cloud-run'],
)
def deploy_model(
    project_id: str,
    region: str,
    endpoint_name: str,
    container_image_uri: str,
    model_resource: Input[Artifact],
) -> bool:
    """
    Deploy the trained model to Vertex AI.

    Args:
        - project_id: str, the project id
        - region: str, the region
        - endpoint_name: str, the endpoint name
        - container_image_uri: str, the container image URI
        - model_resource: Input[Artifact], the model resource

    Returns:
        - bool: True if the model is successfully deployed, False otherwise
    """

    import os
    import logging

    from google.cloud import run_v2
    from google.protobuf.duration_pb2 import Duration

    logging.basicConfig(level=logging.INFO, force=True)
    logger = logging.getLogger(__name__)

    logger.info(f'Deploying model to Cloud Run')
    logger.info(f'Using container image: {container_image_uri}')
    logger.info(f'Using endpoint name: {endpoint_name}')

    logger.info('Initializing Cloud Run client')

    # Initialize Cloud Run client
    client = run_v2.ServicesClient()

    # Define the service path
    parent_path = f'projects/{project_id}/locations/{region}'
    service_path = f'{parent_path}/services/{endpoint_name}'

    # vpc_connector_name: This is the name of the VPC connector setup in the GKE cluster
    # See Terraform: google_vpc_access_connector.gke_serverless_connector
    vpc_connector_name = 'gke-cloudrun-connector'
    vpc_connector = f'projects/{project_id}/locations/{region}/connectors/{vpc_connector_name}'

    logger.info(f'Creating service: {service_path}')

    try:
        # Check if service already exists
        service = client.get_service(name=service_path)

        logger.info(
            f'Cloud Run service "{endpoint_name}" exists. Updating...')

        # Update the existing service
        service.template.containers[0].image = container_image_uri

        # Add VPC connector
        service.template.vpc_access = run_v2.VpcAccess(
            connector=vpc_connector,
            egress=run_v2.VpcAccess.VpcEgress.ALL_TRAFFIC
        )

        # Update the service
        operation = client.update_service(
            service=service,
            update_mask={
                'paths': ['template']
            }
        )

    except Exception as e:
        logger.warning('Cloud Run service does not exist. Creating...')

        # Define the Cloud Run Service configuration
        service = run_v2.Service(
            template=run_v2.RevisionTemplate(
                containers=[
                    run_v2.Container(
                        image=container_image_uri,  # Model container
                        resources=run_v2.ResourceRequirements(
                            limits={'memory': '2Gi', 'cpu': '4'}
                        )
                    )
                ],
                vpc_access=run_v2.VpcAccess(  # Attach VPC connector
                    connector=vpc_connector,
                    egress=run_v2.VpcAccess.VpcEgress.ALL_TRAFFIC
                )
            ),
        )
        # Create new service
        operation = client.create_service(
            parent=parent_path,
            service=service,
            service_id=endpoint_name
        )

    # Wait for the operation to complete
    response = operation.result()

    if response:
        cloud_run_url = response.uri
        logger.info(f'Service deployed on CloudRun: {cloud_run_url}')
    else:
        logger.error('Service deployment failed')
        return False

    return True
