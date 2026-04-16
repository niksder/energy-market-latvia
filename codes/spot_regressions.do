cls
clear

cd "/home/niks/Projects/solar-power-latvia"
do "codes/load_data.do"

*******************
*** Regressions ***
*******************

* Simple regression of effect of gas price on energy price without controls

reg ln_energy_price ln_gas_price

// scatter ln_energy_price ln_gas_price

* Add controls for time of day, day of week, and month

reg ln_energy_price ln_gas_price i.hour i.day_of_week i.month

* Add controls for weather variables

reg ln_energy_price ln_gas_price ///
    temperature wind sun ln_water_storage precipitation ///
    i.hour i.day_of_week i.month, vce(cluster date)

* Check the effect of war as a dummy

reg ln_energy_price war ///
    temperature wind sun ln_water_storage precipitation ///
    i.hour i.day_of_week i.month, vce(cluster date)
