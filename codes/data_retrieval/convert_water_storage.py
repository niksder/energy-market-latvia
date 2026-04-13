import os
import csv
from datetime import datetime, timedelta
import xml.etree.ElementTree as ET
from dotenv import load_dotenv

load_dotenv()
DATA_DIR = os.getenv('DATA_DIR')
WATER_STORAGE_DIR = os.getenv('WATER_STORAGE_DIR')

NS = 'urn:iec62325.351:tc57wg16:451-6:generationloaddocument:3:0'
YEARS = range(2020, 2027)

rows = []

for year in YEARS:
    file_path = os.path.join(DATA_DIR, WATER_STORAGE_DIR, f'water_storage_{year}.csv')
    tree = ET.parse(file_path)
    root = tree.getroot()

    for ts in root.findall(f'{{{NS}}}TimeSeries'):
        for period in ts.findall(f'{{{NS}}}Period'):
            start_str = period.find(f'{{{NS}}}timeInterval/{{{NS}}}start').text
            resolution_str = period.find(f'{{{NS}}}resolution').text

            # Parse start time (format: 2019-12-29T22:00Z)
            start_dt = datetime.fromisoformat(start_str.replace('Z', '+00:00'))

            if resolution_str == 'P7D':
                delta = timedelta(weeks=1)
            elif resolution_str == 'PT60M':
                delta = timedelta(hours=1)
            elif resolution_str == 'PT15M':
                delta = timedelta(minutes=15)
            else:
                raise ValueError(f'Unexpected resolution: {resolution_str}')

            for point in period.findall(f'{{{NS}}}Point'):
                position = int(point.find(f'{{{NS}}}position').text)
                quantity = float(point.find(f'{{{NS}}}quantity').text)
                # Each point represents the start of its interval
                dt = start_dt + (position - 1) * delta
                rows.append((dt.strftime('%Y-%m-%d %H:%M:%S'), quantity))

# Sort by time and deduplicate
rows.sort(key=lambda r: r[0])
seen = set()
unique_rows = []
for row in rows:
    if row[0] not in seen:
        seen.add(row[0])
        unique_rows.append(row)

output_path = os.path.join(DATA_DIR, 'water_storage.csv')
with open(output_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['week_start', 'water_storage_mwh'])
    writer.writerows(unique_rows)

print(f'Wrote {len(unique_rows)} rows to {output_path}')
