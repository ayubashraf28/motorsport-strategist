extends GdUnitTestSuite

const RaceConfigLoader = preload("res://scripts/race_config_loader.gd")
const RaceTypes = preload("res://sim/src/race_types.gd")


func test_schema_4_parses_safety_car_block() -> void:
	var config_dict: Dictionary = _base_config_dict("4.0")
	config_dict["safety_car"] = {
		"enabled": true,
		"trigger_probability_per_lap": 0.08,
		"max_events": 2,
		"min_lap": 2,
		"cooldown_laps": 1,
		"sc_laps_min": 3,
		"sc_laps_max": 4,
		"vsc_laps_min": 2,
		"vsc_laps_max": 3,
		"vsc_probability": 0.4,
		"sc_speed_cap": 25.0,
		"sc_leader_pace_ratio": 0.9,
		"vsc_speed_multiplier": 0.6,
		"restart_drs_lock_laps": 2
	}

	var result: Dictionary = RaceConfigLoader.load_race_config_from_text(JSON.stringify(config_dict))
	var errors: PackedStringArray = result.get("errors", PackedStringArray())
	assert(errors.is_empty())
	var config: RaceTypes.RaceConfig = result.get("config", null) as RaceTypes.RaceConfig
	assert(config != null)
	assert(config.safety_car != null)
	assert(config.safety_car.enabled)
	assert(abs(config.safety_car.trigger_probability_per_lap - 0.08) < 0.0001)


func test_missing_safety_car_block_is_backward_compatible() -> void:
	var config_dict: Dictionary = _base_config_dict("3.0")
	var result: Dictionary = RaceConfigLoader.load_race_config_from_text(JSON.stringify(config_dict))
	var errors: PackedStringArray = result.get("errors", PackedStringArray())
	assert(errors.is_empty())
	var config: RaceTypes.RaceConfig = result.get("config", null) as RaceTypes.RaceConfig
	assert(config != null)
	assert(config.safety_car == null)


func test_invalid_safety_car_values_return_errors() -> void:
	var config_dict: Dictionary = _base_config_dict("4.0")
	config_dict["safety_car"] = {
		"enabled": true,
		"trigger_probability_per_lap": 1.5,
		"max_events": -1,
		"min_lap": 0,
		"cooldown_laps": -1,
		"sc_laps_min": 0,
		"sc_laps_max": -2,
		"vsc_laps_min": 0,
		"vsc_laps_max": -1,
		"vsc_probability": 1.3,
		"sc_speed_cap": 0.0,
		"sc_leader_pace_ratio": 1.3,
		"vsc_speed_multiplier": 1.0,
		"restart_drs_lock_laps": -2
	}

	var result: Dictionary = RaceConfigLoader.load_race_config_from_text(JSON.stringify(config_dict))
	var errors: PackedStringArray = result.get("errors", PackedStringArray())
	assert(not errors.is_empty())


func _base_config_dict(schema_version: String) -> Dictionary:
	return {
		"schema_version": schema_version,
		"count_first_lap_from_start": true,
		"seed": 7,
		"default_time_scale": 1.0,
		"total_laps": 10,
		"track": {
			"geometry_asset": "../../data/tracks/monza/monza_centerline.json",
			"physics": {
				"a_lat_max": 25.0,
				"a_long_accel": 8.0,
				"a_long_brake": 20.0,
				"v_top_speed": 83.0,
				"curvature_epsilon": 0.0001
			}
		},
		"cars": [
			{
				"id": "A1",
				"display_name": "A1",
				"v_ref": 80.0,
				"starting_compound": "soft",
				"starting_fuel_kg": 100.0,
				"team_id": "team_a"
			},
			{
				"id": "A2",
				"display_name": "A2",
				"v_ref": 79.0,
				"starting_compound": "medium",
				"starting_fuel_kg": 100.0,
				"team_id": "team_a"
			}
		],
		"compounds": [
			{
				"name": "soft",
				"degradation": {
					"warmup_laps": 0.3,
					"peak_multiplier": 1.0,
					"degradation_rate": 0.02,
					"min_multiplier": 0.7,
					"optimal_threshold": 0.75,
					"cliff_threshold": 0.3,
					"cliff_multiplier": 2.0
				}
			},
			{
				"name": "medium",
				"degradation": {
					"warmup_laps": 0.5,
					"peak_multiplier": 0.99,
					"degradation_rate": 0.015,
					"min_multiplier": 0.75,
					"optimal_threshold": 0.75,
					"cliff_threshold": 0.3,
					"cliff_multiplier": 2.0
				}
			}
		]
	}
