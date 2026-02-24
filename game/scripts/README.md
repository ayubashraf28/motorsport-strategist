# game/scripts

Runtime presentation orchestration for the Godot client.

Ownership and purpose:
- `race_controller.gd`: frame loop, fixed-step driving, UI wiring, and scene orchestration.
- `track_sampler.gd`: baked polyline and distance-to-position mapping for the track.
- `car_dot.gd`: lightweight visual representation for each simulated car.
- `race_config_loader.gd`: JSON config parsing and validation before sim initialization.
- `pace_debug_overlay.gd`: color-coded pace profile and blend-window debug rendering.

Rules:
- do not place authoritative race timing rules here
- keep this layer focused on rendering, input, and bridging to `game/sim/src`
