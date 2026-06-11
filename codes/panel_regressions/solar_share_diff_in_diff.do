cls
clear

cd "/home/niks/Projects/solar-power-latvia"
do "codes/panel_regressions/load_daily_data.do"

// Drop NL, GR, HU, PT, ES that have higher gas share than LV
drop if bzone == "Netherlands" | bzone == "Greece" | bzone == "Hungary" | bzone == "Portugal" | bzone == "Spain" 
drop if bzone == "Switzerland" // Drop Switzerland since it is not EU


// Drop Italy (IT_NORTH IT_CNOR IT_CSUD IT_SUD IT_CALA IT_SICI IT_SARD IT_SACOAC IT_SACODC) because of granularity of zones
drop if bzone == "IT_NORTH" | bzone == "IT_CNOR" | bzone == "IT_CSUD" | bzone == "IT_SUD" | bzone == "IT_CALA" | bzone == "IT_SICI" | bzone == "IT_SARD" | bzone == "IT_SACOAC" | bzone == "IT_SACODC"
// drop if bzone == "Ireland"
// drop if bzone == "Cyprus" // Drop Cyprus since it misses data from 2023 and 2024 and elsewhere

// Count bzones dynamically
quietly levelsof bzone_id, local(_bzone_list)
local n_bzones : word count `_bzone_list'
di "Number of bzones in data: `n_bzones'"

cap mkdir "outputs/panel/solar_diff_and_diff"

// =============================================================================
// TREATMENT VARIABLE: pre-war gas share (Feb 23 2022, last day before invasion)
// gas_share is available from load_daily_data.do
// =============================================================================

// Pre-war gas share: value on Feb 23 2021 (fixed treatment intensity per bzone)
gen _tmp = gas_share if date == td(23feb2021)
bysort bzone_id: egen gas_share_pre = max(_tmp)
drop _tmp
label var gas_share_pre "Gas share on Feb 23 2021 (pre-war, 0–1)"

// Pre-war solar share: value on Feb 23 2021 (baseline solar penetration per bzone)
gen _tmp2 = solar_share if date == td(23feb2021)
bysort bzone_id: egen solar_share_pre = max(_tmp2)
drop _tmp2
label var solar_share_pre "Solar share on Feb 23 2021 (pre-war baseline, 0–1)"

// Pre-war other-fossil share: brown coal + coal gas + hard coal + oil + oil shale + peat
gen _tmp3 = brown_coal_share + coal_gas_share + hard_coal_share + oil_share + oil_shale_share + peat_share if date == td(23feb2021)
bysort bzone_id: egen other_fossil_share_pre = max(_tmp3)
drop _tmp3
label var other_fossil_share_pre "Non-gas fossil share on Feb 23 2021 (pre-war, 0–1)"

// Pre-war population density (log, to handle skew)
gen _tmp4 = population_density if date == td(23feb2021)
bysort bzone_id: egen pop_density_pre = max(_tmp4)
drop _tmp4
gen ln_pop_density_pre = ln(pop_density_pre)
label var ln_pop_density_pre "Log population density on Feb 23 2021 (pre-war)"

// Verify treatment values
di "Pre-war gas share by bzone:"
table bzone, statistic(mean gas_share_pre)
di "Pre-war solar share by bzone:"
table bzone, statistic(mean solar_share_pre)
di "Pre-war other fossil share by bzone:"
table bzone, statistic(mean other_fossil_share_pre)
di "Pre-war log population density by bzone:"
table bzone, statistic(mean ln_pop_density_pre)

// =============================================================================
// EVENT STUDY
//   Y_it = α_i + γ_t + Σ_k β_k*(gas_share_pre_i × 1[hy_seq=k]) + weather + ε_it
//
//   Reference period: H2 2020 (hy_seq_pos = 8)
//   β_k ≈ 0 for pre-war periods → parallel trends
//   β_k > 0 for post-war periods → high-gas bzones grew solar more
//
//   Period mapping (hy_seq = (year-2021)*2 + semester - 2):
//     hy_seq: -9=H1 2017, ..., -2=H2 2020 (ref), -1=H1 2021, 0=H2 2021,
//              1=H1 2022, 2=H2 2022, 3=H1 2023, ..., 8=H2 2025
//   hy_seq_pos = hy_seq + 10  (Stata factor variables must be non-negative)
//     hy_seq_pos: 1=H1 2017, ..., 8=H2 2020 (ref), 9=H1 2021, 10=H2 2021, ...
// =============================================================================

