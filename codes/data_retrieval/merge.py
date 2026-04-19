import bisect
import csv
import math
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

WEEKLY_FILES = [
	{'name': 'water_storage', 'file': 'water_storage.csv', 'merge_key': 'week_start'},
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

day_columns = []
values_by_day = {}

for spec in DAILY_FILES:
	input_path = os.path.join(DATA_DIR, spec['file'])
	require_file(input_path)

	with open(input_path, 'r', newline='') as f:
		reader = csv.DictReader(f)
		if spec['merge_key'] not in reader.fieldnames:
			raise ValueError(f"Merge key '{spec['merge_key']}' not found in {spec['file']}")

		for row in reader:
			day_value = (row.get(spec['merge_key']) or '').strip()[:10]
			if not day_value:
				continue

			if day_value not in values_by_day:
				values_by_day[day_value] = {}

			prefixed = prefixed_columns(spec['name'], row, spec['merge_key'])
			for col_name, value in prefixed.items():
				if col_name not in day_columns:
					day_columns.append(col_name)
				if value != '':
					values_by_day[day_value][col_name] = value

week_columns = []
values_by_week = {}

for spec in WEEKLY_FILES:
	input_path = os.path.join(DATA_DIR, spec['file'])
	require_file(input_path)

	with open(input_path, 'r', newline='') as f:
		reader = csv.DictReader(f)
		if spec['merge_key'] not in reader.fieldnames:
			raise ValueError(f"Merge key '{spec['merge_key']}' not found in {spec['file']}")

		for row in reader:
			week_value = (row.get(spec['merge_key']) or '').strip()
			if not week_value:
				continue

			if week_value not in values_by_week:
				values_by_week[week_value] = {}

			prefixed = prefixed_columns(spec['name'], row, spec['merge_key'])
			for col_name, value in prefixed.items():
				if col_name not in week_columns:
					week_columns.append(col_name)
				if value != '':
					values_by_week[week_value][col_name] = value

week_starts_sorted = sorted(values_by_week.keys())

year_columns = []
values_by_year = {}

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

	day_value = merged_row.get('time', '')[:10]  # Extract date part from time
	if day_value in values_by_day:
		merged_row.update(values_by_day[day_value])

	# Weekly merge: find the most recent week_start <= current timestamp
	time_value = merged_row.get('time', '')
	if week_starts_sorted and time_value:
		idx = bisect.bisect_right(week_starts_sorted, time_value[:19]) - 1
		if idx >= 0:
			merged_row.update(values_by_week[week_starts_sorted[idx]])

# Add column for days since the start of war in Ukraine (2022-02-24)
war_start_date = datetime(2022, 2, 24)
for time_value, merged_row in rows_by_time.items():
	try:
		current_date = datetime.fromisoformat(time_value)
		days_since_war = (current_date - war_start_date).days
		merged_row['days_since_war'] = max(0, days_since_war + 1)
		if 'days_since_war' not in time_columns:
			time_columns.insert(0, 'days_since_war')
	except ValueError:
		# If time_value is not a valid date, skip this calculation
		continue

# Add electricity_exports: Latvia's net export trade balance from crossborder flows
crossborder_path = os.path.join(DATA_DIR, 'crossborder_flows.csv')
if os.path.exists(crossborder_path):
	with open(crossborder_path, 'r', newline='') as f:
		reader = csv.DictReader(f)
		for row in reader:
			time_value = (row.get('time') or '').strip()
			if not time_value or time_value not in rows_by_time:
				continue
			lv_ee = float(row.get('LV_EE', '') or 0)
			lv_lt = float(row.get('LV_LT', '') or 0)
			lv_ru = float(row.get('LV_RU', '') or 0)
			ee_lv = float(row.get('EE_LV', '') or 0)
			lt_lv = float(row.get('LT_LV', '') or 0)
			ru_lv = float(row.get('RU_LV', '') or 0)
			rows_by_time[time_value]['electricity_exports'] = (lv_ee + lv_lt + lv_ru) - (ee_lv + lt_lv + ru_lv)
	if 'electricity_exports' not in time_columns:
		time_columns.append('electricity_exports')

# time,year,month,day_of_week,hour,days_since_war,energy_prices_price,energy_sources_B01,energy_sources_B04,energy_sources_B11,energy_sources_B16,energy_sources_B19,energy_sources_B20,weather_u100,weather_v100,weather_t2m,weather_ssrd,weather_tp,natural_gas_prices_Price,natural_gas_prices_Vol.,energy_capacities_B01,energy_capacities_B04,energy_capacities_B11,energy_capacities_B16,energy_capacities_B19,energy_capacities_B20

column_translations = {
	'energy_prices_price': 'energy_price',
	'energy_sources_B01': 'biomass_production',
	'energy_sources_B04': 'gas_production',
	'energy_sources_B11': 'hydro_production',
	'energy_sources_B16': 'solar_production',
	'energy_sources_B19': 'wind_production',
	'energy_sources_B20': 'other_production',
	'weather_u100': 'wind_u100',
	'weather_v100': 'wind_v100',
	'weather_t2m': 'temperature',
	'weather_ssrd': 'sun',
	'weather_tp': 'precipitation',
	'natural_gas_prices_Price': 'gas_price',
	'natural_gas_prices_Vol.': 'gas_volume',
	'energy_capacities_B01': 'biomass_capacity',
	'energy_capacities_B04': 'gas_capacity',
	'energy_capacities_B11': 'hydro_capacity',
	'energy_capacities_B16': 'solar_capacity',
	'energy_capacities_B19': 'wind_capacity',
	'energy_capacities_B20': 'other_capacity',
	'water_storage_water_storage_mwh': 'water_storage',
}

# Rename the header columns based on the translations
time_columns = [column_translations.get(col, col) for col in time_columns]
year_columns = [column_translations.get(col, col) for col in year_columns]
day_columns = [column_translations.get(col, col) for col in day_columns]
week_columns = [column_translations.get(col, col) for col in week_columns]

# Rename fields in rows_by_time based on the translations
for merged_row in rows_by_time.values():
	for old_col, new_col in column_translations.items():
		if old_col in merged_row:
			merged_row[new_col] = merged_row.pop(old_col)

# Create wind column as the magnitude of u100 and v100
for merged_row in rows_by_time.values():
	u = float(merged_row.get('wind_u100', '0') or '0')
	v = float(merged_row.get('wind_v100', '0') or '0')
	merged_row['wind'] = math.sqrt(u**2 + v**2)
	if 'wind' not in time_columns:
		time_columns.append('wind')

# Create gas_price_weekly rolling average column
gas_price_weekly_values = []
for time_value in sorted(rows_by_time.keys()):
	merged_row = rows_by_time[time_value]
	gas_price = merged_row.get('gas_price')
	if gas_price is not None:
		try:
			gas_price_weekly_values.append(float(gas_price))
		except ValueError:
			pass  # Ignore non-numeric values

	if len(gas_price_weekly_values) > 0: # Roll over the week (merged data is hourly)
		merged_row['gas_price_weekly'] = sum(gas_price_weekly_values[-168:]) / min(len(gas_price_weekly_values[-168:]), 168)
	else:
		merged_row['gas_price_weekly'] = ''

	if 'gas_price_weekly' not in time_columns:
		time_columns.append('gas_price_weekly')

output_path = os.path.join(DATA_DIR, OUTPUT_FILE)
header = ['time', 'year', 'month', 'day_of_week', 'hour'] + time_columns + year_columns + day_columns + week_columns

with open(output_path, 'w', newline='') as f:
	writer = csv.DictWriter(f, fieldnames=header)
	writer.writeheader()
	for time_value in sorted(rows_by_time.keys()):
		writer.writerow(rows_by_time[time_value])

print(f'Wrote {len(rows_by_time)} rows to {output_path}')
