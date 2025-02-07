from kfp.dsl import component, Input, Artifact


@component(
    base_image='python:3.12',
    packages_to_install=['scikit-learn', 'numpy', 'xgboost'],
)
def evaluate_model(
    xtest_data: Input[Artifact],
    ytest_data: Input[Artifact],
    model: Input[Artifact],
) -> bool:
    """
    Evaluate the model using historical data from the Feature Store.

    Args:
        xtest_data: Artifact of the test data
        ytest_data: Artifact of the test labels
        model: Artifact of the trained model

    Returns:
        bool: True if the model evaluation is successful, False
    """

    import logging

    import numpy as np
    import xgboost as xgb
    from sklearn.metrics import log_loss
    from sklearn.metrics import accuracy_score, precision_score
    from sklearn.metrics import recall_score, f1_score

    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)

    def evaluate_model(model_xgb, _x_test, y_test):

        # Predict
        y_pred_probs = model_xgb.predict(_x_test)
        y_pred = y_pred_probs.argmax(axis=1)

        # Evaluate
        final_log_loss = log_loss(y_test, y_pred_probs)

        # Log model metrics
        accuracy = accuracy_score(y_test, y_pred)
        precision = precision_score(y_test, y_pred, average='weighted')
        recall = recall_score(y_test, y_pred, average='weighted')
        f1 = f1_score(y_test, y_pred, average='weighted')

        return final_log_loss, accuracy, precision, recall, f1

    # 1. Deserialize the model and test data

    try:
        logger.info(f'Loading the model from {model.path}...')

        xgb_model = xgb.Booster()
        xgb_model.load_model(model.path)

        xtest = xgb.DMatrix(xtest_data.path)
        ytest = np.load(ytest_data.path)

        # 2. Now we will evaluate the model

        final_log_loss, accuracy, precision, recall, f1 = evaluate_model(
            xgb_model, xtest, ytest
        )

        print(f'Final Log Loss: {final_log_loss}')
        print(f'Accuracy: {accuracy}')
        print(f'Precision: {precision}')
        print(f'Recall: {recall}')
        print(f'F1: {f1}')

    except Exception as e:
        logger.error(f'Failed to evaluate the model: {e}')
        return False

    return True
