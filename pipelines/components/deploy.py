from kfp.dsl import component


@component(
    base_image="python:3.12",
    packages_to_install=["google-cloud-aiplatform"],
)
def deploy_model(
    project_id: str,
    region: str,
    container_image: str,
    endpoint_name: str,
):
    from google.cloud import aiplatform

    aiplatform.init(project=project_id, location=region)

    # Upload model
    model = aiplatform.Model.upload(
        display_name="custom-prediction-model",
        container_image_uri=container_image,
    )

    # Create or get endpoint
    endpoints = aiplatform.Endpoint.list(
        filter=f'display_name="{endpoint_name}"')
    if endpoints:
        endpoint = endpoints[0]
    else:
        endpoint = aiplatform.Endpoint.create(display_name=endpoint_name)

    # Deploy the model
    model.deploy(
        endpoint=endpoint,
        deployed_model_display_name="custom-prediction-deployment",
        machine_type="n1-standard-4",
    )
