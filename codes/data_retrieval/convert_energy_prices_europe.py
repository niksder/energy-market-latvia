import os
import csv
from collections import defaultdict
from datetime import datetime, timedelta
import xml.etree.ElementTree as ET
from dotenv import load_dotenv

load_dotenv()
DATA_DIR = os.getenv('DATA_DIR')
ENERGY_PRICES_EUROPE_DIR = os.getenv('ENERGY_PRICES_EUROPE_DIR')

COUNTRIES = [
    {'name': 'Germany', 'code': '10YCB-GERMANY--8', 'weight': 83237124},
    {'name': 'France', 'code': '10YFR-RTE------C', 'weight': 68091703},
    {'name': 'Italy', 'code': '10Y1001A1001A73I', 'weight': 59030133},
    {'name': 'Netherlands', 'code': '10YNL----------L', 'weight': 17590672},
]

NS = 'urn:iec62325.351:tc57wg16:451-3:publicationdocument:7:3'
YEARS = range(2020, 2027)


def parse_country_year(country, year):
    """Parse one country/year XML file and return {time_str: avg_hourly_price}."""
    file_path = os.path.join(DATA_DIR, ENERGY_PRICES_EUROPE_DIR, f'energy_prices_{country["name"]}_{year}.csv')
    tree = ET.parse(file_path)
    root = tree.getroot()

    hour_prices = defaultdict(list)

    for ts in root.findall(f'{{{NS}}}TimeSeries'):
        for period in ts.findall(f'{{{NS}}}Period'):
            start_str = period.find(f'{{{NS}}}timeInterval/{{{NS}}}start').text
            resolution_str = period.find(f'{{{NS}}}resolution').text

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
                dt_hour = dt.replace(minute=0, second=0, microsecond=0)
                hour_prices[dt_hour.strftime('%Y-%m-%d %H:%M:%S')].append(price)

    return {t: sum(prices) / len(prices) for t, prices in hour_prices.items()}


# Accumulate weighted price sums and total weights per timestamp
weighted_sum = defaultdict(float)
total_weight = defaultdict(float)

for country in COUNTRIES:
    for year in YEARS:
        try:
            hourly = parse_country_year(country, year)
        except FileNotFoundError:
            print(f'Missing file for {country["name"]} {year}, skipping.')
            continue
        for time_str, price in hourly.items():
            weighted_sum[time_str] += price * country['weight']
            total_weight[time_str] += country['weight']

# Compute weighted average and sort
output_rows = sorted(
    [(t, weighted_sum[t] / total_weight[t]) for t in weighted_sum],
    key=lambda r: r[0],
)

output_path = os.path.join(DATA_DIR, 'energy_prices_europe.csv')
with open(output_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['time', 'price'])
    writer.writerows(output_rows)

print(f'Wrote {len(output_rows)} rows to {output_path}')
