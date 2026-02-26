extends RefCounted
class_name RaceConfigLoader

const RaceTypes = preload("res://sim/src/race_types.gd")
const DegradationModel = preload("res://sim/src/degradation_model.gd")
const TyreCompound = preload("res://sim/src/tyre_compound.gd")
const FuelModel = preload("res://sim/src/fuel_model.gd")
const TrackLoader = preload("res://scripts/track_loader.gd")


static func load_race_config(paths: PackedStringArray = PackedStringArray()) -> Dictionary:
	var candidate_paths: PackedStringArray = paths
	if candidate_paths.is_empty():
		candidate_paths = PackedStringArray([
			ProjectSettings.globalize_path("res://../config/race_v3.json"),
			ProjectSettings.globalize_path("res://../config/race_v2.json"),
			ProjectSettings.globalize_path("res://../config/race_v1.1.json"),
			ProjectSettings.globalize_path("res://../config/race_v1.json")
		])

	var load_result: Dictionary = _read_first_existing_file(candidate_paths)
	var load_errors: PackedStringArray = load_result.get("errors", PackedStringArray())
	if not load_errors.is_empty():
		return {
			"config": null,
			"errors": load_errors,
			"source_path": ""
		}

	var parse_result: Dictionary = _parse_config_json(
		load_result.get("content", ""),
		load_result.get("path", "")
	)
	parse_result["source_path"] = load_result.get("path", "")
	return parse_result


static func load_race_config_from_text(json_text: String, source_path: String = "") -> Dictionary:
	var parse_result: Dictionary = _parse_config_json(json_text, source_path)
	parse_result["source_path"] = source_path
	return parse_result


static func _read_first_existing_file(candidate_paths: PackedStringArray) -> Dictionary:
	var errors: PackedStringArray = PackedStringArray()
	for path in candidate_paths:
		if not FileAccess.file_exists(path):
			continue

		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			errors.append("Failed to open race config at '%s'." % path)
			continue

		return {
			"path": path,
			"content": file.get_as_text(),
			"errors": PackedStringArray()
		}

	errors.append("Could not find race config. Checked: %s" % ", ".join(candidate_paths))
	return {
		"path": "",
		"content": "",
		"errors": errors
	}


static func _parse_config_json(content: String, source_path: String = "") -> Dictionary:
	var errors: PackedStringArray = PackedStringArray()
	var parser: JSON = JSON.new()
	var parse_status: int = parser.parse(content)
	if parse_status != OK:
		errors.append("Invalid JSON in race config: %s" % parser.get_error_message())
		return {"config": null, "errors": errors}

	if typeof(parser.data) != TYPE_DICTIONARY:
		errors.append("Race config root must be a JSON object.")
		return {"config": null, "errors": errors}

	var root: Dictionary = parser.data
	var config: RaceTypes.RaceConfig = RaceTypes.RaceConfig.new()
	var schema_version: String = _parse_schema_version(root, errors)
	config.schema_version = schema_version

	_parse_common_fields(root, config, errors)
	if schema_version == "3.0" or schema_version == "4.0":
		_parse_v3_config(root, config, errors, source_path)
	elif schema_version == "2.0":
		_parse_v2_config(root, config, errors)
	elif schema_version == "1.1":
		_parse_v1_1_config(root, config, errors)
	else:
		_parse_v1_config(root, config, errors)

	if not errors.is_empty():
		return {"config": null, "errors": errors}
	return {"config": config, "errors": PackedStringArray()}


static func _parse_schema_version(root: Dictionary, errors: PackedStringArray) -> String:
	var schema_raw: Variant = root.get("schema_version", "1.0")
	if typeof(schema_raw) != TYPE_STRING:
		errors.append("schema_version must be a string when provided.")
		return "1.0"

	var schema_version: String = String(schema_raw).strip_edges()
	if schema_version.is_empty():
		return "1.0"
	if schema_version != "1.0" and schema_version != "1.1" and schema_version != "2.0" and schema_version != "3.0" and schema_version != "4.0":
		errors.append("Unsupported schema_version '%s'." % schema_version)
		return "1.0"
	return schema_version


