"""
Generates 6 months of synthetic food waste data for model training.
Factors: day-of-week, weekends, festivals, seasonal trends, random noise.
"""
import csv
import random
import os
from datetime import datetime, timedelta

FOOD_TYPES = ['rice', 'dal', 'roti', 'vegetables', 'curry', 'biryani', 'bread', 'fruits', 'dairy']

# Indian festivals (approximate dates for 2026)
FESTIVALS = [
    ('2026-01-14', 'Makar Sankranti'),
    ('2026-01-26', 'Republic Day'),
    ('2026-03-14', 'Holi'),
    ('2026-03-30', 'Eid al-Fitr'),
    ('2026-04-14', 'Baisakhi'),
    ('2026-08-15', 'Independence Day'),
    ('2026-08-26', 'Janmashtami'),
    ('2026-09-06', 'Ganesh Chaturthi'),
    ('2026-10-02', 'Gandhi Jayanti'),
    ('2026-10-20', 'Dussehra'),
    ('2026-11-09', 'Diwali'),
    ('2026-12-25', 'Christmas'),
]

FESTIVAL_DATES = set()
for date_str, name in FESTIVALS:
    d = datetime.strptime(date_str, '%Y-%m-%d').date()
    # Add festival day and day before/after
    for offset in [-1, 0, 1]:
        FESTIVAL_DATES.add(d + timedelta(days=offset))

BASE_QUANTITIES = {
    'rice': 8.0,
    'dal': 5.0,
    'roti': 6.0,
    'vegetables': 4.5,
    'curry': 4.0,
    'biryani': 7.0,
    'bread': 3.0,
    'fruits': 2.5,
    'dairy': 2.0,
}

def generate_data(start_date, end_date, output_file):
    rows = []
    current = start_date

    while current <= end_date:
        day_of_week = current.weekday()  # 0=Mon, 6=Sun
        is_weekend = 1 if day_of_week >= 5 else 0
        is_festival = 1 if current in FESTIVAL_DATES else 0
        month = current.month

        # Seasonal factor (more waste in summer/wedding season)
        seasonal = 1.0
        if month in [4, 5, 6]:  # Summer
            seasonal = 1.2
        elif month in [11, 12, 1]:  # Winter/wedding season
            seasonal = 1.15

        for food_type in FOOD_TYPES:
            base = BASE_QUANTITIES[food_type]

            # Day-of-week pattern
            dow_factor = 1.0
            if day_of_week == 4:  # Friday
                dow_factor = 1.15
            elif day_of_week == 5:  # Saturday
                dow_factor = 1.35
            elif day_of_week == 6:  # Sunday
                dow_factor = 1.25
            elif day_of_week == 0:  # Monday (leftover from weekend)
                dow_factor = 0.85

            # Festival spike
            festival_factor = 1.6 if is_festival else 1.0

            # Random noise
            noise = random.gauss(0, base * 0.15)

            quantity = base * dow_factor * seasonal * festival_factor + noise
            quantity = max(0.1, round(quantity, 1))

            rows.append({
                'date': current.strftime('%Y-%m-%d'),
                'day_of_week': day_of_week,
                'is_weekend': is_weekend,
                'is_festival': is_festival,
                'month': month,
                'food_type': food_type,
                'quantity_kg': quantity
            })

        current += timedelta(days=1)

    # Write CSV
    os.makedirs('data', exist_ok=True)
    with open(output_file, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=['date', 'day_of_week', 'is_weekend', 'is_festival', 'month', 'food_type', 'quantity_kg'])
        writer.writeheader()
        writer.writerows(rows)

    print(f"✅ Generated {len(rows)} rows -> {output_file}")
    return rows


if __name__ == '__main__':
    end = datetime(2026, 9, 15).date()
    start = end - timedelta(days=180)
    generate_data(start, end, 'data/synthetic_waste.csv')
