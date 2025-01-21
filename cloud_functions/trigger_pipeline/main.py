import os
from google.cloud import aiplatform

def trigger_pipeline(request):
    project_id = os.environ.get("PROJECT_ID")
    region = os.environ.get("REGION")

    # Initialize Vertex AI
    aiplatform.init(project=project_id, location=region)

    # Define pipeline
    pipeline_job = aiplatform.PipelineJob(
        display_name="data-preprocessing-pipeline",
        template_path="gs://YOUR_BUCKET_NAME/pipeline.json",
    )
    pipeline_job.run()

    return "Pipeline triggered successfully", 200
