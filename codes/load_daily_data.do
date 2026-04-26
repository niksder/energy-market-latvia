cd "/home/niks/Projects/solar-power-latvia"
import delimited "data/merged_data.csv", clear

// Drop the first line 
drop in 1

gen double ms = clock(time, "YMD hms")
format ms %tc

gen date = dofc(ms)
format date %td

// Drop observations starting from 2026-01-01
drop if date >= td(01jan2026)

// Replace . in gas prices with last observed value (before collapse)
replace gas_price = gas_price[_n-1] if gas_price == .

// Convert precipitation from m to mm (before collapse)
replace precipitation = precipitation * 1000

// Collapse to daily data
// Sum: production columns, electricity_exports, precipitation
// Mean: everything else
collapse ///
    (sum)  biomass_production gas_production hydro_production ///
           solar_production wind_production other_production ///
           electricity_exports precipitation ///
    (mean) energy_price wind_u100 wind_v100 temperature sun ///
           energy_price_europe temperature_europe wind ///
           gas_price_weekly precipitation_24h precipitation_weekly ///
           precipitation_monthly biomass_capacity gas_capacity ///
           hydro_capacity solar_capacity wind_capacity other_capacity ///
           gas_price water_storage days_since_war ///
           year month week_of_year day_of_week, ///
    by(date)

// Re-define ln variables
gen ln_energy_price = ln(energy_price)
gen ln_energy_price_europe = ln(energy_price_europe)
gen ln_gas_price = ln(gas_price)
gen ln_precipitation = ln(precipitation + 1) // Add 1 to avoid log(0)
gen ln_water_storage = ln(water_storage + 1) // Add 1 to avoid log(0)
gen ln_sun = ln(sun + 1) // Add 1 to avoid log(0)

gen sun_x_solar_capacity = ln_sun * solar_capacity

gen hdd = cond((temperature - 273.15) < 15, 15 - (temperature - 273.15), 0)
gen cdd = cond((temperature - 273.15) > 25, (temperature - 273.15) - 25, 0)

gen hdd_europe = cond((temperature_europe - 273.15) < 15, 15 - (temperature_europe - 273.15), 0)
gen cdd_europe = cond((temperature_europe - 273.15) > 22, (temperature_europe - 273.15) - 22, 0)

gen war = days_since_war > 0

tsset date

do "codes/gen_gas_resid_daily.do"