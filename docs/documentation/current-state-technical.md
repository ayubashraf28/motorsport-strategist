# Motorsport Strategist: Current Technical State

## 1. Executive Summary

This repository is a Godot-based racing manager prototype with an authoritative deterministic simulation core and a presentation layer.

As of `2026-02-25`, the implemented runtime baseline is effectively **V3.1**:
- V1 pace-profile mode is supported.
- V1.1 physics-derived speed-profile mode is supported.
- V2 systems are supported (standings, race state, overtaking, degradation).
- V3 systems are supported (compounds, stint tracking, fuel, pit stops, strategy requests).
- V3.1 updates are present (continuous tyre curve behavior, pit lane distance movement, richer HUD telemetry semantics).

The simulation core remains in `game/sim/src`, has no `Node` dependency, and is driven by fixed-step updates from `game/scripts/race_controller.gd`.

## 2. Repository Snapshot

Top-level layout:
- `config/`: versioned runtime configs (`race_v0.json`, `race_v1.json`, `race_v1.1.json`, `race_v2.json`, `race_v3.json`)
- `data/`: track assets and runtime data folders (`data/tracks/`, ignored `data/telemetry/`)
- `docs/`: architecture docs, ADRs, plans, and this documentation bundle
- `game/`: Godot project (runtime scripts, scenes, UI, sim code/tests)
- `sim/`: future extraction boundary for engine-agnostic simulation packages
- `tools/`: CI and helper scripts

Current repo metrics:
- Total files: `153`
- Simulation source modules (`game/sim/src`): `15`
- Simulation test suites (`game/sim/tests`): `15`
- Runtime presentation scripts (`game/scripts`): `9`

## 3. Technology Stack

- Engine/runtime: Godot `4.6.x` (`game/project.godot` uses feature `4.6`)
- Language: GDScript (runtime, sim, UI, tests)
- Test framework: GdUnit4 (headless in CI via `godot-gdunit-labs/gdUnit4-action@v1.2.2`, GdUnit version `v6.1.1`)
- Utility scripting: Python 3 stdlib (`tools/scripts/import_track.py`)
- CI/CD: GitHub Actions

No external package manager dependencies are currently used for simulation runtime logic.

## 4. Delivery History (What Has Been Done)

Recent milestones from git history:
- `9d1bd43` (`2026-02-24`): V1.1 physics-derived speed profile
- `c5374c5` (`2026-02-24`): V2 race systems + HUD
- `740090e` (`2026-02-25`): V3 foundations (degradation/fuel related expansion)
- `bfdec88` (`2026-02-25`): V3.1 tyre realism + HUD pace telemetry updates
- `5482114` (`2026-02-25`): lap snapshot telemetry logger writing to repo data folder
- `2299432` (`2026-02-25`): richer telemetry events for pit/request lifecycle + normalized v_ref in V3 config

Feature progression implemented:
- **V0**: deterministic lap timing and basic race visualization
- **V1**: pace segments with smoothing across boundaries
- **V1.1**: curvature-based physics speed profile and track asset pipeline
- **V2**: standings, finite race flow, degradation, overtaking, richer HUD
- **V3**: tyre compounds, stint tracking, fuel model, pit stop lifecycle, pit strategy requests
- **V3.1**: continuous degradation curve behavior, pit lane distance interpolation, normalized HUD pace telemetry, telemetry logging

## 5. Runtime Architecture

### 5.1 Layer Boundaries

Simulation layer (`game/sim/src`):
- Authoritative race logic and state transitions
- Deterministic calculations
- No scene tree or `Node` dependencies

Presentation layer (`game/scripts`, `game/scenes`, `game/ui`):
- Loads config and track assets
- Drives fixed-step loop
- Maps simulation distances to world coordinates
- Renders HUD and debug overlays
- Emits telemetry logs for offline analysis

### 5.2 Main Runtime Flow

1. `race_controller.gd` loads config via `RaceConfigLoader`.
2. Loader checks configs in this order:
   - `config/race_v3.json`
   - `config/race_v2.json`
   - `config/race_v1.1.json`
   - `config/race_v1.json`
