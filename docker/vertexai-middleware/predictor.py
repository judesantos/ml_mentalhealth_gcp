"""
This module defines the custom container for the Vertex AI model

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
    - AIP_MODEL_DIR: The path to the model artifact in the container
    - AIP_HTTP_PORT: The port on which the container listens
    - AIP_HEALTH_ROUTE: The health check endpoint
    - AIP_PREDICT_ROUTE: The prediction endpoint
"""

import os
import joblib
from functools import lru_cache

import logging
from typing import List, Dict

import pandas as pd
import xgboost as xgb

from ml_inference_data import MentalHealthData

from flask import Flask, request, jsonify
from threading import Lock

# Create a Flask app
app = Flask(__name__)
model_lock = Lock()

# The trained model object - initialized to None
# Load on first request
xgb_model = None

# Enable logging
logging.basicConfig(level=logging.INFO)
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


def _load_model():
    """
    Load the trained model from the model artifact in the container.
    Loads the trained model from the environment variable AIP_MODEL_DIR which
    was set in the Vertex AI registration step.
    """
    global xgb_model
    if xgb_model is None:
        # Check if the model path is set
        model_path = os.getenv('AIP_MODEL_DIR')
        if model_path is None or not os.path.exists('AIP_MODEL_DIR'):
            raise ValueError('Model path (AIP_MODEL_DIR) not found. Exiting.')

        # Load the model from the given path
        xgb_model = xgb.Booster()
        xgb_model.load_model(model_path)

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


def _preprocess_input(data: List[Dict[str, str]]):
    """
    Preprocess incoming inference data by applying necessary transformations.
    Args:
        data (dict): The input JSON data containing feature values.
    Returns:
        np.array: Transformed feature array for model prediction.
    """
    _data = _reorder_features(data)
    # Convert data to DataFrame
    df = pd.DataFrame(_data, columns=EXPECTED_FEATURE_ORDER)

    # Prepare our inference data
    # MentalHealthData can process both feature with target data,
    # or just feature data, including composite features
    # In this case, we are only interested in the feature and composite
    # data
    return MentalHealthData(df)


def _reorder_features(batch: List[Dict[str, str]]):
    """
    Reorder input data to match the expected feature order.
    The submitted batch data is expected to be without missing values

    The reordering requires the incoming batch to be in dictionary format
    so as to be able to determine the feature names of each input value.
    Once the proper order is determnined, we can now do away with the
    column names in the batch and return only the values in
    the correct order.
    Args:
        data list[dict]: Input data as a dictionary.
        expected_order (list): List of features in the correct order.
    Returns:
        list[List]: Batch of features in the correct order.
    """

    ordered_batch = []

    for features in batch:
        _features = [int(features[feature]) for feature in
                     EXPECTED_FEATURE_ORDER if feature in features]
        # Append the ordered feature values to the batch
        ordered_batch.append(_features)

    logger.debug(f'Ordered batch: {ordered_batch}')
    return ordered_batch

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
        # Load the model
        model = _load_model()

        # Get JSON data
        input_data = request.get_json()
        if not input_data:
            logger.error('No input data provided.')
            return jsonify({'error': 'No input data provided.'}), 400
        if len(input_data) != 55:
            logger.error('Invalid number of parameters.')
            return jsonify({'error': 'Invalid number of parameters.'}), 400

        # Preprocess input
        processed_data = _preprocess_input(input_data)

        # Make prediction
        with model_lock:
            prediction = _predict(processed_data, model)

        # Return response
        return jsonify({
            'success': 'true',
            'prediction': prediction.tolist()
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
    # Vertext AI custom containers require the app to listen on port 8080
    app.run(host='0.0.0.0', port=8080)
