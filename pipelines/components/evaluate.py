from kfp.dsl import component, Input, Artifact, Dataset


@component(
    base_image="python:3.12",
    packages_to_install=["scikit-learn", "pandas"]
)
def evaluate_model(preprocessed_data: Input[Dataset], model_path: Input[Artifact]) -> float:
    import pandas as pd
    from sklearn.metrics import accuracy_score
    import joblib

    # Load preprocessed data and model
    data = pd.read_csv(preprocessed_data.path)
    X = data.drop(columns=["target"])
    y = data["target"]
    model = joblib.load(model_path.path)

    # Evaluate model
    predictions = model.predict(X)
    accuracy = accuracy_score(y, predictions)
    print(f"Model Accuracy: {accuracy}")
    return accuracy
