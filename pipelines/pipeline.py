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
from components.build.build import build_container
from components.deploy import deploy_model


@component(base_image='python:3.12')
def cleanup(message: str):
    """
    Cleanup the workspace after the pipeline execution.
    """
    print(message)


def run_mental_health_pipeline(
    project_id: str,
    region: str,
    bucket_name: str,
    featurestore_id: str,
    entity_type_id: str,
    container_image_uri: str,
    endpoint_name: str,
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
        endpoint_name (str): The Vertex AI endpoint name.
    """

    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)

    # Define the exit handler to cleanup the workspace
    handle_exit = cleanup(message='Terminating pipeline, error occurred.')

    with dsl.ExitHandler(exit_task=handle_exit):
        # Exit early if any one of the pipeline step fails

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
        preprocess_task.set_caching_options(enable_caching=False)

        with dsl.If(preprocess_task.outputs['Output'] == True, name='preprocess-success'):

            # -------------------------------------
            # Step 2: Train model
            # -------------------------------------

            train_task = train_model(
                project_id=project_id,
                region=region,
                featurestore_id=featurestore_id,
                entity_type_id=entity_type_id
            ).after(preprocess_task)
            train_task.set_caching_options(enable_caching=False)

            with dsl.If(train_task.outputs['Output'] == True, name='train-success'):

                xtest_data = train_task.outputs['xtest_output']
                ytest_data = train_task.outputs['ytest_output']
                model = train_task.outputs['model_output']

                # -------------------------------------
                # Step 3: Evaluate model
                # -------------------------------------

                evaluate_task = evaluate_model(
                    xtest_data=xtest_data,
                    ytest_data=ytest_data,
                    model=model
                ).after(train_task)
                evaluate_task.set_caching_options(enable_caching=False)

                if dsl.If(evaluate_task.outputs['Output'] == True, name='evaluate-success'):

                    # -------------------------------------
                    # Step 4: Build container
                    # -------------------------------------

                    build_task = build_container(
                        model=model,
                        project_id=project_id,
                        container_image_uri=container_image_uri
                    ).after(evaluate_task)
                    build_task.set_caching_options(enable_caching=False)

                    if dsl.If(build_task.outputs['Output'] == True, name='build-success'):

                        # -------------------------------------
                        # Step 5: Register model
                        # -------------------------------------

                        # Instead of registering the model, we register the custome middleware
                        # to Vertex AI Model Registry

                        register_task = register_model(
                            container_image_uri=container_image_uri,
                            project_id=project_id,
                            region=region,
                            display_name='xgboost-middleware'
                        ).after(build_task)
                        register_task.set_caching_options(enable_caching=False)

                        if dsl.If(register_task.outputs['Output'] == True, name='register-model-success'):

                            # -------------------------------------
                            # Step 6: Deploy model
                            # -------------------------------------

                            deploy_task = deploy_model(
                                project_id=project_id,
                                region=region,
                                container_image_uri=container_image_uri,
                                endpoint_name=endpoint_name
                            ).after(register_task)
                            deploy_task.set_caching_options(
                                enable_caching=False)


@pipeline(
    name='preprocess-train-register-build-deploy-pipeline',
    description='''Pipeline to preprocess, train, evaluate, register,
    build container, and deploy model.''',
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
        endpoint_name,
    )


# Compile the pipeline
Compiler().compile(
    pipeline_func=mental_health_pipeline,
    package_path='pipeline.json',  # Use this for deploying the pipeline
)
