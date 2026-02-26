# game/scripts

Runtime presentation orchestration for the Godot client.

Ownership and purpose:
- `race_controller.gd`: frame loop, fixed-step driving, HUD wiring, and scene orchestration.
- `race_setup.gd`: pre-race setup flow (track, laps, fuel toggle, player team selection).
- `game_state.gd`: shared game state and schema `4.0` race-composition entry point.
- `race_config_loader.gd`: schema-aware config parsing/validation (`1.0`, `1.1`, `2.0`, `3.0`, `4.0`).
- `ai_strategy_controller.gd`: AI pit/mode decisions for non-player teams.
- `race_engineer.gd`: advisory message generation (tyres, pit windows, DRS, SC/VSC, team-order opportunities).
- `lap_snapshot_logger.gd`: additive telemetry JSONL snapshots/events.
- `team_registry.gd`: team/driver registry lookups and car/team config helpers.
- `track_sampler.gd`: baked polyline and distance-to-position mapping for the track.
- `track_loader.gd`: reads derived geometry assets and returns typed runtime data.
- `car_dot.gd`: lightweight visual representation for each simulated car.
- `pace_debug_overlay.gd`: color-coded pace profile and blend-window debug rendering.
- `curvature_debug_overlay.gd`: color-coded curvature rendering for V1.1+ track debugging.
- `speed_debug_overlay.gd`: color-coded speed-limit rendering for V1.1+ profile debugging.

Rules:
- do not place authoritative race timing or deterministic race-control rules here
- keep this layer focused on rendering, input, and bridging to `game/sim/src`