static func _parse_common_fields(root: Dictionary, config: RaceTypes.RaceConfig, errors: PackedStringArray) -> void:
	var count_first_lap_raw: Variant = root.get("count_first_lap_from_start", true)
	if typeof(count_first_lap_raw) != TYPE_BOOL:
		errors.append("count_first_lap_from_start must be a boolean.")
	else:
		config.count_first_lap_from_start = count_first_lap_raw

	var seed_raw: Variant = root.get("seed", 0)
	if _is_numeric(seed_raw):
		config.seed = int(seed_raw)
	else:
		errors.append("seed must be numeric.")

	var default_time_scale_raw: Variant = root.get("default_time_scale", 1.0)
	if _is_numeric(default_time_scale_raw):
		config.default_time_scale = float(default_time_scale_raw)
	else:
		errors.append("default_time_scale must be numeric.")
	if config.default_time_scale <= 0.0:
		errors.append("default_time_scale must be greater than zero.")

	var total_laps_raw: Variant = root.get("total_laps", 0)
	if _is_numeric(total_laps_raw):
		config.total_laps = int(total_laps_raw)
		if config.total_laps < 0:
			errors.append("total_laps must be >= 0.")
	else:
		errors.append("total_laps must be numeric.")

	var debug_raw: Variant = root.get("debug", {})
	if typeof(debug_raw) == TYPE_DICTIONARY:
		var parse_debug_result: Dictionary = _parse_debug(debug_raw)
		var debug_errors: PackedStringArray = parse_debug_result.get("errors", PackedStringArray())
		for debug_error in debug_errors:
			errors.append(debug_error)
		var parsed_debug: RaceTypes.DebugConfig = parse_debug_result.get("debug", null)
		if parsed_debug != null:
			config.debug = parsed_debug
	else:
		errors.append("debug must be an object when provided.")


static func _parse_v1_config(root: Dictionary, config: RaceTypes.RaceConfig, errors: PackedStringArray) -> void:
	var track_raw: Variant = root.get("track", null)
	if typeof(track_raw) != TYPE_DICTIONARY:
		errors.append("track must be an object.")
	else:
		var track_result: Dictionary = _parse_pace_track(track_raw)
		var track_errors: PackedStringArray = track_result.get("errors", PackedStringArray())
		for track_error in track_errors:
			errors.append(track_error)
		var parsed_track: RaceTypes.PaceProfileConfig = track_result.get("track", null)
		if parsed_track != null:
			config.track = parsed_track

	var cars_raw: Variant = root.get("cars", [])
	if typeof(cars_raw) != TYPE_ARRAY:
		errors.append("cars must be an array.")
		return

	config.cars = _parse_v1_cars(cars_raw, errors)
	if config.cars.is_empty():
		errors.append("At least one valid car entry is required.")


static func _parse_v1_1_config(root: Dictionary, config: RaceTypes.RaceConfig, errors: PackedStringArray) -> void:
	var track_raw: Variant = root.get("track", null)
	if typeof(track_raw) != TYPE_DICTIONARY:
		errors.append("track must be an object.")
	else:
		var track_result: Dictionary = _parse_speed_track(track_raw)
		var track_errors: PackedStringArray = track_result.get("errors", PackedStringArray())
		for track_error in track_errors:
			errors.append(track_error)
		var parsed_track: RaceTypes.SpeedProfileConfig = track_result.get("track", null)
		if parsed_track != null:
			config.track = parsed_track

	var cars_raw: Variant = root.get("cars", [])
	if typeof(cars_raw) != TYPE_ARRAY:
		errors.append("cars must be an array.")
		return

	config.cars = _parse_v1_1_cars(cars_raw, errors)
	if config.cars.is_empty():
		errors.append("At least one valid car entry is required.")


static func _parse_v2_config(root: Dictionary, config: RaceTypes.RaceConfig, errors: PackedStringArray) -> void:
	_parse_v1_1_config(root, config, errors)

	var global_degradation_raw: Variant = root.get("degradation", null)
	if global_degradation_raw != null:
		if typeof(global_degradation_raw) != TYPE_DICTIONARY:
			errors.append("degradation must be an object when provided.")
		else:
			var global_degradation_result: Dictionary = _parse_degradation_config(global_degradation_raw, "degradation")
			var global_degradation_errors: PackedStringArray = global_degradation_result.get("errors", PackedStringArray())
			for degradation_error in global_degradation_errors:
				errors.append(degradation_error)
			config.degradation = global_degradation_result.get("config", null)

	var overtaking_raw: Variant = root.get("overtaking", null)
	if overtaking_raw != null:
		if typeof(overtaking_raw) != TYPE_DICTIONARY:
			errors.append("overtaking must be an object when provided.")
		else:
			var overtaking_result: Dictionary = _parse_overtaking_config(overtaking_raw, "overtaking")
			var overtaking_errors: PackedStringArray = overtaking_result.get("errors", PackedStringArray())
			for overtaking_error in overtaking_errors:
				errors.append(overtaking_error)
			config.overtaking = overtaking_result.get("config", null)

	var cars_raw: Variant = root.get("cars", [])
	if typeof(cars_raw) == TYPE_ARRAY:
		var cars_array: Array = cars_raw
		_apply_v2_car_overrides(cars_array, config.cars, errors)


