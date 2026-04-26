cls
clear

cd "/home/niks/Projects/solar-power-latvia"
do "codes/load_daily_data.do"

// Create daily_gas_lp_asymmetric directory ONLY if it doesn't exist
cap mkdir "outputs/daily_gas_lp_asymmetric"

local H = 14   // 2 weeks

// Split gas shock into positive and negative components
gen gas_resid_pos = max(0, gas_resid_daily)
gen gas_resid_neg = min(0, gas_resid_daily) * (-1)  // Negate to make it positive for easier interpretation

tempname results
postfile `results' h beta_pos se_pos beta_neg se_neg pval_sym using irf_lp, replace

/***********************************************************
************ LOCAL PROJECTIONS FOR GAS SHOCK ****************
* Separate positive and negative shocks to test asymmetry  *
* ("rockets and feathers" hypothesis).                     *
* Symmetry test H0: beta_pos = beta_neg at each horizon.   *
************************************************************/

forvalues h = 0/`H' {

    regress F`h'.d_ln_energy_price ///
        gas_resid_pos gas_resid_neg ///
        L(1/7).d_ln_energy_price ///
        L(1/7).gas_resid_pos L(1/7).gas_resid_neg ///
        temperature hdd cdd wind ln_sun sun_x_solar_capacity ln_water_storage precipitation precipitation_weekly precipitation_monthly ///
        i.day_of_week i.month, vce(robust)

    test gas_resid_pos = gas_resid_neg
    post `results' (`h') (_b[gas_resid_pos]) (_se[gas_resid_pos]) (_b[gas_resid_neg]) (_se[gas_resid_neg]) (r(p))
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
* Overlay positive and negative IRFs for comparison.       *
* effect_neg_comp = beta_neg * 0.10 is the "implied"        *
* positive response from a -10% shock; equals effect_pos   *
* under symmetry.                                          *
************************************************************/

use irf_lp, clear

// Positive shock: response to a +10% gas price shock
gen effect_pos       = beta_pos * 0.10
gen upper_pos        = (beta_pos + 1.96*se_pos) * 0.10
gen lower_pos        = (beta_pos - 1.96*se_pos) * 0.10

// Negative shock: negate the -10% response so it is on the same scale
// (i.e. the "implied" positive response from negative shocks)
gen effect_neg_comp  = beta_neg * 0.10
gen upper_neg_comp   = (beta_neg + 1.96*se_neg) * 0.10
gen lower_neg_comp   = (beta_neg - 1.96*se_neg) * 0.10

twoway ///
    (rarea upper_pos lower_pos h, color(navy%15) lwidth(none)) ///
    (line effect_pos h, lwidth(medthick) lcolor(navy)) ///
    (rarea upper_neg_comp lower_neg_comp h, color(maroon%15) lwidth(none)) ///
    (line effect_neg_comp h, lwidth(medthick) lcolor(maroon) lpattern(dash)), ///
    yline(0) ///
    legend(order(2 "+10% shock (β+)" 4 "−10% shock (β−)")) ///
    xtitle("Days after gas shock") ///
    ytitle("Response of electricity price") ///
    title("Asymmetric gas shock IRFs")

graph export "outputs/daily_gas_lp_asymmetric/daily_irf_gas_shock_asymmetric.png", replace

// Cumulative responses
gen cum_pos       = sum(effect_pos)
gen cum_pos_upper = sum(upper_pos)
gen cum_pos_lower = sum(lower_pos)

gen cum_neg_comp       = sum(effect_neg_comp)
gen cum_neg_upper_comp = sum(upper_neg_comp)
gen cum_neg_lower_comp = sum(lower_neg_comp)

twoway ///
    (rarea cum_pos_upper cum_pos_lower h, color(navy%15) lwidth(none)) ///
    (line cum_pos h, lwidth(medthick) lcolor(navy)) ///
    (rarea cum_neg_upper_comp cum_neg_lower_comp h, color(maroon%15) lwidth(none)) ///
    (line cum_neg_comp h, lwidth(medthick) lcolor(maroon) lpattern(dash)), ///
    yline(0) ///
    legend(order(2 "+10% shock (β+)" 4 "−10% shock (β−)")) ///
    xtitle("Days after gas shock") ///
    ytitle("Cumulative response of electricity price")

graph export "outputs/daily_gas_lp_asymmetric/daily_cumulative_irf_gas_shock_asymmetric.png", replace

// Symmetry test p-values across horizons
twoway ///
    (line pval_sym h, lwidth(medthick)) ///
    (function y=0.05, range(0 14) lpattern(dash) lcolor(red)), ///
    xtitle("Horizon (days)") ///
    ytitle("p-value (H0: β+ = β−)") ///
    title("Symmetry test across horizons") ///
    legend(order(1 "p-value" 2 "5% threshold"))

graph export "outputs/daily_gas_lp_asymmetric/daily_symmetry_test.png", replace

