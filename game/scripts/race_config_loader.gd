extends RefCounted
class_name RaceConfigLoader

const RaceTypes = preload("res://sim/src/race_types.gd")


static func load_race_config(paths: PackedStringArray = PackedStringArray()) -> Dictionary:
	var candidate_paths := paths
	if candidate_paths.is_empty():
		candidate_paths = PackedStringArray([
			ProjectSettings.globalize_path("res://../config/race_v0.json")
		])

	var load_result := _read_first_existing_file(candidate_paths)
	var load_errors: PackedStringArray = load_result.get("errors", PackedStringArray())
	if not load_errors.is_empty():
		return {
			"config": null,
			"errors": load_errors,
			"source_path": ""
		}

	var parse_result := _parse_config_json(load_result.get("content", ""))
	parse_result["source_path"] = load_result.get("path", "")
	return parse_result


static func _read_first_existing_file(candidate_paths: PackedStringArray) -> Dictionary:
	var errors := PackedStringArray()

	for path in candidate_paths:
		if not FileAccess.file_exists(path):
			continue

		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			errors.append("Failed to open race config at '%s'." % path)
			continue

		return {
			"path": path,
			"content": file.get_as_text(),
			"errors": PackedStringArray()
		}

	errors.append(
		"Could not find race config. Checked: %s" % ", ".join(candidate_paths)
	)
	return {
		"path": "",
		"content": "",
		"errors": errors
	}


static func _parse_config_json(content: String) -> Dictionary:
	var errors := PackedStringArray()
	var parser := JSON.new()
	var parse_status := parser.parse(content)
	if parse_status != OK:
		errors.append("Invalid JSON in race config: %s" % parser.get_error_message())
		return {
			"config": null,
			"errors": errors
		}

	if typeof(parser.data) != TYPE_DICTIONARY:
		errors.append("Race config root must be a JSON object.")
		return {
			"config": null,
			"errors": errors
		}

	var root: Dictionary = parser.data
	var config := RaceTypes.RaceConfig.new()

	var count_first_lap_raw = root.get("count_first_lap_from_start", true)
	if typeof(count_first_lap_raw) != TYPE_BOOL:
		errors.append("count_first_lap_from_start must be a boolean.")
	else:
		config.count_first_lap_from_start = count_first_lap_raw

	var seed_raw = root.get("seed", 0)
	if _is_numeric(seed_raw):
		config.seed = int(seed_raw)
	else:
		errors.append("seed must be numeric.")

	var default_time_scale_raw = root.get("default_time_scale", 1.0)
	if _is_numeric(default_time_scale_raw):
		config.default_time_scale = float(default_time_scale_raw)
	else:
		errors.append("default_time_scale must be numeric.")

	if config.default_time_scale <= 0.0:
		errors.append("default_time_scale must be greater than zero.")

	var cars_raw = root.get("cars", [])
	if typeof(cars_raw) != TYPE_ARRAY:
		errors.append("cars must be an array.")
		return {
			"config": null,
			"errors": errors
		}

	var seen_ids := {}
	for index in range(cars_raw.size()):
		var car_entry = cars_raw[index]
		if typeof(car_entry) != TYPE_DICTIONARY:
			errors.append("cars[%d] must be an object." % index)
			continue

		var car_dict: Dictionary = car_entry
		var id_raw = car_dict.get("id", "")
		if typeof(id_raw) != TYPE_STRING or id_raw.strip_edges().is_empty():
			errors.append("cars[%d].id must be a non-empty string." % index)
			continue

		var car_id: String = id_raw.strip_edges()
		if seen_ids.has(car_id):
			errors.append("cars[%d].id '%s' is duplicated." % [index, car_id])
			continue
		seen_ids[car_id] = true

		var speed_raw = car_dict.get("speed_units_per_sec", null)
		if not _is_numeric(speed_raw):
			errors.append("cars[%d].speed_units_per_sec must be numeric." % index)
			continue

		var speed := float(speed_raw)
		if speed <= 0.0:
			errors.append("cars[%d].speed_units_per_sec must be greater than zero." % index)
			continue

		var display_name := car_id
		var display_name_raw = car_dict.get("display_name", car_id)
		if typeof(display_name_raw) == TYPE_STRING and not display_name_raw.strip_edges().is_empty():
			display_name = display_name_raw.strip_edges()

		var car_config := RaceTypes.CarConfig.new()
		car_config.id = car_id
		car_config.display_name = display_name
		car_config.speed_units_per_sec = speed
		config.cars.append(car_config)

	if config.cars.is_empty():
		errors.append("At least one valid car entry is required.")

	if not errors.is_empty():
		return {
			"config": null,
			"errors": errors
		}

	return {
		"config": config,
		"errors": PackedStringArray()
	}


static func _is_numeric(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
