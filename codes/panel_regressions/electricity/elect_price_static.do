cls
clear

cd "/home/niks/Projects/solar-power-latvia"
do "codes/panel_regressions/load_daily_data.do"

// Count bzones dynamically
quietly levelsof bzone_id, local(_bzone_list)
local n_bzones : word count `_bzone_list'
di "Number of bzones in data: `n_bzones'"

cap mkdir "outputs/panel/electricity"
cap mkdir "outputs/panel/electricity/static"

// =============================================================================
// MERGE IN NATURAL GAS PRICES
//   gas_price is a single daily time series (not bzone-specific) and is not
//   included in the panel collapse. We load it separately and merge by date.
// =============================================================================

preserve
    import delimited "data/natural_gas_prices.csv", clear varnames(1)
    // time column is "YYYY-MM-DD HH:MM:SS"
    gen str10 date_str = substr(time, 1, 10)
    gen double date = date(date_str, "YMD")
    format date %td
    rename price gas_price
    keep date gas_price
    // Forward-fill any gaps (weekends / holidays)
    sort date
    replace gas_price = gas_price[_n-1] if gas_price == .
    tempfile gas_prices
    save `gas_prices'
restore

merge m:1 date using `gas_prices', keep(master match) nogen

// Forward-fill remaining missing gas prices within panel (if any)
sort bzone_id date
replace gas_price = gas_price[_n-1] if gas_price == . & bzone_id == bzone_id[_n-1]

gen ln_gas_price = ln(gas_price)
label var gas_price    "Natural gas price (EUR/MWh)"
label var ln_gas_price "Log natural gas price"

// =============================================================================
// STATIC SPOT REGRESSION
//
//   ln_energy_price_it = α_i + γ_t
//                      + β_1*(gas_price_t × gas_share_it)
//                      + β_2*gas_share_it
//                      + weather controls
//                      + ε_it
//
//   α_i = bzone FE       (absorbed by xtreg fe)
//   γ_ym = year×month FE  (i.year#i.month; ~108 dummies, controls for common
//                          monthly trends incl. gas price seasonality)
//
//   Full date FEs are avoided: gas_price is common to all bzones on a given
//   day, so i.date would absorb it entirely. Year-month FEs are sufficient
//   and computationally feasible.
//
//   β_1 > 0 means higher-gas-share zones face disproportionately higher prices
//   when gas prices are elevated.
//
//   SE clustered at bzone level.
// =============================================================================

label var gas_share              "Gas share (0--1)"
label var temperature            "Temperature (K)"
label var hdd                    "Heating degree days"
label var cdd                    "Cooling degree days"
label var wind                   "Wind speed (m/s)"
label var ln_sun                 "Log sunshine (ln(sun+1))"
label var precipitation          "Precipitation (mm, daily)"
label var precipitation_weekly   "Precipitation (mm, weekly)"
label var precipitation_monthly  "Precipitation (mm, monthly)"

xtreg ln_energy_price ///
    c.gas_price#c.gas_share gas_share ///
    temperature hdd cdd wind ln_sun precipitation precipitation_weekly precipitation_monthly ///
    i.day_of_week i.year#i.month, ///
    fe vce(cluster bzone_id)
eststo static_price

