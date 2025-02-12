import os
import logging
from typing import List, Dict

import pandas as pd
import xgboost as xgb

from ml_inference_data import MentalHealthData

from flask import Flask, request, jsonify

# Create a Flask app
app = Flask(__name__)

# Enable console logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Load the trained model from the environment variable MODEL_URI which
# was set in the Vertex AI registration step.
MODEL_PATH = os.getenv('MODEL_URI')

model = xgb.Booster()
model.load_model(MODEL_PATH)

# Define feature names and expected order

FEATURE_NAMES = [
    'poorhlth', 'physhlth', 'genhlth', 'diffwalk', 'diffalon',
    'checkup1', 'diffdres', 'addepev3', 'acedeprs', 'sdlonely', 'lsatisfy',
    'emtsuprt', 'decide', 'cdsocia1', 'cddiscu1', 'cimemlo1', 'smokday2',
    'alcday4', 'marijan1', 'exeroft1', 'usenow3', 'firearm5', 'income3',
    'educa', 'employ1', 'sex', 'marital', 'adult', 'rrclass3', 'qstlang',
    '_state', 'veteran3', 'medcost1', 'sdhbills', 'sdhemply', 'sdhfood1',
    'sdhstre1', 'sdhutils', 'sdhtrnsp', 'cdhous1', 'foodstmp', 'pregnant',
    'asthnow', 'havarth4', 'chcscnc1', 'chcocnc1', 'diabete4', 'chccopd3',
    'cholchk3', 'bpmeds1', 'bphigh6', 'cvdstrk3', 'cvdcrhd4', 'chckdny2',
    'cholmed3'
]

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

# Define preprocessing function


def _predict(mh: MentalHealthData):
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


@app.route('/predict', methods=['POST'])
def predict():
    """
    Handle incoming prediction requests and return model inference results.
    """
    try:
        # Get JSON data
        input_data = request.get_json()
        if not input_data:
            return jsonify({'error': 'No input data provided'}), 400

        # Preprocess input
        processed_data = _preprocess_input(input_data)

        # Make prediction
        prediction = _predict(processed_data)

        # Return response
        return jsonify({
            'success': 'true',
            'prediction': prediction.tolist()
        })

    except Exception as e:
        logger.error(f'An error occurred: {e}')
        return jsonify({
            'success': 'false',
            'error': 'Server error occurred'
        }), 500


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)
