# config

Shared runtime configuration files.

## Runtime config routing

`RaceConfigLoader` checks configs in this order:
1. `config/race_v2.json`
2. `config/race_v1.1.json`
3. `config/race_v1.json`

Schema routing:
- `schema_version: "2.0"` => physics-derived speed profile mode + race end + degradation + overtaking.
- `schema_version: "1.1"` => physics-derived speed profile mode.
- missing `schema_version` or `"1.0"` => pace-segment mode.

## V2 schema (`race_v2.json`)

Extends V1.1 with:
- `total_laps` (`int`, `>= 0`; `0` means unlimited race distance).
- `degradation` (`object`, optional): global tyre-like pace degradation defaults.
- `overtaking` (`object`, optional): proximity/threshold/cooldown interaction rules.
- `cars[].degradation` (`object`, optional): per-car degradation override.

`degradation` fields:
- `warmup_laps` (`float`, `>= 0`)
- `peak_multiplier` (`float`, `> 0` and `<= 2.0`)
- `degradation_rate` (`float`, `>= 0`)
- `min_multiplier` (`float`, `> 0` and `<= peak_multiplier`)

`overtaking` fields:
- `enabled` (`bool`)
- `proximity_distance` (`float`, `>= 0`)
- `overtake_speed_threshold` (`float`, `>= 0`)
- `held_up_speed_buffer` (`float`, `>= 0`)
- `cooldown_seconds` (`float`, `>= 0`)

## V1.1 schema (`race_v1.1.json`)

Required root fields:
- `schema_version` (`string`): must be `"1.1"`.
- `count_first_lap_from_start` (`bool`).
- `seed` (`int` or `float` numeric).
- `default_time_scale` (`float`, `> 0`).
- `track` (`object`):
- `geometry_asset` (`string`, non-empty): path to derived geometry JSON.
- `physics` (`object`) with:
- `a_lat_max` (`float`, `> 0`)
- `a_long_accel` (`float`, `> 0`)
- `a_long_brake` (`float`, `> 0`)
- `v_top_speed` (`float`, `> 0`)
- `curvature_epsilon` (`float`, `> 0`)
- `cars` (`array`, at least one valid entry):
- `id` (`string`, unique, non-empty)
- `display_name` (`string`, optional, defaults to `id`)
- `v_ref` (`float`, `> 0`)

Optional debug fields:
- `debug.show_curvature_overlay` (`bool`, default `false`)
- `debug.show_speed_overlay` (`bool`, default `true`)
- `debug.show_pace_profile` (`bool`, default `true`, used by V1 path)

## V1 schema (`race_v1.json`)

Required fields:
- `track.blend_distance` (`float`, `>= 0`)
- `track.pace_segments[]`:
- `start_distance`, `end_distance` (`float`)
- `multiplier` (`float`, `> 0`)
- `cars[].base_speed_units_per_sec` (`float`, `> 0`)

Runtime notes:
- V1 validates segment coverage against baked track length.
- V1.1 derives track length and curvature from the loaded geometry asset.
- V2 uses the same geometry/physics track parsing as V1.1 and adds race-state/interaction behavior.
- Invalid config blocks simulation startup and the HUD shows explicit errors.
