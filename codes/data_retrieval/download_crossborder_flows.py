import requests
import os
from tenacity import sleep
from dotenv import load_dotenv

# Get evironment variables


load_dotenv()
ENTSOE_KEY = os.getenv('ENTSOE_KEY')
DATA_DIR = os.getenv('DATA_DIR')
CROSSBORDER_FLOWS_DIR = os.getenv('CROSSBORDER_FLOWS_DIR')
SLEEP_TIME = float(os.getenv('SLEEP_TIME', 0.3))

# Download crossborder flows from ENTSOE API and save to CSV file

NEIGHBORING_BIDDING_ZONES = [
    '10YLT-1001A0008Q',  # Lithuania
    '10Y1001A1001A39I',  # Estonia
    '10Y1001A1001A49F',  # Russia
]

BIDDING_ZONE_DICT = {
    '10YLV-1001A00074': 'LV',
    '10YLT-1001A0008Q': 'LT',
    '10Y1001A1001A39I': 'EE',
    '10Y1001A1001A49F': 'RU',
}

def download_crossborder_flows(year=2026, out_domain='10YLV-1001A00074', in_domain=''):
    # Define the API endpoint and parameters
    api_url = 'https://web-api.tp.entsoe.eu/api'
    params = {
        'documentType': 'A11',
        'out_Domain': out_domain,
        'in_Domain': in_domain,
        'periodStart': str(year) + '01010000',
        'periodEnd': str(year) + '12312359',
        'securityToken': ENTSOE_KEY
    }

    # Make the API request
    response = requests.get(api_url, params=params)

    # Check if the request was successful
    if response.status_code == 200:
        # Save the content to a CSV file
        file_path = os.path.join(DATA_DIR, CROSSBORDER_FLOWS_DIR, f'crossborder_flows_{year}_{BIDDING_ZONE_DICT[out_domain]}_{BIDDING_ZONE_DICT[in_domain]}.csv')
        with open(file_path, 'wb') as file:
            file.write(response.content)
        print(f'Crossborder flows for {year} downloaded successfully and saved to {file_path}')
    else:
        print(f'Failed to download crossborder flows for {year}. Status code: {response.status_code}')


years = [2020, 2021, 2022, 2023, 2024, 2025, 2026]

for year in years:
    for in_domain in NEIGHBORING_BIDDING_ZONES:
        sleep(SLEEP_TIME)  # Sleep for the specified time to avoid hitting API rate limits
        download_crossborder_flows(year, out_domain='10YLV-1001A00074', in_domain=in_domain)

    for out_domain in NEIGHBORING_BIDDING_ZONES:
        sleep(SLEEP_TIME)  # Sleep for the specified time to avoid hitting API rate limits
        download_crossborder_flows(year, out_domain=out_domain, in_domain='10YLV-1001A00074')

    