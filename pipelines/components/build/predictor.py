from flask import Flask, request, jsonify
import joblib
import numpy as np
import pandas as pd

app = Flask(__name__)

# Load the trained model
MODEL_PATH = "/app/model.joblib"
model = joblib.load(MODEL_PATH)

# Define preprocessing function


def preprocess_input(data):
    """
    Preprocess incoming inference data by applying necessary transformations.

    Args:
        data (dict): The input JSON data containing feature values.

    Returns:
        np.array: Transformed feature array for model prediction.
    """
    # Convert data to DataFrame
    df = pd.DataFrame([data])

    # Ensure all required composite features exist
    # Adjust based on model requirements
    required_features = ["feature1", "feature2", "feature3"]
    for feature in required_features:
        if feature not in df:
            df[feature] = 0  # Default value, change as necessary

    return df.values


@app.route("/predict", methods=["POST"])
def predict():
    """
    Handle incoming prediction requests and return model inference results.
    """
    try:
        # Get JSON data
        input_data = request.get_json()
        if not input_data:
            return jsonify({"error": "No input data provided"}), 400

        # Preprocess input
        processed_data = preprocess_input(input_data)

        # Make prediction
        prediction = model.predict(processed_data)

        # Return response
        return jsonify({"prediction": prediction.tolist()})

    except Exception as e:
        return jsonify({"error": str(e)}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