3. Track init:
   - V1 path: `TrackPath` curve sampling
   - V1.1/V2/V3 path: `TrackLoader` reads geometry JSON
4. Simulator init:
   - `RaceSimulator.initialize(config, runtime_params)`
5. Frame loop:
   - `FixedStepRunner.advance(delta, time_scale, simulator.step)`
6. `RaceSimulator.step` processes chunks (up to `1/120s` chunk size):
   - Compute natural speeds (including degradation/fuel/pit handling)
   - Resolve overtaking interactions
   - Apply movement and lap-crossing updates
   - Update standings
7. Controller updates car dots + HUD and passes snapshots to lap logger.

### 5.3 Determinism Controls

- Fixed step: `1/120` seconds
- Max steps per frame: `16` (spiral-of-death guard)
- Internal integration chunking for large `dt`
- Analytic lap-crossing timestamps
- Standings based on `total_distance`

## 6. Core Modules

### 6.1 Data and Types (`race_types.gd`)

Defines:
- Config types: `RaceConfig`, `CarConfig`, `PaceProfileConfig`, `SpeedProfileConfig`, `PhysicsVehicleConfig`, `DegradationConfig`, `TyreCompoundConfig`, `FuelConfig`, `PitConfig`, `OvertakingConfig`, `DebugConfig`
- Runtime types: `RaceRuntimeParams`, `CarState`, `RaceSnapshot`, `CompletedStint`
- Enums: `RaceState`, `PitPhase`, `TyrePhase`

Key runtime fields in `CarState` include:
- Position/lifecycle: `position`, `total_distance`, `is_finished`, `finish_position`, `finish_time`
- Tyre/performance telemetry: `degradation_multiplier`, `tyre_life_ratio`, `tyre_phase`, `reference_speed_units_per_sec`, `strategy_multiplier`
- Strategy state: `current_compound`, `stint_lap_count`, `stint_number`, `is_in_pit`, `pit_phase`, `pit_time_remaining`, `pit_stops_completed`, pit targets
- Fuel/traffic: `fuel_kg`, `fuel_multiplier`, `is_held_up`, `held_up_by`

### 6.2 Race Simulator (`race_simulator.gd`)

Responsibilities:
- Input validation
- Pace-profile or speed-profile setup
- Per-step progression and lap crossing registration
- Integration with standings, race state machine, degradation, overtaking, compounds/stints, fuel, pit systems

Key behavior:
- V1 path: `effective_speed = base_speed * pace_multiplier`
- V1.1+ path: `effective_speed = sampled_physics_speed * (v_ref / v_top_speed)`
- Runtime scales by degradation and fuel multipliers
- Pit phases override movement and speed through `PitStopManager`

### 6.3 V3/V3.1 Race Systems

- `tyre_compound.gd`: compound lookup/validation
- `stint_tracker.gd`: active compound, stint lap count/number, history
- `fuel_model.gd`: consumption, refuel, mass penalty multiplier
- `pit_strategy.gd`: pending pit request state
- `pit_stop_manager.gd`: entry/stopped/exit phases, distance-based pit movement, wrap-safe lane interpolation
- `degradation_model.gd`: warmup + threshold-based tyre behavior, life/phase helpers, validation

### 6.4 Telemetry Logger

`game/scripts/lap_snapshot_logger.gd` writes JSONL telemetry to `data/telemetry` (ignored by git):
- Session markers: `session_start`, `session_end`
- Lap snapshots: `lap_start_snapshot`
- Lifecycle events: `pit_request_change`, `pit_state_change`, `pit_stop_complete`, `compound_change`, `car_finished`

Payload includes per-car race, tyre, fuel, pit, pace, and timing fields for offline analysis.

## 7. Config and Schema Support

Supported schemas:
- `"1.0"` or missing: V1 pace profile
- `"1.1"`: physics speed profile
- `"2.0"`: V1.1 + race end/degradation/overtaking
- `"3.0"`: V2 + compounds/fuel/pit strategy systems

Current runtime defaults to V3 first due loader order.

V3-specific config currently includes:
- `compounds[]` with degradation parameters (`peak`, `rate`, `min`, thresholds)
- `fuel` model config
- `pit` config with pit entry/exit/box distances and stop behavior
- Per-car `starting_compound` and `starting_fuel_kg`