di "Interaction coef (gas_price × gas_share): " %9.4f _b[c.gas_price#c.gas_share] ///
   "  SE: " %9.4f _se[c.gas_price#c.gas_share]
di "N = " e(N) "  R2_within = " %6.4f e(r2_w)

// =============================================================================
// FWL MARGINAL EFFECTS PLOT
//   Marginal effect of gas_price on ln_energy_price at varying gas_share levels.
//   Since the model is ln_energy_price = β*(gas_price × gas_share) + ...,
//   d(ln_energy_price)/d(gas_price) = β*gas_share, which is linear in gas_share.
//   margins makes this explicit and gives cluster-robust CIs.
// =============================================================================

margins, dydx(gas_price) at(gas_share=(0(0.05)0.50))

marginsplot, ///
    xline(0, lcolor(gray) lpattern(dash)) ///
    ytitle("Marginal effect of gas price on log electricity price") ///
    xtitle("Gas share in energy mix") ///
    title("Gas Price Pass-Through by Gas Dependency") ///
    subtitle("Marginal effect of gas price at varying gas share levels") ///
    note("Based on: xtreg ln_energy_price c.gas_price#c.gas_share gas_share + controls" ///
         "Two-way FE (bzone, year×month). SE clustered at bzone level.", size(vsmall)) ///
    recast(line) recastci(rarea) ///
    ciopts(fcolor(maroon%25) lwidth(none)) ///
    plotopts(lcolor(maroon) lwidth(medthick)) ///
    scheme(s2color)

graph export "outputs/panel/electricity/static/gas_passthrough_by_gasshare.png", ///
    replace width(1400) height(900)

// =============================================================================
// ALSO: LOG-LOG VERSION (semi-elasticity: ln_gas_price × gas_share)
// =============================================================================

xtreg ln_energy_price ///
    c.ln_gas_price#c.gas_share gas_share ///
    temperature hdd cdd wind ln_sun precipitation precipitation_weekly precipitation_monthly ///
    i.day_of_week i.year#i.month, ///
    fe vce(cluster bzone_id)
eststo static_price_log

di "Interaction coef (ln_gas_price × gas_share): " %9.4f _b[c.ln_gas_price#c.gas_share] ///
   "  SE: " %9.4f _se[c.ln_gas_price#c.gas_share]
di "N = " e(N) "  R2_within = " %6.4f e(r2_w)

// =============================================================================
// FWL PARTIAL REGRESSION PLOT
//   By the Frisch-Waugh-Lovell theorem, the OLS coefficient on (ln_gas_price×gas_share)
//   equals the slope from regressing the residuals of ln_energy_price (after
//   partialling out all other regressors) on the residuals of (ln_gas_price×gas_share)
//   (after partialling out all other regressors).
//   The scatter of these two residual vectors is the FWL plot.
// =============================================================================

// Construct the interaction as a plain variable for residualising
gen ln_gas_price_X_share = ln_gas_price * gas_share
label var ln_gas_price_X_share "ln(gas\_price) $\times$ gas\_share"

// Step 1: residualise ln_energy_price on all controls except the interaction
quietly xtreg ln_energy_price gas_share ///
    temperature hdd cdd wind ln_sun precipitation precipitation_weekly precipitation_monthly ///
    i.day_of_week i.year#i.month, ///
    fe
predict double resid_y, e
label var resid_y "Residual: ln(electricity price)"

// Step 2: residualise ln_gas_price_X_share on the same controls
quietly xtreg ln_gas_price_X_share gas_share ///
    temperature hdd cdd wind ln_sun precipitation precipitation_weekly precipitation_monthly ///
    i.day_of_week i.year#i.month, ///
    fe
predict double resid_x, e
label var resid_x "Residual: ln(gas price) $\times$ gas share"

// Step 3: FWL scatter with fitted line
twoway ///
    (scatter resid_y resid_x, mcolor(navy%20) msize(vsmall) msymbol(circle)) ///
    (lfit    resid_y resid_x, lcolor(maroon) lwidth(medthick)), ///
    yline(0, lpattern(dash) lcolor(gray)) ///
    xline(0, lpattern(dash) lcolor(gray)) ///
    xtitle("Residual: ln(gas price) {&times} gas share (after controls)") ///
    ytitle("Residual: log electricity price (after controls)") ///
    title("FWL Partial Regression Plot") ///
    subtitle("Gas price pass-through after partialling out all controls and FEs") ///
    legend(off) ///
    note("Slope = " %6.4f _b[c.ln_gas_price#c.gas_share] ". Two-way FE (bzone, year{&times}month). Controls: weather, day-of-week.", size(vsmall)) ///
    scheme(s2color)

graph export "outputs/panel/electricity/static/fwl_gas_passthrough.png", ///
    replace width(1400) height(900)

drop resid_y resid_x ln_gas_price_X_share

// =============================================================================
// OUTPUT TABLE
// =============================================================================

esttab static_price static_price_log ///
    using "outputs/panel/electricity/static/static_price_gas.tex", ///
    replace booktabs se label ///
    drop(*.year#*.month *.day_of_week) ///
    varlabels(c.gas_price#c.gas_share "Gas price $\times$ Gas share" ///
              c.ln_gas_price#c.gas_share "ln(Gas price) $\times$ Gas share") ///
    title("Static regression: effect of gas price $\times$ gas share on log electricity price") ///
    mtitles("Levels: \$gas\_price \times gas\_share\$" "Log: \$\ln gas\_price \times gas\_share\$") ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    stats(N r2_w, fmt(%9.0f %6.4f) labels("Observations" "Within \$R^2\$")) ///
    note("Two-way FE: bidding zone (\texttt{xtreg fe}) and year$\times$month. SE clustered at bzone level ($N=`n_bzones'$ bidding zones).")

di "Done. Outputs saved to outputs/panel/electricity/static/"
