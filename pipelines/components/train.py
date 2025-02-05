import pathlib as Path

import numpy as np
from sklearn.model_selection import train_test_split

from kfp.dsl import component, Output, Artifact
from google.cloud import aiplatform

import components.model.xgb_model as xm


@component(
    base_image="python:3.12",
    packages_to_install=["scikit-learn", "joblib", "pandas"],
)
def train_model(
    project_id: str,
    region: str,
    featurestore_id: str,
    entity_type_id: str,
    xtest_output: Output[Artifact],
    ytest_output: Output[Artifact],
    model_output: Output[Artifact],
):
    # 1. Fetch the latest data from the training Feature Store

    # Initialize Vertex AI SDK
    aiplatform.init(project=project_id, location=region)

    # Read all historical feature values from Feature Store
    featurestore = aiplatform.Featurestore(featurestore_id)
    feature_values = featurestore.batch_read_feature_values(
        entity_type_id=entity_type_id
    ).to_dataframe()

    # 2. Prepare the datasets for training - save test for evaluation

    # Let's prepare the datasets for training and save the rest for testing

    target = "_MENT14D"
    features = feature_values.drop(columns=[target])

    # 3. Split into train (60%), eval(20%), and test(20%) sets

    train_data, temp_data = train_test_split(
        features, train_size=0.6, stratify=feature_values)
    eval_data, test_data = train_test_split(
        temp_data, test_size=0.5, stratify=temp_data[target])

    # 4. Now we will train the model

    # Separate the target from the features
    X_train = train_data.drop(columns=[target])
    y_train = train_data[target]
    x_val = eval_data.drop(columns=[target])
    y_val = eval_data[target]
    x_test = test_data.drop(columns=[target])
    y_test = test_data[target]

    _y_train = xm.target_label_mapping(y=y_train)
    _y_val = xm.target_label_mapping(y=y_val)
    _y_test = xm.target_label_mapping(y=y_test)

    # Train the model
    xgb_model, _x_test = xm.train_model(
        X_train,
        _y_train,
        x_val,
        _y_val,
        x_test,
        _y_test
    )

    if xgb_model is None or _x_test is None:
        raise ValueError("Training failed.")

    # 4. Save the model and test sets for the evaluation component

    xgb_model.save_model(model_output.path)
    _x_test.save_binary(xtest_output.path)
    np.save(ytest_output.path, _y_test)
