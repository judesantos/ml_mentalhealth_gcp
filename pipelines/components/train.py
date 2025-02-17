from kfp.dsl import component, Output, Artifact


@component(
    base_image='python:3.12',
    packages_to_install=[
        'scikit-learn',
        'xgboost',
        'pandas',
        'numpy',
        'bayesian-optimization',
        'google-cloud-bigquery-storage',
        'google-cloud-bigquery',
        'db-dtypes',
        'joblib'
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

    """
    The module contains functions to train the model, tune the hyperparameters,
    test and save the model. Hyperparameter tuning is done using
    Bayesian optimization with xgboost as the model.

    The test data is split into training and validation sets,
    then the model is trained using the training and validation sets.
    The model with the lowest log-loss is selected as the best model and
    evaluated using the test set.
    """

    import os
    import logging
    import joblib

    import numpy as np
    import pandas as pd

    import xgboost as xgb
    from sklearn.model_selection import train_test_split
    from bayes_opt import BayesianOptimization
    from sklearn.metrics import log_loss
    from sklearn.utils.class_weight import compute_class_weight

    from google.cloud import bigquery

    logging.basicConfig(level=logging.INFO, force=True)
    logger = logging.getLogger(__name__)

    TARGET = 'ment14d'
    FEATURE_IDS = [
        'poorhlth', 'physhlth', 'genhlth', 'diffwalk', 'diffalon',
        'checkup1', 'diffdres', 'addepev3', 'acedeprs', 'sdlonely', 'lsatisfy',
        'emtsuprt', 'decide', 'cdsocia1', 'cddiscu1', 'cimemlo1', 'smokday2',
        'alcday4', 'marijan1', 'exeroft1', 'usenow3', 'firearm5', 'income3',
        'educa', 'employ1', 'sex', 'marital', 'adult', 'rrclass3', 'qstlang',
        'state', 'veteran3', 'medcost1', 'sdhbills', 'sdhemply', 'sdhfood1',
        'sdhstre1', 'sdhutils', 'sdhtrnsp', 'cdhous1', 'foodstmp', 'pregnant',
        'asthnow', 'havarth4', 'chcscnc1', 'chcocnc1', 'diabete4', 'chccopd3',
        'cholchk3', 'bpmeds1', 'bphigh6', 'cvdstrk3', 'cvdcrhd4', 'chckdny2',
        'cholmed3', 'ment14d'
    ]

    # ####################################
    #    Helper Functions
    # ####################################

    # Mapping class description of the actual target label.
    # _target_class_mapping = {1: '0 Days',
    #                         2: '1-13 Days', 3: '14+ Days', 9: 'Unsure'}
    #
    # xgboost class label mapping to description
    # _alt_target_class_mapping = {0: '0 Days',
    #                              1: '1-13 Days', 2: '14+ Days', 3: 'Unsure'}

    class MentalHealthData():
        """
        Mental Health Data class defines the dataset characteristics including
        the feature groups by type and the target variable

        Attributes:
        target (str): target variable
        categorical_features (list): list of categorical features
        """

        def __init__(self, df):
            """
            Initialize the dataset and define the dataset characteristics

            Task:
            - Load and prepare the dataset
            - Define the dataset characteristics
            """

            # 1. Make a copy of the dataset
            self._df = df.copy()

            # Integrate composite features
            self._integrate_composite_features()

            # 2. Define the target variable
            self.target = 'ment14d'

            # Define the feature groups

            # 3. Numeric features need scaler
            continuous_features = ['physhlth', 'poorhlth', 'marijan1']
            aggregated_features = [
                'Mental_Health_Composite',
                'Income_Education_Interaction',
                'Physical_Mental_Interaction',
            ]
            non_categorical_features = continuous_features + aggregated_features

            # 4. Categorical features
            self.categorical_features = [
                col for col in self._df.columns
                if col not in (non_categorical_features + [self.target])
            ]

        def get_data(self):
            """
            Return the dataset

            Returns:
            pd.DataFrame: dataset
            """
            return self._df

        def _integrate_composite_features(self):
            # Create a new copy of the cleaned dataset
            mental_health_features = ['emtsuprt', 'addepev3', 'poorhlth']
            # Using Nonlinear interaction
            self._df['Physical_Mental_Interaction'] = self._df['genhlth'].astype(
                int) * self._df['physhlth']
            # Income and Education Interaction
            self._df['Income_Education_Interaction'] = self._df['income3'].astype(
                int) * self._df['educa'].astype(int)
            # Mental Health
            self._df['Mental_Health_Composite'] = self._df[
                mental_health_features
            ].mean(axis=1)

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

        return model_xgb, _x_test

    # ####################################
    #    Main logic
    # ####################################

    try:
        # 1. Fetching training data

        logger.info('Initializing biqquery client...')

        client = bigquery.Client(project=project_id, location=region)

        query = f'''
            SELECT {','.join(str(feat) for feat in FEATURE_IDS)}
            FROM `{project_id}.{featurestore_id}.{entity_type_id}`
        '''

        logger.info('Reading records from the Feature Store...')

        # TODO: Temporary - reduce the dataset size for testing
        tmp_training_df = client.query(query).to_dataframe()
        df = tmp_training_df.sample(frac=0.04)

        # 1a. Incorporate composite features

        mh = MentalHealthData(df)
        training_df = mh.get_data()

        logger.info(
            f'Feature Store records fetched successfully. count={training_df.shape[0]}')

        # 2. Prepare the datasets for training - save test for evaluation

        logger.info('Preparing the datasets for training...')

        target = TARGET
        X, y = training_df.drop(columns=[target]), training_df[target]

        # 3. Split into train (60%), eval(20%), and test(20%) sets

        X_train, x_temp, y_train, y_temp = train_test_split(
            X,
            y,
            stratify=y,
            test_size=0.4
        )

        x_val, x_test, y_val, y_test = train_test_split(
            x_temp,
            y_temp,
            stratify=y_temp,
            test_size=0.5
        )

        _y_train = target_label_mapping(y=y_train)
        _y_val = target_label_mapping(y=y_val)
        _y_test = target_label_mapping(y=y_test)

        # 4. Now we will train the model

        logger.info('Training the model...')

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

        logger.info('Saving the model and test sets...')

        joblib.dump(xgb_model, model_output.path)

        logger.info(f'Model saved to {model_output.path}')

        _x_test.save_binary(xtest_output.path)

        logger.info(f'Test features saved to {xtest_output.path}')

        np.save(ytest_output.path, _y_test)
        # np.save appends `.npy` to the file name which is not conformant
        # with the output.path file naming format - Rename the file to
        # remove the .npy extension
        if os.path.exists(ytest_output.path + ".npy") and not os.path.exists(ytest_output.path):
            os.rename(ytest_output.path + ".npy", ytest_output.path)

        logger.info(f'Test target saved to {ytest_output.path}')
        logger.info('Model training completed successfully.')

    except Exception as e:
        logger.error(f'Error training model: {str(e)}')
        raise e

    return True
