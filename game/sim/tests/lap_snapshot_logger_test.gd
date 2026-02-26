extends GdUnitTestSuite

const RaceTypes = preload("res://sim/src/race_types.gd")
const LapSnapshotLogger = preload("res://scripts/lap_snapshot_logger.gd")


func test_start_session_writes_initial_lap_snapshot_for_each_car() -> void:
	var logger := LapSnapshotLogger.new()
	var snapshot: RaceTypes.RaceSnapshot = _build_snapshot([
		_build_car("car_01", 1, 0),
		_build_car("car_02", 2, 0)
	], 0.0)

	logger.start_session(snapshot, "user://telemetry_test")
	assert(logger.get_last_error().is_empty())
	var output_path: String = logger.get_output_path()
	assert(not output_path.is_empty())
	logger.close()

	var entries: Array = _read_jsonl(output_path)
	var lap_entries: Array = _filter_entries(entries, "lap_start_snapshot")
	assert(lap_entries.size() == 2)
	assert(int(lap_entries[0]["lap_number"]) == 1)
	assert(int(lap_entries[1]["lap_number"]) == 1)
	assert(lap_entries[0].has("driver_mode"))
	assert(lap_entries[0].has("drs_active"))
	assert(lap_entries[0].has("drs_eligible"))
	assert(lap_entries[0].has("team_id"))
	assert(lap_entries[0].has("team_order"))
	assert(lap_entries[0].has("team_order_target"))
	assert(lap_entries[0].has("safety_car_phase"))
	assert(lap_entries[0].has("safety_car_laps_remaining"))


func test_capture_logs_only_when_lap_count_increases() -> void:
	var logger := LapSnapshotLogger.new()
	var snapshot: RaceTypes.RaceSnapshot = _build_snapshot([
		_build_car("car_01", 1, 0)
	], 0.0)

	logger.start_session(snapshot, "user://telemetry_test")
	assert(logger.get_last_error().is_empty())
	logger.capture(snapshot)

	var car: RaceTypes.CarState = snapshot.cars[0]
	car.lap_count = 1
	car.last_lap_time = 2.0
	snapshot.race_time = 2.0
	logger.capture(snapshot)
	var output_path: String = logger.get_output_path()
	logger.close()

	var entries: Array = _read_jsonl(output_path)
	var lap_entries: Array = _filter_entries(entries, "lap_start_snapshot")
	assert(lap_entries.size() == 2)
	assert(int(lap_entries[0]["lap_number"]) == 1)
	assert(int(lap_entries[1]["lap_number"]) == 2)


func test_capture_logs_pit_and_request_events() -> void:
	var logger := LapSnapshotLogger.new()
	var snapshot: RaceTypes.RaceSnapshot = _build_snapshot([
		_build_car("car_01", 1, 0)
	], 0.0)
	var pending_requests := {}

	logger.start_session(snapshot, "user://telemetry_test")
	assert(logger.get_last_error().is_empty())

	pending_requests["car_01"] = {"compound": "hard", "fuel_kg": 90.0}
	logger.capture(snapshot, pending_requests)

	var car: RaceTypes.CarState = snapshot.cars[0]
	car.is_in_pit = true
	car.pit_phase = RaceTypes.PitPhase.ENTRY
	snapshot.race_time = 1.0
	logger.capture(snapshot, pending_requests)

	car.pit_phase = RaceTypes.PitPhase.STOPPED
	snapshot.race_time = 2.0
	logger.capture(snapshot, pending_requests)

	car.pit_phase = RaceTypes.PitPhase.RACING
	car.is_in_pit = false
	car.pit_stops_completed = 1
	car.current_compound = "hard"
	snapshot.race_time = 3.0
	pending_requests.erase("car_01")
	logger.capture(snapshot, pending_requests)

	var output_path: String = logger.get_output_path()
	logger.close()

	var entries: Array = _read_jsonl(output_path)
	assert(_filter_entries(entries, "pit_request_change").size() >= 2)
	assert(_filter_entries(entries, "pit_state_change").size() >= 3)
	assert(_filter_entries(entries, "pit_stop_complete").size() >= 1)
	assert(_filter_entries(entries, "compound_change").size() >= 1)


func _build_snapshot(cars: Array, race_time: float) -> RaceTypes.RaceSnapshot:
	var snapshot := RaceTypes.RaceSnapshot.new()
	snapshot.race_state = RaceTypes.RaceState.RUNNING
	snapshot.race_time = race_time
	for raw_car in cars:
		var car: RaceTypes.CarState = raw_car as RaceTypes.CarState
		if car != null:
			snapshot.cars.append(car)
	return snapshot


func _build_car(car_id: String, position: int, lap_count: int) -> RaceTypes.CarState:
	var car := RaceTypes.CarState.new()
	car.id = car_id
	car.position = position
	car.lap_count = lap_count
	car.total_distance = float(lap_count) * 100.0
	car.reference_speed_units_per_sec = 50.0
	car.effective_speed_units_per_sec = 50.0
	car.degradation_multiplier = 0.95
	car.tyre_life_ratio = 0.85
	car.tyre_phase = RaceTypes.TyrePhase.OPTIMAL
	car.fuel_kg = 100.0
	car.fuel_multiplier = 0.95
	car.strategy_multiplier = 0.9025
	car.current_compound = "soft"
	car.best_lap_time = 2.0
	car.last_lap_time = 2.0 if lap_count > 0 else -1.0
	return car


func _read_jsonl(path: String) -> Array:
	var entries: Array = []
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return entries
	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if line.is_empty():
			continue
		var parser: JSON = JSON.new()
		if parser.parse(line) == OK and typeof(parser.data) == TYPE_DICTIONARY:
			entries.append(parser.data)
	file.close()
	return entries


func _filter_entries(entries: Array, event_type: String) -> Array:
	var filtered: Array = []
	for raw_entry in entries:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw_entry
		if String(entry.get("event", "")) == event_type:
			filtered.append(entry)
	return filtered
