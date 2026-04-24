import glob
import os
import pandas as pd
from dotenv import load_dotenv

load_dotenv()
DATA_DIR = os.getenv('DATA_DIR')
WEATHER_EUROPE_DATA_DIR = os.getenv('WEATHER_EUROPE_DATA_DIR')
OUTPUT_FILE = os.path.join(DATA_DIR, "weather_europe.csv")

COUNTRIES = [ # Population in 2022 https://ec.europa.eu/eurostat/databrowser/view/tps00001/default/table?lang=en&category=t_demo.t_demo_pop
    {"name": "germany",     "weight": 83237124},
    {"name": "france",      "weight": 68091703},
    {"name": "italy",       "weight": 59030133},
    {"name": "netherlands", "weight": 17590672},
]

total_weight = sum(c["weight"] for c in COUNTRIES)

country_averages = []
for country in COUNTRIES:
    csv_files = glob.glob(os.path.join(DATA_DIR, WEATHER_EUROPE_DATA_DIR, country["name"], "point_*", "*.csv"))
    if not csv_files:
        raise FileNotFoundError(f"No CSV files found for country '{country['name']}' under {os.path.join(DATA_DIR, WEATHER_EUROPE_DATA_DIR, country['name'])}")

    frames = []
    for path in csv_files:
        df = pd.read_csv(path, parse_dates=["valid_time"])
        frames.append(df)

    combined = pd.concat(frames, ignore_index=True)
    value_cols = [c for c in combined.columns if c not in ("valid_time", "latitude", "longitude")]
    avg = (
        combined.groupby("valid_time", sort=True)[value_cols]
        .mean()
        .reset_index()
    )
    avg["_weight"] = country["weight"]
    country_averages.append(avg)

all_countries = pd.concat(country_averages, ignore_index=True)
value_cols = [c for c in all_countries.columns if c not in ("valid_time", "_weight")]

weighted = (
    all_countries.groupby("valid_time", sort=True)
    .apply(lambda g: pd.Series(
        {col: (g[col] * g["_weight"]).sum() / g["_weight"].sum() for col in value_cols}
    ))
    .reset_index()
)

weighted.to_csv(OUTPUT_FILE, index=False)
print(f"Saved {len(weighted)} rows to {OUTPUT_FILE}")
