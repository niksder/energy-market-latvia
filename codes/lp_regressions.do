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

gen sun_x_solar_capacity = ln_sun * solar_capacity

reg ln_energy_price ln_gas_price L(0/3).ln_gas_price_weekly ///
    temperature wind ln_sun sun_x_solar_capacity ln_water_storage precipitation precipitation_weekly precipitation_monthly ///
    i.hour i.day_of_week i.month

// Plot real price and estimated price on a timeline
predict ln_energy_price_hat, xb
gen energy_price_hat = exp(ln_energy_price_hat)

bysort year month: egen energy_price_mean = mean(energy_price)
bysort year month: egen energy_price_hat_mean = mean(energy_price_hat)

twoway (line energy_price_mean date, sort) ///
       (line energy_price_hat_mean date, sort), ///
       legend(label(1 "Actual Price") label(2 "Estimated Price")) ///
       title("Actual vs Estimated Energy Price Over Time (Using Lagged Weekly Values)") ///
       xtitle("Date") ytitle("Energy Price")

// Save the plot
graph export "outputs/actual_vs_estimated_energy_price_lagged_weekly_values.png", replace