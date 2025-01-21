import os
from google.cloud import aiplatform

def deploy_model(request):
    project_id = os.environ.get("PROJECT_ID")
    region = os.environ.get("REGION")

    aiplatform.init(project=project_id, location=region)

    # Create or get an endpoint
    endpoint = aiplatform.Endpoint.create(display_name="vertex-model-endpoint")

    # Deploy the model
    model = aiplatform.Model.list(filter="display_name=vertex-trained-model")[0]
    endpoint.deploy(model=model, deployed_model_display_name="deployed-model")

    return f"Model deployed to endpoint {endpoint.display_name}", 200
