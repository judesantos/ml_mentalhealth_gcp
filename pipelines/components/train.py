from kfp.dsl import component, Output, Artifact


@component(
    base_image='python:3.12',
    packages_to_install=[
        'scikit-learn', 'xgboost', 'numpy',
        'google-cloud-aiplatform', 'bayesian-optimization',
    ],
)
def train_model(
    project_id: str,
    region: str,
    featurestore_id: str,
    entity_type_id: str,
    xtest_output: Output[Artifact],
    ytest_output: Output[Artifact],
    model_output: Output[Artifact],
) -> bool:
    """
    Train the model using historical data from the Feature Store.

    Args:
        project_id (str): The GCP project ID.
        featurestore_id (str): The Vertex AI Feature Store ID.
        entity_type_id (str): The Vertex AI Entity Type ID.
        region (str): The GCP region.
        xtest_output (Output[Artifact]): The path to save the test features.
        ytest_output (Output[Artifact]): The path to save the test target.
        model_output (Output[Artifact]): The path to save the trained model.

    Returns:
        bool: True if the model is successfully trained, False otherwise
    """

    # ####################################
    #    Helper Functions
    # ####################################
    """
    The module contains functions to train the model, tune the hyperparameters,
    test and save the model. Hyperparameter tuning is done using
    Bayesian optimization with xgboost as the model.

    The test data is split into training and validation sets,
    then the model is trained using the training and validation sets.
    The model with the lowest log-loss is selected as the best model and
    evaluated using the test set.
    """

    import logging

    import numpy as np
    import xgboost as xgb
    from sklearn.model_selection import train_test_split
    from bayes_opt import BayesianOptimization
    from sklearn.metrics import log_loss
    from sklearn.utils.class_weight import compute_class_weight
    from google.cloud import aiplatform

    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)

    # Mapping class description of the actual target label.
    # _target_class_mapping = {1: '0 Days',
    #                         2: '1-13 Days', 3: '14+ Days', 9: 'Unsure'}
    #
    # xgboost class label mapping to description
    # _alt_target_class_mapping = {0: '0 Days',
    #                              1: '1-13 Days', 2: '14+ Days', 3: 'Unsure'}

    def target_label_mapping(y=None):
        ''' Convert target dataset labels to xgboost which starts from 0 '''
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
            logger.error('Hyperparameter tuning failed.')
            return None

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

            # Tuning is done, get the best parameters

            best_params = optimizer.max['params']
            best_params['max_depth'] = int(best_params['max_depth'])
            best_params['num_boost_round'] = int(
                best_params['num_boost_round'])
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

    # ####################################
    #    Main logic
    # ####################################

    try:
        # 1. Fetch the latest data from the training Feature Store

        # Initialize Vertex AI SDK
        aiplatform.init(
            project=project_id,
            location=region,
        )

        # Read all historical feature values from Feature Store
        featurestore = aiplatform.Featurestore(featurestore_id)
        feature_values = featurestore.batch_read_feature_values(
            entity_type_id=entity_type_id
        ).to_dataframe()

        # 2. Prepare the datasets for training - save test for evaluation

        # Let's prepare the datasets for training and save the rest for testing

        target = '_ment14d'
        features = feature_values.drop(columns=[target])

        # 3. Split into train (60%), eval(20%), and test(20%) sets

        train_data, temp_data = train_test_split(
            features, train_size=0.6, stratify=feature_values)
        eval_data, test_data = train_test_split(
            temp_data, test_size=0.5, stratify=temp_data[target])

        # 4. Now we will train the model

        # Separate the target from the features
        X_train = train_data.drop(columns=[target])
        y_train = train_data[target]
        x_val = eval_data.drop(columns=[target])
        y_val = eval_data[target]
        x_test = test_data.drop(columns=[target])
        y_test = test_data[target]

        _y_train = target_label_mapping(y=y_train)
        _y_val = target_label_mapping(y=y_val)
        _y_test = target_label_mapping(y=y_test)

        # Train the model
        xgb_model, _x_test = train_model(
            X_train,
            _y_train,
            x_val,
            _y_val,
            x_test,
            _y_test
        )

        if xgb_model is None or _x_test is None:
            logger.error('Model training failed.')
            return False

        # 4. Save the model and test sets for the evaluation component

        xgb_model.save_model(model_output.path)
        _x_test.save_binary(xtest_output.path)
        np.save(ytest_output.path, _y_test)

        logger.info(f'Model saved to {model_output.path}')

    except Exception as e:
        logger.error(f'An error occurred: {e}')
        return False

    return True
