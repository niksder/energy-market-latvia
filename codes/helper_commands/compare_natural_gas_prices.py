import os
import re
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd

from dotenv import load_dotenv

load_dotenv()

DATA_DIR = os.getenv('DATA_DIR')
CONSTANTS_DIR = DATA_DIR + '/' + os.getenv('CONSTANTS_DIR', 'constants')
OUTPUTS_DIR = os.getenv('OUTPUTS_DIR', 'outputs')

DAILY_PRICES_PATH = DATA_DIR + "/natural_gas_prices.csv"
HOUSEHOLD_TSV_PATH = CONSTANTS_DIR + "/estat_nrg_pc_204.tsv"
NON_HOUSEHOLD_TSV_PATH = CONSTANTS_DIR + "/estat_nrg_pc_205.tsv"
PLOT_OUTPUT_PATH = OUTPUTS_DIR + "/natural_gas_prices_comparison.png"
BIYEARLY_WIDE_OUTPUT_PATH = DATA_DIR + "/natural_gas_prices_biyearly_wide.csv"
START_DATE = pd.Timestamp("2020-01-01")

# Latvia series filters used in Eurostat tables.
GEO = "LV"
FREQ = "S"
SIEC = "E7000"
TAX = "I_TAX"
CURRENCY = "EUR"

HOUSEHOLD_CONSUMPTION_BAND = "KWH1000-2499"
NON_HOUSEHOLD_CONSUMPTION_BAND = "MWH20-499"


def _parse_numeric_value(raw_value: str):
	"""Extract numeric value from Eurostat cells like '0.3247', '0.3247 e', or ':'."""
	value = (raw_value or "").strip()
	if not value or value == ":":
		return pd.NA

	match = re.search(r"-?\d+(?:\.\d+)?", value)
	if not match:
		return pd.NA

	return float(match.group())


def _semester_to_date(period: str):
	"""Convert labels like '2024-S1'/'2024-S2' to a timestamp (Jan/Jul 1st)."""
	label = (period or "").strip()
	match = re.fullmatch(r"(\d{4})-S([12])", label)
	if not match:
		return pd.NaT

	year = int(match.group(1))
	semester = int(match.group(2))
	month = 1 if semester == 1 else 7
	return pd.Timestamp(year=year, month=month, day=1)


def load_eurostat_series(tsv_path: Path, consumption_band: str, series_label: str) -> pd.DataFrame:
	df = pd.read_csv(tsv_path, sep="\t")
	df.columns = [col.strip() for col in df.columns]

	dimensions_column = df.columns[0]
	dimensions = df[dimensions_column].str.split(",", expand=True)
	dimensions.columns = ["freq", "siec", "nrg_cons", "unit", "tax", "currency", "geo"]

	df = pd.concat([dimensions, df.drop(columns=[dimensions_column])], axis=1)

	filtered = df[
		(df["freq"] == FREQ)
		& (df["siec"] == SIEC)
		& (df["nrg_cons"] == consumption_band)
		& (df["tax"] == TAX)
		& (df["currency"] == CURRENCY)
		& (df["geo"] == GEO)
	]

	if filtered.empty:
		raise ValueError(
			f"No Eurostat data found for {series_label} with geo={GEO}, nrg_cons={consumption_band}."
		)

	value_columns = [
		col
		for col in filtered.columns
		if col not in {"freq", "siec", "nrg_cons", "unit", "tax", "currency", "geo"}
	]

	long_df = filtered.melt(
		id_vars=["freq", "siec", "nrg_cons", "unit", "tax", "currency", "geo"],
		value_vars=value_columns,
		var_name="period",
		value_name="value_raw",
	)

	long_df["eur_per_kwh"] = long_df["value_raw"].apply(_parse_numeric_value)
	long_df["date"] = long_df["period"].apply(_semester_to_date)
	long_df = long_df.dropna(subset=["eur_per_kwh", "date"])

	long_df["eur_per_mwh"] = long_df["eur_per_kwh"] * 1000.0
	long_df["series"] = series_label

	long_df = long_df[long_df["date"] >= START_DATE]
	return long_df[["date", "eur_per_mwh", "series"]].sort_values("date")


def load_daily_prices(csv_path: Path) -> pd.DataFrame:
	daily = pd.read_csv(csv_path)
	daily["date"] = pd.to_datetime(daily["time"], errors="coerce")
	daily["eur_per_mwh"] = pd.to_numeric(daily["Price"], errors="coerce")
	daily = daily.dropna(subset=["date", "eur_per_mwh"])
	daily["series"] = "Daily TTF futures"
	daily = daily[daily["date"] >= START_DATE]
	return daily[["date", "eur_per_mwh", "series"]].sort_values("date")


