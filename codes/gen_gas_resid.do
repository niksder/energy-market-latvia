

gen d_ln_gas_price = D.ln_gas_price
gen d_ln_energy_price_europe = D.ln_energy_price_europe

reg d_ln_gas_price ///
    L(1/4).d_ln_gas_price ///
    L(1/4).d_ln_energy_price_europe ///
    temperature_europe ///
    i.hour i.day_of_week i.month

predict gas_resid, resid

// Plot gas_resid over time
twoway bar gas_resid date, ///
    title("Residuals of Log Difference of Gas Price Over Time") ///
    xtitle("Date") ytitle("Residuals of Log Difference of Gas Price") ///
    xlabel(#7, format(%tdMon_CCYY) angle(45))

// Save the plot
graph export "outputs/gas_price_residuals_over_time.png", replace


// Now do the same for daily data

preserve

    collapse (mean) gas_price energy_price_europe temperature_europe, by(date)
    gen ln_gas_price = ln(gas_price)
    gen ln_energy_price_europe = ln(energy_price_europe)

    tsset date

    gen d_ln_gas_price = D.ln_gas_price
    gen d_ln_energy_price_europe = D.ln_energy_price_europe
    reg d_ln_gas_price ///
        L(1/3).d_ln_gas_price ///
        L(1/3).d_ln_energy_price_europe ///
        temperature_europe

    predict gas_resid_daily, resid
    // Plot gas_resid_daily over time
    twoway bar gas_resid_daily date, ///
        title("Residuals of Log Difference of Gas Price Over Time (Daily Data)") ///
        xtitle("Date") ytitle("Residuals of Log Difference of Gas Price") ///
        xlabel(#7, format(%tdMon_CCYY) angle(45))

    // Save the plot
    graph export "outputs/gas_price_residuals_over_time_daily.png", replace

restore

// Now same thing for weekly data

preserve

    collapse (mean) gas_price energy_price_europe temperature_europe, by(year week_of_year)
    sort year week_of_year
    gen week_seq = _n
    gen ln_gas_price = ln(gas_price)
    gen ln_energy_price_europe = ln(energy_price_europe)

    tsset week_seq

    gen d_ln_gas_price = D.ln_gas_price
    gen d_ln_energy_price_europe = D.ln_energy_price_europe
    reg d_ln_gas_price ///
        L(1/3).d_ln_gas_price ///
        L(1/3).d_ln_energy_price_europe ///
        temperature_europe

    predict gas_resid_weekly, resid
    gen week_label = string(year) + "-W" + string(week_of_year, "%02.0f")
    // Build xlabel string: label every 8th bar with its week_label
    levelsof week_seq, local(seqs)
    local xlabels ""
    foreach s of local seqs {
        if mod(`s', 8) == 1 {
            levelsof week_label if week_seq == `s', local(lbl) clean
            local xlabels `"`xlabels' `s' "`lbl'""'
        }
    }
    // Plot gas_resid_weekly over time
    twoway bar gas_resid_weekly week_seq, ///
        title("Residuals of Log Difference of Gas Price Over Time (Weekly Data)") ///
        xtitle("Week") ytitle("Residuals of Log Difference of Gas Price") ///
        xlabel(`xlabels', angle(45))

    // Save the plot
    graph export "outputs/gas_price_residuals_over_time_weekly.png", replace
restore

// Now same for months

preserve

    collapse (mean) gas_price energy_price_europe temperature_europe, by(year month)
    sort year month
    gen month_seq = _n
    gen ln_gas_price = ln(gas_price)
    gen ln_energy_price_europe = ln(energy_price_europe)

    tsset month_seq

    gen d_ln_gas_price = D.ln_gas_price
    gen d_ln_energy_price_europe = D.ln_energy_price_europe
    reg d_ln_gas_price ///
        L(1/3).d_ln_gas_price ///
        L(1/3).d_ln_energy_price_europe ///
        temperature_europe

    predict gas_resid_monthly, resid
    gen month_label = string(year) + "-" + string(month, "%02.0f")
    // Build xlabel string: label every 3rd bar with its month_label
    levelsof month_seq, local(seqs)
    local xlabels ""
    foreach s of local seqs {
        if mod(`s', 3) == 1 {
            levelsof month_label if month_seq == `s', local(lbl) clean
            local xlabels `"`xlabels' `s' "`lbl'""'
        }
    }
    // Plot gas_resid_monthly over time
    twoway bar gas_resid_monthly month_seq, ///
        title("Residuals of Log Difference of Gas Price Over Time (Monthly Data)") ///
        xtitle("Month") ytitle("Residuals of Log Difference of Gas Price") ///
        xlabel(`xlabels', angle(45))

    // Save the plot
    graph export "outputs/gas_price_residuals_over_time_monthly.png", replace
restore