static func _parse_v3_config(
	root: Dictionary,
	config: RaceTypes.RaceConfig,
	errors: PackedStringArray,
	source_path: String
) -> void:
	_parse_v2_config(root, config, errors)

	var compounds_raw: Variant = root.get("compounds", [])
	if compounds_raw == null:
		compounds_raw = []
	if typeof(compounds_raw) != TYPE_ARRAY:
		errors.append("compounds must be an array when provided.")
	else:
		config.compounds = _parse_compounds(compounds_raw, errors)
		if not config.compounds.is_empty():
			var compound_errors: PackedStringArray = TyreCompound.validate_compounds(config.compounds)
			for compound_error in compound_errors:
				errors.append(compound_error)

	var fuel_raw: Variant = root.get("fuel", null)
	if fuel_raw != null:
		if typeof(fuel_raw) != TYPE_DICTIONARY:
			errors.append("fuel must be an object when provided.")
		else:
			var fuel_result: Dictionary = _parse_fuel_config(fuel_raw, "fuel")
			var fuel_errors: PackedStringArray = fuel_result.get("errors", PackedStringArray())
			for fuel_error in fuel_errors:
				errors.append(fuel_error)
			config.fuel = fuel_result.get("config", null)

	var pit_raw: Variant = root.get("pit", null)
	if pit_raw != null:
		if typeof(pit_raw) != TYPE_DICTIONARY:
			errors.append("pit must be an object when provided.")
		else:
			var pit_result: Dictionary = _parse_pit_config(pit_raw, "pit")
			var pit_errors: PackedStringArray = pit_result.get("errors", PackedStringArray())
			for pit_error in pit_errors:
				errors.append(pit_error)
			config.pit = pit_result.get("config", null)

	var cars_raw: Variant = root.get("cars", [])
	if typeof(cars_raw) == TYPE_ARRAY:
		var cars_array: Array = cars_raw
		_apply_v3_car_overrides(cars_array, config.cars, errors)

	var drs_raw: Variant = root.get("drs", {})
	if typeof(drs_raw) == TYPE_DICTIONARY:
		config.drs = drs_raw
	elif drs_raw != null:
		errors.append("drs must be an object when provided.")

	_validate_pit_distances_against_track_length(config, source_path, errors)


static func _parse_pace_track(track_raw: Dictionary) -> Dictionary:
	var errors: PackedStringArray = PackedStringArray()
	var track: RaceTypes.PaceProfileConfig = RaceTypes.PaceProfileConfig.new()

	var blend_distance_raw: Variant = track_raw.get("blend_distance", null)
	if not _is_numeric(blend_distance_raw):
		errors.append("track.blend_distance must be numeric.")
	else:
		track.blend_distance = float(blend_distance_raw)
		if track.blend_distance < 0.0:
			errors.append("track.blend_distance must be >= 0.")

	var segments_raw: Variant = track_raw.get("pace_segments", null)
	if typeof(segments_raw) != TYPE_ARRAY:
		errors.append("track.pace_segments must be an array.")
	else:
		var segments: Array = segments_raw
		for index in range(segments.size()):
			var segment_value: Variant = segments[index]
			if typeof(segment_value) != TYPE_DICTIONARY:
				errors.append("track.pace_segments[%d] must be an object." % index)
				continue

			var segment_dict: Dictionary = segment_value
			var start_raw: Variant = segment_dict.get("start_distance", null)
			var end_raw: Variant = segment_dict.get("end_distance", null)
			var multiplier_raw: Variant = segment_dict.get("multiplier", null)

			if not _is_numeric(start_raw):
				errors.append("track.pace_segments[%d].start_distance must be numeric." % index)
				continue
			if not _is_numeric(end_raw):
				errors.append("track.pace_segments[%d].end_distance must be numeric." % index)
				continue
			if not _is_numeric(multiplier_raw):
				errors.append("track.pace_segments[%d].multiplier must be numeric." % index)
				continue

			var segment: RaceTypes.PaceSegmentConfig = RaceTypes.PaceSegmentConfig.new()
			segment.start_distance = float(start_raw)
			segment.end_distance = float(end_raw)
			segment.multiplier = float(multiplier_raw)

			if segment.end_distance <= segment.start_distance:
				errors.append(
					"track.pace_segments[%d] end_distance must be greater than start_distance." % index
				)
				continue
			if segment.multiplier <= 0.0:
				errors.append("track.pace_segments[%d].multiplier must be > 0." % index)
				continue

			track.pace_segments.append(segment)

	if track.pace_segments.is_empty():
		errors.append("track.pace_segments must include at least one valid segment.")

	return {"track": track, "errors": errors}


