import csv
import os
from datetime import datetime
from dotenv import load_dotenv


load_dotenv()

DEFAULT_DATA_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'data'))
DATA_DIR = os.getenv('DATA_DIR', DEFAULT_DATA_DIR)
OUTPUT_FILE = 'merged_data.csv'

TIME_SERIES_FILES = [
	{'name': 'energy_prices', 'file': 'energy_prices.csv', 'merge_key': 'time'},
	{'name': 'energy_sources', 'file': 'energy_sources.csv', 'merge_key': 'time'},
	{'name': 'weather', 'file': 'weather.csv', 'merge_key': 'valid_time'},
]

DAILY_FILES = [ 
	{'name': 'natural_gas_prices', 'file': 'natural_gas_prices.csv', 'merge_key': 'time'}, # https://www.investing.com/commodities/ice-dutch-ttf-gas-c1-futures-historical-data
]

YEARLY_FILES = [
	{'name': 'energy_capacities', 'file': 'energy_capacities.csv', 'merge_key': 'year'},
]


def require_file(path):
	if not os.path.exists(path):
		raise FileNotFoundError(f'Missing input file: {path}')


def parse_year_from_time(time_value):
	try:
		return str(datetime.fromisoformat(time_value).year)
	except ValueError:
		return ''
	
def parse_month_from_time(time_value):
	try:
		return str(datetime.fromisoformat(time_value).month)
	except ValueError:
		return ''
	
def parse_day_of_week_from_time(time_value):
	try:
		return str(datetime.fromisoformat(time_value).weekday())
	except ValueError:
		return ''
	
def parse_hour_from_time(time_value):
	try:
		return str(datetime.fromisoformat(time_value).hour)
	except ValueError:
		return ''


def prefixed_columns(dataset_name, row, excluded_key):
	values = {}
	for column, value in row.items():
		if column == excluded_key:
			continue
		values[f'{dataset_name}_{column}'] = value
	return values


rows_by_time = {}
time_columns = []

for spec in TIME_SERIES_FILES:
	input_path = os.path.join(DATA_DIR, spec['file'])
	require_file(input_path)

	with open(input_path, 'r', newline='') as f:
		reader = csv.DictReader(f)
		if spec['merge_key'] not in reader.fieldnames:
			raise ValueError(f"Merge key '{spec['merge_key']}' not found in {spec['file']}")

		for row in reader:
			time_value = (row.get(spec['merge_key']) or '').strip()
			if not time_value:
				continue

			if time_value not in rows_by_time:
				rows_by_time[time_value] = {'time': time_value}

			prefixed = prefixed_columns(spec['name'], row, spec['merge_key'])
			for col_name, value in prefixed.items():
				if col_name not in time_columns:
					time_columns.append(col_name)
				if value != '':
					rows_by_time[time_value][col_name] = value

for time_value, merged_row in rows_by_time.items():
	merged_row['year'] = parse_year_from_time(time_value)
	merged_row['month'] = parse_month_from_time(time_value)
	merged_row['day_of_week'] = parse_day_of_week_from_time(time_value)
	merged_row['hour'] = parse_hour_from_time(time_value)

year_columns = []
values_by_year = {}

for spec in DAILY_FILES:
	input_path = os.path.join(DATA_DIR, spec['file'])
	require_file(input_path)

	with open(input_path, 'r', newline='') as f:
		reader = csv.DictReader(f)
		if spec['merge_key'] not in reader.fieldnames:
			raise ValueError(f"Merge key '{spec['merge_key']}' not found in {spec['file']}")

		for row in reader:
			date_value = (row.get(spec['merge_key']) or '').strip()
			if not date_value:
				continue

			year_value = parse_year_from_time(date_value)
			if not year_value:
				continue

			if year_value not in values_by_year:
				values_by_year[year_value] = {}

			prefixed = prefixed_columns(spec['name'], row, spec['merge_key'])
			for col_name, value in prefixed.items():
				if col_name not in year_columns:
					year_columns.append(col_name)
				if value != '':
					values_by_year[year_value][col_name] = value

for spec in YEARLY_FILES:
	input_path = os.path.join(DATA_DIR, spec['file'])
	require_file(input_path)

	with open(input_path, 'r', newline='') as f:
		reader = csv.DictReader(f)
		if spec['merge_key'] not in reader.fieldnames:
			raise ValueError(f"Merge key '{spec['merge_key']}' not found in {spec['file']}")

		for row in reader:
			year_value = (row.get(spec['merge_key']) or '').strip()
			if not year_value:
				continue

			if year_value not in values_by_year:
				values_by_year[year_value] = {}

			prefixed = prefixed_columns(spec['name'], row, spec['merge_key'])
			for col_name, value in prefixed.items():
				if col_name not in year_columns:
					year_columns.append(col_name)
				if value != '':
					values_by_year[year_value][col_name] = value

for merged_row in rows_by_time.values():
	year_value = merged_row.get('year', '')
	if year_value in values_by_year:
		merged_row.update(values_by_year[year_value])

output_path = os.path.join(DATA_DIR, OUTPUT_FILE)
header = ['time', 'year', 'month', 'day_of_week', 'hour'] + time_columns + year_columns

with open(output_path, 'w', newline='') as f:
	writer = csv.DictWriter(f, fieldnames=header)
	writer.writeheader()
	for time_value in sorted(rows_by_time.keys()):
		writer.writerow(rows_by_time[time_value])

print(f'Wrote {len(rows_by_time)} rows to {output_path}')
