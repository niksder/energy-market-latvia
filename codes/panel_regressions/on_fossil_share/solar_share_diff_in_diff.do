cls
clear

cd "/home/niks/Projects/solar-power-latvia"
do "codes/panel_regressions/load_daily_data.do"

cap mkdir "outputs/panel/solar_diff_and_diff/on_fossil_share"


/* // Drop NL, GR, HU, PT, ES that have higher gas share than LV
drop if bzone == "Netherlands" | bzone == "Greece" | bzone == "Hungary" | bzone == "Portugal" | bzone == "Spain" 

// Drop bzones with higher fossil share than Latvia
drop if bzone == "Poland" | bzone == "Estonia" | bzone == "Czechia" | bzone == "Germany" | bzone == "Romania" | bzone == "Bulgaria" | bzone == "Croatia" */

/* Italy (IT\_CNOR) & 36.4\% \\
Germany & 36.5\% \\
Portugal & 37.0\% \\
Romania & 37.7\% \\
Hungary & 37.8\% \\
Bulgaria & 45.3\% \\
Italy (IT\_SUD) & 45.5\% \\
Ireland & 46.1\% \\
Czechia & 47.7\% \\
Italy (IT\_NORTH) & 48.5\% \\
Italy (IT\_CSUD) & 53.2\% \\
Netherlands & 54.2\% \\
Italy (IT\_SICI) & 59.4\% \\
Estonia & 64.1\% \\
Greece & 65.9\% \\
Italy (IT\_SARD) & 69.1\% \\
Italy (IT\_CALA) & 79.7\% \\
Poland & 85.6\% \\
Cyprus & 94.8\% \\
Italy (IT\_SACOAC) & .\% \\
Italy (IT\_SACODC) & .\% \\ */

drop if bzone == "Germany" | bzone == "Portugal" | bzone == "Romania" | bzone == "Hungary" | bzone == "Bulgaria" | bzone == "Czechia" | bzone == "Ireland" | bzone == "Netherlands" | bzone == "Greece" | bzone == "Estonia" | bzone == "Poland" | bzone == "Cyprus"

//drop if bzone == "Germany" || bzone == "Bulgaria" || bzone == "Ireland" || bzone == "Czechia" || bzone == "Netherlands" || bzone == "Greece" || bzone == "Estonia" || bzone == "Poland" || bzone == "Cyprus"
drop if bzone == "IT_NORTH" | bzone == "IT_CNOR" | bzone == "IT_CSUD" | bzone == "IT_SUD" | bzone == "IT_CALA" | bzone == "IT_SICI" | bzone == "IT_SARD" | bzone == "IT_SACOAC" | bzone == "IT_SACODC"

drop if bzone == "Croatia" // Missing data in 2017-2018

// Count bzones dynamically
quietly levelsof bzone_id, local(_bzone_list)
local n_bzones : word count `_bzone_list'
di "Number of bzones in data: `n_bzones'"

// =============================================================================
// TREATMENT VARIABLE: pre-war fossil share (Feb 23 2021, last day before invasion)
// fossil_share is available from load_daily_data.do
// =============================================================================

// Pre-war fossil share: value on Feb 23 2021 (fixed treatment intensity per bzone)
gen _tmp = gas_share + brown_coal_share + coal_gas_share + hard_coal_share + oil_share + oil_shale_share + peat_share if date == td(23feb2021)
bysort bzone_id: egen fossil_share_pre = max(_tmp)
drop _tmp
label var fossil_share_pre "Fossil share on Feb 23 2021 (pre-war, 0–1)"

// Pre-war solar share: value on Feb 23 2021 (baseline solar penetration per bzone)
gen _tmp2 = solar_share if date == td(23feb2021)
bysort bzone_id: egen solar_share_pre = max(_tmp2)
drop _tmp2
label var solar_share_pre "Solar share on Feb 23 2021 (pre-war baseline, 0–1)"


// Verify treatment values
di "Pre-war solar share by bzone:"
table bzone, statistic(mean solar_share_pre)
di "Pre-war fossil share by bzone:"
table bzone, statistic(mean fossil_share_pre)

// =============================================================================
// POST-INVASION INDICATOR  (Russia invaded Ukraine Feb 24 2022)
// =============================================================================

gen post = (date >= td(24feb2022))
label var post "Post-invasion dummy (>= Feb 24 2022)"

// =============================================================================
// MAIN DiD REGRESSIONS
//   Y_it = α_i + γ_t + β*(fossil_share_pre_i × post_t) + weather + ε_it
//
//   α_i  = bzone fixed effects (absorbed by xtreg fe)
//   γ_t  = date fixed effects (i.date controls for all common daily shocks,
//           including seasonality; identified because weather varies
//           cross-sectionally within each day)
//   β    = DiD coefficient: extra solar output per pp of pre-war fossil share
//           in the post-invasion period, relative to pre-invasion
//
//   SE clustered at bzone level (N=14; interpret CI conservatively)
// =============================================================================

