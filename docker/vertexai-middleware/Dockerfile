# Use a slim Python 3.12 base image
FROM python:3.12-slim

# Set the working directory
WORKDIR /opt/app

# Set environment variables to prevent Python from buffering stdout and stdin
ENV PYTHONUNBUFFERED=1

# Install system dependencies (only what's necessary)
# libgomp1 - Required for XGBoost
RUN apt-get update \
    && apt-get install -y --no-install-recommends libgomp1  \
    && rm -rf /var/lib/apt/lists/*

# Copy the application files
COPY predictor.py .
COPY ml_inference_data.py .

# Install Python dependencies
RUN pip install --no-cache-dir \
    fastapi \
    pandas \
    uvicorn \
    joblib \
    xgboost \
    google-cloud-storage

# Expose the port the app will run on
EXPOSE 8080

# Run the FastAPI app with Uvicorn
ENTRYPOINT ["uvicorn", "predictor:app", "--host", "0.0.0.0", "--port", "8080", "--log-level", "debug"]

