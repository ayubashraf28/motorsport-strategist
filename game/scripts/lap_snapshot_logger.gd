extends RefCounted
class_name LapSnapshotLogger

const RaceTypes = preload("res://sim/src/race_types.gd")
const StandingsCalculator = preload("res://sim/src/standings_calculator.gd")

const _DEFAULT_OUTPUT_DIR: String = "user://telemetry"

var _output_path: String = ""
var _file: FileAccess = null
var _last_logged_lap_by_car: Dictionary = {}
var _last_error: String = ""


func start_session(snapshot: RaceTypes.RaceSnapshot, output_dir: String = _DEFAULT_OUTPUT_DIR) -> void:
	close()
	_last_error = ""
	_output_path = ""
	_last_logged_lap_by_car.clear()

	var clean_dir: String = output_dir.strip_edges()
	if clean_dir.is_empty():
		clean_dir = _DEFAULT_OUTPUT_DIR

	var absolute_dir: String = _resolve_output_dir(clean_dir)
	var make_dir_error: int = DirAccess.make_dir_recursive_absolute(absolute_dir)
	if make_dir_error != OK:
		_last_error = "Failed to create telemetry directory '%s' (code=%d)." % [absolute_dir, make_dir_error]
		return

	var stamp: String = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	_output_path = absolute_dir.path_join("lap_snapshots_%s.jsonl" % stamp)
	_file = FileAccess.open(_output_path, FileAccess.WRITE)
	if _file == null:
		_last_error = "Failed to open telemetry file at '%s'." % _output_path
		_output_path = ""
		return

	_write_json_line({
		"event": "session_start",
		"created_unix_s": Time.get_unix_time_from_system()
	})

	if snapshot == null:
		return

	var interval_map: Dictionary = StandingsCalculator.compute_interval_to_car_ahead(snapshot.cars)
	for raw_car in snapshot.cars:
		var car: RaceTypes.CarState = raw_car as RaceTypes.CarState
		if car == null:
			continue
		_write_lap_snapshot(snapshot, car, interval_map)
		_last_logged_lap_by_car[car.id] = car.lap_count


func capture(snapshot: RaceTypes.RaceSnapshot) -> void:
	if _file == null or snapshot == null:
		return

	var interval_map: Dictionary = StandingsCalculator.compute_interval_to_car_ahead(snapshot.cars)
	for raw_car in snapshot.cars:
		var car: RaceTypes.CarState = raw_car as RaceTypes.CarState
		if car == null:
			continue

		var last_logged_lap: int = int(_last_logged_lap_by_car.get(car.id, -1))
		if car.lap_count <= last_logged_lap:
			continue

		_write_lap_snapshot(snapshot, car, interval_map)
		_last_logged_lap_by_car[car.id] = car.lap_count


func close() -> void:
	if _file != null:
		_write_json_line({
			"event": "session_end",
			"closed_unix_s": Time.get_unix_time_from_system()
		})
		_file.close()
	_file = null


func get_output_path() -> String:
	return _output_path


func get_last_error() -> String:
	return _last_error


func _resolve_output_dir(path_value: String) -> String:
	if path_value.begins_with("res://") or path_value.begins_with("user://"):
		return ProjectSettings.globalize_path(path_value)
	if path_value.is_absolute_path():
		return path_value
	return ProjectSettings.globalize_path(path_value)


func _write_lap_snapshot(
	snapshot: RaceTypes.RaceSnapshot,
	car: RaceTypes.CarState,
	interval_map: Dictionary
) -> void:
	var gap_to_ahead_seconds: Variant = null
	if car.position > 1 and car.effective_speed_units_per_sec > 0.0:
		var interval_distance: float = float(interval_map.get(car.id, 0.0))
		gap_to_ahead_seconds = interval_distance / car.effective_speed_units_per_sec

	_write_json_line({
		"event": "lap_start_snapshot",
		"race_time_s": snapshot.race_time,
		"race_state": _race_state_name(snapshot.race_state),
		"car_id": car.id,
		"position": car.position,
		"completed_laps": car.lap_count,
		"lap_number": car.lap_count + 1,
		"gap_to_ahead_s": _finite_or_null(gap_to_ahead_seconds),
		"distance_along_track": car.distance_along_track,
		"total_distance": car.total_distance,
		"current_compound": car.current_compound,
		"stint_number": car.stint_number,
		"stint_lap_count": car.stint_lap_count,
		"degradation_multiplier": _finite_or_null(car.degradation_multiplier),
		"tyre_life_ratio": _finite_or_null(car.tyre_life_ratio),
		"tyre_phase": _tyre_phase_name(car.tyre_phase),
		"fuel_kg": _finite_or_null(car.fuel_kg),
		"fuel_multiplier": _finite_or_null(car.fuel_multiplier),
		"strategy_multiplier": _finite_or_null(car.strategy_multiplier),
		"reference_speed_units_per_sec": _finite_or_null(car.reference_speed_units_per_sec),
		"effective_speed_units_per_sec": _finite_or_null(car.effective_speed_units_per_sec),
		"last_lap_time_s": _finite_or_null(car.last_lap_time),
		"best_lap_time_s": _finite_or_null(car.best_lap_time),
		"is_in_pit": car.is_in_pit
	})


func _write_json_line(payload: Dictionary) -> void:
	if _file == null:
		return
	_file.store_line(JSON.stringify(payload))
	_file.flush()


func _finite_or_null(value: Variant) -> Variant:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return null if value == null else value
	var casted_value: float = float(value)
	if is_nan(casted_value) or is_inf(casted_value):
		return null
	return casted_value


func _race_state_name(state: int) -> String:
	match state:
		RaceTypes.RaceState.NOT_STARTED:
			return "NOT_STARTED"
		RaceTypes.RaceState.RUNNING:
			return "RUNNING"
		RaceTypes.RaceState.FINISHING:
			return "FINISHING"
		RaceTypes.RaceState.FINISHED:
			return "FINISHED"
	return "UNKNOWN"


func _tyre_phase_name(phase: int) -> String:
	match phase:
		RaceTypes.TyrePhase.OPTIMAL:
			return "OPTIMAL"
		RaceTypes.TyrePhase.GRADUAL:
			return "GRADUAL"
		RaceTypes.TyrePhase.CLIFF:
			return "CLIFF"
	return "UNKNOWN"
