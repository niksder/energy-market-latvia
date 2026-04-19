import os
import csv
from collections import defaultdict
from datetime import datetime, timedelta
import xml.etree.ElementTree as ET
from dotenv import load_dotenv

load_dotenv()
DATA_DIR = os.getenv('DATA_DIR')
CROSSBORDER_FLOWS_DIR = os.getenv('CROSSBORDER_FLOWS_DIR')

NS = 'urn:iec62325.351:tc57wg16:451-3:publicationdocument:7:0'
YEARS = range(2020, 2027)

COUNTRY_PAIRS = ['EE_LV', 'LV_EE', 'LT_LV', 'LV_LT', 'RU_LV', 'LV_RU']

# pair -> time_str -> list of quantities (to average sub-hourly data)
pair_hour_quantities = {pair: defaultdict(list) for pair in COUNTRY_PAIRS}

for year in YEARS:
    for pair in COUNTRY_PAIRS:
        file_path = os.path.join(DATA_DIR, CROSSBORDER_FLOWS_DIR, f'crossborder_flows_{year}_{pair}.csv')
        if not os.path.exists(file_path):
            print(f'File not found, skipping: {file_path}')
            continue

        tree = ET.parse(file_path)
        root = tree.getroot()

        for ts in root.findall(f'{{{NS}}}TimeSeries'):
            for period in ts.findall(f'{{{NS}}}Period'):
                start_str = period.find(f'{{{NS}}}timeInterval/{{{NS}}}start').text
                resolution_str = period.find(f'{{{NS}}}resolution').text

                # Parse start time (format: 2020-01-01T00:00Z)
                start_dt = datetime.fromisoformat(start_str.replace('Z', '+00:00'))

                if resolution_str == 'PT60M':
                    delta = timedelta(hours=1)
                elif resolution_str == 'PT15M':
                    delta = timedelta(minutes=15)
                else:
                    raise ValueError(f'Unexpected resolution: {resolution_str}')

                for point in period.findall(f'{{{NS}}}Point'):
                    position = int(point.find(f'{{{NS}}}position').text)
                    quantity = float(point.find(f'{{{NS}}}quantity').text)
                    dt = start_dt + (position - 1) * delta
                    # Truncate to the hour so 15-min quantities get averaged per hour
                    dt_hour = dt.replace(minute=0, second=0, microsecond=0)
                    pair_hour_quantities[pair][dt_hour.strftime('%Y-%m-%d %H:%M:%S')].append(quantity)

# Collect all unique time points across all pairs
all_times = set()
for pair in COUNTRY_PAIRS:
    all_times.update(pair_hour_quantities[pair].keys())
all_times = sorted(all_times)

output_path = os.path.join(DATA_DIR, 'crossborder_flows.csv')
with open(output_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['time'] + COUNTRY_PAIRS)
    for time_str in all_times:
        row = [time_str]
        for pair in COUNTRY_PAIRS:
            quantities = pair_hour_quantities[pair].get(time_str)
            row.append(sum(quantities) / len(quantities) if quantities else '')
        writer.writerow(row)

print(f'Wrote {len(all_times)} rows to {output_path}')
