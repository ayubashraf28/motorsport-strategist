# motorsport-strategist

Production-ready repository bootstrap for a `main` + environments workflow.

## Racing Manager Prototype v0

The repository now includes a runnable Godot 4.5 prototype:
- closed-loop 2D track
- cars represented as moving dots
- per-car lap count, current lap, last lap, and best lap timing
- pause/reset/time-scale controls (`1x`, `2x`, `4x`)

Main project entry:
- Godot project: `game/project.godot`
- Main scene: `game/scenes/main.tscn`

Runtime config:
- `config/race_v0.json`
- Track length is derived from the track `Curve2D` bake at runtime.

### v0 customization

How to edit the track curve:
1. Open `game/project.godot`.
2. Open `res://scenes/main.tscn`.
3. Select the `TrackPath` node and edit its `Curve2D` points in the inspector/2D editor.
4. Run scene; track length and lap timing use the baked curve length automatically.

How to add/remove cars:
1. Edit `config/race_v0.json`.
2. Add/remove entries in `cars`.
3. Ensure each car has unique `id` and `speed_units_per_sec > 0`.

Where the sim logic lives:
- authoritative deterministic simulation: `game/sim/src`
- simulation tests: `game/sim/tests`
- presentation bridge: `game/scripts/race_controller.gd`

### Local run

1. Install Godot 4.5.x.
2. Open `game/project.godot`.
3. Run `res://scenes/main.tscn`.

### Tests

- Deterministic simulation tests live in `game/sim/tests`.
- CI runs them headlessly via GdUnit4 in `PR Checks / guardrails`.
- Local invocation:
1. Install Godot 4.5.x.
2. Install GdUnit4 into `game/addons/gdUnit4` (local only, not committed).
3. Temporarily remove `game/sim/tests/.gdignore`.
4. Open `game/project.godot` and run the test suites under `res://sim/tests` from the GdUnit panel.

## Branching and release model

- `main`: always releasable, protected branch
- Feature branches: `feat/*`, `fix/*`, `chore/*`
- UAT candidates: tags `rc-vX.Y.Z-N` from `main`
- Production releases: tags `vX.Y.Z` from `main`

## Environments

- `dev`: build artifacts for internal testing on every merge to `main`
- `uat`: release candidate artifacts from `rc-vX.Y.Z-N` tags
- `prod`: stable release artifacts from `v*` tags

## Repository layout

- `sim/`: deterministic simulation logic and tests
- `game/`: Godot project and assets
- `tools/`: CI helpers and local automation scripts
- `docs/`: architecture notes, ADRs, and UI/UX standards
- `config/`: shared configuration templates and environment examples
- `AGENTS.md`: repository working rules for future implementation
