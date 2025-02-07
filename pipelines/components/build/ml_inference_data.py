"""
This module prepares (preprocessing) the dataset for model training

We define here the different characteristics of the dataset we want to
provde to the model.

"""

TARGET = '_ment14d'


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
        self.target = TARGET

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
