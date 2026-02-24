# Monza Track Asset

This folder contains the derived Monza centerline geometry used by V1.1.

Source:
- Dataset: `TUMFTM/racetrack-database`
- File: `Monza.csv`
- License: LGPL-3.0

Repository link:
- https://github.com/TUMFTM/racetrack-database

Import pipeline:
1. Obtain `Monza.csv` from the source repository (not committed here).
2. Run:
   - `python tools/scripts/import_track.py --input-csv data/tracks/monza/Monza_raw.csv --output-json data/tracks/monza/monza_centerline.json --sample-interval 4.0 --scale 0.35`
3. Commit only `monza_centerline.json`.

Notes:
- `Monza_raw.csv` is intentionally git-ignored.
- Geometry is centered, Y-flipped for Godot convention, scaled at import time,
  and uniformly resampled.
