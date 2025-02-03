from kfp.dsl import pipeline
from kfp.compiler import Compiler

from components.preprocess import preprocess_data
from components.train import train_model
from components.evaluate import evaluate_model
from components.register import register_model
from components.build import build_container
from components.deploy import deploy_model


@pipeline(
    name="preprocess-train-register-build-deploy-pipeline",
    description="Pipeline to preprocess, train, evaluate, register, build container, and deploy model.",
)
def mental_health_pipeline(
    input_data: str,
    project_id: str,
    region: str,
    repo_name: str,
    container_image: str,
    endpoint_name: str,
):
    # Step 1: Preprocess data
    preprocess_task = preprocess_data(input_data=input_data)

    # Step 2: Train model
    train_task = train_model(
        preprocessed_data=preprocess_task.outputs["output_data"]
    )

    # Step 3: Evaluate model
    evaluate_task = evaluate_model(
        preprocessed_data=preprocess_task.outputs["output_data"],
        model_path=train_task.outputs["model_path"]
    )

    # Step 4: Register model
    register_task = register_model(
        model_path=train_task.outputs["model_path"],
        project_id=project_id,
        region=region,
        display_name="registered-model"
    )

    # Step 5: Build container
    build_task = build_container(
        model_path=train_task.outputs["model_path"],
        project_id=project_id,
        region=region,
        repo_name=repo_name,
        container_image=container_image
    )

    # Step 6: Deploy model
    deploy_task = deploy_model(
        project_id=project_id,
        region=region,
        container_image=f'{region}-docker.pkg.dev/{project_id}/'
        f'{repo_name}/{container_image}:latest",'
        f'endpoint_name={endpoint_name}',
        endpoint_name=endpoint_name
    )


# Compile the pipeline using KFP v2 compiler.
Compiler().compile(
    pipeline_func=mental_health_pipeline,
    package_path="pipeline.json",
)
