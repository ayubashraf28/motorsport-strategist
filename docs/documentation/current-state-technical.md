# Motorsport Strategist: Current Technical State

## 1. Executive Summary

This repository is a Godot-based racing manager prototype with an authoritative deterministic simulation core and a presentation layer.

As of `2026-02-26`, the implemented runtime baseline is effectively **V3.2**:
- V1 pace-profile mode is supported.
- V1.1 physics-derived speed-profile mode is supported.
- V2 systems are supported (standings, race state, overtaking, degradation).
- V3 systems are supported (compounds, stint tracking, fuel, pit stops, strategy requests).
- V3.1 updates are present (continuous tyre curve behavior, pit lane distance movement, telemetry logging).
- V3.2 updates are present (full game flow with menus, F1-style timing tower HUD, track auto-fit/rotation, AI strategy controller, multi-track support with 5 circuits, team registry).

The simulation core remains in `game/sim/src`, has no `Node` dependency, and is driven by fixed-step updates from `game/scripts/race_controller.gd`.

## 2. Repository Snapshot

Top-level layout:
- `config/`: versioned runtime configs (`race_v0.json` through `race_v3.json`), `teams.json`, `tracks/` directory with per-track config
- `data/`: track geometry assets (`data/tracks/{monza,spa,silverstone,suzuka,interlagos}/`) and runtime telemetry (`data/telemetry/`, git-ignored)
- `docs/`: architecture docs, ADRs, plans, and this documentation bundle
- `game/`: Godot project (runtime scripts, scenes, UI, sim code/tests)
- `sim/`: future extraction boundary for engine-agnostic simulation packages
- `tools/`: CI and helper scripts

Current repo metrics:
- Simulation source modules (`game/sim/src`): `15`
- Simulation test suites (`game/sim/tests`): `15`
- Runtime presentation scripts (`game/scripts`): `16` (up from 9; includes game flow, registries, AI strategy)
- Game scenes (`game/scenes`): `4` (`main_menu`, `race_setup`, `main`, `results`)

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
- **V3.1**: continuous degradation curve behavior, pit lane distance interpolation, telemetry logging
- **V3.2**: full game flow (main menu → race setup → race → results), F1-style timing tower HUD with cycling data modes, TrackView layer separation, auto-fit track rotation/scaling, AI strategy controller, team/track registries, multi-track support (5 circuits), 8-car grid

## 5. Runtime Architecture

### 5.1 Layer Boundaries

Simulation layer (`game/sim/src`):
- Authoritative race logic and state transitions
- Deterministic calculations
- No scene tree or `Node` dependencies

Game flow layer (`game/scripts`, `game/scenes`):
- `GameState` autoload singleton carries config between scenes
- Scene flow: `main_menu.tscn` → `race_setup.tscn` → `main.tscn` → `results.tscn`
- `TeamRegistry` and `TrackRegistry` provide data lookups from JSON configs

Presentation layer (`game/scripts`, `game/scenes`, `game/ui`):
- Loads config and track assets
- Drives fixed-step loop
- Maps simulation distances to world coordinates via `TrackView` layer
- Renders F1-style timing tower HUD on independent `CanvasLayer`
- Emits telemetry logs for offline analysis

### 5.2 Scene Architecture

The main race scene (`main.tscn`) separates track rendering from UI:

```
Main (Node2D) — race_controller.gd
  TrackView (Node2D) — single transform for rotation/scale/position
    TrackPath (Path2D)
    TrackLine (Line2D)
    PaceDebugOverlay / CurvatureDebugOverlay / SpeedDebugOverlay
    StartFinishMarker (Line2D)
    CarsLayer (Node2D)
  HudLayer (CanvasLayer) — independent of TrackView transform
    RaceHud
```

`TrackView` is auto-fitted after track load: the algorithm computes the polyline bounding box, tests 0° vs 90° rotation, picks the orientation that best fills the available viewport area (excluding HUD regions), and applies uniform scale + position.

### 5.3 Main Runtime Flow

1. Player navigates main menu → race setup (track/team selection) → race scene.
2. `GameState` autoload carries `active_config`, `car_colors`, `ai_thresholds`, and `track_geometry_asset_path` to the race scene.
3. `race_controller.gd` loads config from `GameState` (or falls back to disk for editor debugging).
4. Track init:
   - V1 path: `TrackPath` curve sampling
   - V1.1+ path: `TrackLoader` reads geometry JSON from `data/tracks/`
5. Track auto-fit: `_fit_track_to_viewport()` rotates/scales/centers `TrackView` to fill available viewport area.
6. Simulator init:
   - `RaceSimulator.initialize(config, runtime_params)`
7. AI strategy init: `AiStrategyController` configured with per-car pit thresholds and available compounds.
8. Frame loop:
   - `FixedStepRunner.advance(delta, time_scale, simulator.step)`
   - AI strategy evaluates each snapshot for pit decisions
