import numpy as np
import pandas as pd
import xgboost as xgb

from kfp.dsl import component, Input, Artifact
from google.cloud import aiplatform

from components.model.xgb_model import evaluate_model


@component(
    base_image="python:3.12",
    packages_to_install=["scikit-learn", "pandas"]
)
def evaluate_model(
    project_id: str,
    region: str,
    featurestore_id: str,
    entity_type_id: str,
    xtest_data: Input[Artifact],
    ytest_data: Input[Artifact],
    model: Input[Artifact],
) -> float:
    """
    Evaluate the model using historical data from the Feature Store.
    """

    # 1. Deserialize the model and test data

    xgb_model = xgb.Booster()
    xgb_model.load_model(model.path)

    xtest = xgb.DMatrix(xtest_data.path)
    ytest = np.load(ytest_data.path)

    # 2. Now we will evaluate the model

    final_log_loss, accuracy, precision, recall, f1 = evaluate_model(
        xgb_model, xtest, ytest
    )

    print(f"Final Log Loss: {final_log_loss}")
    print(f"Accuracy: {accuracy}")
    print(f"Precision: {precision}")
    print(f"Recall: {recall}")
    print(f"F1: {f1}")