static func _parse_speed_track(track_raw: Dictionary) -> Dictionary:
	var errors: PackedStringArray = PackedStringArray()
	var speed_track: RaceTypes.SpeedProfileConfig = RaceTypes.SpeedProfileConfig.new()

	var geometry_asset_raw: Variant = track_raw.get("geometry_asset", "")
	if typeof(geometry_asset_raw) != TYPE_STRING or String(geometry_asset_raw).strip_edges().is_empty():
		errors.append("track.geometry_asset must be a non-empty string.")
	else:
		speed_track.geometry_asset_path = String(geometry_asset_raw).strip_edges()

	var physics_raw: Variant = track_raw.get("physics", null)
	if typeof(physics_raw) != TYPE_DICTIONARY:
		errors.append("track.physics must be an object.")
	else:
		var physics_result: Dictionary = _parse_physics_config(physics_raw)
		var physics_errors: PackedStringArray = physics_result.get("errors", PackedStringArray())
		for physics_error in physics_errors:
			errors.append(physics_error)
		var physics_config: RaceTypes.PhysicsVehicleConfig = physics_result.get("physics", null)
		if physics_config != null:
			speed_track.physics = physics_config

	return {"track": speed_track, "errors": errors}


static func _parse_physics_config(physics_raw: Dictionary) -> Dictionary:
	var errors: PackedStringArray = PackedStringArray()
	var physics: RaceTypes.PhysicsVehicleConfig = RaceTypes.PhysicsVehicleConfig.new()

	physics.a_lat_max = _read_positive_float(physics_raw, "a_lat_max", errors, "track.physics")
	physics.a_long_accel = _read_positive_float(physics_raw, "a_long_accel", errors, "track.physics")
	physics.a_long_brake = _read_positive_float(physics_raw, "a_long_brake", errors, "track.physics")
	physics.v_top_speed = _read_positive_float(physics_raw, "v_top_speed", errors, "track.physics")
	physics.curvature_epsilon = _read_positive_float(physics_raw, "curvature_epsilon", errors, "track.physics")

	return {"physics": physics, "errors": errors}


static func _parse_v1_cars(cars_raw: Variant, errors: PackedStringArray) -> Array[RaceTypes.CarConfig]:
	var cars: Array[RaceTypes.CarConfig] = []
	var seen_ids: Dictionary = {}
	var car_entries: Array = cars_raw
	for index in range(car_entries.size()):
		var entry: Variant = car_entries[index]
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("cars[%d] must be an object." % index)
			continue

		var car_dict: Dictionary = entry
		var car_id: String = _read_car_id(car_dict, index, seen_ids, errors)
		if car_id.is_empty():
			continue

		var speed_raw: Variant = car_dict.get("base_speed_units_per_sec", null)
		if not _is_numeric(speed_raw):
			errors.append("cars[%d].base_speed_units_per_sec must be numeric." % index)
			continue
		var base_speed: float = float(speed_raw)
		if base_speed <= 0.0:
			errors.append("cars[%d].base_speed_units_per_sec must be > 0." % index)
			continue

		var car_config: RaceTypes.CarConfig = RaceTypes.CarConfig.new()
		car_config.id = car_id
		car_config.display_name = _read_display_name(car_dict, car_id)
		car_config.base_speed_units_per_sec = base_speed
		car_config.v_ref = base_speed
		cars.append(car_config)

	return cars


static func _parse_v1_1_cars(cars_raw: Variant, errors: PackedStringArray) -> Array[RaceTypes.CarConfig]:
	var cars: Array[RaceTypes.CarConfig] = []
	var seen_ids: Dictionary = {}
	var car_entries: Array = cars_raw
	for index in range(car_entries.size()):
		var entry: Variant = car_entries[index]
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("cars[%d] must be an object." % index)
			continue

		var car_dict: Dictionary = entry
		var car_id: String = _read_car_id(car_dict, index, seen_ids, errors)
		if car_id.is_empty():
			continue

		var v_ref_raw: Variant = car_dict.get("v_ref", null)
		if not _is_numeric(v_ref_raw):
			errors.append("cars[%d].v_ref must be numeric." % index)
			continue
		var v_ref: float = float(v_ref_raw)
		if v_ref <= 0.0:
			errors.append("cars[%d].v_ref must be > 0." % index)
			continue

		var car_config: RaceTypes.CarConfig = RaceTypes.CarConfig.new()
		car_config.id = car_id
		car_config.display_name = _read_display_name(car_dict, car_id)
		car_config.v_ref = v_ref
		# Keep this set for HUD and state defaults; simulator uses v_ref in V1.1 mode.
		car_config.base_speed_units_per_sec = v_ref
		cars.append(car_config)

	return cars


