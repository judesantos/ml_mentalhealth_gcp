from kfp.dsl import component, Output, Dataset


@component(
    base_image="python:3.12",
    packages_to_install=["pandas", "numpy"]
)
def preprocess_data(input_data: str, output_data: Output[Dataset]):
    import pandas as pd
    import numpy as np

    # Load and preprocess data
    data = pd.read_csv(input_data)
    data.fillna(0, inplace=True)  # Example preprocessing
    data.to_csv(output_data.path, index=False)
