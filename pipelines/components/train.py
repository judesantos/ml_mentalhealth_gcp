from kfp.v2.dsl import component, Input, Output, Dataset, Model

@component(
    base_image="python:3.12",
    packages_to_install=["scikit-learn"]
)
def train(
    training_data: Input[Dataset], model: Output[Model]
):
    pass
    # Code to train the model here