static func _apply_v2_car_overrides(cars_raw: Array, cars: Array[RaceTypes.CarConfig], errors: PackedStringArray) -> void:
	var cars_by_id: Dictionary = {}
	for car in cars:
		if car != null and not car.id.is_empty():
			cars_by_id[car.id] = car

	for index in range(cars_raw.size()):
		var entry: Variant = cars_raw[index]
		if typeof(entry) != TYPE_DICTIONARY:
			continue

		var car_dict: Dictionary = entry
		var id_raw: Variant = car_dict.get("id", "")
		if typeof(id_raw) != TYPE_STRING:
			continue
		var car_id: String = String(id_raw).strip_edges()
		if car_id.is_empty() or not cars_by_id.has(car_id):
			continue

		var degradation_raw: Variant = car_dict.get("degradation", null)
		if degradation_raw == null:
			continue
		if typeof(degradation_raw) != TYPE_DICTIONARY:
			errors.append("cars[%d].degradation must be an object when provided." % index)
			continue
		var parse_result: Dictionary = _parse_degradation_config(
			degradation_raw,
			"cars[%d].degradation" % index
		)
		var parse_errors: PackedStringArray = parse_result.get("errors", PackedStringArray())
		for parse_error in parse_errors:
			errors.append(parse_error)
		var target_car: RaceTypes.CarConfig = cars_by_id[car_id]
		target_car.degradation = parse_result.get("config", null)


static func _apply_v3_car_overrides(cars_raw: Array, cars: Array[RaceTypes.CarConfig], errors: PackedStringArray) -> void:
	var cars_by_id: Dictionary = {}
	for car in cars:
		if car != null and not car.id.is_empty():
			cars_by_id[car.id] = car

	for index in range(cars_raw.size()):
		var entry: Variant = cars_raw[index]
		if typeof(entry) != TYPE_DICTIONARY:
			continue

		var car_dict: Dictionary = entry
		var id_raw: Variant = car_dict.get("id", "")
		if typeof(id_raw) != TYPE_STRING:
			continue
		var car_id: String = String(id_raw).strip_edges()
		if car_id.is_empty() or not cars_by_id.has(car_id):
			continue

		var target_car: RaceTypes.CarConfig = cars_by_id[car_id]
		if car_dict.has("starting_compound"):
			var starting_compound_raw: Variant = car_dict.get("starting_compound", "")
			if typeof(starting_compound_raw) != TYPE_STRING:
				errors.append("cars[%d].starting_compound must be a string when provided." % index)
			else:
				target_car.starting_compound = String(starting_compound_raw).strip_edges()

		if car_dict.has("starting_fuel_kg"):
			var starting_fuel_raw: Variant = car_dict.get("starting_fuel_kg", -1.0)
			if not _is_numeric(starting_fuel_raw):
				errors.append("cars[%d].starting_fuel_kg must be numeric when provided." % index)
			else:
				target_car.starting_fuel_kg = float(starting_fuel_raw)


static func _read_car_id(
	car_dict: Dictionary,
	index: int,
	seen_ids: Dictionary,
	errors: PackedStringArray
) -> String:
	var id_raw: Variant = car_dict.get("id", "")
	if typeof(id_raw) != TYPE_STRING:
		errors.append("cars[%d].id must be a string." % index)
		return ""
	var clean_id: String = String(id_raw).strip_edges()
	if clean_id.is_empty():
		errors.append("cars[%d].id must be non-empty." % index)
		return ""
	if seen_ids.has(clean_id):
		errors.append("cars[%d].id '%s' is duplicated." % [index, clean_id])
		return ""
	seen_ids[clean_id] = true
	return clean_id


static func _read_display_name(car_dict: Dictionary, fallback_id: String) -> String:
	var display_name_raw: Variant = car_dict.get("display_name", fallback_id)
	if typeof(display_name_raw) != TYPE_STRING:
		return fallback_id
	var clean_name: String = String(display_name_raw).strip_edges()
	return clean_name if not clean_name.is_empty() else fallback_id


static func _parse_debug(debug_raw: Dictionary) -> Dictionary:
	var errors: PackedStringArray = PackedStringArray()
	var debug: RaceTypes.DebugConfig = RaceTypes.DebugConfig.new()

	var show_pace_profile_raw: Variant = debug_raw.get("show_pace_profile", true)
	if typeof(show_pace_profile_raw) != TYPE_BOOL:
		errors.append("debug.show_pace_profile must be a boolean.")
	else:
		debug.show_pace_profile = show_pace_profile_raw

	var show_curvature_raw: Variant = debug_raw.get("show_curvature_overlay", false)
	if typeof(show_curvature_raw) != TYPE_BOOL:
		errors.append("debug.show_curvature_overlay must be a boolean.")
	else:
		debug.show_curvature_overlay = show_curvature_raw

	var show_speed_raw: Variant = debug_raw.get("show_speed_overlay", true)
	if typeof(show_speed_raw) != TYPE_BOOL:
		errors.append("debug.show_speed_overlay must be a boolean.")
	else:
		debug.show_speed_overlay = show_speed_raw

	return {"debug": debug, "errors": errors}


