# config

Shared runtime configuration files.

## Runtime config routing

`RaceConfigLoader` checks race config files in this order:
1. `config/race_v4.json`
2. `config/race_v3.json`
3. `config/race_v2.json`
4. `config/race_v1.1.json`
5. `config/race_v1.json`

Schema routing:
- `schema_version: "4.0"`: V3 features + Safety Car/VSC + team metadata (`cars[].team_id`).
- `schema_version: "3.0"`: compounds + fuel + pit + DRS.
- `schema_version: "2.0"`: degradation + overtaking.
- `schema_version: "1.1"`: physics-derived speed profile mode.
- missing `schema_version` or `"1.0"`: pace-segment mode.

## V4 additions

`cars[]`:
- `team_id` (`string`, optional for backward compatibility, required for team-scope controls).

`safety_car` (`object`, optional):
- `enabled` (`bool`)
- `trigger_probability_per_lap` (`float`, `[0,1]`)
- `max_events` (`int`, `>= 0`)
- `min_lap` (`int`, `>= 1`)
- `cooldown_laps` (`int`, `>= 0`)
- `sc_laps_min` / `sc_laps_max` (`int`, `> 0`, max `>=` min)
- `vsc_laps_min` / `vsc_laps_max` (`int`, `> 0`, max `>=` min)
- `vsc_probability` (`float`, `[0,1]`)
- `sc_speed_cap` (`float`, `> 0`)
- `sc_leader_pace_ratio` (`float`, `(0,1]`)
- `vsc_speed_multiplier` (`float`, `(0,1)`)
- `restart_drs_lock_laps` (`int`, `>= 0`)

If `safety_car` is absent, race-control behavior is disabled and existing behavior is preserved.

## Track configs

`config/tracks/*.json` are used by race setup composition (`GameState.compose_race_config`) and currently include:
- `track` (geometry + physics)
- `pit`
- `compounds`
- `fuel`
- `overtaking`
- `drs`
- `safety_car`
- `default_laps`

## Runtime notes

- Config validation is strict; startup is blocked with explicit errors when invalid.
- Telemetry schema is additive: new fields are appended without breaking older consumers.
