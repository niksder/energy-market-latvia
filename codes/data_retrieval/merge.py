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
	{'name': 'energy_prices_europe', 'file': 'energy_prices_europe.csv', 'merge_key': 'time'},
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
	
def parse_week_of_year_from_time(time_value):
	try:
		return str(datetime.fromisoformat(time_value).isocalendar()[1])
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
	merged_row['week_of_year'] = parse_week_of_year_from_time(time_value)

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

# Add temperature_europe from weather_europe.csv (t2m column only)
weather_europe_path = os.path.join(DATA_DIR, 'weather_europe.csv')
if os.path.exists(weather_europe_path):
	with open(weather_europe_path, 'r', newline='') as f:
		reader = csv.DictReader(f)
		for row in reader:
			time_value = (row.get('valid_time') or '').strip()
			if not time_value or time_value not in rows_by_time:
				continue
			rows_by_time[time_value]['temperature_europe'] = row.get('t2m', '')
	if 'temperature_europe' not in time_columns:
		time_columns.append('temperature_europe')

# time,year,month,day_of_week,hour,days_since_war,energy_prices_price,energy_sources_B01,energy_sources_B04,energy_sources_B11,energy_sources_B16,energy_sources_B19,energy_sources_B20,weather_u100,weather_v100,weather_t2m,weather_ssrd,weather_tp,natural_gas_prices_Price,natural_gas_prices_Vol.,energy_capacities_B01,energy_capacities_B04,energy_capacities_B11,energy_capacities_B16,energy_capacities_B19,energy_capacities_B20

column_translations = {
	'energy_prices_price': 'energy_price',
	'energy_prices_europe_price': 'energy_price_europe',
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

# Create accumulated precipitation
precipitation_values = []
for time_value in sorted(rows_by_time.keys()):
	merged_row = rows_by_time[time_value]
	precipitation = merged_row.get('precipitation')
	if precipitation is not None:
		try:
			precipitation_values.append(float(precipitation))
		except ValueError:
			pass  # Ignore non-numeric values

	if len(precipitation_values) > 0: # Accumulate over the past 24 hours (merged data is hourly) and 168 hours (weekly)
		merged_row['precipitation_24h'] = sum(precipitation_values[-24:])
		merged_row['precipitation_weekly'] = sum(precipitation_values[-168:])
		merged_row['precipitation_monthly'] = sum(precipitation_values[-720:])
	else:
		merged_row['precipitation_24h'] = ''
		merged_row['precipitation_weekly'] = ''
		merged_row['precipitation_monthly'] = ''

	if 'precipitation_24h' not in time_columns:
		time_columns.append('precipitation_24h')
	if 'precipitation_weekly' not in time_columns:
		time_columns.append('precipitation_weekly')
	if 'precipitation_monthly' not in time_columns:
		time_columns.append('precipitation_monthly')


# Impute 2023 solar_production from monthly ENB statistics, distributed proportionally to sun. Data from https://stat.gov.lv/lv/statistikas-temas/noz/energetika/tabulas/enb010m-elektroenergijas-razosana-imports-eksports-un?themeCode=EN
ENB_SOLAR_FILE = os.path.join(DATA_DIR, 'constants', 'ENB010m_20260429-171145.csv')
if os.path.exists(ENB_SOLAR_FILE):
	enb_monthly_solar = {}  # {(year, month): total_mwh}
	with open(ENB_SOLAR_FILE, 'r', newline='', encoding='utf-8-sig') as f:
		reader = csv.reader(f)
		next(reader)  # title row
		next(reader)  # blank line
		headers = next(reader)  # "Rādītāji", "2020M01", ...
		for row in reader:
			if not row:
				continue
			if 'saules' not in row[0].lower():
				continue
			for i, col_header in enumerate(headers):
				if i == 0 or 'M' not in col_header:
					continue
				try:
					year_str, month_str = col_header.split('M')
					year_key = int(year_str)
					month_key = int(month_str)
					value_str = (row[i] if i < len(row) else '').strip()
					if value_str and value_str not in ('…', '..', ''):
						enb_monthly_solar[(year_key, month_key)] = float(value_str) * 1000  # million kWh -> MWh
				except (ValueError, IndexError):
					continue
			break  # only need the solar row

	# Group row keys by (year, month)
	yearmonth_groups = {}
	for time_value in rows_by_time:
		try:
			dt = datetime.fromisoformat(time_value)
			key = (dt.year, dt.month)
			if key not in yearmonth_groups:
				yearmonth_groups[key] = []
			yearmonth_groups[key].append(time_value)
		except ValueError:
			continue

	# Zero out solar_production for all pre-2023 rows (production was negligible)
	for (year, month), time_values in yearmonth_groups.items():
		if year >= 2023:
			continue
		for tv in time_values:
			merged_row = rows_by_time[tv]
			if merged_row.get('solar_production', '') == '':
				merged_row['solar_production'] = 0.0

	# Distribute monthly totals proportionally to sun for months missing solar_production
	for (year, month), time_values in yearmonth_groups.items():
		if year != 2023:
			continue
		monthly_total_mwh = enb_monthly_solar.get((year, month), 0.0)

		# Sum sun across all hours in the month as the denominator
		total_sun = 0.0
		for tv in time_values:
			try:
				total_sun += max(0.0, float(rows_by_time[tv].get('sun') or 0))
			except (ValueError, TypeError):
				pass

		for tv in time_values:
			merged_row = rows_by_time[tv]
			if merged_row.get('solar_production', '') != '':
				continue  # already has data
			try:
				sun_val = max(0.0, float(merged_row.get('sun') or 0))
			except (ValueError, TypeError):
				sun_val = 0.0
			if total_sun > 0:
				merged_row['solar_production'] = monthly_total_mwh * sun_val / total_sun
			else:
				merged_row['solar_production'] = 0.0

output_path = os.path.join(DATA_DIR, OUTPUT_FILE)
header = ['time', 'year', 'month', 'week_of_year', 'day_of_week', 'hour'] + time_columns + year_columns + day_columns + week_columns

with open(output_path, 'w', newline='') as f:
	writer = csv.DictWriter(f, fieldnames=header)
	writer.writeheader()
	for time_value in sorted(rows_by_time.keys()):
		writer.writerow(rows_by_time[time_value])

print(f'Wrote {len(rows_by_time)} rows to {output_path}')
