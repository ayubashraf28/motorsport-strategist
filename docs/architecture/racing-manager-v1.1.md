# Racing Manager Prototype v1.1 Architecture

## Goal

Replace hand-authored pace multipliers (V1) with a physics-derived speed profile so cars:
- slow correctly for corners based on track curvature and grip
- brake and accelerate over realistic distances
- require no manual segment tuning when adding new tracks

## Core boundary

### Simulation (`game/sim/src`)

Authoritative logic — no file I/O, no Godot Node dependencies:
- track geometry validation and curvature sampling (`track_geometry.gd`)
- physics speed profile construction and sampling (`speed_profile.gd`)
- car effective speed computation (`v_ref * speed_profile.sample_speed(distance) / v_top_speed`)
- deterministic chunk integration
- lap crossing and timing updates

### Presentation (`game/scripts`, `game/scenes`, `game/ui`)

Responsibilities:
- load `config/race_v1.1.json` and parse physics parameters
- load track geometry asset (`data/tracks/monza/monza_centerline.json`) via `TrackLoader`
- build `TrackSampler` from loaded polyline for position queries
- pass `TrackGeometryData` to sim via `RaceRuntimeParams`
- render dots and timing HUD (unchanged from V1)
- render curvature debug overlay
- render speed profile debug overlay

## Data flow

1. Controller loads config from `config/race_v1.1.json`.
2. `TrackLoader` reads `monza_centerline.json` → `TrackGeometryData` + raw polyline.
3. `TrackSampler.configure_from_polyline(polyline)` → total lap length + position queries.
4. Simulator initialises with:
   - car `v_ref` values
   - `SpeedProfileConfig` (physics params + asset path)
   - `RaceRuntimeParams` (track length + `TrackGeometryData`)
5. `SpeedProfile.configure(geometry, physics)` runs the physics algorithm:
   - compute corner speed limits from curvature
   - forward pass (acceleration constraint)
   - backward pass (braking constraint)
   - store final `v_profile` array
6. Runtime loop (unchanged structure):
   - fixed-step runner drives `sim.step(fixed_dt)` at 1/120 s chunks
   - per chunk: `speed = speed_profile.sample_speed(distance) * (v_ref / v_top_speed)`
   - controller maps distance to world position and updates HUD/overlays

## Physics model (Level B)

### Corner speed limit

```
v_corner(s) = min(sqrt(a_lat_max / max(|κ(s)|, ε)), v_top_speed)
```

Where `κ(s)` is the curvature at distance `s` (stored in `TrackGeometryData`).

### Braking and acceleration (forward/backward pass)

Iterated twice around the circular track array to satisfy loop boundary condition:

```
Forward:  v_fwd[i+1] = min(v_corner[i+1], sqrt(v_fwd[i]² + 2 · a_long_accel · ds))
Backward: v_bwd[i-1] = min(v_corner[i-1], sqrt(v_bwd[i]² + 2 · a_long_brake · ds))
Final:    v[i]        = min(v_corner[i], v_fwd[i], v_bwd[i])
```

### Per-car scaling

```
effective_speed = speed_profile.sample_speed(distance) * (v_ref / v_top_speed)
```

`v_ref` is the car's reference speed — the speed it would achieve on a flat straight. Lower `v_ref` uniformly scales the physics profile down. The cornering shape is identical across all cars; only the scale differs.

## Track asset pipeline

```
TUMFTM Monza.csv (LGPL-3.0, not committed)
        ↓
tools/scripts/import_track.py
        ↓
data/tracks/monza/monza_centerline.json  (committed, derived asset)
        ↓
TrackLoader (presentation layer, runtime)
        ↓
TrackGeometryData (positions + curvatures)  →  SpeedProfile (sim layer)
PackedVector2Array (polyline)               →  TrackSampler (presentation layer)
```

## Config schema version routing

`RaceConfigLoader` checks `schema_version`:
- absent or `"1.0"` → V1 parse path (`PaceProfileConfig`, pace segments)
- `"1.1"` → V1.1 parse path (`SpeedProfileConfig`, physics params)

V1 and V1.1 configs co-exist. The simulator branches on the type of `RaceConfig.track`.

## Debug overlays

| Overlay | Data source | Color meaning |
|---|---|---|
| Pace profile (V1) | `Array[PaceSegmentConfig]` | multiplier threshold |
| Curvature | `TrackGeometryData.curvatures` | high κ = red, low κ = green |
| Speed limit | `SpeedProfile.get_speed_array()` | low speed = red, high speed = green |

D key cycles: curvature → speed → off → curvature.

## Failure handling

Invalid V1.1 config examples:
- missing or empty `geometry_asset`
- non-positive physics parameters
- `TrackGeometryData` curvature array length mismatch
- null geometry in `RaceRuntimeParams` for a V1.1 config

Behaviour:
- simulator does not start
- HUD shows explicit validation errors
- all controls disabled

## Determinism notes

- speed profile is computed once at initialisation from fixed config + geometry data
- `sample_speed` is pure interpolation on a fixed array — same input, same output
- curvature values are pre-computed in the import script, not recalculated at runtime
- fixed-step loop and chunk integration unchanged from V1
