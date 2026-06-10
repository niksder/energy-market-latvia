cls
clear

cd "/home/niks/Projects/solar-power-latvia"
do "codes/load_data.do"

*******************
*** Regressions ***
*******************

* Simple regression of effect of gas price on energy price without controls

eststo gas1: reg ln_energy_price ln_gas_price

// scatter ln_energy_price ln_gas_price

* Add controls for time of day, day of week, and month

eststo gas2: reg ln_energy_price ln_gas_price i.hour i.day_of_week i.month

* Add controls for weather variables

eststo gas3: reg ln_energy_price ln_gas_price ///
    temperature wind ln_sun sun_x_solar_capacity ln_water_storage precipitation precipitation_weekly precipitation_monthly ///
    i.hour i.day_of_week i.month, vce(cluster date)

// Plot real price and estimated price on a timeline
predict ln_energy_price_hat, xb
gen energy_price_hat = exp(ln_energy_price_hat)

bysort year month: egen energy_price_mean = mean(energy_price)
bysort year month: egen energy_price_hat_mean = mean(energy_price_hat)

twoway (line energy_price_mean date, sort) ///
       (line energy_price_hat_mean date, sort), ///
       legend(label(1 "Actual Price") label(2 "Estimated Price")) ///
       title("Actual vs Estimated Energy Price Over Time (Using Gas Price)") ///
       xtitle("Date") ytitle("Energy Price")

// Save the plot
graph export "outputs/actual_vs_estimated_energy_price3.png", replace

* Check the effect of war as a dummy

reg ln_energy_price war ///
    temperature wind ln_sun sun_x_solar_capacity ln_water_storage precipitation precipitation_weekly precipitation_monthly ///
    i.hour i.day_of_week i.month, vce(cluster date)

predict ln_energy_price_hat_war, xb
gen energy_price_hat_war = exp(ln_energy_price_hat_war)

bysort year month: egen energy_price_hat_war_mean = mean(energy_price_hat_war)

twoway (line energy_price_mean date, sort) ///
       (line energy_price_hat_war_mean date, sort), ///
       legend(label(1 "Actual Price") label(2 "Estimated Price")) ///
       title("Actual vs Estimated Energy Price Over Time (Using War Dummy)") ///
       xtitle("Date") ytitle("Energy Price")

graph export "outputs/actual_vs_estimated_energy_price_war_dummy.png", replace

// =============================================================================
// EXPORT GAS PRICE REGRESSIONS TO LATEX
// =============================================================================

esttab gas1 gas2 gas3 ///
    using "outputs/gas_price_regressions.tex", ///
    replace booktabs se label ///
    drop(*.hour *.day_of_week *.month) ///
    varlabels(ln_gas_price "ln(Gas price)") ///
    title("Effect of log gas price on log electricity price") ///
    mtitles("No controls" "Time FE" "Weather + Time FE") ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    stats(N r2, fmt(%9.0f %6.4f) labels("Observations" "\$R^2\$")) ///
    note("SE in parentheses. Column (3) clustered by date. Time FE: hour, day-of-week, month.")