## 8. Track Data Pipeline

Track source:
- TUMFTM racetrack database (Monza), LGPL-3.0 attribution documented

Pipeline:
- Script: `tools/scripts/import_track.py`
- Input (not committed): `Monza_raw.csv`
- Output (committed): `data/tracks/monza/monza_centerline.json`

Committed Monza asset metadata:
- `import_script_version`: `1.0`
- `sample_count`: `507`
- `sample_interval_units`: `3.9950794939321073`
- `track_length_units`: `2025.5053034235784`

## 9. UI/UX and Runtime Presentation

Main scene:
- `game/scenes/main.tscn`

HUD (`game/ui/race_hud.gd` + `.tscn`):
- Columns: `P`, `ID`, `Compound`, `Speed`, `Lap Count`, `Stint`, `Gap`, `Tyre`, `Fuel`, `Current Lap`, `Last Lap`, `Best Lap`
- Speed cell includes normalized pace view (`xx.x u/s | Nyy%`)
- Tyre cell shows life+phase (`NN% OPTIMAL/GRADUAL/CLIFF`)
- Supports pit strategy actions (`PIT` / `CANCEL`)
- Includes pause/reset/speed controls

Debug overlays:
- Pace overlay (V1)
- Curvature overlay (V1.1+)
- Speed profile overlay (V1.1+)
- Toggle key: `D`

## 10. Testing and Validation

### 10.1 Implemented Test Coverage

Test suites in `game/sim/tests` now cover:
- Fixed-step determinism and cap behavior
- Simulator lap timing/crossings/reset/validation
- Pace profile validation/smoothing
- Standings and interval math
- Race state transitions and finish sequencing
- Degradation behavior and validation
- Overtaking interactions and cooldowns
- Tyre compound resolution/validation
- Stint tracker behavior
- Fuel model behavior
- Pit strategy request lifecycle
- Pit stop manager movement/lifecycle
- Telemetry logger event/snapshot behavior
- Track geometry and speed profile correctness

### 10.2 CI Validation

`PR Checks / guardrails` workflow executes:
- Lint script (`tools/ci/lint.sh`): merge-marker detection
- Test script (`tools/ci/test.sh`): baseline checks, external runners if present
- Headless GdUnit suites (`res://sim/tests`)
- Build sanity script (`tools/ci/build_sanity.sh`)

### 10.3 Local Validation Notes

In this environment, `bash` and `godot` CLI are not consistently available, so full local CI parity is limited from PowerShell-only runs.

## 11. CI/CD and Release Automation

Workflows:
- `pr-checks.yml`: required guardrails on PRs to `main`
- `build-main.yml`: artifacts for `main` pushes/manual dispatch
- `release-candidate.yml`: prereleases for `rc-vX.Y.Z-N`
- `release.yml`: production releases for `vX.Y.Z`

## 12. Documentation Inventory

Existing docs in repo:
- Architecture docs (V0, V1, V1.1)
- ADRs for major technical decisions
- Implementation plans (`docs/plans/`)
- Contributing and folder-level ownership READMEs
- This current-state documentation bundle

## 13. Current Technical Risks and Gaps

1. Documentation drift remains a risk as schema and telemetry evolve quickly; cross-file updates must stay synchronized.
2. `CODEOWNERS` remains placeholder-only.
3. Local tooling friction remains for Windows-first environments without a standardized local test runner path.
4. Telemetry is rich but currently JSONL-only; no in-repo parser/report tooling is provided yet.
5. Snapshot-level analytics should treat pit laps and asynchronous lap-start timestamps carefully to avoid misclassification.

## 14. Handoff Checklist for New Engineers

1. Read this file and `current-state-business.md`.
2. Start runtime from `game/project.godot` -> `res://scenes/main.tscn`.
3. Start with `config/race_v3.json`; then verify fallback configs (`v2`, `v1.1`, `v1`).
4. Use `game/sim/src` as authoritative behavior source.
5. Use telemetry files in `data/telemetry/` for race behavior analysis (files are git-ignored by default).
