cls
clear

cd "/home/niks/Projects/solar-power-latvia"
do "codes/panel_regressions_countries/load_daily_data.do"

// No countries dropped - table covers all countries in the data.

cap mkdir "outputs/panel_countries/solar_diff_and_diff/on_fossil_share"

// =============================================================================
// Compute pre-war fossil share (avg 2020) for every country
// =============================================================================

gen _fossil = gas_share + brown_coal_share + coal_gas_share + hard_coal_share + oil_share + oil_shale_share + peat_share
gen _tmp = _fossil if year(date) == 2020
bysort country_id: egen fossil_share_pre = mean(_tmp)
drop _tmp _fossil
label var fossil_share_pre "Fossil share avg 2020 (0–1)"

// =============================================================================
// LATEX TABLE: countries and pre-war fossil shares (sorted ascending)
// =============================================================================
preserve
    bysort country_id: keep if _n == 1
    keep country fossil_share_pre
    sort fossil_share_pre

    tempname fh_fs
    file open `fh_fs' using ///
        "outputs/panel_countries/solar_diff_and_diff/on_fossil_share/fossil_share_by_country.tex", ///
        write replace

    file write `fh_fs' "\begin{table}[htbp]" _n
    file write `fh_fs' "\centering" _n
    file write `fh_fs' "\caption{Pre-war fossil share by country (average 2020)}" _n
    file write `fh_fs' "\label{tab:fossil_share_country}" _n
    file write `fh_fs' "\begin{tabular}{lc}" _n
    file write `fh_fs' "\hline\hline" _n
    file write `fh_fs' "Country & Pre-war fossil share \\" _n
    file write `fh_fs' "\hline" _n

    local N_c = _N
    forvalues i = 1/`N_c' {
        local lbl    = country[`i']
        local fs_val = fossil_share_pre[`i']
        local fs_str = strtrim(string(`fs_val' * 100, "%5.1f"))
        file write `fh_fs' "`lbl' & `fs_str'\% \\" _n
    }

    file write `fh_fs' "\hline\hline" _n
    file write `fh_fs' "\multicolumn{2}{p{0.55\linewidth}}{\footnotesize" _n
    file write `fh_fs' " \textit{Note}: Pre-war fossil share = gas + coal + oil + peat share," _n
    file write `fh_fs' " averaged over 2020. Sorted ascending by fossil share. All countries included.} \\" _n
    file write `fh_fs' "\end{tabular}" _n
    file write `fh_fs' "\end{table}" _n

    file close `fh_fs'
    di "LaTeX table saved to outputs/panel_countries/solar_diff_and_diff/on_fossil_share/fossil_share_by_country.tex"
restore
