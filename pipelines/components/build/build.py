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


@component(
    base_image='python:3.12',
    packages_to_install=['google-cloud-build'],
)
def build_container(
    model: Input[Artifact],
    project_id: str,
    container_image_uri: str,
) -> bool:
    """
    Build a container image using Cloud Build.

    Build steps:
        - Write a Dockerfile
        - Build the Docker image
        - Push the Docker image to Container Registry

    Args:
        - model_path: Artifact of the trained model
        - project_id: str, the project id
        - container_image_uri: str, the container image name

    Returns:
        - bool: True if the container image is successfully built, False otherwise
    """

    import logging

    from google.cloud.devtools.cloudbuild_v1.services.cloud_build import CloudBuildClient
    from google.cloud.devtools.cloudbuild_v1.types import Build

    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)

    try:
        # 1.Write a Dockerfile

        MODEL_PATH = 'model.path'
        logger.info(f'Copying the model to the current directory from {
                    model.path}...')

        logger.info(f'Model copied to {path}')
        logger.info('Writing the Dockerfile...')

        dockerfile = f'''
        FROM python:3.12
        WORKDIR /app
        COPY {model.path} /app/{MODEL_PATH}
        COPY predictor.py /app/
        COPY ml_inference_data.py /app/
        RUN pip install flask pandas numpy scikit-learn xgboost
        EXPOSE 8080
        CMD ['python', 'predictor.py']
        '''
        with open('Dockerfile', 'w') as f:
            f.write(dockerfile)

        # 2. Define a middleware image build using Cloud Build client

        logger.info('Building the container image...')

        build = Build(
            steps=[
                {  # Build the Docker image
                    'name': 'gcr.io/cloud-builders/docker',
                    'args': ['build', '-t', container_image_uri, '.']
                },
                {  # Push the Docker image to Container Registry
                    'name': 'gcr.io/cloud-builders/docker',
                    'args': ['push', container_image_uri]
                }
            ],
            images=[container_image_uri],
            tags=[container_image_uri],
        )

        # 3. Run the build

        logger.info('Running the build...')

        CloudBuildClient().create_build(project_id=project_id, build=build)

        logger.info('Container image built successfully!')

    except Exception as e:
        logger.error(f'Failed to build the container image: {e}')
        return False

    return True