// Spec 1: solar share
xtreg solar_share c.fossil_share_pre#i.post /*solar_share_pre*/ ///
    /*i.day_of_week*/ i.month, ///
    fe vce(cluster bzone_id)
eststo did_levels
boottest c.fossil_share_pre#1.post, boottype(wild) cluster(bzone_id) reps(9999) seed(42) // Wild cluster bootstrap for robust inference with few clusters

di "DiD coef (levels): " %9.3f _b[c.fossil_share_pre#1.post] ///
   "  SE: " %9.3f _se[c.fossil_share_pre#1.post]

gen ln_solar_share = ln(solar_share + 1)
label var ln_solar_share "ln(solar_share + 1)"

// Spec 2: ln(solar_share + 1) — semi-elasticity interpretation
xtreg ln_solar_share c.fossil_share_pre#i.post /*solar_share_pre*/ ///
    /*i.day_of_week*/ i.month, ///
    fe vce(cluster bzone_id)
eststo did_log
boottest c.fossil_share_pre#1.post, boottype(wild) cluster(bzone_id) reps(9999) seed(42) // Wild cluster bootstrap for robust inference with few clusters

di "DiD coef (log): " %9.4f _b[c.fossil_share_pre#1.post] ///
   "  SE: " %9.4f _se[c.fossil_share_pre#1.post]

// =============================================================================
// EVENT STUDY
//   Y_it = α_i + γ_t + Σ_k β_k*(fossil_share_pre_i × 1[hy_seq=k]) + weather + ε_it
//
//   Reference period: H2 2020 (hy_seq_pos = 8)
//   β_k ≈ 0 for pre-war periods → parallel trends
//   β_k > 0 for post-war periods → high-fossil bzones grew solar more
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
// Using factor variable notation (c.fossil_share_pre#ib10.hy_seq_pos) causes
// Stata to pair the FE and interaction omissions: when it drops one period FE
// as redundant after within-transformation, it also drops the matching
// interaction — even if that interaction is estimable. By creating the
// interactions as plain variables, Stata sees them as standalone continuous
// regressors and applies collinearity detection independently of the period FE.
foreach k of local hy_pos_vals {
    if `k' != 8 {
        gen inter_hy`k' = fossil_share_pre * (hy_seq_pos == `k')
        label var inter_hy`k' "fossil_share_pre × (hy_seq_pos==`k')"
    }
}

local inter_vars ""
foreach k of local hy_pos_vals {
    if `k' != 8 local inter_vars "`inter_vars' inter_hy`k'"
}

// Two-way FE: bzone absorbed by xtreg fe, period absorbed by ib8.hy_seq_pos.
// ib8 sets H2 2020 as the omitted base for both FE and interactions.
xtreg solar_share `inter_vars' /*solar_share_pre*/ ///
    /* coal_share_pre */ ///
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
        scalar _es_lb90_`i'   = 0
        scalar _es_ub90_`i'   = 0
        scalar _es_wse_`i'    = 0
        scalar _es_wp_`i'     = .
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
        quietly boottest inter_hy`k', boottype(wild) cluster(bzone_id) reps(9999) seed(42) level(90)
        scalar _es_lb90_`i'   = r(CI)[1,1]
        scalar _es_ub90_`i'   = r(CI)[1,2]
    }
    local i = `i' + 1
}

// Extract Latvia's pre-war fossil share (scalar survives preserve/restore)
quietly summarize fossil_share_pre if bzone == "Latvia"
scalar lv_fossil_share_pre = r(mean)
di "Latvia pre-war fossil share (pp): " %5.2f lv_fossil_share_pre

preserve
    clear
    set obs `nper'
    gen period = .
    gen coef   = .
    gen lb95   = .
    gen ub95   = .
    gen lb90   = .
    gen ub90   = .

    forvalues i = 1/`nper' {
        replace period = _es_period_`i' in `i'
        replace coef   = _es_coef_`i'   in `i'
        replace lb95   = _es_lb_`i'     in `i'
        replace ub95   = _es_ub_`i'     in `i'
        replace lb90   = _es_lb90_`i'   in `i'
        replace ub90   = _es_ub90_`i'   in `i'
    }

    sort period

    twoway ///
        /* (rcap lb95 ub95 period, lcolor(navy%30)) */ ///
        (rcap lb90 ub90 period, lcolor(navy%55)) ///
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
        ytitle("Coef (% per pp of pre-war fossil share)") ///
        title("Effect of pre-war fossil exposure on solar share") ///
        subtitle("DiD event study; reference = H2 2020; red line = invasion Feb 24 2022") ///
        note("Two-way FE (bidding zone, time). Controls: month for seasonality." ///
             "Wild cluster bootstrapping used for SE at bzone level (N = `n_bzones' bidding zones)." ///
             "90% confidence intervals reported.", size(vsmall)) ///
        scheme(s2color)

    graph export "outputs/panel/solar_diff_and_diff/on_fossil_share/event_study_solar_share_no_croatia.png", ///
        replace width(1400) height(900)
    // -------------------------------------------------------------------------
    // LATVIA-SPECIFIC EFFECT: coef × Latvia's pre-war fossil share
    // Interpretation: extra pp of solar share Latvia gained (vs. counterfactual
    // of zero fossil dependence) relative to the H2 2020 reference period.
    // -------------------------------------------------------------------------
    local lv_fossil = scalar(lv_fossil_share_pre)
    local lv_fossil_fmt : di %5.1f `lv_fossil'

    forvalues i = 1/`nper' {
        replace coef = _es_coef_`i'   * `lv_fossil' in `i'
        replace lb95 = _es_lb_`i'    * `lv_fossil' in `i'
        replace ub95 = _es_ub_`i'    * `lv_fossil' in `i'
        replace lb90 = _es_lb90_`i'  * `lv_fossil' in `i'
        replace ub90 = _es_ub90_`i'  * `lv_fossil' in `i'
    }

    twoway ///
        /* (rcap lb95 ub95 period, lcolor(maroon%30)) */ ///
        (rcap lb90 ub90 period, lcolor(maroon%55)) ///
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
        ytitle("Extra solar share (pp) vs. zero-fossil-dependence counterfactual") ///
        title("Latvia: solar share attributable to pre-war fossil dependence") ///
        subtitle("DiD coefs × Latvia fossil share (`lv_fossil_fmt' pp); ref = H2 2020; red = invasion") ///
        note("Two-way FE (bidding zone, time). Controls: month for seasonality." ///
             "Wild cluster bootstrapping used for SE at bzone level (N = `n_bzones' bidding zones)." ///
             "90% confidence intervals reported.", size(vsmall)) ///
        scheme(s2color)

    graph export "outputs/panel/solar_diff_and_diff/on_fossil_share/event_study_latvia_effect_solar_share_no_croatia.png", ///
        replace width(1400) height(900)
