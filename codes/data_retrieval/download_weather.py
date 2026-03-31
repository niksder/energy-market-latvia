import cdsapi
import os
import json
import csv
import zipfile
from dotenv import load_dotenv
from shapely.geometry import shape, Point
from tenacity import sleep

# Get environment variables
load_dotenv()
DATA_DIR = os.getenv('DATA_DIR')
WEATHER_DATA_DIR = os.getenv('WEATHER_DATA_DIR')
CONSTANTS_DIR = os.getenv('CONSTANTS_DIR')
SLEEP_TIME = float(os.getenv('SLEEP_TIME', 0.3))
GRID_STEP_KM = float(os.getenv('GRID_STEP_KM', 50))

# Load geojson
geojson_path = os.path.join(DATA_DIR, CONSTANTS_DIR, "latvia.geojson")
with open(geojson_path, 'r') as f:
    geojson_data = json.load(f)

# Extract polygon from geojson
polygon = shape(geojson_data['features'][0]['geometry'])

# Get bounds of polygon (minx, miny, maxx, maxy)
bounds = polygon.bounds
min_lon, min_lat, max_lon, max_lat = bounds

# Convert km to approximate degrees (1 degree ≈ 111 km)
grid_step = GRID_STEP_KM / 111.0

# Generate grid of points
grid_points = []
lon = min_lon
while lon <= max_lon:
    lat = min_lat
    while lat <= max_lat:
        point = Point(lon, lat)
        # Check if point is within the polygon
        if polygon.contains(point):
            grid_points.append((lon, lat))
        lat += grid_step
    lon += grid_step

print(f"\n{'='*60}")
print(f"Found {len(grid_points)} grid points within Latvia")
print(f"{'='*60}")
print(f"This will download {len(grid_points)} weather files (~{len(grid_points)*0.5:.1f} MB estimated)")
print(f"Estimated time: ~{len(grid_points) * 0.3 / 60:.1f} minutes (with {SLEEP_TIME}s delay between requests)\n")

# Ask for confirmation
response = input("Proceed with downloads? (yes/no): ").strip().lower()
if response != 'yes':
    print("Cancelled.")
    exit()

# Prepare variables for request
dataset = "reanalysis-era5-single-levels-timeseries"
variables = [
    "surface_solar_radiation_downwards",
    "2m_temperature",
    "total_precipitation",
    "100m_u_component_of_wind",
    "100m_v_component_of_wind"
]

# Download weather data for each point and track locations
client = cdsapi.Client()
locations_data = []

weather_output_dir = os.path.join(DATA_DIR, WEATHER_DATA_DIR)
os.makedirs(weather_output_dir, exist_ok=True)

# Download data for each point
for idx, (lon, lat) in enumerate(grid_points):
    print(f"Processing point {idx+1}/{len(grid_points)}: ({lon:.4f}, {lat:.4f})")
    
    request = {
        "variable": variables,
        "location": {"longitude": lon, "latitude": lat},
        "date": ["2020-01-01/2026-03-11"],
        "data_format": "csv"
    }
    
    # Create unique filename for each point
    point_filename = f"weather_data_{idx:04d}_{lon:.4f}_{lat:.4f}.zip"
    target = os.path.join(weather_output_dir, point_filename)
    
    try:
        result = client.retrieve(dataset, request, target)
        
        # Extract zip file
        extract_dir = os.path.join(weather_output_dir, f"point_{idx:04d}")
        with zipfile.ZipFile(target, 'r') as zip_ref:
            zip_ref.extractall(extract_dir)
        
        # Remove zip file after extraction
        os.remove(target)
        
        # Track this location
        locations_data.append({
            'point_id': idx,
            'longitude': lon,
            'latitude': lat,
            'data_directory': extract_dir,
            'data_file': point_filename
        })
        
        sleep(SLEEP_TIME)
    except Exception as e:
        print(f"Error downloading data for point ({lon:.4f}, {lat:.4f}): {e}")

# Save locations to CSV
locations_csv_path = os.path.join(weather_output_dir, "weather_locations.csv")
with open(locations_csv_path, 'w', newline='') as csvfile:
    fieldnames = ['point_id', 'longitude', 'latitude', 'data_directory', 'data_file']
    writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
    
    writer.writeheader()
    for row in locations_data:
        writer.writerow(row)

print(f"\nCompleted! Locations saved to {locations_csv_path}")
print(f"Total points processed: {len(locations_data)}")