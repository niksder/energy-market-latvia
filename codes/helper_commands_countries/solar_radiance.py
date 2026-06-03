import os
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from dotenv import load_dotenv

load_dotenv()
PANEL_DATA_DIR = os.getenv('PANEL_DATA_DIR')
OUTPUTS_DIR = os.getenv('OUTPUTS_DIR', 'outputs')

MERGED_PANEL_DATA_PATH = os.path.join(PANEL_DATA_DIR, 'country_panel_data.csv')

df = pd.read_csv(MERGED_PANEL_DATA_PATH, usecols=['country', 'sun', 'year'])

years = [2019, 2020, 2021, 2022, 2023]
df = df[df['year'].isin(years)]

# Sum solar radiance per country per year
yearly = df.groupby(['country', 'year'])['sun'].sum().reset_index()

countries = sorted(yearly['country'].unique())
n_countries = len(countries)
n_years = len(years)

x = np.arange(n_countries)
width = 0.15
offsets = np.linspace(-(n_years - 1) / 2, (n_years - 1) / 2, n_years) * width

fig, ax = plt.subplots(figsize=(max(16, n_countries * 0.6), 7))

colors = plt.cm.tab10(np.linspace(0, 0.5, n_years))

for i, year in enumerate(years):
    vals = [
        yearly.loc[(yearly['country'] == c) & (yearly['year'] == year), 'sun'].values[0]
        if len(yearly.loc[(yearly['country'] == c) & (yearly['year'] == year)]) > 0 else 0
        for c in countries
    ]
    ax.bar(x + offsets[i], vals, width=width, label=str(year), color=colors[i])

ax.set_xticks(x)
ax.set_xticklabels(countries, rotation=45, ha='right', fontsize=9)
ax.set_xlabel('Country')
ax.set_ylabel('Total Annual Solar Radiance (sum of hourly values)')
ax.set_title('Yearly Solar Radiance by Country (2019–2023)')
ax.legend(title='Year')
ax.yaxis.set_major_formatter(plt.FuncFormatter(lambda v, _: f'{v/1e6:.1f}M' if v >= 1e6 else f'{v/1e3:.0f}k'))

plt.tight_layout()
plt.savefig(os.path.join(OUTPUTS_DIR, 'solar_radiance_by_country.png'), dpi=150)
plt.show()
