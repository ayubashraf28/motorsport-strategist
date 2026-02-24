# game/sim/src

Pure deterministic race simulation logic.

Constraints:
- no `Node` dependencies
- no scene/UI references
- deterministic state transitions given config and fixed dt input

Current modules:
- `race_types.gd`: typed config/state/snapshot models
- `race_simulator.gd`: race clock, distance update, and lap timing rules
- `standings_calculator.gd`: authoritative per-step position ordering and interval math
- `race_state_machine.gd`: lap-based race state transitions and finish order tracking
- `degradation_model.gd`: stateless warmup/peak/degradation multiplier computation
- `overtaking_manager.gd`: proximity-threshold interaction and cooldown handling
- `fixed_step_runner.gd`: deterministic accumulator helper used by presentation
- `pace_profile.gd`: deterministic track pace profile validation and smooth sampling
- `track_geometry.gd`: geometry validation/resampling and curvature computation helpers
- `speed_profile.gd`: physics-derived speed profile generation and distance sampling
