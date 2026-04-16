cls
clear

cd "/home/niks/Projects/solar-power-latvia"
do "codes/load_data.do"

*******************
*** Regressions ***
*******************


* Do LP regression to check dynamic effects of gas price changes on energy price

/* 
lpirf ln_energy_price ln_gas_price, lags(1 2 3 4) ///
    controls(temperature wind sun ln_water_storage precipitation i.hour i.day_of_week i.month)
 */

/* forvalues i = 0/24 {
    reg ln_energy_price L`i'.ln_gas_price ///
        temperature wind sun ln_water_storage precipitation ///
        i.hour i.day_of_week i.month, vce(cluster date)
} */

reg ln_energy_price L(0/3).ln_gas_price ///
    temperature wind precipitation ///
    i.hour i.day_of_week i.month