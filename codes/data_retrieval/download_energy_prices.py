import requests
import os
from tenacity import sleep
from dotenv import load_dotenv

# Get evironment variables


load_dotenv()
ENTSOE_KEY = os.getenv('ENTSOE_KEY')
DATA_DIR = os.getenv('DATA_DIR')
ENERGY_PRICES_DIR = os.getenv('ENERGY_PRICES_DIR')
SLEEP_TIME = float(os.getenv('SLEEP_TIME', 0.3))

# Download energy prices from ENTSOE API and save to CSV file

def download_energy_prices(year=2026):
    # Define the API endpoint and parameters
    api_url = 'https://web-api.tp.entsoe.eu/api'
    params = {
        'documentType': 'A44',
        'out_Domain': '10YLV-1001A00074',
        'in_Domain': '10YLV-1001A00074',
        'periodStart': str(year) + '01010000',
        'periodEnd': str(year) + '12312359',
        'securityToken': ENTSOE_KEY
    }

    # Make the API request
    response = requests.get(api_url, params=params)

    # Check if the request was successful
    if response.status_code == 200:
        # Save the content to a CSV file
        file_path = os.path.join(DATA_DIR, ENERGY_PRICES_DIR, f'energy_prices_{year}.csv')
        with open(file_path, 'wb') as file:
            file.write(response.content)
        print(f'Energy prices for {year} downloaded successfully and saved to {file_path}')
    else:
        print(f'Failed to download energy prices for {year}. Status code: {response.status_code}')


years = [2020, 2021, 2022, 2023, 2024, 2025, 2026]

for year in years:
    sleep(SLEEP_TIME)  # Sleep for the specified time to avoid hitting API rate limits
    download_energy_prices(year)