import os
import csv
from collections import defaultdict
from dotenv import load_dotenv

load_dotenv()

CSV_PATH = os.path.join(os.path.dirname(__file__), '..', '..', 'data', 'panel_data', 'country_panel_data.csv')

# (display label, list of columns)
GROUPS = [
    ('Price',      ['energy_price']),
    ('Production', ['gas_production', 'solar_production', 'brown_coal_production',
                    'coal_gas_production', 'hard_coal_production', 'oil_production',
                    'oil_shale_production', 'peat_production', 'hydro_ps_production',
                    'hydro_ror_production', 'hydro_wr_production', 'wind_off_production',
                    'wind_on_production', 'total_generation']),
    ('Weather',    ['wind_u100', 'wind_v100', 'temperature', 'sun', 'precipitation', 'wind']),
    ('Socioec.',   ['gdp_pps', 'population_density']),
]

GREEN  = '\033[32m'
RED    = '\033[31m'
DIM    = '\033[90m'
BOLD   = '\033[1m'
RESET  = '\033[0m'

BLOCK  = '█'
DOT    = '·'

COL_WIDTH = 8  # visible chars per year column


def load_data():
    """Return {group_label: {country: {year: bool}}} from country_panel_data.csv."""
    group_data = {label: defaultdict(lambda: defaultdict(bool)) for label, _ in GROUPS}

    with open(CSV_PATH, newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            country = row.get('country', '').strip()
            time_val = row.get('time', '')
            year = time_val[:4]
            if not country or not year.isdigit():
                continue

            for label, cols in GROUPS:
                if group_data[label][country][year]:
                    continue  # already confirmed for this group/country/year
                for col in cols:
                    val = row.get(col, '')
                    if val is None or val.strip() == '':
                        continue
                    try:
                        if float(val) != 0.0:
                            group_data[label][country][year] = True
                            break
                    except ValueError:
                        pass

    return group_data


def colored_block(has_data):
    if has_data is None:
        return DIM + DOT + RESET
    return (GREEN if has_data else RED) + BLOCK + RESET


def main():
    group_data = load_data()

    all_countries = sorted({c for gd in group_data.values() for c in gd})
    all_years = sorted({y for gd in group_data.values() for cd in gd.values() for y in cd})

    country_width = max(len(c) for c in all_countries) + 3
    table_width = country_width + COL_WIDTH * len(all_years)

    for label, _ in GROUPS:
        fd = group_data[label]

        print()
        print(BOLD + f'  {label}  ' + RESET)
        print(DIM + '─' * table_width + RESET)

        header = ' ' * country_width
        for year in all_years:
            header += BOLD + year.center(COL_WIDTH) + RESET
        print(header)

        print(DIM + '─' * table_width + RESET)

        for country in all_countries:
            row_str = country.ljust(country_width)
            country_years = fd.get(country, {})
            for year in all_years:
                has = country_years.get(year, None)
                row_str += '   ' + colored_block(has) + '    '
            print(row_str)

        print(DIM + '─' * table_width + RESET)

    # ── Legend ────────────────────────────────────────────────────────────────
    print()
    print(f'{GREEN}{BLOCK}{RESET} has data   {RED}{BLOCK}{RESET} all null/zero   {DIM}{DOT}{RESET} country/year not in file')


if __name__ == '__main__':
    main()
