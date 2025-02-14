"""
This module contains the Cloud Function to trigger the Vertex AI pipeline

The function is triggered by an HTTP request and uses the Vertex AI Python
client library to trigger the pipeline - implemented here.

The function trigger_pipeline is deployed as a Cloud Function in
Google Cloud Platform (GCP)

Steps:
    1. Parse the request payload
    2. Initialize Vertex AI
    3. Trigger the pipeline
    4. Handle exceptions
    5. Return the response
"""

import os
from google.cloud import aiplatform

import logging
from google.cloud import logging as cloud_logging


def trigger_pipeline(request):
    """
    Trigger the Vertex AI pipeline to start the data preprocessing job.
    """
    # Initialize the Cloud Logging client
    client = cloud_logging.Client()
    client.setup_logging()

    project_id = os.environ.get('PROJECT_ID')
    region = os.environ.get('REGION')
    bucket_name = os.environ.get('BUCKET_NAME')

    logging.debug(f'trigger_pipeline request.json: {request.get_json()}')

    # Parse the request payload (JSON)
    parameters = {}

    try:
        request_json = request.get_json(silent=True)
        if request_json and 'parameters' in request_json:
            parameters = request_json['parameters']
    except Exception as e:
        logging.error(f'Error: {str(e.with_traceback(None))}')
        return f'Error parsing request payload: {str(e)}', 400

    try:
        logging.info('Initializing Vertex AI...')

        # Initialize Vertex AI
        aiplatform.init(project=project_id, location=region)

        # Define the pipeline JSON file location in GCS
        pipeline_file = f'gs://{bucket_name}/pipeline.json'

        logging.info('Triggering pipeline...')

        # Define pipeline and set the destination of the pipeline template
        pipeline_job = aiplatform.PipelineJob(
            display_name='data-preprocessing-pipeline',
            template_path=pipeline_file,
            parameter_values=parameters
        )

        logging.info('Run pipeline.')

        pipeline_job.run()

    except Exception as e:
        logging.exception(
            'An error occurred while running the AI platform pipeline.')
        return f'AI platform error: {str(e)}', 400

    return 'Pipeline triggered successfully', 200
