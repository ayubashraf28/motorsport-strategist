extends RefCounted
class_name TeamRegistry

const RaceTypes = preload("res://sim/src/race_types.gd")


static func _get_teams_path() -> String:
	return ProjectSettings.globalize_path("res://../config/teams.json")


static func load_teams() -> Dictionary:
	var path: String = _get_teams_path()
	if not FileAccess.file_exists(path):
		return {"teams": [], "errors": PackedStringArray(["Teams file not found at '%s'." % path])}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"teams": [], "errors": PackedStringArray(["Failed to open teams file at '%s'." % path])}

	var json: JSON = JSON.new()
	var err: Error = json.parse(file.get_as_text())
	if err != OK:
		return {"teams": [], "errors": PackedStringArray(["Failed to parse teams file: %s" % json.get_error_message()])}

	var data: Dictionary = json.data
	if not data.has("teams") or not data["teams"] is Array:
		return {"teams": [], "errors": PackedStringArray(["Teams file missing 'teams' array."])}

	return {"teams": data["teams"], "errors": PackedStringArray()}


static func build_car_configs(teams_data: Array, base_v_ref: float, fuel_capacity_kg: float) -> Array:
	var cars: Array = []
	for team in teams_data:
		var v_ref: float = base_v_ref + team.get("v_ref_offset", 0.0)
		var compound: String = team.get("starting_compound", "medium")
		var team_id: String = String(team.get("id", "")).strip_edges()
		for driver in team.get("drivers", []):
			var car_config: RaceTypes.CarConfig = RaceTypes.CarConfig.new()
			car_config.id = driver.get("id", "")
			car_config.display_name = driver.get("display_name", car_config.id)
			car_config.v_ref = v_ref
			car_config.starting_compound = compound
			car_config.starting_fuel_kg = fuel_capacity_kg
			car_config.team_id = team_id
			cars.append(car_config)
	return cars


static func get_team_for_driver(teams_data: Array, driver_id: String) -> Dictionary:
	for team in teams_data:
		for driver in team.get("drivers", []):
			if driver.get("id", "") == driver_id:
				return team
	return {}


static func get_team_color(teams_data: Array, driver_id: String) -> Color:
	var team: Dictionary = get_team_for_driver(teams_data, driver_id)
	if team.is_empty():
		return Color.WHITE
	return Color.html(team.get("color", "#FFFFFF"))


static func get_ai_pit_threshold(teams_data: Array, driver_id: String) -> float:
	var team: Dictionary = get_team_for_driver(teams_data, driver_id)
	if team.is_empty():
		return 0.35
	return team.get("pit_threshold", 0.35)


static func get_all_ai_thresholds(teams_data: Array) -> Dictionary:
	var thresholds: Dictionary = {}
	for team in teams_data:
		var threshold: float = team.get("pit_threshold", 0.35)
		for driver in team.get("drivers", []):
			thresholds[driver.get("id", "")] = threshold
	return thresholds


static func get_car_colors(teams_data: Array) -> Dictionary:
	var colors: Dictionary = {}
	for team in teams_data:
		var color: Color = Color.html(team.get("color", "#FFFFFF"))
		for driver in team.get("drivers", []):
			colors[driver.get("id", "")] = color
	return colors


static func get_team_ids(teams_data: Array) -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for team in teams_data:
		var team_id: String = String(team.get("id", "")).strip_edges()
		if not team_id.is_empty():
			ids.append(team_id)
	return ids
