cls
clear

cd "/home/niks/Projects/solar-power-latvia"
do "codes/load_daily_data.do"

// Create daily_energy_price_lp_symmetric directory ONLY if it doesn't exist
cap mkdir "outputs/daily_energy_price_lp_symmetric"

local H = 14   // 2 weeks

tempname results
postfile `results' h beta se using irf_lp, replace

/***********************************************************
************ LOCAL PROJECTIONS FOR GAS SHOCK ****************
************************************************************/

/* gen shock_smooth = (gas_resid_daily + L1.gas_resid_daily)/2
replace gas_resid_daily = shock_smooth */

forvalues h = 0/`H' {

    regress F`h'.d_ln_energy_price ///
        gas_resid_daily ///
        L(1/7).d_ln_energy_price ///
        L(1/7).gas_resid_daily ///
        temperature hdd cdd wind ln_sun sun_x_solar_capacity ln_water_storage precipitation precipitation_weekly precipitation_monthly ///
        i.day_of_week i.month, vce(robust)

    post `results' (`h') (_b[gas_resid_daily]) (_se[gas_resid_daily])
}

postclose `results'

/***********************************************************
************ EXTRACT SHOCK AROUND INVASION START ****************
************************************************************/

// Extract shock residuals while the original dataset is still loaded
local shock_date    = td(24feb2022)
local next_date     = td(25feb2022)
local invasion_start = td(24feb2022)

summarize gas_resid_daily if date == `shock_date', meanonly
local shock_resid = r(mean)

summarize gas_resid_daily if date == `next_date', meanonly
local next_resid = r(mean)

forvalues k = 0/`H' {
    local d = `invasion_start' + `k'
    summarize gas_resid_daily if date == `d', meanonly
    local inv_resid_`k' = r(mean)
}

/************************************************************
************ PLOT THE IRF OF A 10% GAS SHOCK ****************
************************************************************/

use irf_lp, clear

replace beta = beta * 0.10
gen upper = beta + 1.96*(se * 0.10)
gen lower = beta - 1.96*(se * 0.10)

twoway ///
    (line beta h, lwidth(medthick)) ///
    (line upper h, lpattern(dash) lcolor(red)) ///
    (line lower h, lpattern(dash) lcolor(gray)), ///
    yline(0) ///
    xtitle("Days after gas shock") ///
    ytitle("Response of electricity price")

// Save the plot
graph export "outputs/daily_energy_price_lp_symmetric/daily_irf_gas_shock.png", replace

// Plot the cumulative response

gen cum_beta  = sum(beta)
gen cum_upper = sum(upper)
gen cum_lower = sum(lower)

twoway ///
    (line cum_beta h, lwidth(medthick)) ///
    (line cum_upper h, lpattern(dash) lcolor(red)) ///
    (line cum_lower h, lpattern(dash) lcolor(gray)), ///
    yline(0) ///
    xtitle("Days after gas shock") ///
    ytitle("Cumulative response of electricity price")

// Save the plot
graph export "outputs/daily_energy_price_lp_symmetric/daily_cumulative_irf_gas_shock.png", replace


replace beta = beta * (1 / 0.10)
replace upper = beta + 1.96*se
replace lower = beta - 1.96*se

/***********************************************************************************
************ PLOT THE IRF OF THE INVASION SHOCK FOR 2 DAYS OF SHOCK ****************
************************************************************************************/

gen war_effect = .
gen war_upper = .
gen war_lower = .

forvalues h = 0/`H' {
    local idx = `h' + 1

    * contribution from Feb 24 shock
    replace war_effect = `shock_resid' * beta[`idx'] if h == `h'
    replace war_upper  = cond(`shock_resid' >= 0, `shock_resid' * upper[`idx'], `shock_resid' * lower[`idx']) if h == `h'
    replace war_lower  = cond(`shock_resid' >= 0, `shock_resid' * lower[`idx'], `shock_resid' * upper[`idx']) if h == `h'

    * add Feb 25 contribution (only if h >= 1)
    if `h' > 0 {
        local prev_idx = `h'
        replace war_effect = war_effect + `next_resid' * beta[`prev_idx']                                                                if h == `h'
        replace war_upper  = war_upper  + cond(`next_resid' >= 0, `next_resid' * upper[`prev_idx'], `next_resid' * lower[`prev_idx'])    if h == `h'
        replace war_lower  = war_lower  + cond(`next_resid' >= 0, `next_resid' * lower[`prev_idx'], `next_resid' * upper[`prev_idx'])    if h == `h'
    }
}

twoway ///
    (line war_effect h, lwidth(medthick)) ///
    (line war_upper h, lpattern(dash) lcolor(red)) ///
    (line war_lower h, lpattern(dash) lcolor(gray)), ///
    yline(0) ///
    xtitle("Days after invasion shock") ///
    ytitle("Effect on electricity price")

// Save the plot
graph export "outputs/daily_energy_price_lp_symmetric/daily_irf_invasion_shock.png", replace

gen cum_war  = sum(war_effect)
gen cum_war_u = sum(war_upper)
gen cum_war_l = sum(war_lower)

twoway ///
    (line cum_war h, lwidth(medthick)) ///
    (line cum_war_u h, lpattern(dash) lcolor(red)) ///
    (line cum_war_l h, lpattern(dash) lcolor(gray)), ///
    yline(0) ///
    xtitle("Days after invasion shock") ///
    ytitle("Cumulative effect on electricity price")

// Save the plot
graph export "outputs/daily_energy_price_lp_symmetric/daily_cumulative_irf_invasion_shock.png", replace

/***********************************************************************************
************ PLOT THE IRF OF THE INVASION SHOCK FOR 2 WEEK INVASION WINDOW *********
************************************************************************************/


gen invasion_effect = 0
gen invasion_upper  = 0
gen invasion_lower  = 0

forvalues h = 0/`H' {
    forvalues k = 0/`h' {
        local r = `inv_resid_`k''
        local idx = `h' - `k' + 1
        replace invasion_effect = invasion_effect + `r' * beta[`idx'] if h == `h'
        replace invasion_upper  = invasion_upper  + cond(`r' >= 0, `r' * upper[`idx'], `r' * lower[`idx']) if h == `h'
        replace invasion_lower  = invasion_lower  + cond(`r' >= 0, `r' * lower[`idx'], `r' * upper[`idx']) if h == `h'
    }
}

twoway ///
    (line invasion_effect h, lwidth(medthick)) ///
    (line invasion_upper h, lpattern(dash) lcolor(red)) ///
    (line invasion_lower h, lpattern(dash) lcolor(gray)), ///
    yline(0) ///
    xtitle("Days after invasion start") ///
    ytitle("Effect on electricity price (full invasion window)")

graph export "outputs/daily_energy_price_lp_symmetric/daily_irf_invasion_full.png", replace

gen cum_invasion   = sum(invasion_effect)
gen cum_invasion_u = sum(invasion_upper)
gen cum_invasion_l = sum(invasion_lower)

twoway ///
    (line cum_invasion h, lwidth(medthick)) ///
    (line cum_invasion_u h, lpattern(dash) lcolor(red)) ///
    (line cum_invasion_l h, lpattern(dash) lcolor(gray)), ///
    yline(0) ///
    xtitle("Days after invasion start") ///
    ytitle("Cumulative effect on electricity price (full invasion window)")

graph export "outputs/daily_energy_price_lp_symmetric/daily_cumulative_irf_invasion_full.png", replace
