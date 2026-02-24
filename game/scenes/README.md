# game/scenes

Game scene definitions and scene composition.

Current entrypoint:
- `main.tscn`: single-screen v0 prototype (track + cars + HUD)

Keep scene logic thin; delegate deterministic timing rules to `game/sim/src`.
