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
        'pyarrow',
        'google-cloud-storage',
        'google-cloud-bigquery',
        'uuid7',
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

    import datetime
    import logging
    from uuid_extensions import uuid7

    import pandas as pd
    from google.cloud import storage, bigquery

    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)

    FEATURE_NAMES = [
        'POORHLTH', 'PHYSHLTH', 'GENHLTH', 'DIFFWALK', 'DIFFALON',
        'CHECKUP1', 'DIFFDRES', 'ADDEPEV3', 'ACEDEPRS', 'SDLONELY', 'LSATISFY',
        'EMTSUPRT', 'DECIDE', 'CDSOCIA1', 'CDDISCU1', 'CIMEMLO1', 'SMOKDAY2',
        'ALCDAY4', 'MARIJAN1', 'EXEROFT1', 'USENOW3', 'FIREARM5', 'INCOME3',
        'EDUCA', 'EMPLOY1', 'SEX', 'MARITAL', 'ADULT', 'RRCLASS3', 'QSTLANG',
        '_STATE', 'VETERAN3', 'MEDCOST1', 'SDHBILLS', 'SDHEMPLY', 'SDHFOOD1',
        'SDHSTRE1', 'SDHUTILS', 'SDHTRNSP', 'CDHOUS1', 'FOODSTMP', 'PREGNANT',
        'ASTHNOW', 'HAVARTH4', 'CHCSCNC1', 'CHCOCNC1', 'DIABETE4', 'CHCCOPD3',
        'CHOLCHK3', 'BPMEDS1', 'BPHIGH6', 'CVDSTRK3', 'CVDCRHD4', 'CHCKDNY2',
        'CHOLMED3', '_MENT14D'
    ]

    return True

    # ####################################
    #    Helper methods
    # ####################################

    def get_latest_file(bucket_name, prefix=None):
        '''Fetches the latest file from a GCS bucket.'''

        logger.info(f'Fetching the latest file from the GCS bucket..')

        client = storage.Client()
        bucket = client.bucket(bucket_name)
        blobs = list(bucket.list_blobs(prefix=prefix))

        # Sort by last modified time
        blobs.sort(key=lambda x: x.updated, reverse=True)

        if not blobs:
            logger.error('No files found in GCS bucket.')

        latest_blob = blobs[0]  # Get the latest file

        logger.info(f'Latest file: {latest_blob.name}')

        # Store the latest file in /tmp for retrieval by the kfp component.

        logger.info(f'Downloading the latest file to /tmp...')

        local_path = f'/tmp/{latest_blob.name.split('/')[-1]}'
        latest_blob.download_to_filename(local_path)

        logger.info(f'File downloaded to {local_path}')

        return local_path
        # Load and preprocess data

    # ####################################
    #    Main logic
    # ####################################

    try:
        # Initialize BigQuery client

        logger.info(f'Fetching the latest file from the GCS bucket {
                    bucket_name}...')

        parent, data_file_subdir = bucket_name.split('/', 1)

        # Fetch the latest file from the GCS bucket
        latest_file = get_latest_file(
            bucket_name=parent, prefix=data_file_subdir)

        logger.info(f'Loading the file into a pandas DataFrame...')

        # Load the file into a pandas DataFrame
        df = pd.read_csv(latest_file, index_col=0)
        # Get all included columns. See: FEATURE_NAMES
        df = df[FEATURE_NAMES]
        # Convert all data columns to int
        df = df.astype('int64')
        # Add a 'entity_id':id, 'feature_time':ts columns
        #  (Vertex-ai feature store requirement),
        df['id'] = [str(uuid7()) for _ in range(len(df))]
        df['ts'] = pd.Timestamp.utcnow().strftime('%Y-%m-%d %H:%M:%S')

        # Get the columns from the DataFrame converted to lowercase,
        # removing the prefix '_' in any column name
        df.columns = [col.lower().lstrip('_') for col in df.columns]

        logger.info(f'Ingesting {df.shape[0]} rows into {entity_type_id}...')

        # Ingest the data into the featurestore

        full_table_id = f'{project_id}.{featurestore_id}.{entity_type_id}'

        job_config = bigquery.LoadJobConfig(
            write_disposition=bigquery.WriteDisposition.WRITE_APPEND,  # Append to existing table
            autodetect=True,  # Auto-detect schema
        )

        logger.info('Initializing biqquery client...')

        client = bigquery.Client(project=project_id, location=region)

        logger.info(f'Ingesting {df.shape[0]} rows into {entity_type_id}...')

        # Load data into BigQuery
        job = client.load_table_from_dataframe(
            df, full_table_id, job_config=job_config)

        job.result()  # Waits for the job to complete

        logger.info(f'Ingested {job.output_rows} rows into {entity_type_id}.')

    except Exception as e:
        logger.error(f'An error occurred: {str(e)}')
        return False

    return True
