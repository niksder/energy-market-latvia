cd "/home/niks/Projects/solar-power-latvia"
import delimited "data/panel_data/country_panel_data.csv", clear

gen str_time = subinstr(time, "T", " ", 1)
replace str_time = subinstr(str_time, "Z", "", 1)
gen double ms = clock(str_time, "YMD hms")
format ms %tc

gen date = dofc(ms)
format date %td

drop if country == "Switzerland" // Not in EU

// Drop observations before 2017-01-01 and after 2026-01-01
drop if date < td(01jan2017) | date >= td(01jan2026)

// Convert precipitation from m to mm (before collapse)
replace precipitation = precipitation * 1000

// Collapse hourly → daily
// Sum: production columns, precipitation
// Mean: everything else
collapse ///
    (sum)  gas_production solar_production ///
           brown_coal_production coal_gas_production hard_coal_production ///
           oil_production oil_shale_production peat_production ///
           hydro_ps_production hydro_ror_production hydro_wr_production ///
           wind_off_production wind_on_production total_generation precipitation ///
    (mean) energy_price wind_u100 wind_v100 temperature sun wind ///
           population_density gdp_pps ///
           year month week_of_year day_of_week, ///
    by(country date)

gen ln_energy_price = ln(energy_price)
gen ln_precipitation = ln(precipitation + 1)
gen ln_sun = ln(sun + 1)

gen hdd = cond((temperature - 273.15) < 15, 15 - (temperature - 273.15), 0)
gen cdd = cond((temperature - 273.15) > 25, (temperature - 273.15) - 25, 0)

// Rolling 7-day and 30-day precipitation sums (mirrors process_merged_data.py)
// Use [_n-k] subscript notation (no xtset required) within by-group
sort country date
by country (date): gen _cump = sum(precipitation)
by country (date): gen precipitation_weekly  = _cump - _cump[_n-7]  if _n > 7
by country (date): replace precipitation_weekly  = _cump if missing(precipitation_weekly)
by country (date): gen precipitation_monthly = _cump - _cump[_n-30] if _n > 30
by country (date): replace precipitation_monthly = _cump if missing(precipitation_monthly)
drop _cump

// Panel setup
egen country_id = group(country)
xtset country_id date

// ─── 365-day rolling production totals, shares, and growth rates ───────────
// Rolling sum via cumsum trick: sum[t] = cumsum[t] - cumsum[t-365]
// For the first <365 observations per country the cumsum itself is used.
local prefixes "gas solar brown_coal coal_gas hard_coal oil oil_shale peat hydro_ps hydro_ror hydro_wr wind_off wind_on"

sort country_id date
by country_id (date): gen _cum_total = sum(total_generation)
gen total_prod_yearly = _cum_total - L365._cum_total if !missing(L365._cum_total)
by country_id (date): replace total_prod_yearly = _cum_total if missing(total_prod_yearly)
drop _cum_total

foreach prefix of local prefixes {
    by country_id (date): gen _cum = sum(`prefix'_production)
    gen `prefix'_prod_yearly = _cum - L365._cum if !missing(L365._cum)
    by country_id (date): replace `prefix'_prod_yearly = _cum if missing(`prefix'_prod_yearly)
    drop _cum

    gen `prefix'_share = `prefix'_prod_yearly / total_prod_yearly
    replace `prefix'_share = . if total_prod_yearly == 0 | missing(total_prod_yearly)

    gen _lp = ln(`prefix'_prod_yearly) if `prefix'_prod_yearly > 0
    gen `prefix'_prod_growth = _lp - L1._lp
    drop _lp

    gen _ls = ln(`prefix'_share) if `prefix'_share > 0
    gen `prefix'_share_growth = _ls - L1._ls
    drop _ls
}

// Re-sort and reset xtset after all operations
sort country_id date
xtset country_id date