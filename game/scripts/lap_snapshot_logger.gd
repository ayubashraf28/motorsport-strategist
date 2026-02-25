extends RefCounted
class_name LapSnapshotLogger

const RaceTypes = preload("res://sim/src/race_types.gd")
const StandingsCalculator = preload("res://sim/src/standings_calculator.gd")

const _DEFAULT_OUTPUT_DIR: String = "user://telemetry"

var _output_path: String = ""
var _file: FileAccess = null
var _last_logged_lap_by_car: Dictionary = {}
var _last_state_by_car: Dictionary = {}
var _last_error: String = ""


func start_session(snapshot: RaceTypes.RaceSnapshot, output_dir: String = _DEFAULT_OUTPUT_DIR) -> void:
	close()
	_last_error = ""
	_output_path = ""
	_last_logged_lap_by_car.clear()
	_last_state_by_car.clear()

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
		_write_lap_snapshot(snapshot, car, interval_map, {})
		_last_logged_lap_by_car[car.id] = car.lap_count
		_last_state_by_car[car.id] = _build_car_state_marker(car, {})


func capture(snapshot: RaceTypes.RaceSnapshot, pending_pit_requests: Dictionary = {}) -> void:
	if _file == null or snapshot == null:
		return

	var interval_map: Dictionary = StandingsCalculator.compute_interval_to_car_ahead(snapshot.cars)
	for raw_car in snapshot.cars:
		var car: RaceTypes.CarState = raw_car as RaceTypes.CarState
		if car == null:
			continue

		var pending_request: Dictionary = _normalize_pending_request(
			pending_pit_requests.get(car.id, {})
		)
		var prev_state: Dictionary = _last_state_by_car.get(car.id, {})
		if not prev_state.is_empty():
			_maybe_write_pending_request_event(snapshot, car, prev_state, pending_request)
			_maybe_write_pit_state_event(snapshot, car, prev_state, pending_request)
			_maybe_write_pit_stop_complete_event(snapshot, car, prev_state, pending_request)
			_maybe_write_compound_change_event(snapshot, car, prev_state, pending_request)
			_maybe_write_finish_event(snapshot, car, prev_state, pending_request)

		var last_logged_lap: int = int(_last_logged_lap_by_car.get(car.id, -1))
		if car.lap_count > last_logged_lap:
			_write_lap_snapshot(snapshot, car, interval_map, pending_request)
			_last_logged_lap_by_car[car.id] = car.lap_count

		_last_state_by_car[car.id] = _build_car_state_marker(car, pending_request)


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
	interval_map: Dictionary,
	pending_request: Dictionary
) -> void:
	var gap_to_ahead_seconds: Variant = null
	if car.position > 1 and car.effective_speed_units_per_sec > 0.0:
		var interval_distance: float = float(interval_map.get(car.id, 0.0))
		gap_to_ahead_seconds = interval_distance / car.effective_speed_units_per_sec

	var payload: Dictionary = _build_car_payload(snapshot, car, pending_request)
	payload["event"] = "lap_start_snapshot"
	payload["gap_to_ahead_s"] = _finite_or_null(gap_to_ahead_seconds)
	payload["lap_number"] = car.lap_count + 1

	_write_json_line(payload)


func _maybe_write_pending_request_event(
	snapshot: RaceTypes.RaceSnapshot,
	car: RaceTypes.CarState,
	prev_state: Dictionary,
	pending_request: Dictionary
) -> void:
	var prev_pending: bool = bool(prev_state.get("pending_request_active", false))
	var next_pending: bool = bool(pending_request.get("is_pending", false))
	var prev_compound: String = String(prev_state.get("pending_request_compound", ""))
	var next_compound: String = String(pending_request.get("requested_compound", ""))
	var prev_fuel: float = float(prev_state.get("pending_request_fuel_kg", -1.0))
	var next_fuel: float = float(pending_request.get("requested_fuel_kg", -1.0))
	var changed: bool = prev_pending != next_pending
	changed = changed or prev_compound != next_compound
	changed = changed or not is_equal_approx(prev_fuel, next_fuel)
	if not changed:
		return

	var payload: Dictionary = _build_car_payload(snapshot, car, pending_request)
	payload["event"] = "pit_request_change"
	payload["previous_pending"] = prev_pending
	payload["current_pending"] = next_pending
	payload["previous_requested_compound"] = prev_compound
	payload["current_requested_compound"] = next_compound
	payload["previous_requested_fuel_kg"] = _finite_or_null(prev_fuel)
	payload["current_requested_fuel_kg"] = _finite_or_null(next_fuel)
	_write_json_line(payload)


func _maybe_write_pit_state_event(
	snapshot: RaceTypes.RaceSnapshot,
	car: RaceTypes.CarState,
	prev_state: Dictionary,
	pending_request: Dictionary
) -> void:
	var prev_is_in_pit: bool = bool(prev_state.get("is_in_pit", false))
	var prev_pit_phase: int = int(prev_state.get("pit_phase", RaceTypes.PitPhase.RACING))
	if prev_is_in_pit == car.is_in_pit and prev_pit_phase == car.pit_phase:
		return

	var payload: Dictionary = _build_car_payload(snapshot, car, pending_request)
	payload["event"] = "pit_state_change"
	payload["previous_is_in_pit"] = prev_is_in_pit
	payload["current_is_in_pit"] = car.is_in_pit
	payload["previous_pit_phase"] = _pit_phase_name(prev_pit_phase)
	payload["current_pit_phase"] = _pit_phase_name(car.pit_phase)
	_write_json_line(payload)


