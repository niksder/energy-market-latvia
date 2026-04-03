# Energy Market in Latvia

Codes for the research project on the impact of the spike of gas prices due to Russia's invasion of Ukraine on the Latvian energy market

## Structure

- `codes` contains all the codes of the project.
  - `data_retrieval` includes codes for downloading and preprocessing of the data.
  - `helper_commands` include smaller scripts of secondary importance to the project.
- `data`, obviously, contains the data used. The folder is used by data retrieval commands to store all the intermediary downloads and processed data. Importantly, `merged_data.csv` contains the main dataset of the project with all the data in it.
  - `constants` has the data that is predownloaded and not dynamically retrieved.
- `outputs` is where graphs and other final use results are stored.

## Data Import

`codes/data_retrieval` contains all the scripts for download and conversion of data from different APIs. First, run the download scripts. Then, the conversion scripts. They will convert XML (or other) type of data into CSVs stored under `data`. The raw data will get their own folders there, while the converted ones will be in `.csv` files. 

The `merge_weather.py` script also has the extra step of merging multi-point data into a single average.

The data for natural gas futures (TTF) is not downloaded via an API but stored under `data/constants`. So are the household and non-houshold bi-yearly gas prices. Additionally `geojson` shape of Latvia is included here for the retrieval of weather data.

As a result `merged_data.csv` is generated with all the data for use in Stata or other scripts.

## Helper Commands

- `preview_weather_grid.py` is just a check of some of the coordinates used for weather data retrieval. Could be later replaced with a map generation.
- `compare_natural_gas_prices.py` matches and plots how household and non-household prices have matched the TTF futures market gas prices.
- `natural_gas_price_relationships.do` includes a regression and a scatter plot for the same relation explored in the previous script.  