9. `RaceSimulator.step` processes chunks (up to `1/120s` chunk size):
   - Compute natural speeds (including degradation/fuel/pit handling)
   - Resolve overtaking interactions
   - Apply movement and lap-crossing updates
   - Update standings
10. Controller updates car dots + HUD and passes snapshots to lap logger.
11. On race finish, results are stored in `GameState` and player can navigate to results screen.

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

### 6.4 Game Flow and Registries

- `game_state.gd`: autoload singleton that carries race config, car colors, AI thresholds, and race results between scenes
- `main_menu.gd`: main menu scene controller
- `race_setup.gd`: race setup screen (track/team selection, grid configuration)
- `results_screen.gd`: post-race results display
- `team_registry.gd`: loads team definitions from `config/teams.json` (team names, car IDs, colors)
- `track_registry.gd`: discovers available tracks from `config/tracks/` and `data/tracks/` directories

### 6.5 AI Strategy Controller

`game/scripts/ai_strategy_controller.gd`:
- Evaluates each race snapshot for AI-controlled cars
- Triggers pit stop requests when tyre life drops below per-car thresholds
- Cycles through available compounds on each stop
- Configurable thresholds passed from `GameState` or defaulted per-car

### 6.6 Telemetry Logger

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
- TUMFTM racetrack database, LGPL-3.0 attribution documented

Pipeline:
- Script: `tools/scripts/import_track.py`
- Input (not committed): raw CSV from racetrack database
- Output (committed): `data/tracks/{track_name}/{track_name}_centerline.json`

Committed track assets (5 circuits):

| Track | Directory | Samples |
|-------|-----------|---------|
| Monza | `data/tracks/monza/` | 507 |
| Spa-Francorchamps | `data/tracks/spa/` | varies |
| Silverstone | `data/tracks/silverstone/` | varies |
| Suzuka | `data/tracks/suzuka/` | varies |
| Interlagos | `data/tracks/interlagos/` | varies |

Track auto-fit at runtime:
- `_fit_track_to_viewport()` in `race_controller.gd` computes the polyline bounding box
- Tests 0° and 90° rotation, picks whichever fills the available viewport area better
- Applies uniform scale at 90% fill with padding
- Centers the track in the viewport area to the right of the timing tower

## 9. UI/UX and Runtime Presentation

### 9.1 Game Flow Scenes

- `game/scenes/main_menu.tscn`: entry point, navigate to race setup
- `game/scenes/race_setup.tscn`: track and team selection, grid configuration
- `game/scenes/main.tscn`: race scene with track rendering and HUD
- `game/scenes/results.tscn`: post-race results display with finish order

### 9.2 Race HUD — F1-Style Timing Tower

The HUD (`game/ui/race_hud.gd` + `.tscn`) uses an F1 Manager-inspired design:

**Timing tower** (left side, semi-transparent dark panel with rounded corners):
- Each row: position number | team color bar | driver code | single data value | pit button
- Data column cycles through modes via `<` / `>` arrow buttons in the header:

| Mode | Shows | Example |
|------|-------|---------|
| INTERVAL | Gap to car ahead | `+1.3` |
| LAST LAP | Last lap time | `1:32.45` |
| TYRE | Compound + life % | `S 72%` |
| FUEL | Fuel remaining | `85.2 kg` |

- TYRE mode only visible when pit stops are enabled
- FUEL mode only visible when fuel simulation is enabled
- Compound letters color-coded: red (S), yellow (M), white (H)
- Low fuel (<15% capacity) turns red
- Tower auto-sizes height to fit the actual car count
- Pit button per row: `P` to request pit, `X` to cancel pending request

**Bottom bar** (full-width, semi-transparent dark panel):
- Race status: lap counter, time scale, race clock
- Controls: Pause/Resume, Reset, 1x/2x/4x speed
- Post-race: Results and Main Menu buttons appear on race finish

**Styling**:
- Panel backgrounds: `rgba(0.08, 0.09, 0.12, 0.88)` with 6px rounded corners
- Position numbers and gap values use subdued colors for visual hierarchy
- Driver names use team colors for identification

### 9.3 Debug Overlays

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
2. Start runtime from `game/project.godot` — entry point is `res://scenes/main_menu.tscn` (main menu → race setup → race).
3. For direct race debugging in editor, `res://scenes/main.tscn` falls back to disk config loading (`config/race_v3.json` → `v2` → `v1.1` → `v1`).
4. Use `game/sim/src` as authoritative behavior source.
5. Use telemetry files in `data/telemetry/` for race behavior analysis (files are git-ignored by default).
6. Team data lives in `config/teams.json`; track geometry assets in `data/tracks/{track_name}/`.