def build_semiannual_averages_from_daily(daily_df: pd.DataFrame) -> pd.DataFrame:
	semiannual = daily_df[["date", "eur_per_mwh"]].copy()
	semiannual["year"] = semiannual["date"].dt.year
	semiannual["semester"] = (semiannual["date"].dt.month > 6).astype(int) + 1

	agg = (
		semiannual.groupby(["year", "semester"], as_index=False)["eur_per_mwh"]
		.mean()
		.rename(columns={"eur_per_mwh": "eur_per_mwh"})
	)

	agg["date"] = agg.apply(
		lambda row: pd.Timestamp(
			year=int(row["year"]),
			month=1 if int(row["semester"]) == 1 else 7,
			day=1,
		),
		axis=1,
	)
	agg["series"] = "Daily prices bi-yearly average"
	return agg[["date", "eur_per_mwh", "series"]].sort_values("date")


def export_biyearly_tables(
	household_df: pd.DataFrame,
	non_household_df: pd.DataFrame,
	daily_semiannual_df: pd.DataFrame,
) -> None:
	biyearly_data = pd.concat(
		[household_df, non_household_df, daily_semiannual_df],
		ignore_index=True,
	).sort_values(["date", "series"])

	biyearly_data["date"] = biyearly_data["date"].dt.strftime("%Y-%m-%d")
	biyearly_data["period"] = biyearly_data["date"].str.slice(0, 4) + "-S" + biyearly_data["date"].str.slice(5, 7).map(
		{"01": "1", "07": "2"}
	)
	biyearly_data = biyearly_data[["date", "period", "series", "eur_per_mwh"]]

	biyearly_wide = (
		biyearly_data.pivot(index=["date", "period"], columns="series", values="eur_per_mwh")
		.reset_index()
		.sort_values("date")
	)
	biyearly_wide.columns.name = None
	biyearly_wide = biyearly_wide.rename(
		columns={
			"Household bi-yearly": "household_price",
			"Non-household bi-yearly": "non_household_price",
			"Daily prices bi-yearly average": "ttf_futures_price",
		}
	)
	biyearly_wide.to_csv(BIYEARLY_WIDE_OUTPUT_PATH, index=False)

	print(f"Saved bi-yearly wide table to: {BIYEARLY_WIDE_OUTPUT_PATH}")


def plot_series(
	daily_df: pd.DataFrame,
	household_df: pd.DataFrame,
	non_household_df: pd.DataFrame,
	daily_semiannual_df: pd.DataFrame,
) -> None:
	plt.figure(figsize=(13, 7))

	plt.plot(
		daily_df["date"],
		daily_df["eur_per_mwh"],
		label="Daily TTF futures (EUR/MWh)",
		color="#1f77b4",
		linewidth=1.1,
		alpha=0.75,
	)

	plt.plot(
		household_df["date"],
		household_df["eur_per_mwh"],
		label="Household bi-yearly (Eurostat nrg_pc_204, LV)",
		color="#d62728",
		linewidth=2.0,
		marker="o",
		markersize=4,
	)

	plt.plot(
		non_household_df["date"],
		non_household_df["eur_per_mwh"],
		label="Non-household bi-yearly (Eurostat nrg_pc_205, LV)",
		color="#2ca02c",
		linewidth=2.0,
		marker="s",
		markersize=4,
	)

	plt.plot(
		daily_semiannual_df["date"],
		daily_semiannual_df["eur_per_mwh"],
		label="Daily prices bi-yearly average (from CSV)",
		color="#111111",
		linewidth=2.0,
		linestyle="--",
		marker="D",
		markersize=4,
	)

	plt.title("Latvia Natural Gas Prices: Daily vs Eurostat Bi-yearly")
	plt.xlabel("Date")
	plt.ylabel("Price (EUR/MWh)")
	plt.grid(True, linestyle="--", linewidth=0.7, alpha=0.4)
	plt.legend()
	plt.tight_layout()

	os.makedirs(os.path.dirname(PLOT_OUTPUT_PATH), exist_ok=True)
	plt.savefig(PLOT_OUTPUT_PATH, dpi=160)
	print(f"Saved plot to: {PLOT_OUTPUT_PATH}")

	plt.show()


daily_df = load_daily_prices(DAILY_PRICES_PATH)
household_df = load_eurostat_series(
	HOUSEHOLD_TSV_PATH,
	HOUSEHOLD_CONSUMPTION_BAND,
	"Household bi-yearly",
)
non_household_df = load_eurostat_series(
	NON_HOUSEHOLD_TSV_PATH,
	NON_HOUSEHOLD_CONSUMPTION_BAND,
	"Non-household bi-yearly",
)
daily_semiannual_df = build_semiannual_averages_from_daily(daily_df)
export_biyearly_tables(household_df, non_household_df, daily_semiannual_df)

plot_series(daily_df, household_df, non_household_df, daily_semiannual_df)
