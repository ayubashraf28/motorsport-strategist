extends Node

const RaceTypes = preload("res://sim/src/race_types.gd")
const TrackRegistry = preload("res://scripts/track_registry.gd")
const TeamRegistry = preload("res://scripts/team_registry.gd")
const RaceConfigLoader = preload("res://scripts/race_config_loader.gd")

var track_list: Array = []
var teams_data: Array = []

var selected_track_id: String = "monza"
var selected_laps: int = 15
var fuel_enabled: bool = true

var active_config: RaceTypes.RaceConfig = null
var track_geometry_asset_path: String = ""
var car_colors: Dictionary = {}
var ai_thresholds: Dictionary = {}
var race_results: Dictionary = {}


func _ready() -> void:
	_load_registries()


func _load_registries() -> void:
	var track_result: Dictionary = TrackRegistry.load_registry()
	if track_result.get("errors", PackedStringArray()).is_empty():
		track_list = track_result["tracks"]

	var team_result: Dictionary = TeamRegistry.load_teams()
	if team_result.get("errors", PackedStringArray()).is_empty():
		teams_data = team_result["teams"]


func get_track_display_name(track_id: String) -> String:
	for entry in track_list:
		if entry.get("id", "") == track_id:
			return entry.get("display_name", track_id)
	return track_id


func compose_race_config() -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()

	var track_result: Dictionary = TrackRegistry.load_track_config(selected_track_id)
	var track_errors: PackedStringArray = track_result.get("errors", PackedStringArray())
	if not track_errors.is_empty():
		return track_errors

	var track_config: Dictionary = track_result["config"]
	track_geometry_asset_path = track_result.get("config_path", "")

	var base_v_ref: float = 83.0
	var track_block: Dictionary = track_config.get("track", {})
	var physics_block: Dictionary = track_block.get("physics", {})
	if physics_block.has("v_top_speed"):
		base_v_ref = physics_block["v_top_speed"]

	var fuel_config: Dictionary = track_config.get("fuel", {})
	var fuel_capacity: float = fuel_config.get("max_capacity_kg", 110.0)

	# Build RaceConfig using the standard loader by composing a full JSON dict
	var race_dict: Dictionary = {
		"schema_version": "3.0",
		"count_first_lap_from_start": true,
		"seed": 42,
		"default_time_scale": 1.0,
		"total_laps": selected_laps,
		"track": track_block,
		"compounds": track_config.get("compounds", []),
		"fuel": fuel_config,
		"pit": track_config.get("pit", {}),
		"overtaking": track_config.get("overtaking", {}),
		"drs": track_config.get("drs", {}),
		"debug": {"show_pace_profile": false, "show_curvature_overlay": false, "show_speed_overlay": true}
	}

	if not fuel_enabled:
		race_dict["fuel"]["enabled"] = false

	# Build car configs from team data
	var car_configs: Array = TeamRegistry.build_car_configs(teams_data, base_v_ref, fuel_capacity)
	var cars_array: Array = []
	for car_config in car_configs:
		var car_dict: Dictionary = {
			"id": car_config.id,
			"display_name": car_config.display_name,
			"v_ref": car_config.v_ref,
			"starting_compound": car_config.starting_compound,
			"starting_fuel_kg": car_config.starting_fuel_kg
		}
		cars_array.append(car_dict)
	race_dict["cars"] = cars_array

	# Use the standard config loader to parse the composed dict
	var json_text: String = JSON.stringify(race_dict)
	var load_result: Dictionary = RaceConfigLoader.load_race_config_from_text(json_text, track_geometry_asset_path)
	var load_errors: PackedStringArray = load_result.get("errors", PackedStringArray())
	if not load_errors.is_empty():
		return load_errors

	active_config = load_result.get("config", null) as RaceTypes.RaceConfig
	if active_config == null:
		return PackedStringArray(["Failed to compose race config."])

	# Build color and AI threshold maps
	car_colors = TeamRegistry.get_car_colors(teams_data)
	ai_thresholds = TeamRegistry.get_all_ai_thresholds(teams_data)

	return PackedStringArray()


func store_race_results(snapshot: RaceTypes.RaceSnapshot) -> void:
	race_results = {}
	if snapshot == null:
		return

	race_results["race_time"] = snapshot.race_time
	race_results["finish_order"] = snapshot.finish_order.duplicate()
	race_results["track_id"] = selected_track_id
	race_results["track_name"] = get_track_display_name(selected_track_id)
	race_results["total_laps"] = selected_laps

	var cars_data: Array = []
	for raw_car in snapshot.cars:
		var car: RaceTypes.CarState = raw_car as RaceTypes.CarState
		if car == null:
			continue
		var team: Dictionary = TeamRegistry.get_team_for_driver(teams_data, car.id)
		cars_data.append({
			"id": car.id,
			"display_name": car.display_name,
			"team_name": team.get("name", ""),
			"team_color": team.get("color", "#FFFFFF"),
			"finish_position": car.finish_position,
			"finish_time": car.finish_time,
			"best_lap_time": car.best_lap_time,
			"pit_stops_completed": car.pit_stops_completed,
			"current_compound": car.current_compound,
			"stint_number": car.stint_number,
		})
	race_results["cars"] = cars_data


func clear_race_results() -> void:
	race_results = {}