/***********************************************************************************
************ PLOT THE IRF OF THE INVASION SHOCK FOR 2 DAYS OF SHOCK ****************
************************************************************************************/

// Residuals can be positive or negative: route to beta_pos (for r>0) or beta_neg (for r<0).
// gas_resid_neg is coded as |r| for negative shocks, so its coefficient beta_neg gives
// the response per unit of negative-shock magnitude. The effect on electricity price is:
//   r > 0:  r   * beta_pos   (positive gas shock → positive/negative elec response)
//   r < 0: |r|  * beta_neg   (negative gas shock → response via beta_neg)
gen war_effect = .
gen war_upper  = .
gen war_lower  = .

forvalues h = 0/`H' {
    local idx = `h' + 1

    * contribution from Feb 24 shock
    if `shock_resid' >= 0 {
        replace war_effect = `shock_resid' * beta_pos[`idx']                                        if h == `h'
        replace war_upper  = `shock_resid' * (beta_pos[`idx'] + 1.96*se_pos[`idx'])                 if h == `h'
        replace war_lower  = `shock_resid' * (beta_pos[`idx'] - 1.96*se_pos[`idx'])                 if h == `h'
    }
    else {
        local abs_shock = -(`shock_resid')
        replace war_effect = `abs_shock' * beta_neg[`idx']                                          if h == `h'
        replace war_upper  = `abs_shock' * (beta_neg[`idx'] + 1.96*se_neg[`idx'])                   if h == `h'
        replace war_lower  = `abs_shock' * (beta_neg[`idx'] - 1.96*se_neg[`idx'])                   if h == `h'
    }

    * add Feb 25 contribution (only if h >= 1)
    if `h' > 0 {
        local prev_idx = `h'
        if `next_resid' >= 0 {
            replace war_effect = war_effect + `next_resid' * beta_pos[`prev_idx']                                       if h == `h'
            replace war_upper  = war_upper  + `next_resid' * (beta_pos[`prev_idx'] + 1.96*se_pos[`prev_idx'])           if h == `h'
            replace war_lower  = war_lower  + `next_resid' * (beta_pos[`prev_idx'] - 1.96*se_pos[`prev_idx'])           if h == `h'
        }
        else {
            local abs_next = -(`next_resid')
            replace war_effect = war_effect + `abs_next' * beta_neg[`prev_idx']                                         if h == `h'
            replace war_upper  = war_upper  + `abs_next' * (beta_neg[`prev_idx'] + 1.96*se_neg[`prev_idx'])             if h == `h'
            replace war_lower  = war_lower  + `abs_next' * (beta_neg[`prev_idx'] - 1.96*se_neg[`prev_idx'])             if h == `h'
        }
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
graph export "outputs/daily_gas_lp_asymmetric/daily_irf_invasion_shock_asymmetric.png", replace

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
graph export "outputs/daily_gas_lp_asymmetric/daily_cumulative_irf_invasion_shock_asymmetric.png", replace

/***********************************************************************************
************ PLOT THE IRF OF THE INVASION SHOCK FOR 2 WEEK INVASION WINDOW *********
************************************************************************************/


gen invasion_effect = 0
gen invasion_upper  = 0
gen invasion_lower  = 0

// Route each daily residual through beta_pos (r>0) or beta_neg (r<0)
forvalues h = 0/`H' {
    forvalues k = 0/`h' {
        local r = `inv_resid_`k''
        local idx = `h' - `k' + 1
        if `r' >= 0 {
            replace invasion_effect = invasion_effect + `r' * beta_pos[`idx']                              if h == `h'
            replace invasion_upper  = invasion_upper  + `r' * (beta_pos[`idx'] + 1.96*se_pos[`idx'])       if h == `h'
            replace invasion_lower  = invasion_lower  + `r' * (beta_pos[`idx'] - 1.96*se_pos[`idx'])       if h == `h'
        }
        else {
            local abs_r = -(`r')
            replace invasion_effect = invasion_effect + `abs_r' * beta_neg[`idx']                          if h == `h'
            replace invasion_upper  = invasion_upper  + `abs_r' * (beta_neg[`idx'] + 1.96*se_neg[`idx'])   if h == `h'
            replace invasion_lower  = invasion_lower  + `abs_r' * (beta_neg[`idx'] - 1.96*se_neg[`idx'])   if h == `h'
        }
    }
}

twoway ///
    (line invasion_effect h, lwidth(medthick)) ///
    (line invasion_upper h, lpattern(dash) lcolor(red)) ///
    (line invasion_lower h, lpattern(dash) lcolor(gray)), ///
    yline(0) ///
    xtitle("Days after invasion start") ///
    ytitle("Effect on electricity price (full invasion window)")

graph export "outputs/daily_gas_lp_asymmetric/daily_irf_invasion_full_asymmetric.png", replace

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

graph export "outputs/daily_gas_lp_asymmetric/daily_cumulative_irf_invasion_full_asymmetric.png", replace
