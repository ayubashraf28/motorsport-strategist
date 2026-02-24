# motorsport-strategist

Racing Manager prototype repository with deterministic simulation and Godot presentation.

## Current gameplay baseline

V1.1 is now supported with two runtime modes:
- V1 pace profile mode (`config/race_v1.json`): hand-authored pace segments.
- V1.1 physics profile mode (`config/race_v1.1.json`): speed derived from track curvature and vehicle limits.

Main project entry:
- Godot project: `game/project.godot`
- Main scene: `game/scenes/main.tscn`

## Run locally

1. Install Godot 4.6.x.
2. Open `game/project.godot`.
3. Run `res://scenes/main.tscn`.

Controls:
- `Space`: pause/resume
- `R`: reset
- `1`, `2`, `4`: simulation speed
- `D`: debug overlay cycle
  - V1.1: speed -> curvature -> off
  - V1: pace profile -> off

## Track data pipeline (V1.1)

Derived Monza geometry asset:
- `data/tracks/monza/monza_centerline.json`

Regenerate from raw CSV:
```bash
python tools/scripts/import_track.py \
  --input-csv data/tracks/monza/Monza_raw.csv \
  --output-json data/tracks/monza/monza_centerline.json \
  --sample-interval 4.0 \
  --scale 0.35
```

Only the derived JSON is committed. Raw CSV is git-ignored.

## Tests

Simulation tests live in `game/sim/tests`.

CI (`PR Checks / guardrails`) runs:
- lint checks
- baseline unit tests
- headless GdUnit suites in `res://sim/tests`

Local GdUnit run:
1. Install GdUnit4 in `game/addons/gdUnit4`.
2. Temporarily remove `game/sim/tests/.gdignore`.
3. Run suites from the GdUnit panel in Godot.
