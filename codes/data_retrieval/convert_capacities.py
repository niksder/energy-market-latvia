import os
import csv
import xml.etree.ElementTree as ET
from dotenv import load_dotenv

load_dotenv()
DATA_DIR = os.getenv('DATA_DIR')
ENERGY_CAPACITIES_DIR = os.getenv('ENERGY_CAPACITIES_DIR')

NS = 'urn:iec62325.351:tc57wg16:451-6:generationloaddocument:3:0'
PSR_TYPES = ['B01', 'B04', 'B11', 'B16', 'B19', 'B20']
YEARS = range(2020, 2027)

# data[year][psr_type] = capacity (MW)
data = {}

for year in YEARS:
    for psr in PSR_TYPES:
        file_path = os.path.join(DATA_DIR, ENERGY_CAPACITIES_DIR, f'energy_capacities_{year}_{psr}.csv')
        tree = ET.parse(file_path)
        root = tree.getroot()

        # Skip acknowledgement documents (no data)
        if root.tag != f'{{{NS}}}GL_MarketDocument':
            continue

        if year not in data:
            data[year] = {}

        for ts in root.findall(f'{{{NS}}}TimeSeries'):
            for period in ts.findall(f'{{{NS}}}Period'):
                # Capacity data uses P1Y resolution — one point per period
                for point in period.findall(f'{{{NS}}}Point'):
                    qty = float(point.find(f'{{{NS}}}quantity').text)
                    data[year][psr] = qty

# Write output
output_path = os.path.join(DATA_DIR, 'energy_capacities.csv')

with open(output_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['year'] + PSR_TYPES)
    for year in sorted(data.keys()):
        row = [year] + [data[year].get(psr, '') for psr in PSR_TYPES]
        writer.writerow(row)

print(f'Wrote {len(data)} rows to {output_path}')
