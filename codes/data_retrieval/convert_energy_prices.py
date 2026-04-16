import os
import csv
from datetime import datetime, timedelta, timezone
import xml.etree.ElementTree as ET
from dotenv import load_dotenv

load_dotenv()
DATA_DIR = os.getenv('DATA_DIR')
ENERGY_PRICES_DIR = os.getenv('ENERGY_PRICES_DIR')

NS = 'urn:iec62325.351:tc57wg16:451-3:publicationdocument:7:3'
YEARS = range(2020, 2027)

rows = []

for year in YEARS:
    file_path = os.path.join(DATA_DIR, ENERGY_PRICES_DIR, f'energy_prices_{year}.csv')
    tree = ET.parse(file_path)
    root = tree.getroot()

    for ts in root.findall(f'{{{NS}}}TimeSeries'):
        for period in ts.findall(f'{{{NS}}}Period'):
            start_str = period.find(f'{{{NS}}}timeInterval/{{{NS}}}start').text
            resolution_str = period.find(f'{{{NS}}}resolution').text

            # Parse start time (format: 2019-12-31T23:00Z)
            start_dt = datetime.fromisoformat(start_str.replace('Z', '+00:00'))

            if resolution_str == 'PT60M':
                delta = timedelta(hours=1)
            elif resolution_str == 'PT15M':
                delta = timedelta(minutes=15)
            else:
                raise ValueError(f'Unexpected resolution: {resolution_str}')

            for point in period.findall(f'{{{NS}}}Point'):
                position = int(point.find(f'{{{NS}}}position').text)
                price = float(point.find(f'{{{NS}}}price.amount').text)
                dt = start_dt + (position - 1) * delta
                # Truncate to the hour so 15-min prices get averaged per hour
                dt_hour = dt.replace(minute=0, second=0, microsecond=0)
                rows.append((dt_hour.strftime('%Y-%m-%d %H:%M:%S'), price))

# Average prices within the same hour, then sort
from collections import defaultdict
hour_prices = defaultdict(list)
for time_str, price in rows:
    hour_prices[time_str].append(price)

unique_rows = sorted(
    [(t, sum(prices) / len(prices)) for t, prices in hour_prices.items()],
    key=lambda r: r[0],
)

output_path = os.path.join(DATA_DIR, 'energy_prices.csv')
with open(output_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['time', 'price'])
    writer.writerows(unique_rows)

print(f'Wrote {len(unique_rows)} rows to {output_path}')
