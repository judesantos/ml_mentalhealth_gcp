"""
This module defines the custom container API endpoint for the Vertex AI model

The container implements the model inference endpoint. It is a Flask app with
a single POST endpoint /predict that accepts JSON data and returns the model
prediction. Incoming prediction requests are prepared, processed, transformed,
before being submitted to the model for prediction.

    Vertex AI Custom Container Requirements:
    - The container must listen on port 8080
    - The container must have a health check endpoint at /health
    - The health check endpoint must return a 200 status code
    - The container must have a prediction endpoint at /predict
    - The container must accept JSON data for prediction
    - The container must return JSON data for prediction

    Vertex AI Predefined Environment Variables:
    - AIP_STORAGE_URI: The path to the model artifact in the container
    - AIP_HTTP_PORT: The port on which the container listens
    - AIP_HEALTH_ROUTE: The health check endpoint
    - AIP_PREDICT_ROUTE: The prediction endpoint

Runs on Gunicorn to manage concurrent requests
"""

import os
import joblib
import logging
from typing import List, Dict
from threading import Lock

import pandas as pd
import xgboost as xgb

from flask import Flask, request, jsonify
from google.cloud import storage

from ml_inference_data import MentalHealthData


# Create a Flask app
app = Flask(__name__)
model_lock = Lock()

# The trained model object - initialized to None
# Load on first request
xgb_model = None

# Enable logging
logging.basicConfig(level=logging.INFO, force=True)
logger = logging.getLogger(__name__)

# ---------------------------------------------------
# Define feature names and expected order of features
# ---------------------------------------------------

EXPECTED_FEATURE_ORDER = [
    'poorhlth', 'physhlth', 'genhlth', 'diffwalk', 'diffalon',
    'checkup1', 'diffdres', 'addepev3', 'acedeprs', 'sdlonely', 'lsatisfy',
    'emtsuprt', 'decide', 'cdsocia1', 'cddiscu1', 'cimemlo1', 'smokday2',
    'alcday4', 'marijan1', 'exeroft1', 'usenow3', 'firearm5', 'income3',
    'educa', 'employ1', 'sex', 'marital', 'adult', 'rrclass3', 'qstlang',
    'state', 'veteran3', 'medcost1', 'sdhbills', 'sdhemply', 'sdhfood1',
    'sdhstre1', 'sdhutils', 'sdhtrnsp', 'cdhous1', 'foodstmp', 'pregnant',
    'asthnow', 'havarth4', 'chcscnc1', 'chcocnc1', 'diabete4', 'chccopd3',
    'cholchk3', 'bpmeds1', 'bphigh6', 'cvdstrk3', 'cvdcrhd4', 'chckdny2',
    'cholmed3'
]

# -----------------------------
# Define preprocessing function
# -----------------------------

# Fallback model uri, AIP_STORAGE_URI is not set (Why - ask Google)
GCS_MODEL_PATH = os.getenv('AIP_STORAGE_URI')


def _load_model():
    """
    Load the trained model from the model artifact in the container.
    Loads the trained model from the environment variable AIP_MODEL_DIR which
    is set in the Vertex AI registration step.
    """
    global xgb_model
    global GCS_MODEL_PATH

    MODEL_URI = 'gs://mlops-gcs-bucket/models/xgb-model/'

    # MODEL_PATH = '/tmp/model.joblib'
    if xgb_model is None:
        if not GCS_MODEL_PATH:
            print('AIP_STORAGE_URI environment variable not set.')
            print(f'Loading model from {MODEL_URI}...')
            GCS_MODEL_PATH = MODEL_URI

        # Extract bucket name and prefix from GCS path

        parts = GCS_MODEL_PATH[5:].split("/", 1)
        bucket_name = parts[0]
        prefix = parts[1] if len(parts) > 1 else ""

        print(f'Setting bucket name: {bucket_name}...')

        # Initialize GCS client

        client = storage.Client()
        bucket = client.bucket(bucket_name)

        # List all blobs in the bucket

        blobs = list(bucket.list_blobs(prefix=prefix))

        if not blobs:
            raise ValueError('No files found in the bucket.')

        # Find the model file with the correct extension

        exts = ['.joblib']  # joblib is our model file extension
        model_blob = next(
            (b for b in blobs if b.name.endswith(tuple(exts))), None)

        if not model_blob:
            raise ValueError('No model file found in the bucket.')

        # Download the model file to /tmp
        model_path = os.path.join('/tmp', os.path.basename(model_blob.name))
        model_blob.download_to_filename(model_path)

        # Load the model
        xgb_model = joblib.load(model_path)

    return xgb_model


