# Motorsport Strategist: Current Technical State

## 1. Executive Summary

This repository is a Godot-based racing manager prototype with an authoritative deterministic simulation layer and a presentation layer.

As of `2026-02-25`, the implemented runtime baseline is effectively **V2**:
- V1 pace-profile mode is still supported.
- V1.1 physics-derived speed-profile mode is still supported.
- V2 adds live standings, finite race state, degradation, overtaking, and updated HUD behavior.

The simulation core is in `game/sim/src`, remains `Node`-free, and is driven via fixed-step updates from `game/scripts/race_controller.gd`.

## 2. Repository Snapshot

Top-level layout:
- `config/`: versioned runtime configs (`race_v0.json`, `race_v1.json`, `race_v1.1.json`, `race_v2.json`)
- `data/`: derived runtime assets (`data/tracks/monza/monza_centerline.json`)
- `docs/`: architecture docs, ADRs, plans, and this documentation bundle
- `game/`: Godot project (runtime scripts, scenes, UI, sim code/tests)
- `sim/`: future extraction boundary for engine-agnostic simulation packages
- `tools/`: CI and helper scripts

Current repo metrics:
- Total files: `126`
- Simulation source modules (`game/sim/src`): `10`
- Simulation test suites (`game/sim/tests`): `9`
- Runtime presentation scripts (`game/scripts`): `8`

## 3. Technology Stack

- Engine/runtime: Godot `4.6.x` (`game/project.godot` uses feature `4.6`)
- Language: GDScript (runtime, sim, UI, tests)
- Test framework: GdUnit4 (headless in CI via `godot-gdunit-labs/gdUnit4-action@v1.2.2`, GdUnit version `v6.1.1`)
- Utility scripting: Python 3 stdlib (`tools/scripts/import_track.py`)
- CI/CD: GitHub Actions

No external package manager dependencies are currently used for sim runtime logic.

## 4. Delivery History (What Has Been Done)

Recent delivery milestones from git history:
- `a88fdea` (`2026-02-24`): repository bootstrap
- `a8b4e7d` (`2026-02-24`): migration to `main` and environment-based delivery flow
- `44eb991` (`2026-02-24`): CI hardening, artifact naming, RC tag policy
- `e88c790` (`2026-02-24`): production-ready structure baseline
- `9d1bd43` (`2026-02-24`): V1.1 physics-derived speed profile implementation
- `c5374c5` (`2026-02-24`): V2 race systems + HUD implementation

Feature progression implemented:
- **V0**: deterministic lap timing and basic race visualization (constant speeds)
- **V1**: pace segments with smoothing across boundaries
- **V1.1**: curvature-based physics speed profile and real track asset pipeline
- **V2**: standings, race end state machine, degradation model, overtaking manager, richer HUD

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

### 5.2 Main Runtime Flow

1. `race_controller.gd` loads config using `RaceConfigLoader`.
2. Loader checks config files in order:
   - `config/race_v2.json`
   - `config/race_v1.1.json`
   - `config/race_v1.json`
3. Track initialization:
   - V1 path: `TrackPath` curve sampling
   - V1.1/V2 path: `TrackLoader` reads geometry JSON and provides polyline + typed geometry
4. Simulator initialization:
   - `RaceSimulator.initialize(config, runtime_params)`
5. Frame loop:
   - `FixedStepRunner.advance(delta, time_scale, simulator.step)`
6. `RaceSimulator.step` processes chunks (up to `1/120s` integration chunks) in four phases:
   - Compute natural speeds
   - Resolve overtaking interactions (if enabled)
   - Apply movement and lap crossings
   - Update standings
7. Controller pulls snapshot and updates car dots + HUD.

### 5.3 Determinism Controls

- Fixed step: `1/120` seconds
- Max steps per frame: `16` (spiral-of-death guard)
- Internal integration chunking for large `dt`
- Analytic lap crossing timestamps for stable lap-time math
- Standings based on `total_distance` (not wrapped lap-local distance)

## 6. Core Modules

### 6.1 Data and Types (`race_types.gd`)

Defines:
- Config types: `RaceConfig`, `CarConfig`, `PaceProfileConfig`, `SpeedProfileConfig`, `PhysicsVehicleConfig`, `DegradationConfig`, `OvertakingConfig`, `DebugConfig`
- Runtime types: `RaceRuntimeParams`, `CarState`, `RaceSnapshot`
- Race state enum: `NOT_STARTED`, `RUNNING`, `FINISHING`, `FINISHED`

Key V2 runtime fields in `CarState`:
- Positioning: `position`, `total_distance`
- Finish state: `is_finished`, `finish_position`, `finish_time`
- Performance state: `degradation_multiplier`, `is_held_up`, `held_up_by`

### 6.2 Race Simulator (`race_simulator.gd`)

Responsibilities:
- Validation of config/runtime inputs
- Pace-profile or speed-profile setup
- Per-step progression and lap crossing registration
- Integration with standings, race state machine, degradation, overtaking

Important behavior:
- V1 path: `effective_speed = base_speed * pace_multiplier`
- V1.1/V2 path: `effective_speed = sampled_physics_speed * (v_ref / v_top_speed)`
- Degradation then scales speed and clamps to floor `0.001`

### 6.3 Pace Profile (`pace_profile.gd`)

- Validates segment continuity and coverage
- Uses smoothstep blending around segment boundaries
- Supports deterministic multiplier sampling around closed loop

