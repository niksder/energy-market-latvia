import os
import json
from dotenv import load_dotenv
from shapely.geometry import shape, Point

# Get environment variables
load_dotenv()
DATA_DIR = os.getenv('DATA_DIR')
CONSTANTS_DIR = os.getenv('CONSTANTS_DIR')
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

print(f"\n{'='*60}")
print(f"Latvia Bounding Box:")
print(f"  Longitude: {min_lon:.4f} to {max_lon:.4f}")
print(f"  Latitude:  {min_lat:.4f} to {max_lat:.4f}")
print(f"{'='*60}\n")

# Convert km to approximate degrees (1 degree ≈ 111 km)
grid_step = GRID_STEP_KM / 111.0

print(f"Grid step: {grid_step:.6f}° (approximately {GRID_STEP_KM} km)\n")

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

print(f"{'='*60}")
print(f"Total grid points within Latvia: {len(grid_points)}")
print(f"{'='*60}\n")

# Show first and last few points
if len(grid_points) > 0:
    print("First 5 points:")
    for i, (lon, lat) in enumerate(grid_points[:5]):
        print(f"  {i}: ({lon:.4f}, {lat:.4f})")
    
    if len(grid_points) > 10:
        print("  ...")
    
    print("Last 5 points:")
    for i, (lon, lat) in enumerate(grid_points[-5:], start=len(grid_points)-5):
        print(f"  {i}: ({lon:.4f}, {lat:.4f})")
    
    print(f"\n✓ Ready to download {len(grid_points)} weather files")
    print("  Run: python download_weather.py")
