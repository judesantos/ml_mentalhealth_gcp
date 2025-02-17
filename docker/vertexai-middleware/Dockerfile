FROM python:3.12-slim

WORKDIR /opt/app

# Set environment variables to prevent Python from buffering stdout and stdin
ENV PYTHONUNBUFFERED=1

# Install the required system packages
RUN apt-get update \
    && apt-get install -y libpq-dev python3-dev gcc \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --upgrade pip

# Copy the application files
COPY predictor.py .
COPY ml_inference_data.py .

# Install the application required Python packages
RUN pip install --no-cache-dir joblib flask pandas numpy scikit-learn xgboost gunicorn google-cloud-storage

EXPOSE 8080

ENTRYPOINT ["gunicorn", "--log-level=debug", "--workers=1", "--threads=1", "--bind=0.0.0.0:8080", "predictor:app"]