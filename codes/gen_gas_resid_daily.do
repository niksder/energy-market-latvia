
gen d_ln_gas_price = D.ln_gas_price
gen d_ln_energy_price_europe = D.ln_energy_price_europe
reg d_ln_gas_price ///
    L(1/7).d_ln_gas_price ///
    L(1/3).d_ln_energy_price_europe ///
    hdd_europe cdd_europe ///
    i.day_of_week i.month

predict gas_resid_daily, resid

preserve 
    // drop observations not between 2022-02-15 and 2022-03-15
    drop if date < td(15feb2022) | date > td(15mar2022)

    // Plot gas_resid_daily over time
    twoway bar gas_resid_daily date, ///
        title("Residuals of Log Difference of Gas Price Over Time (Daily Data)") ///
        xtitle("Date") ytitle("Residuals of Log Difference of Gas Price") ///
        xlabel(#10, format(%tdDD_Mon_CCYY) angle(45))

restore

// Save the plot
graph export "outputs/gas_price_residuals_over_time_daily.png", replace