static func _parse_degradation_config(config_raw: Dictionary, context: String) -> Dictionary:
	var errors: PackedStringArray = PackedStringArray()
	var config: RaceTypes.DegradationConfig = RaceTypes.DegradationConfig.new()

	if config_raw.has("warmup_laps"):
		if _is_numeric(config_raw["warmup_laps"]):
			config.warmup_laps = float(config_raw["warmup_laps"])
		else:
			errors.append("%s.warmup_laps must be numeric." % context)
	if config_raw.has("peak_multiplier"):
		if _is_numeric(config_raw["peak_multiplier"]):
			config.peak_multiplier = float(config_raw["peak_multiplier"])
		else:
			errors.append("%s.peak_multiplier must be numeric." % context)
	if config_raw.has("degradation_rate"):
		if _is_numeric(config_raw["degradation_rate"]):
			config.degradation_rate = float(config_raw["degradation_rate"])
		else:
			errors.append("%s.degradation_rate must be numeric." % context)
	if config_raw.has("min_multiplier"):
		if _is_numeric(config_raw["min_multiplier"]):
			config.min_multiplier = float(config_raw["min_multiplier"])
		else:
			errors.append("%s.min_multiplier must be numeric." % context)
	if config_raw.has("optimal_threshold"):
		if _is_numeric(config_raw["optimal_threshold"]):
			config.optimal_threshold = float(config_raw["optimal_threshold"])
		else:
			errors.append("%s.optimal_threshold must be numeric." % context)
	if config_raw.has("cliff_threshold"):
		if _is_numeric(config_raw["cliff_threshold"]):
			config.cliff_threshold = float(config_raw["cliff_threshold"])
		else:
			errors.append("%s.cliff_threshold must be numeric." % context)
	if config_raw.has("cliff_multiplier"):
		if _is_numeric(config_raw["cliff_multiplier"]):
			config.cliff_multiplier = float(config_raw["cliff_multiplier"])
		else:
			errors.append("%s.cliff_multiplier must be numeric." % context)

	var validation_errors: PackedStringArray = DegradationModel.validate_config(config)
	for validation_error in validation_errors:
		errors.append("%s: %s" % [context, validation_error])

	return {"config": config, "errors": errors}


static func _parse_overtaking_config(config_raw: Dictionary, context: String) -> Dictionary:
	var errors: PackedStringArray = PackedStringArray()
	var config: RaceTypes.OvertakingConfig = RaceTypes.OvertakingConfig.new()

	if config_raw.has("enabled"):
		if typeof(config_raw["enabled"]) == TYPE_BOOL:
			config.enabled = config_raw["enabled"]
		else:
			errors.append("%s.enabled must be a boolean." % context)
	if config_raw.has("proximity_distance"):
		if _is_numeric(config_raw["proximity_distance"]):
			config.proximity_distance = float(config_raw["proximity_distance"])
		else:
			errors.append("%s.proximity_distance must be numeric." % context)
	if config_raw.has("overtake_speed_threshold"):
		if _is_numeric(config_raw["overtake_speed_threshold"]):
			config.overtake_speed_threshold = float(config_raw["overtake_speed_threshold"])
		else:
			errors.append("%s.overtake_speed_threshold must be numeric." % context)
	if config_raw.has("held_up_speed_buffer"):
		if _is_numeric(config_raw["held_up_speed_buffer"]):
			config.held_up_speed_buffer = float(config_raw["held_up_speed_buffer"])
		else:
			errors.append("%s.held_up_speed_buffer must be numeric." % context)
	if config_raw.has("cooldown_seconds"):
		if _is_numeric(config_raw["cooldown_seconds"]):
			config.cooldown_seconds = float(config_raw["cooldown_seconds"])
		else:
			errors.append("%s.cooldown_seconds must be numeric." % context)

	if config.proximity_distance < 0.0:
		errors.append("%s.proximity_distance must be >= 0." % context)
	if config.overtake_speed_threshold < 0.0:
		errors.append("%s.overtake_speed_threshold must be >= 0." % context)
	if config.held_up_speed_buffer < 0.0:
		errors.append("%s.held_up_speed_buffer must be >= 0." % context)
	if config.cooldown_seconds < 0.0:
		errors.append("%s.cooldown_seconds must be >= 0." % context)

	return {"config": config, "errors": errors}