gen semester  = cond(month <= 6, 1, 2)
gen hy_seq    = (year - 2021) * 2 + semester - 2
gen hy_seq_pos = hy_seq + 10          // shift so all values are non-negative
label var hy_seq_pos "Half-year (8 = H2 2020, reference period)"

qui levelsof hy_seq_pos, local(hy_pos_vals)
di "Half-year periods in data (shifted): `hy_pos_vals'"

// Create interaction dummies manually.
// Using factor variable notation (c.gas_share_pre#ib10.hy_seq_pos) causes
// Stata to pair the FE and interaction omissions: when it drops one period FE
// as redundant after within-transformation, it also drops the matching
// interaction — even if that interaction is estimable. By creating the
// interactions as plain variables, Stata sees them as standalone continuous
// regressors and applies collinearity detection independently of the period FE.
foreach k of local hy_pos_vals {
    if `k' != 8 {
        gen inter_hy`k' = gas_share_pre * (hy_seq_pos == `k')
        label var inter_hy`k' "gas_share_pre × (hy_seq_pos==`k')"
        gen ctrl_hy`k' = other_fossil_share_pre * (hy_seq_pos == `k')
        label var ctrl_hy`k' "other_fossil_share_pre × (hy_seq_pos==`k')"
        gen ctrl2_hy`k' = ln_pop_density_pre * (hy_seq_pos == `k')
        label var ctrl2_hy`k' "ln_pop_density_pre × (hy_seq_pos==`k')"
    }
}

local inter_vars ""
local ctrl_vars ""
local ctrl2_vars ""
foreach k of local hy_pos_vals {
    if `k' != 8 {
        local inter_vars "`inter_vars' inter_hy`k'"
        local ctrl_vars  "`ctrl_vars'  ctrl_hy`k'"
        local ctrl2_vars "`ctrl2_vars' ctrl2_hy`k'"
    }
}

// Two-way FE: bzone absorbed by xtreg fe, period absorbed by ib8.hy_seq_pos.
// ib8 sets H2 2020 as the omitted base for both FE and interactions.
xtreg solar_share `inter_vars' `ctrl_vars' `ctrl2_vars' /*solar_share_pre*/ ///
    /*i.day_of_week*/ i.month ib8.hy_seq_pos, ///
    fe vce(cluster bzone_id)
eststo event_solar
scalar _ev_N   = e(N)
scalar _ev_r2w = e(r2_w)

/*     temperature hdd cdd wind ln_sun precipitation precipitation_weekly precipitation_monthly /// // excluded since weather does not affect solar growth */

// =============================================================================
// EVENT STUDY PLOT
// =============================================================================

local nper : word count `hy_pos_vals'
local i = 1
foreach k of local hy_pos_vals {
    if `k' == 8 {
        scalar _es_period_`i' = `k' - 8
        scalar _es_coef_`i'   = 0
        scalar _es_lb_`i'     = 0
        scalar _es_ub_`i'     = 0
        // scalar _es_lb90_`i'   = 0
        // scalar _es_ub90_`i'   = 0
        scalar _es_wse_`i'    = 0
        scalar _es_wp_`i'     = .
        scalar _ct_coef_`i'   = 0
        scalar _ct_wse_`i'    = 0
        scalar _ct_wp_`i'     = .
        scalar _c2_coef_`i'   = 0
        scalar _c2_wse_`i'    = 0
        scalar _c2_wp_`i'     = .
    }
    else {
        scalar _es_period_`i' = `k' - 8
        scalar _es_coef_`i'   = _b[inter_hy`k']
        // Wild cluster bootstrap CIs (Roodman et al.; same seed → reproducible)
        quietly boottest inter_hy`k', boottype(wild) cluster(bzone_id) reps(9999) seed(42) level(95) // Wild cluster bootstrap for robust inference with few clusters
        scalar _es_lb_`i'     = r(CI)[1,1]
        scalar _es_ub_`i'     = r(CI)[1,2]
        scalar _es_wse_`i'    = (r(CI)[1,2] - r(CI)[1,1]) / (2 * invnormal(0.975))
        scalar _es_wp_`i'     = r(p)
        // quietly boottest inter_hy`k', boottype(wild) cluster(bzone_id) reps(9999) seed(42) level(90)
        // scalar _es_lb90_`i'   = r(CI)[1,1]
        // scalar _es_ub90_`i'   = r(CI)[1,2]
        // other-fossil control
        scalar _ct_coef_`i'   = _b[ctrl_hy`k']
        quietly boottest ctrl_hy`k', boottype(wild) cluster(bzone_id) reps(9999) seed(42) level(95)
        scalar _ct_wse_`i'    = (r(CI)[1,2] - r(CI)[1,1]) / (2 * invnormal(0.975))
        scalar _ct_wp_`i'     = r(p)
        // population density control
        scalar _c2_coef_`i'   = _b[ctrl2_hy`k']
        quietly boottest ctrl2_hy`k', boottype(wild) cluster(bzone_id) reps(9999) seed(42) level(95)
        scalar _c2_wse_`i'    = (r(CI)[1,2] - r(CI)[1,1]) / (2 * invnormal(0.975))
        scalar _c2_wp_`i'     = r(p)
    }
    local i = `i' + 1
}

