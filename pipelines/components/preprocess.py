"""
This component fetches the latest file from a GCS bucket and
loads into a pandas DataFrame.

Implements the `preprocess_data` function using kfp.dsl.component
The provided bucket name is used to fetch the latest file from the bucket

Functionality:
- Fetch the latest file from a GCS bucket and store it in a local path
- Load the file into a pandas DataFrame

Output:
- The preprocessed data is saved to the output_data path for
    the next step in the pipeline to consume
"""

from kfp.dsl import component, Output


@component(
    base_image='python:3.12',
    packages_to_install=[
        'pandas',
        'uuid',
        'google-cloud-storage',
        'google-cloud-aiplatform'
    ],
)
def preprocess_data(
    bucket_name: str,
    project_id: str,
    region: str,
    featurestore_id: str,
    entity_type_id: str,
) -> bool:
    """
    Preprocess data by fetching the latest file from a GCS bucket,
    loading into a pandas DataFrame and saving it to the output_data path.

    Args:
        - bucket_name: str, the name of the GCS bucket
        - project_id: str, the project id
        - featurestore_id: str, the featurestore id
        - entity_type_id: str, the entity type id
        - output_data: Output[bool], the output data path

    Returns:
        - bool: True if the data is successfully preprocessed, False otherwise
    """

    import logging
    import uuid
    import pandas as pd
    from google.cloud import storage, aiplatform

    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)

    # ####################################
    #    Helper methods
    # ####################################

    def get_latest_file(bucket_name, prefix=''):
        '''Fetches the latest file from a GCS bucket.'''

        client = storage.Client()
        bucket = client.bucket(bucket_name)
        blobs = list(bucket.list_blobs(prefix=prefix))

        # Sort by last modified time
        blobs.sort(key=lambda x: x.updated, reverse=True)

        if not blobs:
            logger.error('No files found in GCS bucket.')

        latest_blob = blobs[0]  # Get the latest file
        # Store the latest file in /tmp for retrieval by the kfp component.
        local_path = f'/tmp/{latest_blob.name.split('/')[-1]}'
        latest_blob.download_to_filename(local_path)

        return local_path
        # Load and preprocess data

    # ####################################
    #    Main logic
    # ####################################

    try:
        # Initialize Vertex AI Featurestore client
        aiplatform.init(
            project=project_id,
            location=region,
        )

        featurestore = aiplatform.Featurestore(
            featurestore_name=featurestore_id)
        entity_type = featurestore.get_entity_type(entity_type_id)

        # Fetch the latest file from the GCS bucket
        latest_file = get_latest_file(bucket_name)
        df = pd.read_csv(latest_file)

        # Convert the DataFrame to a FeatureValueList
        feature_data = []
        for index, row in df.iterrows():
            feature_data.append({
                'entity_id': str(uuid.uuid4()),
                'feature_values': row.to_dict(),
            })

        # Insert into historical data storage
        # Batch insert (not update) features into the featurestore
        entity_type.batch_create_feature_values(feature_data)

    except Exception as e:
        logger.error(f'An error occurred: {e}')
        return False

    return True
