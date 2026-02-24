# config

Shared configuration templates and environment examples.

## V1 race configuration

`race_v1.json` is the authoritative runtime data source for race setup.

Schema:
- `count_first_lap_from_start` (`bool`, default `true`): first crossing counts as lap 1 when true.
- `seed` (`int`, default `0`): reserved for deterministic randomization in future versions.
- `default_time_scale` (`float`, default `1.0`): startup time scale. Allowed runtime values remain `1x`, `2x`, `4x`.
- `track` (`object`, required):
- `blend_distance` (`float`, required, `>= 0`)
- `pace_segments` (`array`, required, non-empty), each segment:
- `start_distance` (`float`, required)
- `end_distance` (`float`, required, `> start_distance`)
- `multiplier` (`float`, required, `> 0`)
- `cars` (`array`, required): each entry must include:
- `id` (`string`, required, unique, non-empty)
- `display_name` (`string`, optional, falls back to `id`)
- `base_speed_units_per_sec` (`float`, required, `> 0`)
- `debug` (`object`, optional):
- `show_pace_profile` (`bool`, default `true`)

Validation rules:
- `cars` must contain at least one valid car.
- Track length source of truth is the authored `Curve2D` in `game/scenes/main.tscn`.
- Runtime validates pace segments against the baked track length:
- first segment starts at `0`
- strict contiguous coverage with no gaps/overlaps
- last segment ends at track length (within tolerance)
- segment length must be at least `blend_distance`
- Invalid config blocks simulation startup and shows an explicit error in the HUD.

Compatibility note:
- `race_v0.json` is retained for historical reference only and is not used at runtime in V1.
