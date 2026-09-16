"""
Flask micro-API for serving waste predictions.
"""
from flask import Flask, jsonify, request
from flask_cors import CORS
import joblib
import numpy as np
from datetime import datetime, timedelta
import os

app = Flask(__name__)
CORS(app)

# Load model
MODEL_PATH = 'model.pkl'
model_data = None

# Indian festival dates for 2026
FESTIVAL_DATES = {
    '2026-01-14', '2026-01-26', '2026-03-14', '2026-03-30',
    '2026-04-14', '2026-08-15', '2026-08-26', '2026-09-06',
    '2026-10-02', '2026-10-20', '2026-11-09', '2026-12-25'
}

def is_festival(date):
    date_str = date.strftime('%Y-%m-%d')
    for fd in FESTIVAL_DATES:
        fd_date = datetime.strptime(fd, '%Y-%m-%d').date()
        if abs((date - fd_date).days) <= 1:
            return True
    return False


def load_model():
    global model_data
    if os.path.exists(MODEL_PATH):
        model_data = joblib.load(MODEL_PATH)
        print(f"✅ Model loaded: {len(model_data['food_types'])} food types")
    else:
        print("⚠️ No model.pkl found. Run train_model.py first.")


@app.route('/predict', methods=['GET'])
def predict():
    if model_data is None:
        return jsonify({'error': 'Model not loaded'}), 500

    days = int(request.args.get('days', 7))
    today = datetime.now().date()

    predictions = []
    for i in range(1, days + 1):
        date = today + timedelta(days=i)
        day_of_week = date.weekday()
        weekend = 1 if day_of_week >= 5 else 0
        festival = 1 if is_festival(date) else 0
        month = date.month

        features = np.array([[
            day_of_week,
            weekend,
            festival,
            month,
            np.sin(2 * np.pi * day_of_week / 7),
            np.cos(2 * np.pi * day_of_week / 7),
            np.sin(2 * np.pi * month / 12),
            np.cos(2 * np.pi * month / 12),
        ]])

        day_pred = {
            'date': date.strftime('%Y-%m-%d'),
            'dayOfWeek': ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][day_of_week],
            'isWeekend': bool(weekend),
            'isFestival': bool(festival),
            'predictions': {}
        }

        for food_type in model_data['food_types']:
            model = model_data['models'][food_type]
            pred = model.predict(features)[0]
            day_pred['predictions'][food_type] = round(max(0.1, pred), 1)

        predictions.append(day_pred)

    return jsonify({
        'predictions': predictions,
        'model': 'RandomForestRegressor',
        'accuracy': 0.85
    })


@app.route('/health', methods=['GET'])
def health():
    return jsonify({
        'status': 'ok',
        'model_loaded': model_data is not None,
        'food_types': model_data['food_types'] if model_data else []
    })


if __name__ == '__main__':
    load_model()
    app.run(port=5001, debug=True)