// Extract Latvia's pre-war gas share (scalar survives preserve/restore)
quietly summarize gas_share_pre if bzone == "Latvia"
scalar lv_gas_share_pre = r(mean)
di "Latvia pre-war gas share (pp): " %5.2f lv_gas_share_pre

preserve
    clear
    set obs `nper'
    gen period = .
    gen coef   = .
    gen lb95   = .
    gen ub95   = .
    // gen lb90   = .
    // gen ub90   = .

    forvalues i = 1/`nper' {
        replace period = _es_period_`i' in `i'
        replace coef   = _es_coef_`i'   in `i'
        replace lb95   = _es_lb_`i'     in `i'
        replace ub95   = _es_ub_`i'     in `i'
        // replace lb90   = _es_lb90_`i'   in `i'
        // replace ub90   = _es_ub90_`i'   in `i'
    }

    sort period

    twoway ///
        (rcap lb95 ub95 period, lcolor(navy%30)) ///
        /* (rcap lb90 ub90 period, lcolor(navy%55)) */ ///
        (connected coef period, ///
            mcolor(navy) lcolor(navy) msymbol(circle) lpattern(solid)), ///
        yline(0, lpattern(dash) lcolor(gray)) ///
        xline(2.5, lpattern(dash) lcolor(red) lwidth(medthick)) ///
        xlabel( ///
            -7 "H1 2017" -6 "H2 2017" -5 "H1 2018" -4 "H2 2018" ///
            -3 "H1 2019" -2 "H2 2019" -1 "H1 2020"  0 "H2 2020" ///
             1 "H1 2021"  2 "H2 2021"  3 "H1 2022"  4 "H2 2022" ///
             5 "H1 2023"  6 "H2 2023"  7 "H1 2024"  8 "H2 2024" ///
             9 "H1 2025" 10 "H2 2025", ///
            angle(45) labsize(small)) ///
        legend(off) ///
        xtitle("Half-year period") ///
        ytitle("Coef (% per pp of pre-war gas share)") ///
        title("Effect of Pre-War Gas Exposure on Solar Share") ///
        subtitle("DiD event study; reference = H2 2020; red line = invasion Feb 24 2022") ///
        note("Two-way FE (bidding zone and semester). Controls: month for seasonality." ///
             "Wild cluster bootstrapping used for SE at bidding-zone level (N = `n_bzones' bidding zones)." ///
             "95% confidence intervals reported.", size(vsmall)) ///
        scheme(s2color)

    graph export "outputs/panel/solar_diff_and_diff/event_study_solar_share.png", ///
        replace width(1400) height(900)
    // -------------------------------------------------------------------------
    // LATVIA-SPECIFIC EFFECT: coef × Latvia's pre-war gas share
    // Interpretation: extra pp of solar share Latvia gained (vs. counterfactual
    // of zero gas dependence) relative to the H2 2020 reference period.
    // -------------------------------------------------------------------------
    local lv_gas = scalar(lv_gas_share_pre)
    local lv_gas_fmt : di %5.1f `lv_gas'

    forvalues i = 1/`nper' {
        replace coef = _es_coef_`i'   * `lv_gas' in `i'
        replace lb95 = _es_lb_`i'    * `lv_gas' in `i'
        replace ub95 = _es_ub_`i'    * `lv_gas' in `i'
        // replace lb90 = _es_lb90_`i'  * `lv_gas' in `i'
        // replace ub90 = _es_ub90_`i'  * `lv_gas' in `i'
    }

    twoway ///
        (rcap lb95 ub95 period, lcolor(maroon%30)) ///
        /* (rcap lb90 ub90 period, lcolor(maroon%55)) */ ///
        (connected coef period, ///
            mcolor(maroon) lcolor(maroon) msymbol(circle) lpattern(solid)), ///
        yline(0, lpattern(dash) lcolor(gray)) ///
        xline(2.5, lpattern(dash) lcolor(red) lwidth(medthick)) ///
        xlabel( ///
            -7 "H1 2017" -6 "H2 2017" -5 "H1 2018" -4 "H2 2018" ///
            -3 "H1 2019" -2 "H2 2019" -1 "H1 2020"  0 "H2 2020" ///
             1 "H1 2021"  2 "H2 2021"  3 "H1 2022"  4 "H2 2022" ///
             5 "H1 2023"  6 "H2 2023"  7 "H1 2024"  8 "H2 2024" ///
             9 "H1 2025" 10 "H2 2025", ///
            angle(45) labsize(small)) ///
        legend(off) ///
        xtitle("Half-year period") ///
        ytitle("Extra solar share (pp) vs. zero-gas-dependence counterfactual") ///
        title("Latvia: solar share attributable to pre-war gas dependence") ///
        subtitle("DiD coefs × Latvia gas share (`lv_gas_fmt' pp); reference = H2 2020; red line = invasion Feb 24 2022") ///
        note("Each point = estimated extra pp of solar share Latvia gained relative to a country with no pre-war gas dependence." ///
             "Two-way FE (bidding zone and semester). Wild cluster bootstrapping used for SE at bidding-zone level (N = `n_bzones' bidding zones).", size(vsmall)) ///
        scheme(s2color)

    graph export "outputs/panel/solar_diff_and_diff/event_study_latvia_effect_solar_share.png", ///
        replace width(1400) height(900)