def _predict(mh: MentalHealthData, model):
    """
    Make a prediction using the trained model.
    Args:
        data (MentalHealthData): The preprocessed data for prediction.
    Returns:
        np.array: The model prediction.
    """
    # XGb expects data in DMatrix format
    # mh.get_data() passes in the predictors in the correct order
    xgb_features = xgb.DMatrix(mh.get_data())

    # Make predictions
    return model.predict(xgb_features)


def _preprocess_input(data: List):
    """
    Preprocess incoming inference data by applying necessary transformations.
    Args:
        data (dict): The input JSON data containing feature values.
    Returns:
        np.array: Transformed feature array for model prediction.
    """
    # Convert the input data to a pandas DataFrame
    _df = pd.DataFrame(data).astype(int)
    # Reorder the features to match the expected model order
    df = _df[EXPECTED_FEATURE_ORDER]

    # Prepare our inference data
    # MentalHealthData can process both feature with target data,
    # or just feature data, including composite features
    # In this case, we are only interested in the feature and composite
    # data
    return MentalHealthData(df)


# ----------------------------------------------------------------
# Define HTTP route - /predict, /health (As required by Vertex AI)
# for custom containers
# ----------------------------------------------------------------


@app.route('/health', methods=['GET'])
def health_check():
    """
    Define a health check endpoint for the container.
    This is a required endpoint for Vertex AI custom containers.
    """
    print('Health check endpoint called. Returning 200 OK.')
    return jsonify({"status": "healthy"}), 200


@app.route('/predict', methods=['POST'])
def predict():
    """
    Define the prediction endpoint for the container.
    This is the required endpoint spefication for Vertex AI custom containers.
    Handles incoming prediction requests and returns model inference results.
    Args:
        request: The incoming request object.
    Steps:
        1. Parse the request payload
        2. Preprocess the input data
        3. Make the model prediction
        4. Return the response
    Returns:
        JSON: The model prediction.
    """
    try:
        logger.info('Predict endpoint called.')
        # Print raw request headers and body
        logger.debug(f'Request Headers: {request.headers}')
        logger.debug(f'Request JSON: {request.get_json(
            silent=True)}')  # Parsed JSON

        # Validate input

        if request.content_type != "application/json":
            logger.error('Invalid content type. Expected application/json.')
            return jsonify({"error": "Unsupported Media Type. Please use 'application/json'"}), 415

        input_data = request.get_json(silent=True)
        if not input_data:
            logger.error('No input data provided.')
            return jsonify({'error': 'No input data provided.'}), 400

        # Single instance prediction
        if "features" in input_data:
            input_data = [input_data["features"]]
        # Batch prediction
        elif "instances" in input_data:
            input_data = input_data["instances"]
        else:
            logger.error('Invalid input data format.')
            return jsonify({'error': 'Invalid input data format.'}), 400

        if len(input_data[0]) != 55:
            logger.error('Invalid number of parameters.')
            return jsonify({'error': 'Invalid number of parameters.'}), 400

        # Preprocess input
        processed_data = _preprocess_input(input_data)

        # Make prediction
        with model_lock:
            # Load the model
            model = _load_model()
            # Predict!
            logger.info('Making prediction...')
            predictions = _predict(processed_data, model)

        logger.debug(f'Predictions: {predictions}')

        # Return response
        return jsonify({
            'success': 'true',
            'prediction': predictions.tolist()
        })

    except Exception as e:
        logger.exception(f'An error occurred:')
        return jsonify({
            'success': 'false',
            'error': 'Server error occurred'
        }), 500

# -------------------
# Run the Flask app
# -------------------


if __name__ == '__main__':
    # Load the model singleton
    _load_model()
    # Vertext AI custom containers require the app to listen on port 8080
    app.run(
        debug=True,
        host='0.0.0.0',
        port=8080
    )
