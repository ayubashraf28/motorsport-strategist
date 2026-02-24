extends RefCounted
class_name TrackLoader

const RaceTypes = preload("res://sim/src/race_types.gd")


static func load_track_geometry(asset_path: String, config_source_path: String = "") -> Dictionary:
	var errors: PackedStringArray = PackedStringArray()
	var resolved_path: String = _resolve_asset_path(asset_path, config_source_path)
	if resolved_path.is_empty():
		errors.append("Track geometry asset path is empty.")
		return _result(null, PackedVector2Array(), resolved_path, errors)

	if not FileAccess.file_exists(resolved_path):
		errors.append("Track geometry asset not found at '%s'." % resolved_path)
		return _result(null, PackedVector2Array(), resolved_path, errors)

	var file: FileAccess = FileAccess.open(resolved_path, FileAccess.READ)
	if file == null:
		errors.append("Failed to open track geometry asset at '%s'." % resolved_path)
		return _result(null, PackedVector2Array(), resolved_path, errors)

	var parse_result: Dictionary = _parse_geometry_json(file.get_as_text())
	var parse_errors: PackedStringArray = parse_result.get("errors", PackedStringArray())
	for parse_error in parse_errors:
		errors.append(parse_error)

	if not errors.is_empty():
		return _result(null, PackedVector2Array(), resolved_path, errors)

	var geometry: RaceTypes.TrackGeometryData = parse_result.get("geometry", null)
	var polyline: PackedVector2Array = parse_result.get("polyline", PackedVector2Array())
	return _result(geometry, polyline, resolved_path, errors)


static func _resolve_asset_path(asset_path: String, config_source_path: String) -> String:
	var trimmed_asset_path: String = asset_path.strip_edges()
	if trimmed_asset_path.is_empty():
		return ""

	if trimmed_asset_path.begins_with("res://"):
		return ProjectSettings.globalize_path(trimmed_asset_path)

	# Accept absolute paths for local debugging.
	if _is_absolute_path(trimmed_asset_path):
		return trimmed_asset_path

	var base_directory: String = ProjectSettings.globalize_path("res://")
	if not config_source_path.is_empty():
		base_directory = config_source_path.get_base_dir()
	return base_directory.path_join(trimmed_asset_path)


static func _is_absolute_path(path: String) -> bool:
	return path.begins_with("/") or path.contains(":\\") or path.contains(":/")


static func _parse_geometry_json(content: String) -> Dictionary:
	var errors: PackedStringArray = PackedStringArray()
	var parser: JSON = JSON.new()
	var parse_status: int = parser.parse(content)
	if parse_status != OK:
		errors.append("Invalid JSON in track geometry asset: %s" % parser.get_error_message())
		return _result(null, PackedVector2Array(), "", errors)

	if typeof(parser.data) != TYPE_DICTIONARY:
		errors.append("Track geometry root must be a JSON object.")
		return _result(null, PackedVector2Array(), "", errors)

	var root: Dictionary = parser.data
	var sample_interval_raw: Variant = root.get("sample_interval_units", null)
	var track_length_raw: Variant = root.get("track_length_units", null)
	var sample_count_raw: Variant = root.get("sample_count", null)
	var samples_raw: Variant = root.get("samples", null)

	if not _is_numeric(sample_interval_raw):
		errors.append("track.sample_interval_units must be numeric.")
	if not _is_numeric(track_length_raw):
		errors.append("track.track_length_units must be numeric.")
	if not _is_numeric(sample_count_raw):
		errors.append("track.sample_count must be numeric.")
	if typeof(samples_raw) != TYPE_ARRAY:
		errors.append("track.samples must be an array.")

	if not errors.is_empty():
		return _result(null, PackedVector2Array(), "", errors)

	var sample_interval: float = float(sample_interval_raw)
	var declared_track_length: float = float(track_length_raw)
	var declared_sample_count: int = int(sample_count_raw)
	var sample_entries: Array = samples_raw

	if sample_interval <= 0.0:
		errors.append("track.sample_interval_units must be > 0.")
	if declared_track_length <= 0.0:
		errors.append("track.track_length_units must be > 0.")
	if declared_sample_count < 3:
		errors.append("track.sample_count must be >= 3.")
	if sample_entries.size() != declared_sample_count:
		errors.append(
			"track.samples length %d does not match sample_count %d." %
			[sample_entries.size(), declared_sample_count]
		)

	if not errors.is_empty():
		return _result(null, PackedVector2Array(), "", errors)

	var positions_x: PackedFloat32Array = PackedFloat32Array()
	var positions_y: PackedFloat32Array = PackedFloat32Array()
	var curvatures: PackedFloat64Array = PackedFloat64Array()
	var polyline: PackedVector2Array = PackedVector2Array()
	positions_x.resize(declared_sample_count)
	positions_y.resize(declared_sample_count)
	curvatures.resize(declared_sample_count)
	polyline.resize(declared_sample_count)

	for i in range(declared_sample_count):
		var sample_value: Variant = sample_entries[i]
		if typeof(sample_value) != TYPE_DICTIONARY:
			errors.append("track.samples[%d] must be an object." % i)
			continue

		var sample_dict: Dictionary = sample_value
		var x_raw: Variant = sample_dict.get("x", null)
		var y_raw: Variant = sample_dict.get("y", null)
		var kappa_raw: Variant = sample_dict.get("kappa", null)
		if not _is_numeric(x_raw) or not _is_numeric(y_raw) or not _is_numeric(kappa_raw):
			errors.append("track.samples[%d] requires numeric x, y, and kappa." % i)
			continue

		var x: float = float(x_raw)
		var y: float = float(y_raw)
		positions_x[i] = x
		positions_y[i] = y
		curvatures[i] = float(kappa_raw)
		polyline[i] = Vector2(x, y)

	if not errors.is_empty():
		return _result(null, PackedVector2Array(), "", errors)

	var measured_track_length: float = 0.0
	for i in range(declared_sample_count):
		var next_index: int = (i + 1) % declared_sample_count
		measured_track_length += polyline[i].distance_to(polyline[next_index])
	if measured_track_length <= 0.0:
		errors.append("track.samples produced zero track length.")
		return _result(null, PackedVector2Array(), "", errors)

	# Keep runtime geometry self-consistent with the loaded polyline used by view.
	# The declared length is still validated to catch corrupted assets.
	var length_delta: float = abs(measured_track_length - declared_track_length)
	if length_delta > 2.0:
		errors.append(
			"track.track_length_units %.5f disagrees with sampled polyline length %.5f." %
			[declared_track_length, measured_track_length]
		)
		return _result(null, PackedVector2Array(), "", errors)

	var geometry: RaceTypes.TrackGeometryData = RaceTypes.TrackGeometryData.new()
	geometry.sample_count = declared_sample_count
	geometry.ds = sample_interval
	geometry.track_length = measured_track_length
	geometry.positions_x = positions_x
	geometry.positions_y = positions_y
	geometry.curvatures = curvatures
	return _result(geometry, polyline, "", errors)


static func _is_numeric(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _result(
	geometry: RaceTypes.TrackGeometryData,
	polyline: PackedVector2Array,
	resolved_path: String,
	errors: PackedStringArray
) -> Dictionary:
	return {
		"geometry": geometry,
		"polyline": polyline,
		"resolved_path": resolved_path,
		"errors": errors
	}
