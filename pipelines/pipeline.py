"""
This module defines the deployment pipeline for the mental health prediction
model using Vertex AI and Kubeflow Pipelines (KFP).

The model is based on XGBoost (Extreme Gradient Boosting), a classification
algorithm deployed in Vertex AI to predict mental health outcomes based
on survey responses.

Pipeline Steps:
    1. Preprocess Data:
    - Fetch the latest dataset from a GCS bucket.
    - Load it into a pandas DataFrame.
    - Save the processed data to the output path.

    2. Train Model:
    - Train the XGBoost model using the training/validation dataset.
    - Evaluate model performance on the test dataset.
    - Save the trained model and evaluation results.

    3. Evaluate Model:
    - Assess model performance on the test dataset.
    - Calculate and log evaluation metrics.

    4. Register Model:
    - Register the trained model in the Vertex AI Model Registry.

    5. Build Middleware Container:
        The model requires a middleware to preprocess
        inference data. To do this, we host the model in a container image
        which will be wedged between the model and the Vertex AI endpoint.
        Middleware will preprocess the data and send the preprocessed
        result out to the model endpoint.
    - Use Cloud Build to create a container image for the middleware.
    - Package the model for deployment as middleware in Vertex AI.

    6. Deploy Model:
    - Deploy the trained model to a Vertex AI endpoint for serving predictions.
"""

import logging

import kfp.dsl as dsl
from kfp.dsl import pipeline, component
from kfp.compiler import Compiler

from components.preprocess import preprocess_data
from components.train import train_model
from components.evaluate import evaluate_model
from components.register import register_model
from components.deploy_cloudrun import deploy_model


def run_mental_health_pipeline(
    project_id: str,
    region: str,
    bucket_name: str,
    featurestore_id: str,
    entity_type_id: str,
    container_image_uri: str,
    endpoint_name: str
):
    """
    Pipeline to preprocess, train, evaluate, register, build container,
    and deploy model.

    Pipeline Steps:
        1. Preprocess Data: Get the latest dataset from a GCS bucket.
        2. Train Model: Train the XGBoost model using the training dataset.
        3. Evaluate Model: Evaluate model performance on the test dataset.
        4. Register Model: Register the trained model in the Vertex AI Model
            Registry.
        5. Build Middleware Container: Build a container image for the model
            endpoint middleware.
        6. Deploy Model: Deploy the trained model to a Vertex AI endpoint.

    Args:
        bucket_name (str): The name of the GCS bucket.
        project_id (str): The GCP project ID.
        featurestore_id (str): The Vertex AI Feature Store ID.
        entity_type_id (str): The Vertex AI Entity Type ID.
        region (str): The GCP region.
        repo_name (str): The name of the GCP repository.
        container_image (str): The container image name.
    """

    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)

    # We want to cache the results of each step in the pipeline for subsequent
    # runs and reuse the component the same image, but exceptions can
    # invalidate the cache. Handle exceptions and set run_success to False
    # if an error occurs. This will prevent the pipeline from running the
    # next steps, and will not invalidate the cache.
    run_success = True

    # -------------------------------------
    # Step 1: Preprocess data
    # -------------------------------------

    preprocess_task = preprocess_data(
        bucket_name=bucket_name,
        region=region,
        project_id=project_id,
        featurestore_id=featurestore_id,
        entity_type_id=entity_type_id
    )

    run_success = preprocess_task.output

    # -------------------------------------
    # Step 2: Train model
    # -------------------------------------

    if run_success:
        train_task = train_model(
            project_id=project_id,
            region=region,
            featurestore_id=featurestore_id,
            entity_type_id=entity_type_id
        ).after(preprocess_task)  # Make sure to run after preprocessing

    run_success = train_task.outputs['Output']

    # -------------------------------------
    # Step 3: Evaluate model
    # -------------------------------------

    if run_success:
        xtest_data = train_task.outputs['xtest_output']
        ytest_data = train_task.outputs['ytest_output']
        model_artifact = train_task.outputs['model_output']

        evaluate_task = evaluate_model(
            xtest_data=xtest_data,
            ytest_data=ytest_data,
            model=model_artifact
        ).after(train_task)  # Make sure to run after training

    run_success = evaluate_task.output

    # -------------------------------------
    # Step 4: Register model
    # -------------------------------------

    if run_success:
        # Instead of registering the model,
        # we register the custom middleware
        # to Vertex AI Model Registry
        register_task = register_model(
            project_id=project_id,
            region=region,
            display_name='xgb-model',
            model_artifact=model_artifact,
            container_image_uri=container_image_uri,
        ).after(evaluate_task)

    run_success = register_task.outputs['Output']

    # -------------------------------------
    # Step 5: Deploy model
    # -------------------------------------

    if run_success:

        model_resource = register_task.outputs['model_resource']

        deploy_task = deploy_model(
            project_id=project_id,
            region=region,
            endpoint_name=endpoint_name,
            container_image_uri=container_image_uri,
            model_resource=model_resource,
        ).after(register_task)

    run_success = deploy_task.output

    if run_success:
        logger.info('Pipeline completed successfully.')
    else:
        logger.error('Pipeline failed.')


@pipeline(
    name='model-training-pipeline',
    description='''Pipeline to preprocess, train, evaluate,
    build container, register, and deploy model.''',
)
def mental_health_pipeline(
    project_id: str,
    region: str,
    bucket_name: str,
    featurestore_id: str,
    entity_type_id: str,
    container_image_uri: str,
    endpoint_name: str,
):
    run_mental_health_pipeline(
        project_id,
        region,
        bucket_name,
        featurestore_id,
        entity_type_id,
        container_image_uri,
        endpoint_name
    )


# Compile the pipeline
Compiler().compile(
    pipeline_func=mental_health_pipeline,
    package_path='pipeline.json',  # Use this for deploying the pipeline
)
