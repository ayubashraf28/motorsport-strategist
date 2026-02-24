# game

Godot project, scenes, UI, and assets.

Boundaries:
- presentation and rendering logic stay in `game/scenes`, `game/ui`, and `game/scripts`
- authoritative deterministic simulation for runtime race behavior is in `game/sim/src`
- simulation tests are in `game/sim/tests`

Run:
- open `game/project.godot` in Godot 4.6.x
- main scene: `res://scenes/main.tscn`
- race config lookup order: `../config/race_v2.json`, then `../config/race_v1.1.json`, then `../config/race_v1.json`
- debug toggle: press `D`
- V1.1 cycles speed/curvature/off overlays
- V1 cycles pace/off overlay
