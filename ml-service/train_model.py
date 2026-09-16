"""
Trains a Random Forest Regressor on synthetic food waste data.
One model per food type. Saves as model.pkl using joblib.
"""
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_absolute_error, r2_score
import joblib
import os

def train():
    # Load data
    df = pd.read_csv('data/synthetic_waste.csv')
    print(f"Loaded {len(df)} rows")

    # Feature engineering
    df['day_sin'] = np.sin(2 * np.pi * df['day_of_week'] / 7)
    df['day_cos'] = np.cos(2 * np.pi * df['day_of_week'] / 7)
    df['month_sin'] = np.sin(2 * np.pi * df['month'] / 12)
    df['month_cos'] = np.cos(2 * np.pi * df['month'] / 12)

    features = ['day_of_week', 'is_weekend', 'is_festival', 'month', 'day_sin', 'day_cos', 'month_sin', 'month_cos']

    models = {}
    metrics = {}

    food_types = df['food_type'].unique()

    for food_type in food_types:
        food_df = df[df['food_type'] == food_type]
        X = food_df[features]
        y = food_df['quantity_kg']

        X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

        model = RandomForestRegressor(
            n_estimators=100,
            max_depth=10,
            random_state=42,
            n_jobs=-1
        )
        model.fit(X_train, y_train)

        y_pred = model.predict(X_test)
        mae = mean_absolute_error(y_test, y_pred)
        r2 = r2_score(y_test, y_pred)

        models[food_type] = model
        metrics[food_type] = {'mae': round(mae, 3), 'r2': round(r2, 3)}

        print(f"  {food_type:12s} — MAE: {mae:.3f} kg, R²: {r2:.3f}")

    # Save all models
    joblib.dump({'models': models, 'features': features, 'food_types': list(food_types)}, 'model.pkl')
    print(f"\n✅ Models saved to model.pkl")
    print(f"Overall average MAE: {np.mean([m['mae'] for m in metrics.values()]):.3f} kg")

    return models, metrics


if __name__ == '__main__':
    train()
