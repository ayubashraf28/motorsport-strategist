extends RefCounted
class_name TrackRegistry


static func _get_registry_path() -> String:
	return ProjectSettings.globalize_path("res://../config/tracks/registry.json")


static func _get_tracks_dir() -> String:
	return ProjectSettings.globalize_path("res://../config/tracks")


static func load_registry() -> Dictionary:
	var path: String = _get_registry_path()
	if not FileAccess.file_exists(path):
		return {"tracks": [], "errors": PackedStringArray(["Track registry not found at '%s'." % path])}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"tracks": [], "errors": PackedStringArray(["Failed to open track registry at '%s'." % path])}

	var json: JSON = JSON.new()
	var err: Error = json.parse(file.get_as_text())
	if err != OK:
		return {"tracks": [], "errors": PackedStringArray(["Failed to parse track registry: %s" % json.get_error_message()])}

	var data: Dictionary = json.data
	if not data.has("tracks") or not data["tracks"] is Array:
		return {"tracks": [], "errors": PackedStringArray(["Track registry missing 'tracks' array."])}

	return {"tracks": data["tracks"], "errors": PackedStringArray()}


static func load_track_config(track_id: String) -> Dictionary:
	var registry_result: Dictionary = load_registry()
	var errors: PackedStringArray = registry_result.get("errors", PackedStringArray())
	if not errors.is_empty():
		return {"config": {}, "errors": errors}

	var tracks: Array = registry_result["tracks"]
	var config_filename: String = ""
	for entry in tracks:
		if entry.get("id", "") == track_id:
			config_filename = entry.get("config_path", "")
			break

	if config_filename.is_empty():
		return {"config": {}, "errors": PackedStringArray(["Track '%s' not found in registry." % track_id])}

	var config_path: String = _get_tracks_dir() + "/" + config_filename
	if not FileAccess.file_exists(config_path):
		return {"config": {}, "errors": PackedStringArray(["Track config not found at '%s'." % config_path])}

	var file: FileAccess = FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		return {"config": {}, "errors": PackedStringArray(["Failed to open track config at '%s'." % config_path])}

	var json: JSON = JSON.new()
	var err: Error = json.parse(file.get_as_text())
	if err != OK:
		return {"config": {}, "errors": PackedStringArray(["Failed to parse track config: %s" % json.get_error_message()])}

	return {"config": json.data, "config_path": config_path, "errors": PackedStringArray()}


static func get_track_list() -> Array:
	var registry_result: Dictionary = load_registry()
	if not registry_result.get("errors", PackedStringArray()).is_empty():
		return []
	return registry_result["tracks"]
