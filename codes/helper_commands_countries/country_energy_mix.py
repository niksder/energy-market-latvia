"""
Plot the energy mix of a single country over time as a stacked area chart.

Usage:
    python country_energy_mix.py <country>

Example:
    python country_energy_mix.py Latvia
    python country_energy_mix.py Sweden
"""
import argparse
import os
import sys

import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import pandas as pd
from dotenv import load_dotenv

load_dotenv()
PANEL_DATA_DIR = os.getenv('PANEL_DATA_DIR')
OUTPUTS_DIR = os.getenv('OUTPUTS_DIR', 'outputs')

MERGED_PANEL_DATA_PATH = os.path.join(PANEL_DATA_DIR, 'country_panel_data.csv')

OUT_DIR = os.path.join(OUTPUTS_DIR, 'panel_countries', 'others')

# ── Source display names ────────────────────────────────────────────────────────────────────────────
SOURCE_LABELS = {
    'gas_production':        'Gas',
    'brown_coal_production': 'Brown coal',
    'coal_gas_production':   'Coal gas',
    'hard_coal_production':  'Hard coal',
    'oil_production':        'Oil',
    'oil_shale_production':  'Oil shale',
    'peat_production':       'Peat',
    'hydro_ps_production':   'Hydro (pumped storage)',
    'hydro_ror_production':  'Hydro (run-of-river)',
    'hydro_wr_production':   'Hydro (water reservoir)',
    'wind_off_production':   'Wind offshore',
    'wind_on_production':    'Wind onshore',
    'solar_production':      'Solar',
}

# ── Source colors — edit hex values here to change the palette ────────────────────────────────────────────
SOURCE_COLORS = {
    'gas_production':        '#b03a2e',  # muted crimson
    'brown_coal_production': '#7d4e24',  # dark brown
    'coal_gas_production':   '#909497',  # cool grey
    'hard_coal_production':  '#212f3d',  # near-black slate
    'oil_production':        '#9a6b1a',  # amber brown
    'oil_shale_production':  '#c9a97a',  # pale tan
    'peat_production':       '#6b5344',  # dark khaki
    'hydro_ps_production':   '#154360',  # deep navy
    'hydro_ror_production':  '#5499c7',  # muted sky blue
    'hydro_wr_production':   '#1f618d',  # medium blue
    'wind_off_production':   '#1d6a3a',  # forest green
    'wind_on_production':    '#58b07a',  # sage green
    'solar_production':      "#e7be36",  # muted gold
}

ALL_SOURCES = list(SOURCE_LABELS.keys())


def plot_energy_mix(country: str, start_year: int = 2017, end_year: int = 2025) -> None:
    years = list(range(start_year, end_year + 1))
    usecols = ['country', 'time', 'total_generation'] + ALL_SOURCES
    df = pd.read_csv(MERGED_PANEL_DATA_PATH, usecols=usecols, dtype={'country': 'category'})
    df['time'] = pd.to_datetime(df['time'], utc=True, format='mixed')

    df = df[df['country'] == country]
    if df.empty:
        available = pd.read_csv(MERGED_PANEL_DATA_PATH, usecols=['country'])['country'].unique().tolist()
        print(f"No data found for country '{country}'.")
        print("Available countries:", ', '.join(sorted(available)))
        sys.exit(1)

    df = df.set_index('time').sort_index()
    # Compute rolling 365-day yearly sums from raw production
    for col in ALL_SOURCES:
        df[col] = df[col].rolling('365D').sum()
    df['total_gen_yearly'] = df['total_generation'].rolling('365D').sum()
    df = df[df.index.year.isin(years)]
    monthly = df[ALL_SOURCES + ['total_gen_yearly']].resample('ME').mean()

    # Only plot sources that have at least some non-zero data for this country
    present = [col for col in ALL_SOURCES if monthly[col].gt(0).any()]

    fig, ax = plt.subplots(figsize=(14, 6))
    ax.stackplot(
        monthly.index,
        [monthly[col].fillna(0).values for col in present],
        labels=[SOURCE_LABELS[col] for col in present],
        colors=[SOURCE_COLORS[col] for col in present],
        alpha=0.9,
    )
    ax.plot(monthly.index, monthly['total_gen_yearly'].values, color='black',
            linewidth=1.5, linestyle='--', label='Total generation')
    ax.set_title(f'Energy mix — {country}', fontsize=14)
    ax.set_xlabel('Date')
    ax.set_ylabel('Production (MWh, rolling 365-day)')
    ax.yaxis.set_major_formatter(mticker.FuncFormatter(lambda x, _: f'{x:,.0f}'))
    ax.legend(loc='upper left', bbox_to_anchor=(1.01, 1), fontsize=9, frameon=False)
    ax.grid(axis='y', linestyle='--', alpha=0.4)
    fig.tight_layout()

    os.makedirs(OUT_DIR, exist_ok=True)
    safe_name = country.replace(' ', '_').lower()
    path = os.path.join(OUT_DIR, f'energy_mix_prod_{safe_name}.png')
    fig.savefig(path, dpi=150)
    print(f'Plot saved to {path}')
    plt.show()
    plt.close(fig)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Plot the energy mix of a country over time.')
    parser.add_argument('country', help='Country name (e.g. Latvia, Poland, Sweden)')
    parser.add_argument('--start-year', type=int, default=2017)
    parser.add_argument('--end-year', type=int, default=2025)
    args = parser.parse_args()
    plot_energy_mix(args.country, start_year=args.start_year, end_year=args.end_year)
