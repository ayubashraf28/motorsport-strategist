# game/sim/tests

Deterministic GdUnit4 tests for simulation and fixed-step behavior.

Coverage priorities:
- lap timing correctness
- wrap-around crossing behavior under high dt
- reset/initial state invariants
- validation failures for malformed configuration
- reproducibility under identical fixed-step input sequences

Local invocation:
1. Open `game/project.godot` in Godot 4.5.x.
2. Install GdUnit4 locally in `game/addons/gdUnit4`.
3. Run the `res://sim/tests` suites from the GdUnit test panel.

Note:
- `.gdignore` is present so the main game can run without a local GdUnit installation.
- Remove `game/sim/tests/.gdignore` temporarily when running tests locally.
