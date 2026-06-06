cls
clear

cd "/home/niks/Projects/solar-power-latvia"
do "codes/panel_regressions_countries/load_daily_data.do"

cap mkdir "outputs/panel_countries/solar_diff_and_diff/synthetic"
/* 
// Drop NL, GR, HU, PT, ES that have higher gas share than LV
drop if country == "Netherlands" | country == "Greece" | country == "Hungary" | country == "Portugal" | country == "Spain" 

// Drop countries with higher fossil share than Latvia
drop if country == "Poland" | country == "Estonia" | country == "Czechia" | country == "Germany" | country == "Romania" | country == "Bulgaria" | country == "Croatia"

drop if country == "Cyprus" // No price data to do matching */

/* Germany & 36.5\% \\
Portugal & 37.0\% \\
Romania & 37.7\% \\
Hungary & 37.8\% \\
Bulgaria & 45.3\% \\
Ireland & 46.1\% \\
Czechia & 47.7\% \\
Italy & 49.4\% \\
Netherlands & 54.2\% \\
Estonia & 64.1\% \\
Greece & 65.9\% \\
Poland & 85.6\% \\
Cyprus & 94.8\% \\ */

drop if country == "Germany" | country == "Portugal" | country == "Romania" | country == "Hungary" | ///
          country == "Bulgaria" | country == "Ireland" | country == "Czechia" | ///
          country == "Italy" | country == "Netherlands" | country == "Estonia" | ///
          country == "Greece" | country == "Poland" | country == "Cyprus"

drop if country == "Croatia" // Missing data

// =============================================================================
// BASE VARIABLE CONSTRUCTION (computed once; shared across all program calls)
// =============================================================================

gen semester   = cond(month <= 6, 1, 2)
gen hy_seq     = (year - 2021) * 2 + semester - 2
gen hy_seq_pos = hy_seq + 10
label var hy_seq_pos "Half-year (hy_seq_pos 8 = H2 2020)"

gen ln_solar_share = ln(solar_share + 1)
label var ln_solar_share "ln(solar_share + 1)"

gen fossil_share = gas_share + brown_coal_share + coal_gas_share + hard_coal_share + oil_share + oil_shale_share + peat_share
label var fossil_share "Fossil share"

// Save prepared panel and country-name lookup as globals so the program can use them
tempfile synth_panel_tmp
save `synth_panel_tmp'
global g_synth_panel "`synth_panel_tmp'"

