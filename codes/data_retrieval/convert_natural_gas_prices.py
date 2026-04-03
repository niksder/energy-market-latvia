import os
import csv
from datetime import datetime
from dotenv import load_dotenv

load_dotenv()
DATA_DIR = os.getenv('DATA_DIR')
NATURAL_GAS_PRICE_RAW = os.getenv('NATURAL_GAS_PRICE_RAW')
START_YEAR = 2020

KEEP_COLUMNS = ['Price', 'Vol.']

if not DATA_DIR:
	raise ValueError('Missing DATA_DIR in environment variables')

if not NATURAL_GAS_PRICE_RAW:
	raise ValueError('Missing NATURAL_GAS_PRICE_RAW in environment variables')

input_path = os.path.join(DATA_DIR, NATURAL_GAS_PRICE_RAW)
output_path = os.path.join(DATA_DIR, 'natural_gas_prices.csv')

if not os.path.exists(input_path):
	raise FileNotFoundError(f'Missing input file: {input_path}')
rows = []

with open(input_path, 'r', newline='', encoding='utf-8-sig') as f:
	reader = csv.DictReader(f)
	if not reader.fieldnames:
		raise ValueError('Input file has no header row')

	# Normalize headers to handle BOM/whitespace/casing differences.
	reader.fieldnames = [
		(name or '').strip().lstrip('\ufeff')
		for name in reader.fieldnames
	]

	date_column = next((name for name in reader.fieldnames if name.lower() == 'date'), None)
	if not date_column:
		raise ValueError("Input file must contain a 'Date' column")

	for row in reader:
		raw_date = (row.get(date_column) or '').strip()
		if not raw_date:
			continue

		parsed_date = datetime.strptime(raw_date, '%m/%d/%Y')
		if parsed_date.year < START_YEAR:
			continue

		row['time'] = parsed_date.strftime('%Y-%m-%d %H:%M:%S')
		# Only keep selected columns
		row = {col: row[col] for col in ['time'] + KEEP_COLUMNS if col in row}
		rows.append(row)

rows.sort(key=lambda r: r['time'])

fieldnames = ['time'] + [col for col in reader.fieldnames if col in KEEP_COLUMNS]

with open(output_path, 'w', newline='') as f:
	writer = csv.DictWriter(f, fieldnames=fieldnames)
	writer.writeheader()
	writer.writerows(rows)

print(f'Wrote {len(rows)} rows to {output_path}')

