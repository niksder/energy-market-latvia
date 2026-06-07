cls
clear

cd "/home/niks/Projects/solar-power-latvia"
do "codes/panel_regressions/load_daily_data.do"
/* 
// Drop NL, GR, HU, PT, ES that have higher gas share than LV
drop if bzone == "Netherlands" | bzone == "Greece" | bzone == "Hungary" | bzone == "Portugal" | bzone == "Spain" 
drop if bzone == "Switzerland" // Drop Switzerland since it is not EU


// Drop Italy (IT_NORTH IT_CNOR IT_CSUD IT_SUD IT_CALA IT_SICI IT_SARD IT_SACOAC IT_SACODC) because of granularity of zones
drop if bzone == "IT_NORTH" | bzone == "IT_CNOR" | bzone == "IT_CSUD" | bzone == "IT_SUD" | bzone == "IT_CALA" | bzone == "IT_SICI" | bzone == "IT_SARD" | bzone == "IT_SACOAC" | bzone == "IT_SACODC"
// drop if bzone == "Ireland"

drop if bzone == "Cyprus" // Drop Cyprus since it misses data from 2023 and 2024 and elsewhere AND PRICES */


drop if bzone == "Germany" | bzone == "Portugal" | bzone == "Romania" | bzone == "Hungary" | bzone == "Bulgaria" | bzone == "Czechia" | bzone == "Ireland" | bzone == "Netherlands" | bzone == "Greece" | bzone == "Estonia" | bzone == "Poland" | bzone == "Cyprus"

//drop if bzone == "Germany" || bzone == "Bulgaria" || bzone == "Ireland" || bzone == "Czechia" || bzone == "Netherlands" || bzone == "Greece" || bzone == "Estonia" || bzone == "Poland" || bzone == "Cyprus"
drop if bzone == "IT_NORTH" | bzone == "IT_CNOR" | bzone == "IT_CSUD" | bzone == "IT_SUD" | bzone == "IT_CALA" | bzone == "IT_SICI" | bzone == "IT_SARD" | bzone == "IT_SACOAC" | bzone == "IT_SACODC"

drop if bzone == "Croatia" // Missing data in 2017-2018


cap mkdir "outputs/panel/solar_diff_and_diff/synthetic"

// =============================================================================
// BASE VARIABLE CONSTRUCTION (computed once; shared across all program calls)
// =============================================================================

gen semester   = cond(month <= 6, 1, 2)
gen hy_seq     = (year - 2021) * 2 + semester - 2
gen hy_seq_pos = hy_seq + 10
label var hy_seq_pos "Half-year (hy_seq_pos 8 = H2 2020)"

gen ln_solar_share = ln(solar_share + 1)
label var ln_solar_share "ln(solar_share + 1)"

// Save prepared panel and bzone-name lookup as globals so the program can use them
tempfile synth_panel_tmp
save `synth_panel_tmp'
global g_synth_panel "`synth_panel_tmp'"

tempfile synth_bzones_tmp
preserve
    keep bzone_id bzone
    duplicates drop
    save `synth_bzones_tmp'
restore
global g_synth_bzones "`synth_bzones_tmp'"

// Ensure synth is installed
cap which synth
if _rc {
    di as text "Installing synth package..."
    ssc install synth, replace
}

// =============================================================================
// PROGRAM: synth_did
//
//   Runs the full synthetic-control DiD pipeline for a given treatment period.
//   Call as:  synth_did <trperiod_pos>
//
//   Argument
//     trperiod_pos  Integer hy_seq_pos value for the first post-treatment
//                   half-year (e.g. 11 = H1 2022; 6 = H2 2019).
//
//   Derived internally
//     pre_end       trperiod_pos - 1   last pre-treatment half-year for synth
//     ref_pos       trperiod_pos - 3   event-study reference period
//     post          date >= first day of half-year trperiod_pos
//     tag           e.g. "hy2022H1" or "hy2019H2"  (used in filenames)
//
//   hy_seq_pos mapping (hy_seq_pos = hy_seq + 10):
//     1=H1 2017  2=H2 2017 ... 6=H2 2019 ... 8=H2 2020 ... 11=H1 2022 ...
// =============================================================================