static func _parse_compounds(compounds_raw: Variant, errors: PackedStringArray) -> Array[RaceTypes.TyreCompoundConfig]:
	var compounds: Array[RaceTypes.TyreCompoundConfig] = []
	var entries: Array = compounds_raw
	for index in range(entries.size()):
		var entry: Variant = entries[index]
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("compounds[%d] must be an object." % index)
			continue

		var compound_dict: Dictionary = entry
		var name_raw: Variant = compound_dict.get("name", "")
		if typeof(name_raw) != TYPE_STRING:
			errors.append("compounds[%d].name must be a string." % index)
			continue
		var clean_name: String = String(name_raw).strip_edges()
		if clean_name.is_empty():
			errors.append("compounds[%d].name must be non-empty." % index)
			continue

		var degradation_raw: Variant = compound_dict.get("degradation", null)
		if typeof(degradation_raw) != TYPE_DICTIONARY:
			errors.append("compounds[%d].degradation must be an object." % index)
			continue

		var degradation_result: Dictionary = _parse_degradation_config(
			degradation_raw,
			"compounds[%d].degradation" % index
		)
		var degradation_errors: PackedStringArray = degradation_result.get("errors", PackedStringArray())
		for degradation_error in degradation_errors:
			errors.append(degradation_error)

		var compound: RaceTypes.TyreCompoundConfig = RaceTypes.TyreCompoundConfig.new()
		compound.name = clean_name
		compound.degradation = degradation_result.get("config", null)
		compounds.append(compound)
	return compounds


static func _parse_fuel_config(config_raw: Dictionary, context: String) -> Dictionary:
	var errors: PackedStringArray = PackedStringArray()
	var config: RaceTypes.FuelConfig = RaceTypes.FuelConfig.new()

	if config_raw.has("enabled"):
		if typeof(config_raw["enabled"]) == TYPE_BOOL:
			config.enabled = config_raw["enabled"]
		else:
			errors.append("%s.enabled must be a boolean." % context)
	if config_raw.has("max_capacity_kg"):
		if _is_numeric(config_raw["max_capacity_kg"]):
			config.max_capacity_kg = float(config_raw["max_capacity_kg"])
		else:
			errors.append("%s.max_capacity_kg must be numeric." % context)
	if config_raw.has("consumption_per_lap_kg"):
		if _is_numeric(config_raw["consumption_per_lap_kg"]):
			config.consumption_per_lap_kg = float(config_raw["consumption_per_lap_kg"])
		else:
			errors.append("%s.consumption_per_lap_kg must be numeric." % context)
	if config_raw.has("weight_penalty_factor"):
		if _is_numeric(config_raw["weight_penalty_factor"]):
			config.weight_penalty_factor = float(config_raw["weight_penalty_factor"])
		else:
			errors.append("%s.weight_penalty_factor must be numeric." % context)
	if config_raw.has("fuel_empty_penalty"):
		if _is_numeric(config_raw["fuel_empty_penalty"]):
			config.fuel_empty_penalty = float(config_raw["fuel_empty_penalty"])
		else:
			errors.append("%s.fuel_empty_penalty must be numeric." % context)
	if config_raw.has("refuel_rate_kg_per_sec"):
		if _is_numeric(config_raw["refuel_rate_kg_per_sec"]):
			config.refuel_rate_kg_per_sec = float(config_raw["refuel_rate_kg_per_sec"])
		else:
			errors.append("%s.refuel_rate_kg_per_sec must be numeric." % context)

	var validation_errors: PackedStringArray = FuelModel.validate_config(config)
	for validation_error in validation_errors:
		errors.append(validation_error)
	return {"config": config, "errors": errors}


