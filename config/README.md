# config

Shared configuration templates and environment examples.

## v0 race configuration

`race_v0.json` is the data source for prototype race setup.

Schema:
- `count_first_lap_from_start` (`bool`, default `true`): first crossing counts as lap 1 when true.
- `seed` (`int`, default `0`): reserved for deterministic randomization in future versions.
- `default_time_scale` (`float`, default `1.0`): startup time scale. Allowed runtime values remain `1x`, `2x`, `4x`.
- `cars` (`array`, required): each entry must include:
- `id` (`string`, required, unique, non-empty)
- `display_name` (`string`, optional, falls back to `id`)
- `speed_units_per_sec` (`float`, required, `> 0`)

Validation rules:
- `cars` must contain at least one valid car.
- Track length is not configured here; it is computed from the authored `Curve2D` in `game/scenes/main.tscn`.
- Invalid config blocks simulation startup and shows an explicit error in the HUD.