cap program drop synth_did
program define synth_did
    args trperiod_pos

    // ---------------------------------------------------------------
    // Derive treatment half-year metadata
    // ---------------------------------------------------------------
    local pre_end = `trperiod_pos' - 1
    local ref_pos = `trperiod_pos' - 3

    local hy_seq  = `trperiod_pos' - 10
    local sem     = mod(`hy_seq' + 1, 2) + 1            // 1=H1, 2=H2
    local yr      = (`hy_seq' + 2 - `sem') / 2 + 2021
    local mo      = cond(`sem' == 1, 1, 7)              // first month of half-year
    local hy_lbl  = cond(`sem' == 1, "H1", "H2")
    local tag     "hy`yr'`hy_lbl'"

    // Reference period label
    local ref_hy_seq = `ref_pos' - 10
    local ref_sem    = mod(`ref_hy_seq' + 1, 2) + 1
    local ref_yr     = (`ref_hy_seq' + 2 - `ref_sem') / 2 + 2021
    local ref_lbl    = cond(`ref_sem' == 1, "H1", "H2")

    // xline position on centered period axis (gap between pre_end and trperiod)
    local xline_pos = `trperiod_pos' - 8 - 0.5

    di as text ""
    di as text "================================================================="
    di as text "  synth_did: treatment = `hy_lbl' `yr'  (hy_seq_pos = `trperiod_pos')"
    di as text "  pre-match window : hy_seq_pos 1 – `pre_end'"
    di as text "  event-study ref  : hy_seq_pos `ref_pos' = `ref_lbl' `ref_yr'"
    di as text "  output tag       : `tag'"
    di as text "================================================================="

    // ---------------------------------------------------------------
    // Clean up scalars from any previous call
    // ---------------------------------------------------------------
    forvalues j = 1/100 {
        cap scalar drop _sc_id_`j'
        cap scalar drop _sc_wt_`j'
    }

    // ---------------------------------------------------------------
    // Load prepared daily panel; add post indicator
    // ---------------------------------------------------------------
    use "$g_synth_panel", clear

    local post_date_val = mdy(`mo', 1, `yr')
    gen post = (date >= `post_date_val')
    label var post "Post: date >= 01`hy_lbl'`yr'"

    quietly levelsof bzone_id if bzone == "Latvia", local(_lv_list)
    local lv_id : word 1 of `_lv_list'

    tempfile dp_run
    save `dp_run'

    // ---------------------------------------------------------------
    // Step 1: Half-year aggregation for synth
    // ---------------------------------------------------------------
    collapse (mean) gas_share solar_share energy_price ln_solar_share temperature sun precipitation population_density gdp_pps, ///
        by(bzone_id hy_seq_pos)

    // Drop donors with any missing solar_share in pre-treatment window
    bysort bzone_id: egen _n_miss_pre = total(missing(solar_share) & hy_seq_pos <= `pre_end')
    drop if _n_miss_pre > 0 & bzone_id != `lv_id'
    drop _n_miss_pre

    xtset bzone_id hy_seq_pos

    // Scale up GPP PPS for it to have bigger weight in the synth matching
    gen gdp_pps_scaled = gdp_pps * 1000
    label var gdp_pps_scaled "gdp_pps (scaled by 1000 for synth)"
    gen sun_scaled = sun / 10000
    label var sun_scaled "sun (scaled by 10000 for synth)"
    gen energy_price_scaled = energy_price * 100
    label var energy_price_scaled "energy_price (scaled by 100 for synth)"

    // Binary: bzone had > 0.5% mean solar share before the shock
    // Donors with effectively no solar pre-shock get penalised in matching
    bysort bzone_id: egen _mean_pre_solar = mean(cond(hy_seq_pos <= `pre_end', solar_share, .))
    gen high_solar_pre = (_mean_pre_solar > 0.005)
    label var high_solar_pre "Had >0.5% avg solar share pre-shock"
    drop _mean_pre_solar

    // ---------------------------------------------------------------
    // Predictor characteristics table (pre-treatment means per bzone)
    // ---------------------------------------------------------------
    preserve
        keep if hy_seq_pos <= `pre_end'
        collapse (mean) solar_share energy_price population_density gdp_pps sun ///
                 (max)  high_solar_pre, ///
            by(bzone_id)
        merge m:1 bzone_id using "$g_synth_bzones", nogen
        sort bzone_id
        gen byte is_treated = (bzone == "Latvia")
        order bzone is_treated solar_share high_solar_pre energy_price population_density gdp_pps sun
        label var bzone              "Country / bidding zone"
        label var is_treated         "Treated (Latvia=1)"
        label var solar_share        "Solar share (mean, pre-treatment)"
        label var high_solar_pre     "Had >0.5% avg solar share pre-shock"
        label var energy_price "Energy price (mean, pre-treatment)"
        label var population_density "Pop. density (mean, pre-treatment)"
        label var gdp_pps         "GDP PPS (mean, pre-treatment)"
        label var sun             "Sun radiation (mean, pre-treatment)"
        di as text ""
        di as text "=== Synth predictor characteristics by bzone (pre-treatment means) [`tag'] ==="
        list bzone is_treated solar_share high_solar_pre energy_price population_density gdp_pps sun, ///
            noobs sep(0) clean ab(26)
        /* export delimited using ///
            "outputs/panel/solar_diff_and_diff/synthetic/synth_predictors_`tag'.csv", ///
            replace
        di as text "Predictor table saved: outputs/panel/solar_diff_and_diff/synthetic/synth_predictors_`tag'.csv" */

        // LaTeX table: bidding zone characteristics
        tempname fh_pred
        file open `fh_pred' using ///
            "outputs/panel/solar_diff_and_diff/synthetic/synth_predictors_`tag'.tex", ///
            write replace
        file write `fh_pred' "\begin{table}[htbp]" _n
        file write `fh_pred' "\centering" _n
        file write `fh_pred' "\caption{Bidding zone characteristics: pre-treatment means (`hy_lbl' `yr')}" _n
        file write `fh_pred' "\label{tab:synth_predictors_`tag'}" _n
        file write `fh_pred' "\begin{tabular}{lcccccc}" _n
        file write `fh_pred' "\hline\hline" _n
        file write `fh_pred' "Bidding zone & Treated & Solar share (\%) & Energy price & Pop.\ density & GDP PPS & Sun \\" _n
        file write `fh_pred' "\hline" _n
        local N_chars = _N
        forvalues ii = 1/`N_chars' {
            local bname  = bzone[`ii']
            local is_tr  = cond(is_treated[`ii'] == 1, "Yes", "No")
            local sol_s  = strtrim(string(solar_share[`ii'] * 100, "%6.3f"))
            local ep_s   = strtrim(string(energy_price[`ii'], "%6.1f"))
            local pd_s   = strtrim(string(population_density[`ii'], "%6.1f"))
            local gd_s   = strtrim(string(gdp_pps[`ii'], "%6.1f"))
            local su_s   = strtrim(string(sun[`ii'], "%6.1f"))
            file write `fh_pred' "`bname' & `is_tr' & `sol_s' & `ep_s' & `pd_s' & `gd_s' & `su_s' \\" _n
        }
        file write `fh_pred' "\hline\hline" _n
        file write `fh_pred' "\multicolumn{7}{p{0.95\linewidth}}{\footnotesize" _n
        file write `fh_pred' " \textit{Note}: Pre-treatment means (hy\_seq\_pos 1--`pre_end')." _n
        file write `fh_pred' " Solar share converted to \%. Treated = Yes for Latvia." _n
        file write `fh_pred' " Energy price in EUR/MWh; pop.\ density in persons/km\textsuperscript{2}." _n
        file write `fh_pred' " Sun = mean solar radiation.} \\" _n
        file write `fh_pred' "\end{tabular}" _n
        file write `fh_pred' "\end{table}" _n
        file close `fh_pred'
        di as text "Bidding zone characteristics table saved: outputs/panel/solar_diff_and_diff/synthetic/synth_predictors_`tag'.tex"
    restore

    // ---------------------------------------------------------------
    // Step 2: Run synth
    // ---------------------------------------------------------------
    
    // matrix imposedWeights = (0.10, 0.10, 0.30, 0.40, 0.10)
    // numlist imposedWeights = 0.10 0.10 0.30 0.40 0.10 

    synth solar_share ///
        solar_share(1(1)`ref_pos') ///
        energy_price(1(1)`ref_pos') population_density(1(1)`ref_pos') gdp_pps(1(1)`ref_pos') ///
        /*temperature(1(1)`ref_pos')*/ sun(1(1)`ref_pos') /*precipitation(1(1)`ref_pos')*/ ///
        high_solar_pre, ///
        trunit(`lv_id') trperiod(`trperiod_pos') ///
        customV(0.25 0.10 0.25 0.15 0.15 0.10) ///
        /*nested allopt*/

    // ---------------------------------------------------------------
    // Extract donor weights (e(W_weights) is J×2; col 2 = actual weight)
    // ---------------------------------------------------------------
    matrix _W = e(W_weights)
    local n_sc_donors = rowsof(_W)
    local _rnames : rownames _W
    local _j = 0
    foreach _rn of local _rnames {
        local _j = `_j' + 1
        scalar _sc_id_`_j' = `_rn'
        scalar _sc_wt_`_j' = _W[`_j', 2]
    }

    di as text ""
    di as text "=== Synthetic Latvia donor weights [`tag'] ==="
    di as text "  bzone                  weight"
    di as text "  ---------------------- --------"
    preserve
        use "$g_synth_bzones", clear
        tempname fh_wt
        file open `fh_wt' using ///
            "outputs/panel/solar_diff_and_diff/synthetic/synth_weights_`tag'.tex", ///
            write replace
        file write `fh_wt' "\begin{table}[htbp]" _n
        file write `fh_wt' "\centering" _n
        file write `fh_wt' "\caption{Synthetic Latvia donor weights (`hy_lbl' `yr')}" _n
        file write `fh_wt' "\label{tab:synth_weights_`tag'}" _n
        file write `fh_wt' "\begin{tabular}{lc}" _n
        file write `fh_wt' "\hline\hline" _n
        file write `fh_wt' "Bidding zone & Weight \\" _n
        file write `fh_wt' "\hline" _n
        forvalues j = 1/`n_sc_donors' {
            quietly levelsof bzone if bzone_id == scalar(_sc_id_`j'), local(_bname)
            local _bname_str : word 1 of `_bname'
            di as text "  " %-22s "`_bname_str'" %8.4f scalar(_sc_wt_`j')
            local wt_s = strtrim(string(scalar(_sc_wt_`j'), "%6.4f"))
            file write `fh_wt' "`_bname_str' & `wt_s' \\" _n
        }
        file write `fh_wt' "\hline\hline" _n
        file write `fh_wt' "\multicolumn{2}{p{0.5\linewidth}}{\footnotesize" _n
        file write `fh_wt' " \textit{Note}: Donor weights from synthetic control (Abadie et al.\ 2010)." _n
        file write `fh_wt' " Weights sum to one; bidding zones with zero weight are omitted by synth.} \\" _n
        file write `fh_wt' "\end{tabular}" _n
        file write `fh_wt' "\end{table}" _n
        file close `fh_wt'
        di as text "Donor weights table saved: outputs/panel/solar_diff_and_diff/synthetic/synth_weights_`tag'.tex"
    restore

    // ---------------------------------------------------------------
    // Step 3: Apply weights to daily panel → synthetic series
    // ---------------------------------------------------------------
    use `dp_run', clear

    // Compute high_solar_pre from daily panel (same definition as in Step 1)
    bysort bzone_id: egen _mean_pre_solar = mean(cond(hy_seq_pos <= `pre_end', solar_share, .))
    gen high_solar_pre = (_mean_pre_solar > 0.005)
    drop _mean_pre_solar

    gen _synth_wt = 0
    forvalues j = 1/`n_sc_donors' {
        replace _synth_wt = scalar(_sc_wt_`j') if bzone_id == scalar(_sc_id_`j')
    }

    gen _wt_solar          = _synth_wt * solar_share
    gen _wt_ln_solar       = _synth_wt * ln_solar_share
    gen _wt_gas            = _synth_wt * gas_share
    gen _wt_energy_price   = _synth_wt * energy_price
    gen _wt_pop_density    = _synth_wt * population_density
    gen _wt_gdp_pps        = _synth_wt * gdp_pps
    gen _wt_temperature    = _synth_wt * temperature
    gen _wt_sun            = _synth_wt * sun
    gen _wt_precipitation  = _synth_wt * precipitation
    gen _wt_ln_sun         = _synth_wt * ln_sun
    gen _wt_ln_precip      = _synth_wt * ln_precipitation
    gen _wt_high_solar_pre = _synth_wt * high_solar_pre

    preserve
        drop if bzone_id == `lv_id'
        collapse ///
            (sum)  synth_solar_share      = _wt_solar          ///
                   synth_ln_solar_share   = _wt_ln_solar        ///
                   synth_gas_share        = _wt_gas             ///
                   synth_energy_price     = _wt_energy_price    ///
                   synth_pop_density      = _wt_pop_density     ///
                   synth_gdp_pps          = _wt_gdp_pps         ///
                   synth_temperature      = _wt_temperature     ///
                   synth_sun              = _wt_sun             ///
                   synth_precipitation    = _wt_precipitation   ///
                   synth_ln_sun           = _wt_ln_sun          ///
                   synth_ln_precipitation = _wt_ln_precip       ///
                   synth_high_solar_pre   = _wt_high_solar_pre  ///
            (mean) post year month semester hy_seq hy_seq_pos day_of_week, ///
            by(date)
        tempfile _synth_series
        save `_synth_series'
    restore

    keep if bzone_id == `lv_id'
    merge 1:1 date using `_synth_series', nogen

    drop _synth_wt _wt_solar _wt_ln_solar _wt_gas _wt_energy_price _wt_pop_density ///
         _wt_gdp_pps _wt_temperature _wt_sun _wt_precipitation _wt_ln_sun _wt_ln_precip ///
         _wt_high_solar_pre

    // ---------------------------------------------------------------
    // Path plots: Latvia (actual) vs. Synthetic Latvia
    // ---------------------------------------------------------------
    preserve
        collapse (mean) lv_solar = solar_share sc_solar = synth_solar_share ///
                        lv_gas   = gas_share   sc_gas   = synth_gas_share, ///
            by(hy_seq_pos)
        gen period = hy_seq_pos - 8

        // Solar share path
        twoway ///
            (connected sc_solar period, ///
                mcolor(gs8) lcolor(gs8) msymbol(triangle) lpattern(dash) msize(small)) ///
            (connected lv_solar period, ///
                mcolor(maroon) lcolor(maroon) msymbol(circle) lpattern(solid) msize(small)), ///
            xline(`xline_pos', lpattern(dash) lcolor(red) lwidth(medthick)) ///
            xlabel( ///
                -7 "H1 2017" -6 "H2 2017" -5 "H1 2018" -4 "H2 2018" ///
                -3 "H1 2019" -2 "H2 2019" -1 "H1 2020"  0 "H2 2020" ///
                 1 "H1 2021"  2 "H2 2021"  3 "H1 2022"  4 "H2 2022" ///
                 5 "H1 2023"  6 "H2 2023"  7 "H1 2024"  8 "H2 2024" ///
                 9 "H1 2025" 10 "H2 2025", angle(45) labsize(small)) ///
            legend(order(1 "Synthetic Latvia" 2 "Latvia (actual)") ///
                position(11) ring(0) cols(1)) ///
            xtitle("Half-year period") ///
            ytitle("Solar share (half-year mean)") ///
            title("Latvia vs. synthetic: solar share (`hy_lbl' `yr')") ///
            subtitle("Red line = treatment start (`hy_lbl' `yr')") ///
            note("Synthetic control (Abadie et al. 2010).", size(vsmall)) ///
            scheme(s2color)
        graph export "outputs/panel/solar_diff_and_diff/synthetic/synth_path_solar_share_`tag'_fix_dip.png", ///
            replace width(1400) height(900)

        // Gas share path
        twoway ///
            (connected sc_gas period, ///
                mcolor(gs8) lcolor(gs8) msymbol(triangle) lpattern(dash) msize(small)) ///
            (connected lv_gas period, ///
                mcolor(navy) lcolor(navy) msymbol(circle) lpattern(solid) msize(small)), ///
            xline(`xline_pos', lpattern(dash) lcolor(red) lwidth(medthick)) ///
            xlabel( ///
                -7 "H1 2017" -6 "H2 2017" -5 "H1 2018" -4 "H2 2018" ///
                -3 "H1 2019" -2 "H2 2019" -1 "H1 2020"  0 "H2 2020" ///
                 1 "H1 2021"  2 "H2 2021"  3 "H1 2022"  4 "H2 2022" ///
                 5 "H1 2023"  6 "H2 2023"  7 "H1 2024"  8 "H2 2024" ///
                 9 "H1 2025" 10 "H2 2025", angle(45) labsize(small)) ///
            legend(order(1 "Synthetic Latvia" 2 "Latvia (actual)") ///
                position(1) ring(0) cols(1)) ///
            xtitle("Half-year period") ///
            ytitle("Gas share (half-year mean)") ///
            title("Latvia vs. synthetic: gas share (`hy_lbl' `yr')") ///
            subtitle("Red line = treatment start (`hy_lbl' `yr')") ///
            note("Synthetic control (Abadie et al. 2010).", size(vsmall)) ///
            scheme(s2color)
        graph export "outputs/panel/solar_diff_and_diff/synthetic/synth_path_gas_share_`tag'_fix_dip.png", ///
            replace width(1400) height(900)

        // Real vs synthetic paths table (LaTeX)
        sort period
        gen str8 _period_lbl = ""
        replace _period_lbl = "H1 2017" if period == -7
        replace _period_lbl = "H2 2017" if period == -6
        replace _period_lbl = "H1 2018" if period == -5
        replace _period_lbl = "H2 2018" if period == -4
        replace _period_lbl = "H1 2019" if period == -3
        replace _period_lbl = "H2 2019" if period == -2
        replace _period_lbl = "H1 2020" if period == -1
        replace _period_lbl = "H2 2020" if period == 0
        replace _period_lbl = "H1 2021" if period == 1
        replace _period_lbl = "H2 2021" if period == 2
        replace _period_lbl = "H1 2022" if period == 3
        replace _period_lbl = "H2 2022" if period == 4
        replace _period_lbl = "H1 2023" if period == 5
        replace _period_lbl = "H2 2023" if period == 6
        replace _period_lbl = "H1 2024" if period == 7
        replace _period_lbl = "H2 2024" if period == 8
        replace _period_lbl = "H1 2025" if period == 9
        replace _period_lbl = "H2 2025" if period == 10
        tempname fh_path
        file open `fh_path' using "outputs/panel/solar_diff_and_diff/synthetic/synth_path_solar_share_`tag'_fix_dip.tex", write replace
        file write `fh_path' "\begin{table}[htbp]" _n
        file write `fh_path' "\centering" _n
        file write `fh_path' "\caption{Real vs.\ Synthetic Latvia: solar share (`hy_lbl' `yr')}" _n
        file write `fh_path' "\label{tab:synth_path_solar_share_`tag'_fix_dip}" _n
        file write `fh_path' "\begin{tabular}{lcc}" _n
        file write `fh_path' "\hline\hline" _n
        file write `fh_path' "Period & Latvia (actual) & Synthetic Latvia \\" _n
        file write `fh_path' "\hline" _n
        local _npath = _N
        forvalues _i = 1/`_npath' {
            local _plbl = _period_lbl[`_i']
            local _lv   = strtrim(string(lv_solar[`_i'], "%6.4f"))
            local _sc   = strtrim(string(sc_solar[`_i'], "%6.4f"))
            file write `fh_path' "`_plbl' & `_lv' & `_sc' \\" _n
        }
        file write `fh_path' "\hline\hline" _n
        file write `fh_path' "\end{tabular}" _n
        file write `fh_path' "\end{table}" _n
        file close `fh_path'
        di as text "Real vs synthetic paths table saved: outputs/panel/solar_diff_and_diff/synthetic/synth_path_solar_share_`tag'_fix_dip.tex"
    restore

    // ---------------------------------------------------------------
    // Predictor balance: Latvia vs. Synthetic Latvia (pre-treatment)
    // ---------------------------------------------------------------
    preserve
        keep if !post
        collapse (mean) solar_share synth_solar_share ///
                        energy_price synth_energy_price ///
                        population_density synth_pop_density ///
                        gdp_pps synth_gdp_pps ///
                        sun synth_sun ///
                        high_solar_pre synth_high_solar_pre
        tempname fh_bal
        file open `fh_bal' using ///
            "outputs/panel/solar_diff_and_diff/synthetic/synth_balance_`tag'.tex", ///
            write replace
        file write `fh_bal' "\begin{table}[htbp]" _n
        file write `fh_bal' "\centering" _n
        file write `fh_bal' "\caption{Predictor balance: Latvia vs.\ Synthetic Latvia (pre-treatment) (`hy_lbl' `yr')}" _n
        file write `fh_bal' "\label{tab:synth_balance_`tag'}" _n
        file write `fh_bal' "\begin{tabular}{lcc}" _n
        file write `fh_bal' "\hline\hline" _n
        file write `fh_bal' "Variable & Latvia & Synthetic Latvia \\" _n
        file write `fh_bal' "\hline" _n
        local sol_lv = strtrim(string(solar_share[1]          * 100, "%6.3f"))
        local sol_sc = strtrim(string(synth_solar_share[1]    * 100, "%6.3f"))
        file write `fh_bal' "Solar share (\%) & `sol_lv' & `sol_sc' \\" _n
        local ep_lv  = strtrim(string(energy_price[1],               "%6.2f"))
        local ep_sc  = strtrim(string(synth_energy_price[1],         "%6.2f"))
        file write `fh_bal' "Energy price (EUR/MWh) & `ep_lv' & `ep_sc' \\" _n
        local pd_lv  = strtrim(string(population_density[1],         "%6.1f"))
        local pd_sc  = strtrim(string(synth_pop_density[1],          "%6.1f"))
        file write `fh_bal' "Pop.\ density (persons/km\textsuperscript{2}) & `pd_lv' & `pd_sc' \\" _n
        local gd_lv  = strtrim(string(gdp_pps[1],                    "%6.1f"))
        local gd_sc  = strtrim(string(synth_gdp_pps[1],              "%6.1f"))
        file write `fh_bal' "GDP PPS & `gd_lv' & `gd_sc' \\" _n
        local sun_lv = strtrim(string(sun[1],                        "%6.2f"))
        local sun_sc = strtrim(string(synth_sun[1],                  "%6.2f"))
        file write `fh_bal' "Sun radiation & `sun_lv' & `sun_sc' \\" _n
        local hs_lv  = strtrim(string(high_solar_pre[1],             "%2.0f"))
        local hs_sc  = strtrim(string(synth_high_solar_pre[1],       "%6.4f"))
        file write `fh_bal' "High pre-solar (>0.5\%) & `hs_lv' & `hs_sc' \\" _n
        file write `fh_bal' "\hline\hline" _n
        file write `fh_bal' "\multicolumn{3}{p{0.55\linewidth}}{\footnotesize" _n
        file write `fh_bal' " \textit{Note}: Daily pre-treatment means. Synthetic Latvia is the" _n
        file write `fh_bal' " donor-weighted average.} \\" _n
        file write `fh_bal' "\end{tabular}" _n
        file write `fh_bal' "\end{table}" _n
        file close `fh_bal'
        di as text "Predictor balance table saved: outputs/panel/solar_diff_and_diff/synthetic/synth_balance_`tag'.tex"
    restore

    // ---------------------------------------------------------------
    // Step 4: Construct 2-unit panel
    // ---------------------------------------------------------------
    expand 2, gen(treated)
    label var treated "Treated unit (1=Latvia, 0=Synthetic Latvia)"

    gen unit_id = treated + 1
    cap label drop _unit_lbl_`tag'
    label define _unit_lbl_`tag' 1 "Synthetic Latvia" 2 "Latvia"
    label values unit_id _unit_lbl_`tag'

    replace solar_share      = synth_solar_share      if treated == 0
    replace ln_solar_share   = synth_ln_solar_share   if treated == 0
    replace temperature      = synth_temperature      if treated == 0
    replace sun              = synth_sun              if treated == 0
    replace precipitation    = synth_precipitation    if treated == 0
    replace ln_sun           = synth_ln_sun           if treated == 0
    replace ln_precipitation = synth_ln_precipitation if treated == 0

    drop synth_solar_share synth_ln_solar_share synth_gas_share synth_energy_price ///
         synth_pop_density synth_gdp_pps synth_high_solar_pre synth_temperature ///
         synth_sun synth_precipitation synth_ln_sun synth_ln_precipitation

    di as text ""
    di as text "Pre-fit check — mean solar_share by unit × pre/post:"
    table unit_id post, statistic(mean solar_share)

    gen treated_x_post = treated * post
    label var treated_x_post "Latvia × post (`tag')"

    gen month_year = year * 100 + month
    label var month_year "Year-month cluster ID"

    // ---------------------------------------------------------------
    // Main DiD regressions
    // ---------------------------------------------------------------
    regress solar_share treated_x_post treated ///
        i.month, vce(cluster month_year)
    eststo did_levels_`tag'
    di "DiD coef (levels, `tag'): " %9.3f _b[treated_x_post] ///
       "  SE: " %9.3f _se[treated_x_post]

    regress ln_solar_share treated_x_post treated ///
        i.month, vce(cluster month_year)
    eststo did_log_`tag'
    di "DiD coef (log,    `tag'): " %9.4f _b[treated_x_post] ///
       "  SE: " %9.4f _se[treated_x_post]

    // ---------------------------------------------------------------
    // Event study
    // ---------------------------------------------------------------
    qui levelsof hy_seq_pos, local(hy_pos_vals)

    foreach k of local hy_pos_vals {
        if `k' != `ref_pos' {
            gen inter_hy`k' = treated * (hy_seq_pos == `k')
            label var inter_hy`k' "treated × (hy_seq_pos == `k')"
        }
    }

    local inter_vars ""
    foreach k of local hy_pos_vals {
        if `k' != `ref_pos' local inter_vars "`inter_vars' inter_hy`k'"
    }

    regress solar_share `inter_vars' treated ///
        i.month ib`ref_pos'.hy_seq_pos, vce(cluster month_year)
    eststo event_solar_`tag'

    // ---------------------------------------------------------------
    // Event study plot
    // ---------------------------------------------------------------
    local nper : word count `hy_pos_vals'
    local i = 1
    foreach k of local hy_pos_vals {
        if `k' == `ref_pos' {
            scalar _es_period_`i' = `k' - 8
            scalar _es_coef_`i'   = 0
            scalar _es_lb_`i'     = 0
            scalar _es_ub_`i'     = 0
            scalar _es_lb90_`i'   = 0
            scalar _es_ub90_`i'   = 0
        }
        else {
            scalar _es_period_`i' = `k' - 8
            scalar _es_coef_`i'   = _b[inter_hy`k']
            scalar _es_lb_`i'     = _b[inter_hy`k'] - invnormal(0.975) * _se[inter_hy`k']
            scalar _es_ub_`i'     = _b[inter_hy`k'] + invnormal(0.975) * _se[inter_hy`k']
            scalar _es_lb90_`i'   = _b[inter_hy`k'] - invnormal(0.95)  * _se[inter_hy`k']
            scalar _es_ub90_`i'   = _b[inter_hy`k'] + invnormal(0.95)  * _se[inter_hy`k']
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
            (connected coef period, ///
                mcolor(navy) lcolor(navy) msymbol(circle) lpattern(solid)), ///
            yline(0, lpattern(dash) lcolor(gray)) ///
            xline(`xline_pos', lpattern(dash) lcolor(red) lwidth(medthick)) ///
            xlabel( ///
                -7 "H1 2017" -6 "H2 2017" -5 "H1 2018" -4 "H2 2018" ///
                -3 "H1 2019" -2 "H2 2019" -1 "H1 2020"  0 "H2 2020" ///
                 1 "H1 2021"  2 "H2 2021"  3 "H1 2022"  4 "H2 2022" ///
                 5 "H1 2023"  6 "H2 2023"  7 "H1 2024"  8 "H2 2024" ///
                 9 "H1 2025" 10 "H2 2025", angle(45) labsize(small)) ///
            legend(off) ///
            xtitle("Half-year period") ///
            ytitle("Solar share gap: Latvia – Synthetic Latvia (pp)") ///
            title("Event study: solar share (`hy_lbl' `yr')") ///
            subtitle("Red line = treatment start (`hy_lbl' `yr'); ref = `ref_lbl' `ref_yr'") ///
            note("Synthetic control DiD (Abadie et al. 2010). FE: unit + month. SE clustered at month-year level.", size(vsmall)) ///
            scheme(s2color)

        graph export "outputs/panel/solar_diff_and_diff/synthetic/event_study_solar_share_`tag'_fix_dip.png", ///
            replace width(1400) height(900)
    restore

    // ---------------------------------------------------------------
    // LaTeX table: event study coefficients (one row per half-year)
    // ---------------------------------------------------------------
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
        local d = char(36)
        tempname fh_es
        file open `fh_es' using ///
            "outputs/panel/solar_diff_and_diff/synthetic/event_study_solar_coefs_`tag'.tex", ///
            write replace
        file write `fh_es' "\begin{table}[htbp]" _n
        file write `fh_es' "\centering" _n
        file write `fh_es' "\caption{Event study: solar share gap by half-year (Latvia vs.\ Synthetic Latvia) (`hy_lbl' `yr')}" _n
        file write `fh_es' "\label{tab:event_study_`tag'}" _n
        file write `fh_es' "\begin{tabular}{lc}" _n
        file write `fh_es' "\hline\hline" _n
        file write `fh_es' "Period & Solar share gap (pp) \\" _n
        file write `fh_es' " & {\footnotesize (cluster-robust SE)} \\" _n
        file write `fh_es' "\hline" _n
        local N_rows = _N
        forvalues i = 1/`N_rows' {
            local per_val = int(period[`i'])
            local k_val   = `per_val' + 8
            if mod(`k_val', 2) == 1 {
                local per_sem "H1"
                local per_yr  = 2017 + (`k_val' - 1) / 2
            }
            else {
                local per_sem "H2"
                local per_yr  = 2016 + `k_val' / 2
            }
            local per_label "`per_sem' `per_yr'"
            if `k_val' == `ref_pos' {
                file write `fh_es' "`per_label' & 0 \\" _n
                file write `fh_es' "       & {\footnotesize \textit{(reference)}} \\" _n
            }
            else {
                local c_val  = coef[`i']
                local l95    = lb95[`i']
                local u95    = ub95[`i']
                local se_val = (`u95' - `l95') / (2 * 1.959964)
                local t_val  = abs(`c_val') / `se_val'
                if      `t_val' > 2.576 local stars "`d'^{***}`d'"
                else if `t_val' > 1.960 local stars "`d'^{**}`d'"
                else if `t_val' > 1.645 local stars "`d'^{*}`d'"
                else                    local stars ""
                local coef_str = strtrim(string(`c_val',  "%10.4f"))
                local se_str   = strtrim(string(`se_val', "%10.4f"))
                file write `fh_es' "`per_label' & `coef_str'`stars' \\" _n
                file write `fh_es' "       & (`se_str') \\" _n
            }
            if `k_val' == `pre_end' {
                file write `fh_es' "\hline" _n
            }
        }
        file write `fh_es' "\hline\hline" _n
        file write `fh_es' "\multicolumn{2}{p{0.6\linewidth}}{\footnotesize" _n
        file write `fh_es' " \textit{Note}: Synthetic control DiD (Abadie et al.\ 2010)." _n
        file write `fh_es' " Dependent variable: solar share (pp), Latvia minus Synthetic Latvia." _n
        file write `fh_es' " Reference period: `ref_lbl' `ref_yr'." _n
        file write `fh_es' " SE derived from 95\% CI; clustered at month-year level." _n
        file write `fh_es' " `d'^{***}`d' `d'p<0.01`d', `d'^{**}`d' `d'p<0.05`d', `d'^{*}`d' `d'p<0.10`d'" _n
        file write `fh_es' " (normal approximation).} \\" _n
        file write `fh_es' "\end{tabular}" _n
        file write `fh_es' "\end{table}" _n
        file close `fh_es'
        di as text "Event study table saved: outputs/panel/solar_diff_and_diff/synthetic/event_study_solar_coefs_`tag'.tex"
    restore

    di as text "Done [`tag']. Outputs in outputs/panel/solar_diff_and_diff/synthetic/"
end

// =============================================================================
// RUN 1 — Main analysis: treatment = H1 2022  (hy_seq_pos = 11)
// =============================================================================
synth_did 11

// =============================================================================
// RUN 2 — Placebo test: treatment = H2 2019  (hy_seq_pos = 6)
//   If the placebo DiD ≈ 0, it supports that the real effect is not driven
//   by pre-existing trends.
// =============================================================================

// synth_did 6

di as text ""
di as text "All done. Outputs saved to outputs/panel/solar_diff_and_diff/synthetic/"

