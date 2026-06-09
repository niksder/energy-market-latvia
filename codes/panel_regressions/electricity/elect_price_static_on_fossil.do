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
// TREATMENT VARIABLE: rolling fossil share (current, not pre-war)
//   fossil_share = sum of all fossil fuel generation shares
// =============================================================================

gen fossil_share = gas_share + brown_coal_share + coal_gas_share + hard_coal_share ///
                 + oil_share + oil_shale_share + peat_share
label var fossil_share "Fossil share (0--1)"

// =============================================================================
// STATIC SPOT REGRESSION
//
//   ln_energy_price_it = α_i + γ_ym
//                      + β_1*(gas_price_t × fossil_share_it)
//                      + β_2*fossil_share_it
//                      + weather controls
//                      + ε_it
//
//   α_i  = bzone FE       (absorbed by xtreg fe)
//   γ_ym = year×month FE  (i.year#i.month; ~108 dummies, controls for common
//                          monthly trends incl. gas price seasonality)
//
//   Full date FEs are avoided: gas_price is common to all bzones on a given
//   day, so i.date would absorb it entirely. Year-month FEs are sufficient
//   and computationally feasible.
//
//   β_1 > 0 means higher-fossil-share zones face disproportionately higher
//   prices when gas prices are elevated.
//
//   SE clustered at bzone level.
// =============================================================================

label var temperature            "Temperature (K)"
label var hdd                    "Heating degree days"
label var cdd                    "Cooling degree days"
label var wind                   "Wind speed (m/s)"
label var ln_sun                 "Log sunshine (ln(sun+1))"
label var precipitation          "Precipitation (mm, daily)"
label var precipitation_weekly   "Precipitation (mm, weekly)"
label var precipitation_monthly  "Precipitation (mm, monthly)"

xtreg ln_energy_price ///
    c.gas_price#c.fossil_share fossil_share ///
    temperature hdd cdd wind ln_sun precipitation precipitation_weekly precipitation_monthly ///
    i.day_of_week i.year#i.month, ///
    fe vce(cluster bzone_id)
eststo static_price

