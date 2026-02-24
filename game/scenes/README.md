# game/scenes

Game scene definitions and scene composition.

Current entrypoint:
- `main.tscn`: single-screen prototype (track + cars + HUD + start/finish marker + pace debug overlay)

Keep scene logic thin; delegate deterministic timing rules to `game/sim/src`.
