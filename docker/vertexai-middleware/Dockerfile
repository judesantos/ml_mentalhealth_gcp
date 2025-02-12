FROM python:3.12

WORKDIR /app

COPY predictor.py /app/
COPY ml_inference_data.py /app/

RUN pip install flask pandas numpy scikit-learn xgboost

EXPOSE 80

CMD ['python3', 'predictor.py']