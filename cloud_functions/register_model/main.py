import os
from google.cloud import aiplatform

def register_model(request):
    project_id = os.environ.get("PROJECT_ID")
    region = os.environ.get("REGION")

    aiplatform.init(project=project_id, location=region)

    # Register the model
    model = aiplatform.Model.upload(
        display_name="vertex-trained-model",
        artifact_uri="gs://YOUR_BUCKET_NAME/model/",
        serving_container_image_uri="us-docker.pkg.dev/vertex-ai/prediction/sklearn-cpu.0-24:latest",
    )

    return f"Model {model.display_name} registered successfully", 200
