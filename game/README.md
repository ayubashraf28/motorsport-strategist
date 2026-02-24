# game

Godot project, scenes, UI, and assets.

Boundaries:
- presentation and rendering logic stay in `game/scenes`, `game/ui`, and `game/scripts`
- authoritative deterministic simulation for v0 is in `game/sim/src`
- tests for v0 simulation are in `game/sim/tests`

Run:
- open `game/project.godot` in Godot 4.5.x
- main scene: `res://scenes/main.tscn`
- race config is loaded from `../config/race_v0.json`
