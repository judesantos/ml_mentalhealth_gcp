from kfp.dsl import component, Input, Output, Dataset, Artifact


@component(
    base_image="python:3.12",
    packages_to_install=["scikit-learn", "joblib", "pandas"],
)
def train_model(preprocessed_data: Input[Dataset], model_path: Output[Artifact]):
    import pandas as pd
    from sklearn.linear_model import LogisticRegression
    import joblib

    # Load preprocessed data
    data = pd.read_csv(preprocessed_data.path)
    X = data.drop(columns=["target"])
    y = data["target"]

    # Train model
    model = LogisticRegression()
    model.fit(X, y)

    # Save model
    joblib.dump(model, model_path.path)
