import os
from google.cloud import aiplatform

def trigger_pipeline(request):
    """
    Trigger the Vertex AI pipeline to start the data preprocessing job.
    """
    project_id = os.environ.get("PROJECT_ID")
    region = os.environ.get("REGION")
    bucket_name = os.environ.get("BUCKET_NAME")

    # Initialize Vertex AI
    aiplatform.init(project=project_id, location=region)

    # Define pipeline and set the destination of the pipeline template
    pipeline_job = aiplatform.PipelineJob(
        display_name="data-preprocessing-pipeline",
        template_path=f'gs://{bucket_name}/pipeline/pipeline.json',
    )
    pipeline_job.run()

    return "Pipeline triggered successfully", 200
