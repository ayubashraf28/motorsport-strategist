extends RefCounted
class_name RaceConfigLoader

const RaceTypes = preload("res://sim/src/race_types.gd")


static func load_race_config(paths: PackedStringArray = PackedStringArray()) -> Dictionary:
	var candidate_paths := paths
	if candidate_paths.is_empty():
		candidate_paths = PackedStringArray([
			ProjectSettings.globalize_path("res://../config/race_v1.json")
		])

	var load_result := _read_first_existing_file(candidate_paths)
	var load_errors_value: Variant = load_result.get("errors", PackedStringArray())
	var load_errors: PackedStringArray = load_errors_value if load_errors_value is PackedStringArray else PackedStringArray()
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

	var track_raw = root.get("track", null)
	if typeof(track_raw) != TYPE_DICTIONARY:
		errors.append("track must be an object.")
	else:
		var track_result := _parse_track(track_raw)
		var track_errors_value: Variant = track_result.get("errors", PackedStringArray())
		var track_errors: PackedStringArray = track_errors_value if track_errors_value is PackedStringArray else PackedStringArray()
		for track_error in track_errors:
			errors.append(track_error)
		var parsed_track_value: Variant = track_result.get("track", null)
		var parsed_track: RaceTypes.PaceProfileConfig = parsed_track_value as RaceTypes.PaceProfileConfig
		if parsed_track != null:
			config.track = parsed_track

	var debug_raw = root.get("debug", {})
	if typeof(debug_raw) == TYPE_DICTIONARY:
		var debug_result := _parse_debug(debug_raw)
		var debug_errors_value: Variant = debug_result.get("errors", PackedStringArray())
		var debug_errors: PackedStringArray = debug_errors_value if debug_errors_value is PackedStringArray else PackedStringArray()
		for debug_error in debug_errors:
			errors.append(debug_error)
		var parsed_debug_value: Variant = debug_result.get("debug", null)
		var parsed_debug: RaceTypes.DebugConfig = parsed_debug_value as RaceTypes.DebugConfig
		if parsed_debug != null:
			config.debug = parsed_debug
	else:
		errors.append("debug must be an object when provided.")

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

		var speed_raw = car_dict.get("base_speed_units_per_sec", null)
		if not _is_numeric(speed_raw):
			errors.append("cars[%d].base_speed_units_per_sec must be numeric." % index)
			continue

		var speed := float(speed_raw)
		if speed <= 0.0:
			errors.append("cars[%d].base_speed_units_per_sec must be greater than zero." % index)
			continue

		var display_name := car_id
		var display_name_raw = car_dict.get("display_name", car_id)
		if typeof(display_name_raw) == TYPE_STRING and not display_name_raw.strip_edges().is_empty():
			display_name = display_name_raw.strip_edges()

		var car_config := RaceTypes.CarConfig.new()
		car_config.id = car_id
		car_config.display_name = display_name
		car_config.base_speed_units_per_sec = speed
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


static func _parse_track(track_raw: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var track := RaceTypes.PaceProfileConfig.new()

	var blend_distance_raw = track_raw.get("blend_distance", null)
	if not _is_numeric(blend_distance_raw):
		errors.append("track.blend_distance must be numeric.")
	else:
		track.blend_distance = float(blend_distance_raw)
		if track.blend_distance < 0.0:
			errors.append("track.blend_distance must be >= 0.")

	var segments_raw = track_raw.get("pace_segments", null)
	if typeof(segments_raw) != TYPE_ARRAY:
		errors.append("track.pace_segments must be an array.")
	else:
		for index in range(segments_raw.size()):
			var segment_raw = segments_raw[index]
			if typeof(segment_raw) != TYPE_DICTIONARY:
				errors.append("track.pace_segments[%d] must be an object." % index)
				continue

			var segment_dict: Dictionary = segment_raw
			var start_raw = segment_dict.get("start_distance", null)
			var end_raw = segment_dict.get("end_distance", null)
			var multiplier_raw = segment_dict.get("multiplier", null)

			if not _is_numeric(start_raw):
				errors.append("track.pace_segments[%d].start_distance must be numeric." % index)
				continue
			if not _is_numeric(end_raw):
				errors.append("track.pace_segments[%d].end_distance must be numeric." % index)
				continue
			if not _is_numeric(multiplier_raw):
				errors.append("track.pace_segments[%d].multiplier must be numeric." % index)
				continue

			var start_distance: float = float(start_raw)
			var end_distance: float = float(end_raw)
			var multiplier: float = float(multiplier_raw)

			if end_distance <= start_distance:
				errors.append(
					"track.pace_segments[%d] end_distance must be greater than start_distance." % index
				)
				continue
			if multiplier <= 0.0:
				errors.append("track.pace_segments[%d].multiplier must be greater than zero." % index)
				continue

			var segment := RaceTypes.PaceSegmentConfig.new()
			segment.start_distance = start_distance
			segment.end_distance = end_distance
			segment.multiplier = multiplier
			track.pace_segments.append(segment)

	if track.pace_segments.is_empty():
		errors.append("track.pace_segments must include at least one valid segment.")

	return {
		"track": track,
		"errors": errors
	}


static func _parse_debug(debug_raw: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var debug := RaceTypes.DebugConfig.new()
	var show_pace_profile_raw = debug_raw.get("show_pace_profile", true)
	if typeof(show_pace_profile_raw) != TYPE_BOOL:
		errors.append("debug.show_pace_profile must be a boolean.")
	else:
		debug.show_pace_profile = show_pace_profile_raw

	return {
		"debug": debug,
		"errors": errors
	}