static func _parse_pit_config(config_raw: Dictionary, context: String) -> Dictionary:
	var errors: PackedStringArray = PackedStringArray()
	var config: RaceTypes.PitConfig = RaceTypes.PitConfig.new()

	if config_raw.has("enabled"):
		if typeof(config_raw["enabled"]) == TYPE_BOOL:
			config.enabled = config_raw["enabled"]
		else:
			errors.append("%s.enabled must be a boolean." % context)
	if config_raw.has("pit_entry_distance"):
		if _is_numeric(config_raw["pit_entry_distance"]):
			config.pit_entry_distance = float(config_raw["pit_entry_distance"])
		else:
			errors.append("%s.pit_entry_distance must be numeric." % context)
	if config_raw.has("pit_exit_distance"):
		if _is_numeric(config_raw["pit_exit_distance"]):
			config.pit_exit_distance = float(config_raw["pit_exit_distance"])
		else:
			errors.append("%s.pit_exit_distance must be numeric." % context)
	if config_raw.has("pit_box_distance"):
		if _is_numeric(config_raw["pit_box_distance"]):
			config.pit_box_distance = float(config_raw["pit_box_distance"])
		else:
			errors.append("%s.pit_box_distance must be numeric." % context)
	if config_raw.has("pit_lane_speed_limit"):
		if _is_numeric(config_raw["pit_lane_speed_limit"]):
			config.pit_lane_speed_limit = float(config_raw["pit_lane_speed_limit"])
		else:
			errors.append("%s.pit_lane_speed_limit must be numeric." % context)
	if config_raw.has("base_pit_stop_duration"):
		if _is_numeric(config_raw["base_pit_stop_duration"]):
			config.base_pit_stop_duration = float(config_raw["base_pit_stop_duration"])
		else:
			errors.append("%s.base_pit_stop_duration must be numeric." % context)
	if config_raw.has("pit_entry_duration"):
		if _is_numeric(config_raw["pit_entry_duration"]):
			config.pit_entry_duration = float(config_raw["pit_entry_duration"])
		else:
			errors.append("%s.pit_entry_duration must be numeric." % context)
	if config_raw.has("pit_exit_duration"):
		if _is_numeric(config_raw["pit_exit_duration"]):
			config.pit_exit_duration = float(config_raw["pit_exit_duration"])
		else:
			errors.append("%s.pit_exit_duration must be numeric." % context)
	if config_raw.has("min_stop_lap"):
		if _is_numeric(config_raw["min_stop_lap"]):
			config.min_stop_lap = int(config_raw["min_stop_lap"])
		else:
			errors.append("%s.min_stop_lap must be numeric." % context)
	if config_raw.has("max_stops"):
		if _is_numeric(config_raw["max_stops"]):
			config.max_stops = int(config_raw["max_stops"])
		else:
			errors.append("%s.max_stops must be numeric." % context)

	if config.pit_lane_speed_limit <= 0.0:
		errors.append("%s.pit_lane_speed_limit must be > 0." % context)
	if config.base_pit_stop_duration < 1.0:
		errors.append("%s.base_pit_stop_duration must be >= 1.0." % context)
	if config.min_stop_lap < 0:
		errors.append("%s.min_stop_lap must be >= 0." % context)
	if config.max_stops <= 0:
		errors.append("%s.max_stops must be > 0." % context)
	if config.pit_entry_distance < 0.0:
		errors.append("%s.pit_entry_distance must be >= 0." % context)
	if config.pit_exit_distance < 0.0:
		errors.append("%s.pit_exit_distance must be >= 0." % context)
	if is_equal_approx(config.pit_entry_distance, config.pit_exit_distance):
		errors.append("%s.pit_entry_distance must differ from pit_exit_distance." % context)
	if config.pit_box_distance >= 0.0:
		if is_equal_approx(config.pit_box_distance, config.pit_entry_distance):
			errors.append("%s.pit_box_distance must differ from pit_entry_distance." % context)
		if is_equal_approx(config.pit_box_distance, config.pit_exit_distance):
			errors.append("%s.pit_box_distance must differ from pit_exit_distance." % context)

	return {"config": config, "errors": errors}


static func _validate_pit_distances_against_track_length(
	config: RaceTypes.RaceConfig,
	source_path: String,
	errors: PackedStringArray
) -> void:
	if config == null or config.pit == null or not config.pit.enabled:
		return
	if not (config.track is RaceTypes.SpeedProfileConfig):
		return

	var speed_track: RaceTypes.SpeedProfileConfig = config.track as RaceTypes.SpeedProfileConfig
	if speed_track == null or speed_track.geometry_asset_path.strip_edges().is_empty():
		return

	var load_result: Dictionary = TrackLoader.load_track_geometry(speed_track.geometry_asset_path, source_path)
	var load_errors: PackedStringArray = load_result.get("errors", PackedStringArray())
	if not load_errors.is_empty():
		for load_error in load_errors:
			errors.append("pit track-length validation: %s" % load_error)
		return

	var geometry: RaceTypes.TrackGeometryData = load_result.get("geometry", null)
	if geometry == null or geometry.track_length <= 0.0:
		return

	if config.pit.pit_entry_distance >= geometry.track_length:
		errors.append("pit.pit_entry_distance must be in [0, track_length).")
	if config.pit.pit_exit_distance >= geometry.track_length:
		errors.append("pit.pit_exit_distance must be in [0, track_length).")
	if config.pit.pit_box_distance >= geometry.track_length:
		errors.append("pit.pit_box_distance must be in [0, track_length) when provided.")


static func _read_positive_float(
	dict_value: Dictionary,
	key: String,
	errors: PackedStringArray,
	context: String
) -> float:
	var raw: Variant = dict_value.get(key, null)
	if not _is_numeric(raw):
		errors.append("%s.%s must be numeric." % [context, key])
		return 0.0
	var value: float = float(raw)
	if value <= 0.0:
		errors.append("%s.%s must be > 0." % [context, key])
		return 0.0
	return value


static func _is_numeric(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
