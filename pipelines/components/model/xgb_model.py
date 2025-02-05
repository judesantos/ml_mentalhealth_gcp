
"""
This module provides the model training pipeline for the
XGBoost model using the dataset prepared by the preparation pipeline.

The module contains functions to train the model, tune the hyperparameters,
test and save the model. Hyperparameter tuning is done using
Bayesian optimization with xgboost as the model.

The test data is split into training and validation sets,
then the model is trained using the training and validation sets.
The model with the lowest log-loss is selected as the best model and
evaluated using the test set.
"""

import os

import time
from datetime import datetime
import humanfriendly
import pickle as pkl

import pandas as pd
import numpy as np

import xgboost as xgb
from sklearn.model_selection import train_test_split
from bayes_opt import BayesianOptimization
from sklearn.metrics import log_loss
from sklearn.utils.class_weight import compute_class_weight
from sklearn.metrics import accuracy_score, precision_score
from sklearn.metrics import recall_score, f1_score


"""
  Xgboost model class helper functions and variables
  xgboost requires the class labels to start from 0
"""

# Mapping class description of the actual target label.
# _target_class_mapping = {1: '0 Days',
#                         2: '1-13 Days', 3: '14+ Days', 9: 'Unsure'}
#
# xgboost class label mapping to description
# _alt_target_class_mapping = {0: '0 Days',
#                              1: '1-13 Days', 2: '14+ Days', 3: 'Unsure'}


def target_label_mapping(y=None):
    """ Convert target dataset labels to xgboost which starts from 0 """
    # _MENT14D labels:
    #   (0 Days: 1, 1-13 Days: 2, 14+ Days: 3, Unsure: 9)
    # _MENT14D_ to xgboost label mapping
    label_mapping = {1: 0, 2: 1, 3: 2, 9: 3}
    # Convert to xgboost labels
    return np.vectorize(label_mapping.get)(y)


def train_model(
    X_train, _y_train, x_val, _y_val, x_test, _y_test
) -> tuple[xgb.Booster, xgb.DMatrix]:
    """
    Train model given a dataset: Run hyperparameter tuning and
        train the model using evaluation data.
    Returns the best hyperparameters and class weights for the model.

    Returns:
        tuple: best hyperparameters, class weights
    """

    # Compute class weights for balancing the skewness of the target classes(4).

    class_weights = compute_class_weight(
        'balanced',
        classes=np.unique(_y_train),
        y=_y_train
    )
    class_weights_dict = dict(enumerate(class_weights))
    sample_weight = np.array([class_weights_dict[class_label]
                             for class_label in _y_train])

    # Hyper parameter tuning - use validation data
    h_params = _hyper_parameter_tuning(
        X_train,
        _y_train,
        x_val,
        _y_val,
        sample_weight
    )

    if h_params is None:
        raise ValueError("Hyperparameter tuning failed.")

    xgb_model, _x_test = _create_and_train_model(
        X_train,
        _y_train,
        x_test,
        _y_test,
        h_params,
        sample_weight
    )

    if xgb_model is None:
        return None

    return xgb_model, _x_test


