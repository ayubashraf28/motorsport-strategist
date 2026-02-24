# sim/tests

Future repository-level automated tests for shared simulation packages.

Guidelines:
- prioritize deterministic unit tests
- cover edge cases and race-state transitions
- prefer small, fast tests with clear fixtures

Note:
- v0 runnable tests currently live in `game/sim/tests` and run in headless Godot via GdUnit4.
