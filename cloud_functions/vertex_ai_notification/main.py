from google.cloud import aiplatform

def notify_vertex_ai(request):
    """
    Triggered by a Pub/Sub message when a new model is registered.
    """
    request_json = request.get_json()

    # Extract model details from Pub/Sub message
    model_id = request_json.get('model_id')
    endpoint_id = request_json.get('endpoint_id')

    if not model_id or not endpoint_id:
        return "Missing model_id or endpoint_id", 400

    # Update the Vertex AI Endpoint with the new model
    aiplatform.init()
    endpoint = aiplatform.Endpoint(endpoint_id=endpoint_id)
    endpoint.deploy(model=model_id)

    return "Model deployed successfully", 200