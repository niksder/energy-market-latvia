cls
clear

cd "/home/niks/Projects/solar-power-latvia"
do "codes/panel_regressions/load_daily_data.do"

// No bzones dropped — table covers all bidding zones in the data.

cap mkdir "outputs/panel/solar_diff_and_diff/on_fossil_share"

// =============================================================================
// Compute pre-war fossil share (avg 2020) for every bzone
// =============================================================================

gen _fossil = gas_share + brown_coal_share + coal_gas_share + hard_coal_share + oil_share + oil_shale_share + peat_share
gen _tmp = _fossil if year(date) == 2020
bysort bzone_id: egen fossil_share_pre = mean(_tmp)
drop _tmp _fossil
label var fossil_share_pre "Fossil share avg 2020 (0–1)"

// =============================================================================
// LATEX TABLE: bidding zones and pre-war fossil shares (sorted ascending)
// =============================================================================
preserve
    bysort bzone_id: keep if _n == 1
    keep bzone fossil_share_pre
    sort fossil_share_pre

    // Map bzone → display label: "Country (bzone)" for sub-national, else "Country"
    gen str60 label = ""
    replace label = "Austria"                  if bzone == "Austria"
    replace label = "Belgium"                  if bzone == "Belgium"
    replace label = "Bulgaria"                 if bzone == "Bulgaria"
    replace label = "Croatia"                  if bzone == "Croatia"
    replace label = "Cyprus"                   if bzone == "Cyprus"
    replace label = "Czechia"                  if bzone == "Czechia"
    replace label = "Denmark (DK1)"            if bzone == "DK1"
    replace label = "Denmark (DK2)"            if bzone == "DK2"
    replace label = "Estonia"                  if bzone == "Estonia"
    replace label = "Finland"                  if bzone == "Finland"
    replace label = "France"                   if bzone == "France"
    replace label = "Germany"                  if bzone == "Germany"
    replace label = "Greece"                   if bzone == "Greece"
    replace label = "Hungary"                  if bzone == "Hungary"
    replace label = "Ireland"                  if bzone == "Ireland"
    replace label = "Italy (IT\_CALA)"         if bzone == "IT_CALA"
    replace label = "Italy (IT\_CNOR)"         if bzone == "IT_CNOR"
    replace label = "Italy (IT\_CSUD)"         if bzone == "IT_CSUD"
    replace label = "Italy (IT\_NORTH)"        if bzone == "IT_NORTH"
    replace label = "Italy (IT\_SACOAC)"       if bzone == "IT_SACOAC"
    replace label = "Italy (IT\_SACODC)"       if bzone == "IT_SACODC"
    replace label = "Italy (IT\_SARD)"         if bzone == "IT_SARD"
    replace label = "Italy (IT\_SICI)"         if bzone == "IT_SICI"
    replace label = "Italy (IT\_SUD)"          if bzone == "IT_SUD"
    replace label = "Latvia"                   if bzone == "Latvia"
    replace label = "Lithuania"                if bzone == "Lithuania"
    replace label = "Netherlands"              if bzone == "Netherlands"
    replace label = "Poland"                   if bzone == "Poland"
    replace label = "Portugal"                 if bzone == "Portugal"
    replace label = "Romania"                  if bzone == "Romania"
    replace label = "Slovakia"                 if bzone == "Slovakia"
    replace label = "Slovenia"                 if bzone == "Slovenia"
    replace label = "Spain"                    if bzone == "Spain"
    replace label = "Sweden (SE1)"             if bzone == "SE1"
    replace label = "Sweden (SE2)"             if bzone == "SE2"
    replace label = "Sweden (SE3)"             if bzone == "SE3"
    replace label = "Sweden (SE4)"             if bzone == "SE4"
    replace label = bzone                      if label == ""  // fallback

    tempname fh_fs
    file open `fh_fs' using ///
        "outputs/panel/solar_diff_and_diff/on_fossil_share/fossil_share_by_bzone.tex", ///
        write replace

    file write `fh_fs' "\begin{table}[htbp]" _n
    file write `fh_fs' "\centering" _n
    file write `fh_fs' "\caption{Pre-war fossil share by bidding zone (average 2020)}" _n
    file write `fh_fs' "\label{tab:fossil_share_bzone}" _n
    file write `fh_fs' "\begin{tabular}{lc}" _n
    file write `fh_fs' "\hline\hline" _n
    file write `fh_fs' "Bidding zone & Pre-war fossil share \\" _n
    file write `fh_fs' "\hline" _n

    local N_bz = _N
    forvalues i = 1/`N_bz' {
        local lbl    = label[`i']
        local fs_val = fossil_share_pre[`i']
        local fs_str = strtrim(string(`fs_val' * 100, "%5.1f"))
        file write `fh_fs' "`lbl' & `fs_str'\% \\" _n
    }

    file write `fh_fs' "\hline\hline" _n
    file write `fh_fs' "\multicolumn{2}{p{0.55\linewidth}}{\footnotesize" _n
    file write `fh_fs' " \textit{Note}: Pre-war fossil share = gas + coal + oil + peat share," _n
    file write `fh_fs' " averaged over 2020. Sorted ascending by fossil share. All bidding zones included.} \\" _n
    file write `fh_fs' "\end{tabular}" _n
    file write `fh_fs' "\end{table}" _n

    file close `fh_fs'
    di "LaTeX table saved to outputs/panel/solar_diff_and_diff/on_fossil_share/fossil_share_by_bzone.tex"
restore
