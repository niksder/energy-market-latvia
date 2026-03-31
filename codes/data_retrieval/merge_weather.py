import glob
import os
import pandas as pd
from dotenv import load_dotenv

load_dotenv()
DATA_DIR = os.getenv('DATA_DIR')
WEATHER_DATA_DIR = os.getenv('WEATHER_DATA_DIR')
OUTPUT_FILE = os.path.join(DATA_DIR, "weather.csv")

csv_files = glob.glob(os.path.join(DATA_DIR, WEATHER_DATA_DIR, "point_*", "*.csv"))

if not csv_files:
    raise FileNotFoundError(f"No CSV files found under {os.path.join(DATA_DIR, WEATHER_DATA_DIR, 'point_*')}")

frames = []
for path in csv_files:
    df = pd.read_csv(path, parse_dates=["valid_time"])
    frames.append(df)

combined = pd.concat(frames, ignore_index=True)

value_cols = [c for c in combined.columns if c not in ("valid_time", "latitude", "longitude")]
averaged = (
    combined.groupby("valid_time", sort=True)[value_cols]
    .mean()
    .reset_index()
)

averaged.to_csv(OUTPUT_FILE, index=False)
print(f"Saved {len(averaged)} rows to {OUTPUT_FILE}")