tempfile synth_countries_tmp
preserve
    keep country_id country
    duplicates drop
    save `synth_countries_tmp'
restore
global g_synth_countries "`synth_countries_tmp'"

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

    quietly levelsof country_id if country == "Latvia", local(_lv_list)
    local lv_id : word 1 of `_lv_list'

    tempfile dp_run
    save `dp_run'

    // ---------------------------------------------------------------
    // Step 1: Half-year aggregation for synth
    // ---------------------------------------------------------------
    collapse (mean) gas_share brown_coal_share coal_gas_share hard_coal_share oil_share oil_shale_share peat_share solar_share energy_price ln_solar_share temperature sun precipitation population_density gdp_pps, ///
        by(country_id hy_seq_pos)

    gen fossil_share = gas_share + brown_coal_share + coal_gas_share + hard_coal_share + oil_share + oil_shale_share + peat_share
    label var fossil_share "Fossil share (mean, half-year)"

    // Drop donors with any missing solar_share in pre-treatment window
    bysort country_id: egen _n_miss_pre = total(missing(solar_share) & hy_seq_pos <= `pre_end')
    drop if _n_miss_pre > 0 & country_id != `lv_id'
    drop _n_miss_pre

    xtset country_id hy_seq_pos

    // Binary: country had > 0.5% mean solar share before the shock
    // Donors with effectively no solar pre-shock get penalised in matching
    bysort country_id: egen _mean_pre_solar = mean(cond(hy_seq_pos <= `pre_end', solar_share, .))
    gen high_solar_pre = (_mean_pre_solar > 0.005)
    label var high_solar_pre "Had >0.5% avg solar share pre-shock"
    drop _mean_pre_solar

    // ---------------------------------------------------------------
    // Predictor characteristics table (pre-treatment means per country)
    // ---------------------------------------------------------------
    preserve
        keep if hy_seq_pos <= `pre_end'
        collapse (mean) solar_share energy_price population_density gdp_pps sun ///
                 (max)  high_solar_pre, ///
            by(country_id)
        merge m:1 country_id using "$g_synth_countries", nogen
        sort country_id
        gen byte is_treated = (country == "Latvia")
        order country is_treated solar_share high_solar_pre energy_price population_density gdp_pps sun
        label var country            "Country"
        label var is_treated         "Treated (Latvia=1)"
        label var solar_share        "Solar share (mean, pre-treatment)"
        label var high_solar_pre     "Had >0.5% avg solar share pre-shock"
        label var energy_price       "Energy price (mean, pre-treatment)"
        label var population_density "Pop. density (mean, pre-treatment)"
        label var gdp_pps            "GDP PPS (mean, pre-treatment)"
        label var sun                "Sun radiation (mean, pre-treatment)"
        di as text ""
        di as text "=== Synth predictor characteristics by country (pre-treatment means) [`tag'] ==="
        list country is_treated solar_share high_solar_pre energy_price population_density gdp_pps sun, ///
            noobs sep(0) clean ab(26)
        /* export delimited using ///
            "outputs/panel_countries/solar_diff_and_diff/synthetic/synth_predictors_`tag'.csv", ///
            replace
        di as text "Predictor table saved: outputs/panel_countries/solar_diff_and_diff/synthetic/synth_predictors_`tag'.csv" */

        // LaTeX table: country characteristics
        tempname fh_pred
        file open `fh_pred' using ///
            "outputs/panel_countries/solar_diff_and_diff/synthetic/synth_predictors_`tag'.tex", ///
            write replace
        file write `fh_pred' "\begin{table}[htbp]" _n
        file write `fh_pred' "\centering" _n
        file write `fh_pred' "\caption{Country characteristics: pre-treatment means [`tag']}" _n
        file write `fh_pred' "\label{tab:synth_predictors_`tag'}" _n
        file write `fh_pred' "\begin{tabular}{lcccccc}" _n
        file write `fh_pred' "\hline\hline" _n
        file write `fh_pred' "Country & Treated & Solar share (\%) & Energy price & Pop.\ density & GDP PPS & Sun \\" _n
        file write `fh_pred' "\hline" _n
        local N_chars = _N
        forvalues ii = 1/`N_chars' {
            local cname = country[`ii']
            local is_tr = cond(is_treated[`ii'] == 1, "Yes", "No")
            local sol_s = strtrim(string(solar_share[`ii'] * 100, "%6.3f"))
            local ep_s  = strtrim(string(energy_price[`ii'], "%6.1f"))
            local pd_s  = strtrim(string(population_density[`ii'], "%6.1f"))
            local gd_s  = strtrim(string(gdp_pps[`ii'], "%6.1f"))
            local su_s  = strtrim(string(sun[`ii'], "%6.1f"))
            file write `fh_pred' "`cname' & `is_tr' & `sol_s' & `ep_s' & `pd_s' & `gd_s' & `su_s' \\" _n
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
        di as text "Country characteristics table saved: outputs/panel_countries/solar_diff_and_diff/synthetic/synth_predictors_`tag'.tex"
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
        customV(0.10 0.20 0.20 0.20 0.15 0.15) ///
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
    di as text "  country                  weight"
    di as text "  ---------------------- --------"
    preserve
        use "$g_synth_countries", clear
        tempname fh_wt
        file open `fh_wt' using ///
            "outputs/panel_countries/solar_diff_and_diff/synthetic/synth_weights_`tag'.tex", ///
            write replace
        file write `fh_wt' "\begin{table}[htbp]" _n
        file write `fh_wt' "\centering" _n
        file write `fh_wt' "\caption{Synthetic Latvia donor weights [`tag']}" _n
        file write `fh_wt' "\label{tab:synth_weights_`tag'}" _n
        file write `fh_wt' "\begin{tabular}{lc}" _n
        file write `fh_wt' "\hline\hline" _n
        file write `fh_wt' "Country & Weight \\" _n
        file write `fh_wt' "\hline" _n
        forvalues j = 1/`n_sc_donors' {
            quietly levelsof country if country_id == scalar(_sc_id_`j'), local(_bname)
            local _bname_str : word 1 of `_bname'
            di as text "  " %-22s "`_bname_str'" %8.4f scalar(_sc_wt_`j')
            local wt_s = strtrim(string(scalar(_sc_wt_`j'), "%6.4f"))
            file write `fh_wt' "`_bname_str' & `wt_s' \\" _n
        }
        file write `fh_wt' "\hline\hline" _n
        file write `fh_wt' "\multicolumn{2}{p{0.5\linewidth}}{\footnotesize" _n
        file write `fh_wt' " \textit{Note}: Donor weights from synthetic control (Abadie et al.\ 2010)." _n
        file write `fh_wt' " Weights sum to one; countries with zero weight are omitted by synth.} \\" _n
        file write `fh_wt' "\end{tabular}" _n
        file write `fh_wt' "\end{table}" _n
        file close `fh_wt'
        di as text "Donor weights table saved: outputs/panel_countries/solar_diff_and_diff/synthetic/synth_weights_`tag'.tex"
    restore

    // ---------------------------------------------------------------
    // Step 3: Apply weights to daily panel → synthetic series
    // ---------------------------------------------------------------
    use `dp_run', clear

    gen _synth_wt = 0
    forvalues j = 1/`n_sc_donors' {
        replace _synth_wt = scalar(_sc_wt_`j') if country_id == scalar(_sc_id_`j')
    }

    gen _wt_solar         = _synth_wt * solar_share
    gen _wt_ln_solar      = _synth_wt * ln_solar_share
    gen _wt_fossil        = _synth_wt * fossil_share
    gen _wt_temperature   = _synth_wt * temperature
    gen _wt_sun           = _synth_wt * sun
    gen _wt_precipitation = _synth_wt * precipitation
    gen _wt_ln_sun        = _synth_wt * ln_sun
    gen _wt_ln_precip     = _synth_wt * ln_precipitation

    preserve
        drop if country_id == `lv_id'
        collapse ///
            (sum)  synth_solar_share      = _wt_solar         ///
                   synth_ln_solar_share   = _wt_ln_solar       ///
                   synth_fossil_share     = _wt_fossil         ///
                   synth_temperature      = _wt_temperature    ///
                   synth_sun              = _wt_sun            ///
                   synth_precipitation    = _wt_precipitation  ///
                   synth_ln_sun           = _wt_ln_sun         ///
                   synth_ln_precipitation = _wt_ln_precip      ///
            (mean) post year month semester hy_seq hy_seq_pos day_of_week, ///
            by(date)
        tempfile _synth_series
        save `_synth_series'
    restore

    keep if country_id == `lv_id'
    merge 1:1 date using `_synth_series', nogen

    drop _synth_wt _wt_solar _wt_ln_solar _wt_fossil _wt_temperature _wt_sun ///
         _wt_precipitation _wt_ln_sun _wt_ln_precip

    // ---------------------------------------------------------------
    // Path plots: Latvia (actual) vs. Synthetic Latvia
    // ---------------------------------------------------------------
    preserve
        collapse (mean) lv_solar = solar_share sc_solar = synth_solar_share ///
                        lv_fossil   = fossil_share   sc_fossil   = synth_fossil_share, ///
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
            title("Latvia vs. synthetic: solar share [`tag']") ///
            subtitle("Red line = treatment start (`hy_lbl' `yr')") ///
            note("Synthetic control (Abadie et al. 2010).", size(vsmall)) ///
            scheme(s2color)
        graph export "outputs/panel_countries/solar_diff_and_diff/synthetic/synth_path_solar_share_`tag'.png", ///
            replace width(1400) height(900)

        // Fossil share path
        twoway ///
            (connected sc_fossil period, ///
                mcolor(gs8) lcolor(gs8) msymbol(triangle) lpattern(dash) msize(small)) ///
            (connected lv_fossil period, ///
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
            ytitle("Fossil share (half-year mean)") ///
            title("Latvia vs. synthetic: fossil share [`tag']") ///
            subtitle("Red line = treatment start (`hy_lbl' `yr')") ///
            note("Synthetic control (Abadie et al. 2010).", size(vsmall)) ///
            scheme(s2color)
        graph export "outputs/panel_countries/solar_diff_and_diff/synthetic/synth_path_fossil_share_`tag'.png", ///
            replace width(1400) height(900)
    restore

    // ---------------------------------------------------------------
    // Predictor balance: Latvia vs. Synthetic Latvia (pre-treatment)
    // ---------------------------------------------------------------
    preserve
        keep if !post
        collapse (mean) solar_share synth_solar_share ///
                        fossil_share synth_fossil_share ///
                        sun synth_sun ///
                        temperature synth_temperature ///
                        precipitation synth_precipitation
        tempname fh_bal
        file open `fh_bal' using ///
            "outputs/panel_countries/solar_diff_and_diff/synthetic/synth_balance_`tag'.tex", ///
            write replace
        file write `fh_bal' "\begin{table}[htbp]" _n
        file write `fh_bal' "\centering" _n
        file write `fh_bal' "\caption{Predictor balance: Latvia vs.\ Synthetic Latvia (pre-treatment) [`tag']}" _n
        file write `fh_bal' "\label{tab:synth_balance_`tag'}" _n
        file write `fh_bal' "\begin{tabular}{lcc}" _n
        file write `fh_bal' "\hline\hline" _n
        file write `fh_bal' "Variable & Latvia & Synthetic Latvia \\" _n
        file write `fh_bal' "\hline" _n
        local sol_lv = strtrim(string(solar_share[1]         * 100, "%6.3f"))
        local sol_sc = strtrim(string(synth_solar_share[1]   * 100, "%6.3f"))
        file write `fh_bal' "Solar share (\%) & `sol_lv' & `sol_sc' \\" _n
        local fos_lv = strtrim(string(fossil_share[1]        * 100, "%5.1f"))
        local fos_sc = strtrim(string(synth_fossil_share[1]  * 100, "%5.1f"))
        file write `fh_bal' "Fossil share (\%) & `fos_lv' & `fos_sc' \\" _n
        local sun_lv = strtrim(string(sun[1],         "%6.2f"))
        local sun_sc = strtrim(string(synth_sun[1],   "%6.2f"))
        file write `fh_bal' "Sun radiation & `sun_lv' & `sun_sc' \\" _n
        local tmp_lv = strtrim(string(temperature[1]         - 273.15, "%5.2f"))
        local tmp_sc = strtrim(string(synth_temperature[1]   - 273.15, "%5.2f"))
        file write `fh_bal' "Temperature (\ensuremath{^\circ}C) & `tmp_lv' & `tmp_sc' \\" _n
        local prc_lv = strtrim(string(precipitation[1],       "%6.2f"))
        local prc_sc = strtrim(string(synth_precipitation[1], "%6.2f"))
        file write `fh_bal' "Precipitation (mm/day) & `prc_lv' & `prc_sc' \\" _n
        file write `fh_bal' "\hline\hline" _n
        file write `fh_bal' "\multicolumn{3}{p{0.55\linewidth}}{\footnotesize" _n
        file write `fh_bal' " \textit{Note}: Daily pre-treatment means. Synthetic Latvia is the" _n
        file write `fh_bal' " donor-weighted average. Temperature converted from Kelvin.} \\" _n
        file write `fh_bal' "\end{tabular}" _n
        file write `fh_bal' "\end{table}" _n
        file close `fh_bal'
        di as text "Predictor balance table saved: outputs/panel_countries/solar_diff_and_diff/synthetic/synth_balance_`tag'.tex"
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
    replace fossil_share     = synth_fossil_share     if treated == 0
    replace temperature      = synth_temperature      if treated == 0
    replace sun              = synth_sun              if treated == 0
    replace precipitation    = synth_precipitation    if treated == 0
    replace ln_sun           = synth_ln_sun           if treated == 0
    replace ln_precipitation = synth_ln_precipitation if treated == 0

    drop synth_solar_share synth_ln_solar_share synth_fossil_share synth_temperature ///
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
        i.day_of_week i.month, vce(cluster month_year)
    eststo did_levels_`tag'
    di "DiD coef (levels, `tag'): " %9.3f _b[treated_x_post] ///
       "  SE: " %9.3f _se[treated_x_post]

    regress ln_solar_share treated_x_post treated ///
        i.day_of_week i.month, vce(cluster month_year)
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
        i.day_of_week ib`ref_pos'.hy_seq_pos, vce(cluster month_year)
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
            title("Event study: solar share [`tag']") ///
            subtitle("Red line = treatment start (`hy_lbl' `yr'); ref = `ref_lbl' `ref_yr'") ///
            note("Synthetic control DiD (Abadie et al. 2010). FE: unit + month + day-of-week." ///
                 "SE clustered at month-year level.", size(vsmall)) ///
            scheme(s2color)

        graph export "outputs/panel_countries/solar_diff_and_diff/synthetic/event_study_solar_share_`tag'.png", ///
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
        local d = char(36)
        tempname fh_es
        file open `fh_es' using ///
            "outputs/panel_countries/solar_diff_and_diff/synthetic/event_study_solar_coefs_`tag'.tex", ///
            write replace
        file write `fh_es' "\begin{table}[htbp]" _n
        file write `fh_es' "\centering" _n
        file write `fh_es' "\caption{Event study: solar share gap by half-year (Latvia vs.\ Synthetic Latvia) [`tag']}" _n
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
        di as text "Event study table saved: outputs/panel_countries/solar_diff_and_diff/synthetic/event_study_solar_coefs_`tag'.tex"
    restore

    di as text "Done [`tag']. Outputs in outputs/panel_countries/solar_diff_and_diff/synthetic/"
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

 synth_did 6

di as text ""
di as text "All done. Outputs saved to outputs/panel_countries/solar_diff_and_diff/synthetic/"

