cls
clear

cd "/home/niks/Projects/solar-power-latvia"
do "codes/panel_regressions/load_daily_data.do"

// Count bzones dynamically
quietly levelsof bzone_id, local(_bzone_list)
local n_bzones : word count `_bzone_list'
di "Number of bzones in data: `n_bzones'"

cap mkdir "outputs/panel/fossil_share"
cap mkdir "outputs/panel/fossil_share/solanka"

// =============================================================================
// DEPENDENT VARIABLE: fossil_share (current)
// =============================================================================

gen fossil_share = gas_share + brown_coal_share + coal_gas_share + hard_coal_share ///
                 + oil_share + oil_shale_share + peat_share
label var fossil_share "Fossil share (0--1)"

// =============================================================================
// TREATMENT VARIABLE: pre-war fossil share (Feb 23 2021, last day before invasion)
// fossil_share is the sum of all fossil fuel shares
// =============================================================================

gen _tmp = gas_share + brown_coal_share + coal_gas_share + hard_coal_share + oil_share + oil_shale_share + peat_share if date == td(23feb2021)
bysort bzone_id: egen fossil_share_pre = max(_tmp)
drop _tmp
label var fossil_share_pre "Fossil share on Feb 23 2021 (pre-war, 0–1)"

// Verify treatment values
di "Pre-war fossil share by bzone:"
table bzone, statistic(mean fossil_share_pre)

// =============================================================================
// EVENT STUDY
//   Y_it = α_i + γ_t + Σ_k β_k*(fossil_share_pre_i × 1[hy_seq_pos=k]) + controls + ε_it
//
//   Reference period: H2 2020 (hy_seq_pos = 8)
//   β_k ≈ 0 for pre-war periods → parallel trends
//   β_k ≠ 0 for post-war periods → high-fossil bzones changed fossil share differently
//
//   Period mapping:
//     hy_seq_pos: 1=H1 2017, ..., 8=H2 2020 (ref), 9=H1 2021, 10=H2 2021,
//                 11=H1 2022, 12=H2 2022, ...
// =============================================================================

gen semester   = cond(month <= 6, 1, 2)
gen hy_seq     = (year - 2021) * 2 + semester - 2
gen hy_seq_pos = hy_seq + 10
label var hy_seq_pos "Half-year (8 = H2 2020, reference period)"

qui levelsof hy_seq_pos, local(hy_pos_vals)
di "Half-year periods in data (shifted): `hy_pos_vals'"

// Create interaction dummies manually (avoids Stata FE / interaction collinearity issue)
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

// Two-way FE: bzone absorbed by xtreg fe, semester absorbed by ib8.hy_seq_pos
xtreg fossil_share `inter_vars' ///
    temperature hdd cdd wind ln_sun precipitation precipitation_weekly precipitation_monthly ///
    i.day_of_week i.month ib8.hy_seq_pos, ///
    fe vce(cluster bzone_id)
eststo event_fossil
scalar _ev_N   = e(N)
scalar _ev_r2w = e(r2_w)

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
        scalar _es_wse_`i'    = 0
        scalar _es_wp_`i'     = .
    }
    else {
        scalar _es_period_`i' = `k' - 8
        scalar _es_coef_`i'   = _b[inter_hy`k']
        quietly boottest inter_hy`k', boottype(wild) cluster(bzone_id) reps(9999) seed(42) level(95)
        scalar _es_lb_`i'     = r(CI)[1,1]
        scalar _es_ub_`i'     = r(CI)[1,2]
        scalar _es_wse_`i'    = (r(CI)[1,2] - r(CI)[1,1]) / (2 * invnormal(0.975))
        scalar _es_wp_`i'     = r(p)
    }
    local i = `i' + 1
}

preserve
    clear
    set obs `nper'
    gen period = .
    gen coef   = .
    gen lb95   = .
    gen ub95   = .

    forvalues i = 1/`nper' {
        replace period = _es_period_`i' in `i'
        replace coef   = _es_coef_`i'   in `i'
        replace lb95   = _es_lb_`i'     in `i'
        replace ub95   = _es_ub_`i'     in `i'
    }

    sort period

    twoway ///
        (rcap lb95 ub95 period, lcolor(navy%30)) ///
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
        ytitle("Coef (fossil share per pp of pre-war fossil share)") ///
        title("Effect of Pre-War Fossil Exposure on Fossil Share") ///
        subtitle("DiD event study; reference = H2 2020; red line = invasion Feb 24 2022") ///
        note("Two-way FE (bidding zone, time). Controls: month dummies for seasonality." ///
             "Wild cluster bootstrapping used for SE at bzone level (N = `n_bzones' bzones)." ///
             "95% confidence intervals reported.", size(vsmall)) ///
        scheme(s2color)

    graph export "outputs/panel/fossil_share/solanka/event_study_fossil_share_on_fossil.png", ///
        replace width(1400) height(900)
restore

// =============================================================================
// LATEX TABLE: Event Study Results
// =============================================================================
local d = char(36)

tempname fh_tex
file open `fh_tex' using ///
    "outputs/panel/fossil_share/solanka/event_study_fossil_share_on_fossil.tex", ///
    write replace

file write `fh_tex' "\begin{table}[htbp]" _n
file write `fh_tex' "\centering" _n
file write `fh_tex' "\caption{Event study: effect of pre-war fossil exposure on fossil share}" _n
file write `fh_tex' "\label{tab:event_study_fossil_share_fossil}" _n
file write `fh_tex' "\begin{tabular}{lc}" _n
file write `fh_tex' "\hline\hline" _n
file write `fh_tex' "Period & Fossil share \\" _n
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
        local coef_val = scalar(_es_coef_`i')
        local wse_val  = scalar(_es_wse_`i')
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
file write `fh_tex' " Dependent variable: fossil share." _n
file write `fh_tex' " Treatment intensity: pre-war fossil share." _n
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

di "LaTeX table saved to outputs/panel/fossil_share/solanka/event_study_fossil_share_on_fossil.tex"
di "Done. Outputs saved to outputs/panel/fossil_share/solanka/"
