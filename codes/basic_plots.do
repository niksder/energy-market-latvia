cls
clear

cd "/home/niks/Projects/solar-power-latvia"
do "codes/load_data.do"

// Add a column holding monthly average for every month of energy price and gas price
bysort year month: egen energy_price_monthly_avg = mean(energy_price)
bysort year month: egen gas_price_monthly_avg = mean(gas_price)
bysort year month: egen wind_monthly_avg = mean(wind)
bysort year month: egen sun_monthly_avg = mean(sun)
replace sun_monthly_avg = sun_monthly_avg / 10000 // Scale sun to be in the same order of magnitude as energy price
bysort year month: egen temperature_monthly_avg = mean(temperature)
bysort year month: egen precipitation_monthly_avg = sum(precipitation)

// Plot over time the monthly average of energy price and gas price
twoway (line energy_price_monthly_avg date) ///
    (line gas_price_monthly_avg date), ///
    title("Monthly Average Energy Price and Gas Price Over Time") ///
    xtitle("Date") ///
    ytitle("Price")

// Save the plot
graph export "outputs/monthly_avg_energy_gas_price.png", replace


// Plot over time the monthly average of energy price and precipitation
twoway (line energy_price_monthly_avg date) ///
    (line precipitation_monthly_avg date), ///
    title("Monthly Average Energy Price and Precipitation Over Time") ///
    xtitle("Date") ///
    ytitle("Price / Precipitation")

// Save the plot
graph export "outputs/monthly_avg_energy_precipitation.png", replace


// Plot over time the monthly average of energy price and sun
twoway (line energy_price_monthly_avg date) ///
    (line sun_monthly_avg date), ///
    title("Monthly Average Energy Price and Sun Over Time") ///
    xtitle("Date") ///
    ytitle("Price / Sun")

// Save the plot
graph export "outputs/monthly_avg_energy_sun.png", replace


// Scatter
twoway (scatter energy_price_monthly_avg gas_price_monthly_avg) ///
    (lfit energy_price_monthly_avg gas_price_monthly_avg), ///
    title("Monthly Average Energy Price vs Gas Price") ///
    xtitle("Monthly Average Gas Price") ///
    ytitle("Monthly Average Energy Price")

// Save the plot
graph export "outputs/monthly_avg_energy_vs_gas_price.png", replace
