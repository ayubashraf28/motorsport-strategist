# game/sim/src

Pure deterministic race simulation logic.

Constraints:
- no `Node` dependencies
- no scene/UI references
- deterministic state transitions given config and fixed dt input

Current modules:
- `race_types.gd`: typed config/state/snapshot models
- `race_simulator.gd`: race clock, distance update, and lap timing rules
- `fixed_step_runner.gd`: deterministic accumulator helper used by presentation