func _maybe_write_pit_stop_complete_event(
	snapshot: RaceTypes.RaceSnapshot,
	car: RaceTypes.CarState,
	prev_state: Dictionary,
	pending_request: Dictionary
) -> void:
	var prev_stops: int = int(prev_state.get("pit_stops_completed", 0))
	if car.pit_stops_completed <= prev_stops:
		return

	var payload: Dictionary = _build_car_payload(snapshot, car, pending_request)
	payload["event"] = "pit_stop_complete"
	payload["previous_pit_stops_completed"] = prev_stops
	payload["current_pit_stops_completed"] = car.pit_stops_completed
	_write_json_line(payload)


func _maybe_write_compound_change_event(
	snapshot: RaceTypes.RaceSnapshot,
	car: RaceTypes.CarState,
	prev_state: Dictionary,
	pending_request: Dictionary
) -> void:
	var prev_compound: String = String(prev_state.get("current_compound", ""))
	if prev_compound == car.current_compound:
		return

	var payload: Dictionary = _build_car_payload(snapshot, car, pending_request)
	payload["event"] = "compound_change"
	payload["previous_compound"] = prev_compound
	payload["current_compound"] = car.current_compound
	_write_json_line(payload)


func _maybe_write_finish_event(
	snapshot: RaceTypes.RaceSnapshot,
	car: RaceTypes.CarState,
	prev_state: Dictionary,
	pending_request: Dictionary
) -> void:
	var prev_finished: bool = bool(prev_state.get("is_finished", false))
	if prev_finished or not car.is_finished:
		return

	var payload: Dictionary = _build_car_payload(snapshot, car, pending_request)
	payload["event"] = "car_finished"
	_write_json_line(payload)


func _build_car_payload(
	snapshot: RaceTypes.RaceSnapshot,
	car: RaceTypes.CarState,
	pending_request: Dictionary
) -> Dictionary:
	return {
		"event": "lap_start_snapshot",
		"race_time_s": snapshot.race_time,
		"race_state": _race_state_name(snapshot.race_state),
		"car_id": car.id,
		"position": car.position,
		"finish_position": car.finish_position,
		"is_finished": car.is_finished,
		"finish_time_s": _finite_or_null(car.finish_time),
		"completed_laps": car.lap_count,
		"lap_start_time_s": _finite_or_null(car.lap_start_time),
		"distance_along_track": car.distance_along_track,
		"total_distance": car.total_distance,
		"current_multiplier": _finite_or_null(car.current_multiplier),
		"base_speed_units_per_sec": _finite_or_null(car.base_speed_units_per_sec),
		"v_ref": _finite_or_null(car.v_ref),
		"current_compound": car.current_compound,
		"stint_number": car.stint_number,
		"stint_lap_count": car.stint_lap_count,
		"is_in_pit": car.is_in_pit,
		"pit_phase": _pit_phase_name(car.pit_phase),
		"pit_time_remaining_s": _finite_or_null(car.pit_time_remaining),
		"pit_stops_completed": car.pit_stops_completed,
		"pit_target_compound": car.pit_target_compound,
		"pit_target_fuel_kg": _finite_or_null(car.pit_target_fuel_kg),
		"pending_pit_request": bool(pending_request.get("is_pending", false)),
		"pending_request_compound": String(pending_request.get("requested_compound", "")),
		"pending_request_fuel_kg": _finite_or_null(float(pending_request.get("requested_fuel_kg", -1.0))),
		"degradation_multiplier": _finite_or_null(car.degradation_multiplier),
		"tyre_life_ratio": _finite_or_null(car.tyre_life_ratio),
		"tyre_phase": _tyre_phase_name(car.tyre_phase),
		"fuel_kg": _finite_or_null(car.fuel_kg),
		"fuel_multiplier": _finite_or_null(car.fuel_multiplier),
		"strategy_multiplier": _finite_or_null(car.strategy_multiplier),
		"reference_speed_units_per_sec": _finite_or_null(car.reference_speed_units_per_sec),
		"effective_speed_units_per_sec": _finite_or_null(car.effective_speed_units_per_sec),
		"is_held_up": car.is_held_up,
		"held_up_by": car.held_up_by,
		"last_lap_time_s": _finite_or_null(car.last_lap_time),
		"best_lap_time_s": _finite_or_null(car.best_lap_time)
	}


func _build_car_state_marker(car: RaceTypes.CarState, pending_request: Dictionary) -> Dictionary:
	return {
		"lap_count": car.lap_count,
		"is_in_pit": car.is_in_pit,
		"pit_phase": car.pit_phase,
		"pit_stops_completed": car.pit_stops_completed,
		"current_compound": car.current_compound,
		"is_finished": car.is_finished,
		"pending_request_active": bool(pending_request.get("is_pending", false)),
		"pending_request_compound": String(pending_request.get("requested_compound", "")),
		"pending_request_fuel_kg": float(pending_request.get("requested_fuel_kg", -1.0))
	}


func _normalize_pending_request(raw_pending_request: Variant) -> Dictionary:
	if typeof(raw_pending_request) != TYPE_DICTIONARY:
		return {
			"is_pending": false,
			"requested_compound": "",
			"requested_fuel_kg": -1.0
		}
	var pending_dict: Dictionary = raw_pending_request
	return {
		"is_pending": not pending_dict.is_empty(),
		"requested_compound": String(pending_dict.get("compound", "")).strip_edges(),
		"requested_fuel_kg": float(pending_dict.get("fuel_kg", -1.0))
	}


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


func _pit_phase_name(phase: int) -> String:
	match phase:
		RaceTypes.PitPhase.RACING:
			return "RACING"
		RaceTypes.PitPhase.ENTRY:
			return "ENTRY"
		RaceTypes.PitPhase.STOPPED:
			return "STOPPED"
		RaceTypes.PitPhase.EXIT:
			return "EXIT"
	return "UNKNOWN"
