cd "/home/niks/Projects/solar-power-latvia"
import delimited "data/merged_data.csv", clear

// Drop the first line 
drop in 1

gen double ms = clock(time, "YMD hms")
format ms %tc

gen date = dofc(ms)
format date %td

// Integer hour count since 1960-01-01 — avoids floating-point delta issues
gen long t = round(ms / 3600000)
label variable t "Hours since 1960-01-01 00:00:00"

// Replace . in gas prices with last observed value
replace gas_price = gas_price[_n-1] if gas_price == .

// Convert precipitiation from m to mm
replace precipitation = precipitation * 1000

// Define ln variables
gen ln_energy_price = ln(energy_price)
gen ln_gas_price_weekly = ln(gas_price_weekly)
gen ln_gas_price = ln(gas_price)
gen ln_precipitation = ln(precipitation + 1) // Add 1 to avoid log(0)
gen ln_water_storage = ln(water_storage + 1) // Add 1 to avoid log(0)

gen war = days_since_war > 0

tsset t
