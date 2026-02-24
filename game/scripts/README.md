# game/scripts

Runtime presentation orchestration for the Godot client.

Ownership and purpose:
- `race_controller.gd`: frame loop, fixed-step driving, UI wiring, and scene orchestration.
- `track_sampler.gd`: baked polyline and distance-to-position mapping for the track.
- `track_loader.gd`: reads derived geometry assets and returns typed runtime data.
- `car_dot.gd`: lightweight visual representation for each simulated car.
- `race_config_loader.gd`: schema-aware config parsing and validation (`1.0` and `1.1`).
- `pace_debug_overlay.gd`: color-coded pace profile and blend-window debug rendering.
- `curvature_debug_overlay.gd`: color-coded curvature rendering for V1.1 track debugging.
- `speed_debug_overlay.gd`: color-coded speed-limit rendering for V1.1 profile debugging.

Rules:
- do not place authoritative race timing rules here
- keep this layer focused on rendering, input, and bridging to `game/sim/src`
