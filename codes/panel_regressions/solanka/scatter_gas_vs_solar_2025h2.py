"""
Scatter plot: pre-war gas dependence  vs  solar share change to H2 2025
Each dot = one bidding zone, labelled by name.

X-axis: gas share on 2021-02-23  (pre-war treatment intensity)
Y-axis: mean solar share in H2 2025  minus  mean solar share on 2021-02-23
        (i.e. how much solar grew relative to pre-war baseline)

A regression line is overlaid so the overall slope (≈ diff-in-diff coefficient)
is visible at a glance.  Countries in the upper-right quadrant (high gas
dependence + large solar growth) drive the positive treatment effect.
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.patheffects as pe
from scipy import stats
import os

# ── paths ────────────────────────────────────────────────────────────────────
BASE_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "..")
DATA_PATH = os.path.join(BASE_DIR, "data", "panel_data", "merged_panel_data.csv")
OUT_DIR   = os.path.join(BASE_DIR, "outputs", "panel", "solar_diff_and_diff", "solanka")
os.makedirs(OUT_DIR, exist_ok=True)

print("about to load")
# ── load only needed rows via chunked read ────────────────────────────────────
COLS = ["time", "bzone", "gas_share", "solar_share"]
CHUNKSIZE = 50_000

pre_war_rows, h2_rows = [], []

for chunk in pd.read_csv(DATA_PATH, usecols=COLS, chunksize=CHUNKSIZE, low_memory=False):
    chunk["time"] = pd.to_datetime(chunk["time"], utc=True)
    EXCLUDE = {
        "Switzerland",
        "IT_NORTH", "IT_CNOR", "IT_CSUD", "IT_SUD", "IT_CALA",
        "IT_SICI", "IT_SARD", "IT_SACOAC", "IT_SACODC",
    }
    chunk = chunk[~chunk["bzone"].isin(EXCLUDE)]

    mask_pre = chunk["time"].dt.date == pd.Timestamp("2021-02-23").date()
    if mask_pre.any():
        pre_war_rows.append(chunk.loc[mask_pre, ["bzone", "gas_share", "solar_share"]])

    mask_h2 = (chunk["time"].dt.year == 2025) & (chunk["time"].dt.month >= 7)
    if mask_h2.any():
        h2_rows.append(chunk.loc[mask_h2, ["bzone", "gas_share", "solar_share"]])

pre_war_df = pd.concat(pre_war_rows) if pre_war_rows else pd.DataFrame()
h2_df      = pd.concat(h2_rows)      if h2_rows      else pd.DataFrame()

# ── pre-war snapshot  (2021-02-23) ───────────────────────────────────────────
pre_war = (
    pre_war_df.groupby("bzone")[["gas_share", "solar_share"]]
    .mean()
    .rename(columns={"gas_share": "gas_share_pre", "solar_share": "solar_share_pre"})
)

# ── H2 2025 average  (July–December 2025) ────────────────────────────────────
h2_2025 = (
    h2_df.groupby("bzone")[["gas_share", "solar_share"]]
    .mean()
    .rename(columns={"gas_share": "gas_share_h2", "solar_share": "solar_share_h2"})
)

# ── combine ───────────────────────────────────────────────────────────────────
plot_df = pre_war.join(h2_2025, how="inner").dropna()
plot_df["delta_solar"] = plot_df["solar_share_h2"] - plot_df["solar_share_pre"]

# Convert to % for readability
plot_df["gas_share_pre_pct"]  = plot_df["gas_share_pre"]  * 100
plot_df["solar_share_h2_pct"] = plot_df["solar_share_h2"] * 100
plot_df["delta_solar_pct"]    = plot_df["delta_solar"]     * 100

print(f"Bzones in plot: {sorted(plot_df.index.tolist())}")
print(plot_df[["gas_share_pre_pct", "solar_share_h2_pct", "delta_solar_pct"]]
      .sort_values("gas_share_pre_pct", ascending=False).round(2).to_string())

# ── regression line (for delta_solar) ────────────────────────────────────────
x = plot_df["gas_share_pre_pct"].values
y = plot_df["delta_solar_pct"].values
slope, intercept, r, p, _ = stats.linregress(x, y)
x_line = np.linspace(x.min() - 2, x.max() + 2, 200)
y_line = slope * x_line + intercept

# ── colour by direction ───────────────────────────────────────────────────────
# Above regression line → contributes positively; below → negatively
y_pred  = slope * x + intercept
residual = y - y_pred
colors  = np.where(residual >= 0, "#2166ac", "#d6604d")   # blue / red

# ── plot ──────────────────────────────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(10, 7))

ax.plot(x_line, y_line, color="gray", lw=1.4, ls="--",
        label=f"OLS slope = {slope:.2f} pp per 10 pp gas (R²={r**2:.2f}, p={p:.3f})")
ax.axhline(0, color="black", lw=0.6, ls=":")

ax.scatter(x, y, c=colors, s=70, zorder=3, edgecolors="white", linewidths=0.5)

# Label each dot
NUDGE = dict(ha="left", va="center", fontsize=8)
for bzone, row in plot_df.iterrows():
    xi = row["gas_share_pre_pct"]
    yi = row["delta_solar_pct"]
    ax.annotate(
        bzone, xy=(xi, yi), xytext=(5, 0), textcoords="offset points",
        **NUDGE,
        path_effects=[pe.withStroke(linewidth=2, foreground="white")],
    )

ax.set_xlabel("Pre-war gas share (2021-02-23, %)", fontsize=11)
ax.set_ylabel("Δ Solar share: H2 2025 − pre-war (pp)", fontsize=11)
ax.set_title(
    "Gas dependence vs solar growth to H2 2025\n"
    "Blue = above trend (positive residual), Red = below trend (negative residual)",
    fontsize=11,
)
ax.legend(fontsize=9, loc="upper left")
ax.grid(True, alpha=0.3)

plt.tight_layout()
out_path = os.path.join(OUT_DIR, "scatter_gas_dep_vs_solar_growth_2025h2.pdf")
plt.savefig(out_path, dpi=150)
out_path_png = out_path.replace(".pdf", ".png")
plt.savefig(out_path_png, dpi=150)
plt.show()
print(f"Saved: {out_path}")
print(f"Saved: {out_path_png}")
