import os
import csv
from datetime import datetime, timedelta
import xml.etree.ElementTree as ET
from dotenv import load_dotenv

load_dotenv()
DATA_DIR = os.getenv('DATA_DIR')
ENERGY_SOURCES_DIR = os.getenv('ENERGY_SOURCES_DIR')

NS = 'urn:iec62325.351:tc57wg16:451-6:generationloaddocument:3:0'
PSR_TYPES = ['B01', 'B04', 'B11', 'B16', 'B19', 'B20']
YEARS = range(2020, 2027)

# data[time_str][psr_type] = quantity
data = {}

for year in YEARS:
    for psr in PSR_TYPES:
        file_path = os.path.join(DATA_DIR, ENERGY_SOURCES_DIR, f'energy_sources_{year}_{psr}.csv')
        tree = ET.parse(file_path)
        root = tree.getroot()

        # Skip acknowledgement documents (no data)
        if root.tag != f'{{{NS}}}GL_MarketDocument':
            continue

        for ts in root.findall(f'{{{NS}}}TimeSeries'):
            for period in ts.findall(f'{{{NS}}}Period'):
                start_str = period.find(f'{{{NS}}}timeInterval/{{{NS}}}start').text
                end_str = period.find(f'{{{NS}}}timeInterval/{{{NS}}}end').text
                resolution_str = period.find(f'{{{NS}}}resolution').text

                start_dt = datetime.fromisoformat(start_str.replace('Z', '+00:00'))
                end_dt = datetime.fromisoformat(end_str.replace('Z', '+00:00'))

                if resolution_str == 'PT60M':
                    delta = timedelta(hours=1)
                elif resolution_str == 'PT15M':
                    delta = timedelta(minutes=15)
                else:
                    raise ValueError(f'Unexpected resolution: {resolution_str}')

                total_points = int((end_dt - start_dt) / delta)

                # Collect sparse points
                sparse = {}
                for point in period.findall(f'{{{NS}}}Point'):
                    pos = int(point.find(f'{{{NS}}}position').text)
                    qty = float(point.find(f'{{{NS}}}quantity').text)
                    sparse[pos] = qty

                # Expand with forward-fill (A03 curve type)
                current_qty = 0.0
                for pos in range(1, total_points + 1):
                    if pos in sparse:
                        current_qty = sparse[pos]
                    dt = start_dt + (pos - 1) * delta
                    time_str = dt.strftime('%Y-%m-%d %H:%M:%S')
                    if time_str not in data:
                        data[time_str] = {}
                    data[time_str][psr] = current_qty

# Write output
output_path = os.path.join(DATA_DIR, 'energy_sources.csv')
all_times = sorted(data.keys())

with open(output_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['time'] + PSR_TYPES)
    for t in all_times:
        row = [t] + [data[t].get(psr, '') for psr in PSR_TYPES]
        writer.writerow(row)

print(f'Wrote {len(all_times)} rows to {output_path}')