### 6.4 Track Geometry and Speed Profile

`track_geometry.gd`:
- Validates geometry payloads
- Can derive sampled curvature from synthetic polylines (test support)

`speed_profile.gd`:
- Builds `v_corner` from curvature and lateral acceleration
- Applies forward acceleration and backward braking constraints
- Produces sampled speed array with interpolation support

### 6.5 V2 Race Systems

`standings_calculator.gd`:
- Assigns 1-based race positions by descending `total_distance`
- Computes interval-to-car-ahead distances

`race_state_machine.gd`:
- Handles race lifecycle and finish order
- Supports unlimited (`total_laps <= 0`) and finite race lengths

`degradation_model.gd`:
- Stateless warmup/peak/degrade multiplier model
- Config validation for range constraints

`overtaking_manager.gd`:
- Proximity + threshold-based interaction model
- Held-up behavior and per-pair cooldown system

## 7. Config and Schema Support

Supported schemas:
- `"1.0"` or missing `schema_version`: V1 pace profile
- `"1.1"`: physics speed profile
- `"2.0"`: V1.1 + race end, degradation, overtaking

Config routing currently defaults to V2-first loading.

Note:
- `config/race_v0.json` still exists, but loader fallback does not include it.

## 8. Track Data Pipeline

Track source:
- TUMFTM racetrack database (Monza), LGPL-3.0 attribution documented

Pipeline:
- Script: `tools/scripts/import_track.py`
- Input (not committed): `Monza_raw.csv`
- Output (committed): `data/tracks/monza/monza_centerline.json`

Current committed Monza asset metadata:
- `import_script_version`: `1.0`
- `sample_count`: `507`
- `sample_interval_units`: `3.9950794939321073`
- `track_length_units`: `2025.5053034235784`

## 9. UI/UX and Runtime Presentation

Main scene:
- `game/scenes/main.tscn`

HUD (`game/ui/race_hud.gd` + `.tscn`):
- Columns: `P`, `Car ID`, `Speed`, `Laps`, `Gap`, `Deg`, `Current Lap`, `Last Lap`, `Best Lap`
- Shows race status (`Running`, `Finishing...`, `Race Over`)
- Handles Pause, Reset, and speed selection (`1x`, `2x`, `4x`)
- Displays held-up indicator in speed cell (`[H]`)
- Displays finish deltas for completed cars

Debug overlays:
- Pace overlay (V1)
- Curvature overlay (V1.1/V2)
- Speed profile overlay (V1.1/V2)
- Toggle key: `D`

## 10. Testing and Validation

### 10.1 Implemented Test Coverage

Test suites under `game/sim/tests` cover:
- Fixed-step determinism and cap behavior
- Race simulator lap timing/crossings/reset/validation
- Pace profile validation and smoothing continuity
- Standings and interval math
- Race state transitions and finish sequencing
- Degradation math and validation
- Overtaking interactions, trains, cooldown logic
- Track geometry curvature validity
- Physics speed profile correctness/determinism

### 10.2 CI Validation

`PR Checks / guardrails` workflow executes:
- Lint script (`tools/ci/lint.sh`): merge-marker detection
- Test script (`tools/ci/test.sh`): baseline checks, external sim runners if present
- GdUnit4 simulation tests in headless Godot (`res://sim/tests`)
- Build sanity script (`tools/ci/build_sanity.sh`)

### 10.3 Local Validation Notes

In this environment, `bash` is unavailable, so shell scripts could not run directly via `bash`.
Equivalent baseline checks were run in PowerShell:
- Merge-marker scan: pass
- Required directories (`sim`, `game`, `tools`): pass
- Local sim runner detection: no local Python/Node sim runner configured (GdUnit runs in CI)

## 11. CI/CD and Release Automation

Workflows:
- `pr-checks.yml`: required guardrails on PRs to `main`
- `build-main.yml`: artifacts for `main` pushes / manual dispatch (dev environment)
- `release-candidate.yml`: UAT prereleases for tags matching `rc-vX.Y.Z-N`
- `release.yml`: production releases for tags matching `v*`

Artifact strategy:
- Source snapshot zip artifacts generated with metadata
- Retention: 14 days (dev), 30 days (RC), 90 days (prod)

## 12. Documentation Inventory Already Delivered

Existing docs already in repo:
- Architecture: v0, v1, v1.1 docs
- ADRs: v0 placement, v1 smoothing, v1.1 physics profile
- Plans: v1.1 and v2 implementation plans
- Contributing, folder-level ownership READMEs

## 13. Current Technical Risks and Gaps

1. Root `README.md` still describes V1.1 as baseline and should be updated to reflect V2-first runtime.
2. `CODEOWNERS` is placeholder-only; ownership enforcement is not configured in practice.
3. Local test scripts assume `bash`; Windows-only developer environments need PowerShell equivalents or documented prerequisites.
4. CI linting is minimal (merge-marker scan only), with no static analysis/type/style gates yet.
5. No tags currently exist in the repository (`git tag --list` empty), despite release workflow readiness.

## 14. Handoff Checklist for New Engineers

1. Read this file and `current-state-business.md`.
2. Read `docs/architecture/` and `docs/adr/` in order.
3. Start runtime from `game/project.godot` -> `res://scenes/main.tscn`.
4. Start with `config/race_v2.json`; then test fallback configs (`v1.1`, `v1`).
5. Use `game/sim/src` as authoritative behavior source; keep presentation logic in `game/scripts` and `game/ui`.