def _hyper_parameter_tuning(X_train, y_train, x_test, y_test, sample_weight) -> dict:
    """
    This function tunes the hyperparameters for the model using
    the training and validation data.

    The function uses Bayesian optimization with select hyperparameters
    and a predefined range of values using xgboost as the model.
    Creates a new mode at each iteration and evaluates the model using the
    test parameters and measures the log-loss. The model with the
    lowest log-loss is selected as the best model.

    Args:
      X_train: (array) training set features
      y_train: (array) training set target
      x_test: (array) validation set features
      y_test: (array) validation set target
      sample_weight: (array) class weights

    Returns:
      dict: best hyperparameters
    """

    start = time.perf_counter()

    try:
        # Create the tuning model using DMatrix for XGBoost
        _x_train = xgb.DMatrix(
            X_train,
            label=y_train,
            enable_categorical=True,
            weight=sample_weight
        )

        _x_test = xgb.DMatrix(
            x_test,
            label=y_test,
            enable_categorical=True
        )

        # Define Bayesian optimization callback function
        # and train at each iteration
        def xgb_eval(max_depth, learning_rate, num_boost_round, subsample,
                     colsample_bytree, gamma, reg_alpha, reg_lambda):
            params = {
                'eval_metric': 'mlogloss',
                'objective': 'multi:softprob',
                'num_class': 4,
                'max_depth': int(max_depth),
                'learning_rate': learning_rate,
                'subsample': subsample,
                'colsample_bytree': colsample_bytree,
                'gamma': gamma,
                'reg_alpha': reg_alpha,
                'reg_lambda': reg_lambda
            }

            # Train model with current hyperparameters
            model = xgb.train(
                params,
                _x_train,
                num_boost_round=int(num_boost_round),
                # evals=[(_x_test, 'eval')],
                verbose_eval=False
            )

            # Predict probabilities
            y_pred_probs = model.predict(_x_test)
            # Compute log-loss
            return -log_loss(y_test, y_pred_probs)

        # Bounds for hyperparameters
        # TODO - configurable hyperparameters
        param_bounds = {
            # n_estimators is num_boost_round for XGBoostClassifier
            'num_boost_round': [100, 300],
            'max_depth': [3, 10],
            'learning_rate': [0.01, 0.1],
            'subsample': [0.6, 1.0],
            'colsample_bytree': [0.6, 1.0],
            'gamma': [0, 5],
            'reg_alpha': [0, 1],
            'reg_lambda': [1, 5],
        }

        # Bayesian optimization
        optimizer = BayesianOptimization(
            f=xgb_eval,
            pbounds=param_bounds,
            verbose=False
        )
        # Run the optimization tasks then extract optimized results
        optimizer.maximize(init_points=5, n_iter=25)

        elapsed = _get_elapsed(start, time.perf_counter())
        # Tuning is done, get the best parameters

        best_params = optimizer.max['params']
        best_params['max_depth'] = int(best_params['max_depth'])
        best_params['num_boost_round'] = int(best_params['num_boost_round'])
        best_params['learning_rate'] = float(best_params['learning_rate'])
        best_params['subsample'] = float(best_params['subsample'])
        best_params['colsample_bytree'] = float(
            best_params['colsample_bytree'])
        best_params['gamma'] = int(best_params['gamma'])
        best_params['reg_alpha'] = float(best_params['reg_alpha'])
        best_params['reg_lambda'] = int(best_params['reg_lambda'])

        return best_params
    except Exception as e:
        return None


def _create_and_train_model(
        X_train, y_train, x_test, y_test, h_params, sample_weight):
    """
    This function trains the xgboost model using the optimized
    hyperparameters. The model is a classifier with categorical and
    continuous features. The target variable is a multi-class
    classification with 4 classes. The dataset is highly imbalanced
    leaning towards the '0 Days' class and so class weights
    are computed and used in training.

    The model parameter chosen is to minimize the log-
    loss and optimize recall for the minority classes.

    Args:
      X_train: (array) training set features
      y_train: (array) training set target
      x_test: (array) test set features
      y_test: (array) test set target
      h_params: (dict) hyperparameters
      sample_weight: (array) class weights

    Returns:
      object: trained model
    """

    start = time.perf_counter()

    # Train model with best parameters
    params = {
        'eval_metric': 'mlogloss',
        'objective': 'multi:softprob',
        'num_class': 4,
        'max_depth': h_params['max_depth'],
        'learning_rate': h_params['learning_rate'],
        'subsample': h_params['subsample'],
        'colsample_bytree': h_params['colsample_bytree'],
        'gamma': h_params['gamma'],
        'reg_alpha': h_params['reg_alpha'],
        'reg_lambda': h_params['reg_lambda'],
    }
    num_boost_round = h_params['num_boost_round']

    try:
        # Create the tuning model using DMatrix for XGBoost
        _x_train = xgb.DMatrix(
            X_train,
            label=y_train,
            enable_categorical=True,
            weight=sample_weight
        )

        _x_test = xgb.DMatrix(
            x_test,
            label=y_test,
            enable_categorical=True,
        )

        # Train model
        model_xgb = xgb.train(
            params,
            _x_train,
            # evals=[(_x_test, 'eval')],
            num_boost_round=int(num_boost_round),
        )
    except Exception as e:
        return None

    return model_xgb, _x_test


def evaluate_model(model_xgb, _x_test, y_test):

    # Predict
    y_pred_probs = model_xgb.predict(_x_test)
    y_pred = y_pred_probs.argmax(axis=1)

    # Evaluate
    final_log_loss = log_loss(y_test, y_pred_probs)

    # Log model metrics
    accuracy = accuracy_score(y_test, y_pred)
    precision = precision_score(y_test, y_pred, average='weighted')
    recall = recall_score(y_test, y_pred, average='weighted')
    f1 = f1_score(y_test, y_pred, average='weighted')

    return final_log_loss, accuracy, precision, recall, f1


def _save_model(model):
    """ Save model to Vertex AI model registry """


def _get_elapsed(start, end):
    return humanfriendly.format_timespan(end - start)
