cls
clear

cd "/home/niks/Projects/solar-power-latvia"
import delimited "data/merged_data.csv", clear

// drop first line 
drop in 1

gen datetime = clock(time, "YMD hms")
format datetime %tc

gen date = dofc(datetime)
format date %td

gen ln_energy_price = ln(energy_price)
gen ln_gas_price = ln(gas_price)

gen ln_precipitation = ln(precipitation + 1) // Add 1 to avoid log(0)

reg ln_energy_price ln_gas_price

// scatter ln_energy_price ln_gas_price

reg ln_energy_price ln_gas_price i.hour i.day_of_week i.month

reg ln_energy_price ln_gas_price ///
    temperature wind precipitation ///
    i.hour i.day_of_week i.month, vce(cluster date)