restore

// =============================================================================
// LATEX TABLE: Latvia-specific event study (coefs × Latvia fossil share)
// =============================================================================
local d = char(36)   // dollar sign for LaTeX math mode
local lv_fossil = scalar(lv_fossil_share_pre)
local lv_fossil_fmt : di %5.1f `lv_fossil'

tempname fh_tex
file open `fh_tex' using ///
    "outputs/panel/solar_diff_and_diff/on_fossil_share/event_study_latvia_effect_solar_share_no_croatia.tex", ///
    write replace

file write `fh_tex' "\begin{table}[htbp]" _n
file write `fh_tex' "\centering" _n
file write `fh_tex' "\caption{Event study: Latvia solar share attributable to pre-war fossil dependence}" _n
file write `fh_tex' "\label{tab:event_study_latvia_solar}" _n
file write `fh_tex' "\begin{tabular}{lc}" _n
file write `fh_tex' "\hline\hline" _n
file write `fh_tex' "Period & Extra solar share (pp) \\" _n
file write `fh_tex' " & {\footnotesize (wild cluster-robust SE)} \\" _n
file write `fh_tex' "\hline" _n

forvalues i = 1/`nper' {
    local per_val = scalar(_es_period_`i')
    local k_val   = `per_val' + 8
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
        file write `fh_tex' "`per_label' & 0 \\" _n
        file write `fh_tex' "       & {\footnotesize \textit{(reference)}} \\" _n
    }
    else {
        local coef_val = scalar(_es_coef_`i') * `lv_fossil'
        local wse_val  = scalar(_es_wse_`i')  * `lv_fossil'
        local wp_val   = scalar(_es_wp_`i')

        if `wp_val' < 0.01      local stars "`d'^{***}`d'"
        else if `wp_val' < 0.05 local stars "`d'^{**}`d'"
        else if `wp_val' < 0.10 local stars "`d'^{*}`d'"
        else                    local stars ""

        local coef_str = strtrim(string(`coef_val', "%10.4f"))
        local wse_str  = strtrim(string(`wse_val',  "%10.4f"))

        file write `fh_tex' "`per_label' & `coef_str'`stars' \\" _n
        file write `fh_tex' "       & (`wse_str') \\" _n
    }

    if `per_val' == 2 {
        file write `fh_tex' "\hline" _n
    }
}

local ev_N   = scalar(_ev_N)
local ev_r2w = strtrim(string(scalar(_ev_r2w), "%6.4f"))

file write `fh_tex' "\hline\hline" _n
file write `fh_tex' "\multicolumn{2}{p{0.6\linewidth}}{\footnotesize" _n
file write `fh_tex' " \textit{Note}: Two-way FE (bidding zone and semester)." _n
file write `fh_tex' " Dependent variable: solar share (\%)." _n
file write `fh_tex' " Coefficients are DiD estimates scaled by Latvia's pre-war fossil share (`lv_fossil_fmt' pp)." _n
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

di "LaTeX table saved to outputs/panel/solar_diff_and_diff/on_fossil_share/event_study_latvia_effect_solar_share_no_croatia.tex"
di "Done. Outputs saved to outputs/panel/solar_diff_and_diff/on_fossil_share/"

