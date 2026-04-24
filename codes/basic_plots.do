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
    title("Monthly Average Energy Price and Natural Gas Price") ///
    legend(label(1 "Latvia's Wholesale Energy Price") label(2 "Dutch TTF Natural Gas Futures Price")) ///
    legend(position(6)) ///
    xlabel(#7, format(%tdMon_CCYY) angle(45)) ///
    xtitle("Date") ///
    ytitle("Price")

// Save the plot
graph export "outputs/monthly_avg_energy_gas_price.png", replace

preserve

    // Define monthly averages
    /* bysort month year: egen energy_price_monthly_avg = mean(energy_price)
    bysort month year: egen gas_price_monthly_avg = mean(gas_price) */

    gen ln_energy_price_monthly_avg = ln(energy_price_monthly_avg)
    gen ln_gas_price_monthly_avg = ln(gas_price_monthly_avg)

    // Leave only the monthly averages in the dataset
    keep month year date ln_energy_price_monthly_avg ln_gas_price_monthly_avg
    // Drop duplicate months
    bysort month year: keep if _n == 1
    
    tsset year month, monthly

    // Define ln difference monthly variables
    gen d_ln_energy_price = D.ln_energy_price_monthly_avg
    gen d_ln_gas_price = D.ln_gas_price_monthly_avg

    // Plot bar diagram over time the log differences of just gas price (and no energy price)
    twoway bar d_ln_gas_price date, ///
        barwidth(6) ///
        title("Monthly Log Difference of Natural Gas Price Over Time") ///
        xlabel(#7, format(%tdMon_CCYY) angle(45)) ///
        legend(off)

    // Save the plot
    graph export "outputs/monthly_log_diff_energy_gas_price.png", replace

restore


preserve

    // Define weekly averages
    bysort week year: egen energy_price_weekly_avg = mean(energy_price)
    bysort week year: egen gas_price_weekly_avg = mean(gas_price)

    gen ln_energy_price_weekly_avg = ln(energy_price_weekly_avg)
    gen ln_gas_price_weekly_avg = ln(gas_price_weekly_avg)

    // Leave only the weekly averages in the dataset
    keep week year date ln_energy_price_weekly_avg ln_gas_price_weekly_avg
    // Drop duplicate weeks
    bysort week year: keep if _n == 1
    
    tsset year week, weekly

    // Define ln difference weekly variables
    gen d_ln_energy_price = D.ln_energy_price_weekly_avg
    gen d_ln_gas_price = D.ln_gas_price_weekly_avg

    // Plot bar diagram over time the log differences of just gas price (and no energy price)
    twoway bar d_ln_gas_price date, ///
        barwidth(6) ///
        title("Weekly Log Difference of Natural Gas Price Over Time") ///
        xlabel(#7, format(%tdMon_CCYY) angle(45)) ///
        legend(off)

    // Save the plot
    graph export "outputs/weekly_log_diff_energy_gas_price.png", replace

restore


preserve

    // Define daily averages
    bysort date: egen energy_price_daily_avg = mean(energy_price)
    bysort date: egen gas_price_daily_avg = mean(gas_price)

    gen ln_energy_price_daily_avg = ln(energy_price_daily_avg)
    gen ln_gas_price_daily_avg = ln(gas_price_daily_avg)

    // Leave only the daily averages in the dataset
    keep date ln_energy_price_daily_avg ln_gas_price_daily_avg
    // Drop duplicate days
    bysort date: keep if _n == 1
    
    tsset date, daily

    // Define ln difference daily variables
    gen d_ln_energy_price = D.ln_energy_price_daily_avg
    gen d_ln_gas_price = D.ln_gas_price_daily_avg

    // Plot bar diagram over time the log differences of just gas price (and no energy price)
    twoway bar d_ln_gas_price date, ///
        barwidth(6) ///
        title("Daily Log Difference of Natural Gas Price Over Time") ///
        xlabel(#7, format(%tdMon_CCYY) angle(45)) ///
        legend(off)

    // Save the plot
    graph export "outputs/daily_log_diff_energy_gas_price.png", replace

restore



// Plot over time the monthly average of energy price and precipitation
twoway (line energy_price_monthly_avg date) ///
    (line precipitation_monthly_avg date), ///
    title("Latvia's Energy Price and Precipitation Over Time") ///
    legend(label(1 "Energy Price") label(2 "Precipitation")) ///
    xtitle("Date") ///
    ytitle("Price / Precipitation")

// Save the plot
graph export "outputs/monthly_avg_energy_precipitation.png", replace


// Plot over time the monthly average of energy price and sun
twoway (line energy_price_monthly_avg date) ///
    (line sun_monthly_avg date), ///
    title("Monthly Average Latvia's Energy Price and Sun Over Time") ///
    legend(label(1 "Energy Price") label(2 "Sun")) ///
    xtitle("Date") ///
    ytitle("Price / Sun")

// Save the plot
graph export "outputs/monthly_avg_energy_sun.png", replace


// Scatter
twoway (scatter energy_price_monthly_avg gas_price_monthly_avg) ///
    (lfit energy_price_monthly_avg gas_price_monthly_avg), ///
    title("Monthly Average Latvia's Energy Price vs Natural Gas Futures Price") ///
    legend(label(1 "Energy Price") label(2 "Gas Price")) ///
    xtitle("Monthly Average Natural Gas Price") ///
    ytitle("Monthly Average Energy Price")

// Save the plot
graph export "outputs/monthly_avg_energy_vs_gas_price.png", replace
