"""
This module is a pipeline component used for building a container image
using Cloud Build. The container image will server as the middleware for
the ML model, which is then deployed in the Vertex AI endpoint.

The ML model can be deployed in Vertex AI endpoint without a middleware,
but in the case of the mental health prediction model,
we need to preprocess inference data and add a list of required
composite features. The middleware will handle these tasks.
"""
from kfp.dsl import component, Input, Artifact
from google.cloud.devtools.cloudbuild_v1.services.cloud_build import CloudBuildClient
from google.cloud.devtools.cloudbuild_v1.types import Build


@component(
    base_image="python:3.12",
    packages_to_install=["google-cloud-build"],
)
def build_container(
    model_path: Input[Artifact],
    project_id: str,
    region: str,
    repo_name: str,
    container_image: str,
):
    """
    Build a container image using Cloud Build.

    Build steps:
        - Write a Dockerfile
        - Build the Docker image
        - Push the Docker image to Container Registry

    Args:
        - model_path: Artifact of the trained model
        - project_id: str, the project id
        - region: str, the region
        - repo_name: str, the repository name
        - container_image: str, the container image name
    """
    # Write a Dockerfile
    dockerfile = f'''
    FROM python:3.12
    WORKDIR /app
    COPY {model_path.path} /app/model.joblib
    COPY predictor.py /app/
    RUN pip install flask pandas numpy scikit-learn joblib
    EXPOSE 8080
    CMD ["python", "predictor.py"]
    '''
    with open("Dockerfile", "w") as f:
        f.write(dockerfile)

    # Cloud Build client
    client = CloudBuildClient()

    # Define build
    build = Build(steps=[{
        "name": "gcr.io/cloud-builders/docker",
        "args": [
            "build",
            "-t",
            f"{region}-docker.pkg.dev/{project_id}/{repo_name}/{container_image}:latest",
            ".",
        ]}, {
            "name": "gcr.io/cloud-builders/docker",
            "args": [
                "push",
                f"{region}-docker.pkg.dev/{project_id}/{repo_name}/{container_image}:latest",
            ],
        }],
        images=[
            f"{region}-docker.pkg.dev/{project_id}/{repo_name}/{container_image}:latest"],
    )

    # Trigger the build
    client.create_build(project_id=project_id, build=build)
