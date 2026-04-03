clear all
set more off

* Resolve input path from common working directories.
local datafile "/home/niks/Projects/solar-power-latvia/data/natural_gas_prices_biyearly_wide.csv"
capture confirm file "`datafile'"
if _rc {
	local datafile "data/natural_gas_prices_biyearly_wide.csv"
	capture confirm file "`datafile'"
}
if _rc {
	local datafile "codes/data_retrieval/helper_commands/natural_gas_prices_biyearly_wide.csv"
	capture confirm file "`datafile'"
}
if _rc {
	local datafile "natural_gas_prices_biyearly_wide.csv"
	capture confirm file "`datafile'"
}
if _rc {
	local datafile "../../../data/natural_gas_prices_biyearly_wide.csv"
	capture confirm file "`datafile'"
}
if _rc {
	di as error "Could not find natural_gas_prices_biyearly_wide.csv"
	exit 601
}

di as text "Using input file: `datafile'"

import delimited "`datafile'", varnames(1) clear

* Convert ISO date string to Stata daily date.
gen date_stata = date(date, "YMD")
format date_stata %td

di as text ""
di as text "Regression 1: Household price on market price"
regress household_price ttf_futures_price ///
	if !missing(household_price, ttf_futures_price), vce(robust)

di as text ""
di as text "Regression 2: Non-household price on market price"
regress non_household_price ttf_futures_price ///
	if !missing(non_household_price, ttf_futures_price), vce(robust)

di as text ""
di as text "Scatter plots with fitted lines"

twoway ///
	(scatter household_price ttf_futures_price if !missing(household_price, ttf_futures_price), ///
		msymbol(circle) mcolor(navy%70) msize(medium)) ///
	(lfit household_price ttf_futures_price if !missing(household_price, ttf_futures_price), ///
		lcolor(navy) lwidth(medthick)), ///
	title("Household vs Market Price") ///
	xtitle("Market price (TTF futures, EUR/MWh)") ///
	ytitle("Household price (EUR/MWh)") ///
	legend(order(1 "Observations" 2 "Linear fit") pos(6) ring(0)) ///
	name(g_household, replace)

twoway ///
	(scatter non_household_price ttf_futures_price if !missing(non_household_price, ttf_futures_price), ///
		msymbol(circle) mcolor(forest_green%70) msize(medium)) ///
	(lfit non_household_price ttf_futures_price if !missing(non_household_price, ttf_futures_price), ///
		lcolor(forest_green) lwidth(medthick)), ///
	title("Non-household vs Market Price") ///
	xtitle("Market price (TTF futures, EUR/MWh)") ///
	ytitle("Non-household price (EUR/MWh)") ///
	legend(order(1 "Observations" 2 "Linear fit") pos(6) ring(0)) ///
	name(g_nonhousehold, replace)

graph combine g_household g_nonhousehold, cols(2) ///
	title("Bi-yearly Gas Price Relationships") ///
	name(g_combined, replace)

capture graph export "outputs/natural_gas_scatter_relationships.png", replace width(2200)
if _rc {
	capture graph export "codes/data_retrieval/helper_commands/natural_gas_scatter_relationships.png", replace width(2200)
}

