from kfp.v2.dsl import pipeline
from pipelines.components.preprocess import preprocess
from pipelines.components.train import train
from pipelines.components.evaluate import evaluate

@pipeline(name="ml-mentalhealth-pipeline", description="ML Mental Health pipeline.")
def mental_health_pipeline(
    input_data_path: str, model_output_path: str, metrics_output_path: str
):
    preprocess_task = preprocess(input_data_path=input_data_path)

    train_task = train(
        training_data=preprocess_task.outputs["output_data"]
    )

    evaluate_task = evaluate(
        model=train_task.outputs["model"],
        validation_data=preprocess_task.outputs["output_data"]
    )

