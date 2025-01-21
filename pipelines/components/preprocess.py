from kfp.v2.dsl import component, Output, Dataset

@component(
    base_image="python:3.12",
    packages_to_install=["pandas", "numpy"]
)
def preprocess(input_data_path: str, output_data: Output[Dataset]):
    import pandas as pd
    pass
    # Code to preprocess data here

