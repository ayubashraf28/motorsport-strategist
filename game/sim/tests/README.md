# game/sim/tests

Deterministic GdUnit4 tests for simulation and fixed-step behavior.

Coverage priorities:
- lap timing correctness
- wrap-around crossing behavior under high dt
- standings and interval correctness
- race-state transitions and finish ordering
- degradation model behavior and validation
- tyre compound lookup/validation behavior
- stint tracking and pit-history invariants
- fuel multiplier, consumption, and refuel behavior
- pit stop phase transitions and entry/exit rules
- pit strategy queue request/cancel/consume behavior
- overtaking/held-up/cooldown interaction behavior
- safety car / VSC trigger, phase, and DRS gating behavior
- team-order deterministic behavior (let through / hold position / defend)
- reset/initial state invariants
- validation failures for malformed configuration
- reproducibility under identical fixed-step input sequences
- pace profile validation and smooth transition guarantees
- geometry curvature computation validity
- physics speed-profile correctness and determinism

Local invocation:
1. Open `game/project.godot` in Godot 4.6.x.
2. Install GdUnit4 locally in `game/addons/gdUnit4`.
3. Run the `res://sim/tests` suites from the GdUnit test panel.

Note:
- `.gdignore` is present so the main game can run without a local GdUnit installation.
- Remove `game/sim/tests/.gdignore` temporarily when running tests locally.
