cd "/home/niks/Projects/solar-power-latvia"
import delimited "data/merged_data.csv", clear

// Drop the first line 
drop in 1

gen datetime = clock(time, "YMD hms")
format datetime %tc

gen date = dofc(datetime)
format date %td

// Replace . in gas prices with last observed value
replace gas_price = gas_price[_n-1] if gas_price == .

// Convert precipitiation from m to mm
replace precipitation = precipitation * 1000

// Define ln variables
gen ln_energy_price = ln(energy_price)
gen ln_gas_price = ln(gas_price)
gen ln_precipitation = ln(precipitation + 1) // Add 1 to avoid log(0)
gen ln_water_storage = ln(water_storage + 1) // Add 1 to avoid log(0)

gen war = days_since_war > 0

