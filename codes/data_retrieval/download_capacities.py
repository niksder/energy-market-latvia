import requests
import os
from tenacity import sleep
from dotenv import load_dotenv

# Get evironment variables


load_dotenv()
ENTSOE_KEY = os.getenv('ENTSOE_KEY')
DATA_DIR = os.getenv('DATA_DIR')
ENERGY_CAPACITIES_DIR = os.getenv('ENERGY_CAPACITIES_DIR')
SLEEP_TIME = float(os.getenv('SLEEP_TIME', 0.3))

# Download energy capacities from ENTSOE API and save to CSV file

def download_energy_capacities(year=2026, energy_type=None):
    # Define the API endpoint and parameters
    api_url = 'https://web-api.tp.entsoe.eu/api'
    params = {
        'documentType': 'A68',
        'processType': 'A33',
        'out_Domain': '10YLV-1001A00074',
        'in_Domain': '10YLV-1001A00074',
        'periodStart': str(year) + '01010000',
        'periodEnd': str(year) + '12312359',
        'psrType': energy_type,
        'securityToken': ENTSOE_KEY
    }

    # Make the API request
    response = requests.get(api_url, params=params)

    # Check if the request was successful
    if response.status_code == 200:
        # Save the content to a CSV file
        file_path = os.path.join(DATA_DIR, ENERGY_CAPACITIES_DIR, f'energy_capacities_{year}_{energy_type}.csv')
        with open(file_path, 'wb') as file:
            file.write(response.content)
        print(f'Energy capacities for {year} and energy type {energy_type} downloaded successfully and saved to {file_path}')
    else:
        print(f'Failed to download energy capacities for {year} and energy type {energy_type}. Status code: {response.status_code}')


years = [2020, 2021, 2022, 2023, 2024, 2025, 2026]

# [O] B01 = Biomass; B02 = Fossil Brown coal/Lignite; B03 = Fossil Coal-derived gas; B04 = Fossil Gas; B05 = Fossil Hard coal; B06 = Fossil Oil; B07 = Fossil Oil shale; B08 = Fossil Peat; B09 = Geothermal; B10 = Hydro Pumped Storage; B11 = Hydro Run-of-river and poundage; B12 = Hydro Water Reservoir; B13 = Marine; B14 = Nuclear; B15 = Other renewable; B16 = Solar; B17 = Waste; B18 = Wind Offshore; B19 = Wind Onshore; B20 = Other; B25 = Energy storage
energy_types = ['B01', 'B02', 'B03', 'B04', 'B05', 'B06', 'B07', 'B08', 'B09', 'B10', 'B11', 'B12', 'B13', 'B14', 'B15', 'B16', 'B17', 'B18', 'B19', 'B20', 'B25']
energy_type_names = ['Biomass', 'Fossil Brown coal/Lignite', 'Fossil Coal-derived gas', 'Fossil Gas', 'Fossil Hard coal', 'Fossil Oil', 'Fossil Oil shale', 'Fossil Peat', 'Geothermal', 'Hydro Pumped Storage', 'Hydro Run-of-river and poundage', 'Hydro Water Reservoir', 'Marine', 'Nuclear', 'Other renewable', 'Solar', 'Waste', 'Wind Offshore', 'Wind Onshore', 'Other', 'Energy storage']
energy_types_included = ['B01', 'B04', 'B11', 'B16', 'B19', 'B20']
for year in years:
    for energy_type in energy_types_included:
        sleep(SLEEP_TIME)  # Sleep for the specified time to avoid hitting API rate limits
        download_energy_capacities(year, energy_type)