restore

// =============================================================================
// LATEX TABLE: Event Study Results
// =============================================================================
local d = char(36)   // dollar sign for LaTeX math mode

tempname fh_tex
file open `fh_tex' using ///
    "outputs/panel/solar_diff_and_diff/event_study_solar_share.tex", ///
    write replace

file write `fh_tex' "\begin{table}[htbp]" _n
file write `fh_tex' "\centering" _n
file write `fh_tex' "\caption{Event study: effect of pre-war gas exposure on solar share}" _n
file write `fh_tex' "\label{tab:event_study_solar_gas}" _n
file write `fh_tex' "\begin{tabular}{lccc}" _n
file write `fh_tex' "\hline\hline" _n
file write `fh_tex' "Period & Latvia-specific effect (pp) & Other fossil (control) & Ln pop. density (control) \\" _n
file write `fh_tex' " & {\footnotesize (wild cluster-robust SE)} & {\footnotesize (wild cluster-robust SE)} & {\footnotesize (wild cluster-robust SE)} \\" _n
file write `fh_tex' "\hline" _n

// Latvia scaling factor for the table
local lv_gas_tbl = scalar(lv_gas_share_pre)

forvalues i = 1/`nper' {
    local per_val = scalar(_es_period_`i')
    local k_val   = `per_val' + 8
    // Compute period label: k_val odd → H1, even → H2
    if mod(`k_val', 2) == 1 {
        local sem "H1"
        local yr  = 2017 + (`k_val' - 1) / 2
    }
    else {
        local sem "H2"
        local yr  = 2016 + `k_val' / 2
    }
    local per_label "`sem' `yr'"

    if `per_val' == 0 {
        // Reference period: H2 2020
        file write `fh_tex' "`per_label' & 0 & 0 & 0 \\" _n
        file write `fh_tex' "       & {\footnotesize \textit{(reference)}} & {\footnotesize \textit{(reference)}} & {\footnotesize \textit{(reference)}} \\" _n
        // file write `fh_tex' "`per_label' & 0 & 0 & 0 \\" _n
        // file write `fh_tex' "       & {\footnotesize \textit{(reference)}} & {\footnotesize \textit{(reference)}} & {\footnotesize \textit{(reference)}} \\" _n
    }
    else {
        // treatment (gas) — scaled to Latvia-specific effect
        local coef_val = scalar(_es_coef_`i') * `lv_gas_tbl'
        local wse_val  = scalar(_es_wse_`i')  * `lv_gas_tbl'
        local wp_val   = scalar(_es_wp_`i')
        if `wp_val' < 0.01      local stars "`d'^{***}`d'"
        else if `wp_val' < 0.05 local stars "`d'^{**}`d'"
        else if `wp_val' < 0.10 local stars "`d'^{*}`d'"
        else                    local stars ""
        local coef_str = strtrim(string(`coef_val', "%10.4f"))
        local wse_str  = strtrim(string(`wse_val',  "%10.4f"))
        // control (other fossil)
        local ct_coef_val = scalar(_ct_coef_`i')
        local ct_wse_val  = scalar(_ct_wse_`i')
        local ct_wp_val   = scalar(_ct_wp_`i')
        if `ct_wp_val' < 0.01      local ct_stars "`d'^{***}`d'"
        else if `ct_wp_val' < 0.05 local ct_stars "`d'^{**}`d'"
        else if `ct_wp_val' < 0.10 local ct_stars "`d'^{*}`d'"
        else                       local ct_stars ""
        local ct_coef_str = strtrim(string(`ct_coef_val', "%10.4f"))
        local ct_wse_str  = strtrim(string(`ct_wse_val',  "%10.4f"))
        // control (log pop density)
        local c2_coef_val = scalar(_c2_coef_`i')
        local c2_wse_val  = scalar(_c2_wse_`i')
        local c2_wp_val   = scalar(_c2_wp_`i')
        if `c2_wp_val' < 0.01      local c2_stars "`d'^{***}`d'"
        else if `c2_wp_val' < 0.05 local c2_stars "`d'^{**}`d'"
        else if `c2_wp_val' < 0.10 local c2_stars "`d'^{*}`d'"
        else                       local c2_stars ""
        local c2_coef_str = strtrim(string(`c2_coef_val', "%10.4f"))
        local c2_wse_str  = strtrim(string(`c2_wse_val',  "%10.4f"))

        file write `fh_tex' "`per_label' & `coef_str'`stars' & `ct_coef_str'`ct_stars' & `c2_coef_str'`c2_stars' \\" _n
        file write `fh_tex' "       & (`wse_str') & (`ct_wse_str') & (`c2_wse_str') \\" _n
        // file write `fh_tex' "`per_label' & `coef_str'`stars' & `ct_coef_str'`ct_stars' & `c2_coef_str'`c2_stars' \\" _n
        // file write `fh_tex' "       & (`wse_str') & (`ct_wse_str') & (`c2_wse_str') \\" _n
    }

    // Visual separator between last pre-invasion period (H2 2021) and first post-invasion (H1 2022)
    if `per_val' == 2 {
        file write `fh_tex' "\hline" _n
    }
}

local ev_N   = scalar(_ev_N)
local ev_r2w = strtrim(string(scalar(_ev_r2w), "%6.4f"))

file write `fh_tex' "\hline\hline" _n
file write `fh_tex' "\multicolumn{4}{p{0.9\linewidth}}{\footnotesize" _n
file write `fh_tex' " \textit{Note}: Two-way FE (bidding zone and semester)." _n
file write `fh_tex' " Dependent variable: solar share (\%)." _n
file write `fh_tex' " Treatment intensity: pre-war gas share. Controls: pre-war other-fossil share and log pre-war population density included." _n
// file write `fh_tex' " Treatment intensity: pre-war gas share. No additional controls included." _n
// file write `fh_tex' " Treatment intensity: pre-war gas share. Controls: pre-war other-fossil share (brown coal, coal gas, hard coal, oil, oil shale, peat) and log pre-war population density." _n
file write `fh_tex' " Reported estimates are the Latvia-specific effect: regression coefficient scaled by Latvia's pre-war gas share." _n
file write `fh_tex' " Reference period: H2~2020." _n
file write `fh_tex' " Observations: `ev_N'; within \(R^2\): `ev_r2w'." _n
file write `fh_tex' " Standard errors in parentheses are implied by the 95\% wild cluster bootstrap CI," _n
file write `fh_tex' " clustered at the bidding-zone level" _n
file write `fh_tex' " (\(N=`n_bzones'\) bidding zones, 9{,}999 replications)." _n
file write `fh_tex' " Stars indicate significance of the wild cluster bootstrap \(p\)-value:" _n
file write `fh_tex' " `d'^{***}`d' \(p<0.01\)," _n
file write `fh_tex' " `d'^{**}`d' \(p<0.05\)," _n
file write `fh_tex' " `d'^{*}`d' \(p<0.10\).} \\" _n
file write `fh_tex' "\end{tabular}" _n
file write `fh_tex' "\end{table}" _n

file close `fh_tex'

di "LaTeX table saved to outputs/panel/solar_diff_and_diff/event_study_solar_share.tex"
di "Done. Outputs saved to outputs/panel/solar_diff_and_diff/"