di "Interaction coef (gas_price × fossil_share): " %9.4f _b[c.gas_price#c.fossil_share] ///
   "  SE: " %9.4f _se[c.gas_price#c.fossil_share]
di "N = " e(N) "  R2_within = " %6.4f e(r2_within)

// =============================================================================
// FWL MARGINAL EFFECTS PLOT
//   Marginal effect of gas_price on ln_energy_price at varying fossil_share levels.
//   Since the model is ln_energy_price = β*(gas_price × fossil_share) + ...,
//   d(ln_energy_price)/d(gas_price) = β*fossil_share, which is linear in fossil_share.
//   margins makes this explicit and gives cluster-robust CIs.
// =============================================================================

margins, dydx(gas_price) at(fossil_share=(0(0.05)0.50))

marginsplot, ///
    xline(0, lcolor(gray) lpattern(dash)) ///
    ytitle("Marginal effect of gas price on log electricity price") ///
    xtitle("Fossil share in energy mix") ///
    title("Gas Price Pass-Through by Fossil Dependency") ///
    subtitle("Marginal effect of gas price at varying fossil share levels") ///
    note("Based on: xtreg ln_energy_price c.gas_price#c.fossil_share fossil_share + controls" ///
         "Two-way FE (bzone, year×month). SE clustered at bzone level.", size(vsmall)) ///
    recast(line) recastci(rarea) ///
    ciopts(fcolor(maroon%25) lwidth(none)) ///
    plotopts(lcolor(maroon) lwidth(medthick)) ///
    scheme(s2color)

graph export "outputs/panel/electricity/static/gas_passthrough_by_fossilshare.png", ///
    replace width(1400) height(900)

// =============================================================================
// FWL PARTIAL REGRESSION PLOT
//   By the Frisch-Waugh-Lovell theorem, the OLS coefficient on (gas_price×fossil_share)
//   equals the slope from regressing the residuals of ln_energy_price (after
//   partialling out all other regressors) on the residuals of (gas_price×fossil_share)
//   (after partialling out all other regressors).
//   The scatter of these two residual vectors is the FWL plot.
// =============================================================================

// Construct the interaction as a plain variable for residualising
gen gas_price_X_fossil = gas_price * fossil_share
label var gas_price_X_fossil "gas\_price $\times$ fossil\_share"

// Step 1: residualise ln_energy_price on all controls except the interaction
quietly xtreg ln_energy_price fossil_share ///
    temperature hdd cdd wind ln_sun precipitation precipitation_weekly precipitation_monthly ///
    i.day_of_week i.year#i.month, ///
    fe
predict double resid_y, e
label var resid_y "Residual: ln(electricity price)"

// Step 2: residualise gas_price_X_fossil on the same controls
quietly xtreg gas_price_X_fossil fossil_share ///
    temperature hdd cdd wind ln_sun precipitation precipitation_weekly precipitation_monthly ///
    i.day_of_week i.year#i.month, ///
    fe
predict double resid_x, e
label var resid_x "Residual: gas price $\times$ fossil share"

// Step 3: FWL scatter with fitted line
twoway ///
    (scatter resid_y resid_x, mcolor(navy%20) msize(vsmall) msymbol(circle)) ///
    (lfit    resid_y resid_x, lcolor(maroon) lwidth(medthick)), ///
    yline(0, lpattern(dash) lcolor(gray)) ///
    xline(0, lpattern(dash) lcolor(gray)) ///
    xtitle("Residual: gas price {&times} fossil share (after controls)") ///
    ytitle("Residual: log electricity price (after controls)") ///
    title("FWL Partial Regression Plot") ///
    subtitle("Gas price pass-through after partialling out all controls and FEs") ///
    legend(off) ///
    note("Slope = " %6.4f _b[c.gas_price#c.fossil_share] ". Two-way FE (bzone, year{&times}month). Controls: weather, day-of-week.", size(vsmall)) ///
    scheme(s2color)

graph export "outputs/panel/electricity/static/fwl_gas_passthrough_fossil.png", ///
    replace width(1400) height(900)

drop resid_y resid_x gas_price_X_fossil

// =============================================================================
// ALSO: LOG-LOG VERSION (semi-elasticity: ln_gas_price × fossil_share)
// =============================================================================

xtreg ln_energy_price ///
    c.ln_gas_price#c.fossil_share fossil_share ///
    temperature hdd cdd wind ln_sun precipitation precipitation_weekly precipitation_monthly ///
    i.day_of_week i.year#i.month, ///
    fe vce(cluster bzone_id)
eststo static_price_log

di "Interaction coef (ln_gas_price × fossil_share): " %9.4f _b[c.ln_gas_price#c.fossil_share] ///
   "  SE: " %9.4f _se[c.ln_gas_price#c.fossil_share]
di "N = " e(N) "  R2_within = " %6.4f e(r2_within)

// =============================================================================
// OUTPUT TABLE
// =============================================================================

esttab static_price static_price_log ///
    using "outputs/panel/electricity/static/static_price_gas_on_fossil.tex", ///
    replace booktabs se label ///
    drop(*.year#*.month *.day_of_week) ///
    varlabels(c.gas_price#c.fossil_share "Gas price $\times$ Fossil share" ///
              c.ln_gas_price#c.fossil_share "ln(Gas price) $\times$ Fossil share") ///
    title("Static regression: effect of gas price $\times$ fossil share on log electricity price") ///
    mtitles("Levels: \$gas\_price \times fossil\_share\$" "Log: \$\ln gas\_price \times fossil\_share\$") ///
    star(* 0.10 ** 0.05 *** 0.01) ///
    stats(N r2_within, fmt(%9.0f %6.4f) labels("Observations" "Within \$R^2\$")) ///
    note("Two-way FE: bidding zone (\texttt{xtreg fe}) and year$\times$month. SE clustered at bzone level ($N=`n_bzones'$ bidding zones).")

di "Done. Outputs saved to outputs/panel/electricity/static/"
