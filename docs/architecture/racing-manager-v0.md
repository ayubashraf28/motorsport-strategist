# Racing Manager Prototype v0 Architecture

## Goal

Provide a clean foundation for a racing management game with deterministic lap timing and a single-screen visual prototype:
- top-down loop track
- cars rendered as dots
- per-car lap count, current lap, last lap, best lap

## Module boundaries

### Simulation (`game/sim/src`)

Authoritative race rules and state transitions:
- race clock progression
- distance updates by `speed * dt`
- wrap-around lap detection
- lap timing and best/last lap updates

Constraints:
- no `Node` dependencies
- no scene tree references
- no UI logic

### Presentation (`game/scenes`, `game/scripts`, `game/ui`)

Responsibilities:
- load and validate config data
- compute track polyline and track length from `Curve2D`
- run fixed-step accumulator and call `sim.step(fixed_dt)`
- map `distance_along_track` to world positions
- render HUD state and control buttons

Constraints:
- presentation does not own timing rules
- presentation reads snapshots from simulation

## Data flow

1. `race_controller.gd` loads `config/race_v0.json`.
2. `TrackSampler` bakes the `Curve2D` from `TrackPath` and computes total length.
3. Controller initializes `RaceSimulator` with:
- `RaceConfig` (cars, flags, defaults)
- `RaceRuntimeParams.track_length` from baked curve
4. Each frame:
- accumulate `delta * time_scale`
- consume fixed steps (`1/120`) with cap (`16`)
- call `RaceSimulator.step(FIXED_DT)` per fixed step
5. Controller pulls `RaceSnapshot` and updates:
- car dot positions
- HUD table values

## Determinism strategy

- use fixed-step accumulator for runtime updates
- deterministic tests use explicit dt sequences
- cap max steps per frame to avoid spiral-of-death
- emit throttled debug warning when capped

## Lap timing rules

- first lap is counted from race start (`lap_start_time = 0`)
- car crossing count in a frame is derived from distance math
- crossing timestamps are computed analytically for stable lap times
- `best_lap_time` starts as `INF`
- `last_lap_time` starts as `-1.0`

## Error and empty states

- invalid config or invalid track length: simulation does not start and HUD shows explicit error
- empty/invalid car list: HUD shows empty/error state and disables race controls

