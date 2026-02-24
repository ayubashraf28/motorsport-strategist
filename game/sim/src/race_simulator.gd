extends RefCounted
class_name RaceSimulator

const RaceTypes = preload("res://sim/src/race_types.gd")

var _config: RaceTypes.RaceConfig
var _runtime: RaceTypes.RaceRuntimeParams
var _cars: Array[RaceTypes.CarState] = []
var _race_time: float = 0.0
var _is_ready: bool = false
var _validation_errors: PackedStringArray = PackedStringArray()


func initialize(config: RaceTypes.RaceConfig, runtime: RaceTypes.RaceRuntimeParams) -> void:
	_validation_errors = PackedStringArray()
	_is_ready = false
	_cars.clear()

	_validate_inputs(config, runtime)
	if not _validation_errors.is_empty():
		return

	_config = config.clone()
	_runtime = runtime.clone()

	for car_config in _config.cars:
		var state := RaceTypes.CarState.new()
		state.id = car_config.id
		state.display_name = car_config.display_name
		state.speed_units_per_sec = car_config.speed_units_per_sec
		state.reset_runtime_state()
		_cars.append(state)

	_is_ready = true
	reset()


func reset() -> void:
	_race_time = 0.0
	for car in _cars:
		car.reset_runtime_state()


func step(dt_seconds: float) -> void:
	if not _is_ready or dt_seconds <= 0.0:
		return

	var frame_start_time: float = _race_time

	for car in _cars:
		_step_car(car, frame_start_time, dt_seconds)

	_race_time += dt_seconds


func get_snapshot() -> RaceTypes.RaceSnapshot:
	var snapshot := RaceTypes.RaceSnapshot.new()
	snapshot.race_time = _race_time
	for car in _cars:
		snapshot.cars.append(car.clone())
	return snapshot


func is_ready() -> bool:
	return _is_ready


func get_validation_errors() -> PackedStringArray:
	return _validation_errors


func _validate_inputs(config: RaceTypes.RaceConfig, runtime: RaceTypes.RaceRuntimeParams) -> void:
	if config == null:
		_validation_errors.append("RaceConfig is required.")
		return
	if runtime == null:
		_validation_errors.append("RaceRuntimeParams is required.")
		return
	if runtime.track_length <= 0.0:
		_validation_errors.append("Track length must be greater than zero.")

	if config.cars.is_empty():
		_validation_errors.append("At least one car must be configured.")
		return

	var seen_ids: Dictionary = {}
	for car in config.cars:
		if car == null:
			_validation_errors.append("Car configuration entries cannot be null.")
			continue
		var clean_id: String = car.id.strip_edges()
		if clean_id.is_empty():
			_validation_errors.append("Car id cannot be empty.")
			continue
		if seen_ids.has(clean_id):
			_validation_errors.append("Car id '%s' is duplicated." % clean_id)
		else:
			seen_ids[clean_id] = true
		if car.speed_units_per_sec <= 0.0:
			_validation_errors.append("Car '%s' speed_units_per_sec must be greater than zero." % clean_id)


func _step_car(car: RaceTypes.CarState, frame_start_time: float, dt_seconds: float) -> void:
	var speed: float = car.speed_units_per_sec
	if speed <= 0.0:
		return

	var track_length: float = _runtime.track_length
	if track_length <= 0.0:
		return

	var previous_distance: float = car.distance_along_track
	var raw_distance: float = previous_distance + speed * dt_seconds
	var laps_crossed: int = int(floor(raw_distance / track_length))
	car.distance_along_track = fposmod(raw_distance, track_length)

	if laps_crossed <= 0:
		return

	# Guard division points even though speed is validated. This makes math robust
	# against future config mutation or runtime editing.
	if speed <= 0.0:
		return

	var time_to_first_cross: float = (track_length - previous_distance) / speed
	var clamped_time_to_first_cross: float = time_to_first_cross if time_to_first_cross > 0.0 else 0.0
	var first_cross_time: float = frame_start_time + clamped_time_to_first_cross
	var lap_duration: float = track_length / speed

	for crossing_index in range(laps_crossed):
		var crossing_time: float = first_cross_time + float(crossing_index) * lap_duration
		_register_lap_crossing(car, crossing_time)


func _register_lap_crossing(car: RaceTypes.CarState, crossing_time: float) -> void:
	# Optional out-lap handling is kept explicit so that future race modes can
	# switch behavior without touching timing math in step().
	if not _config.count_first_lap_from_start and car.last_lap_time < 0.0 and car.lap_count == 0:
		car.lap_start_time = crossing_time
		return

	var raw_lap_time: float = crossing_time - car.lap_start_time
	var lap_time: float = raw_lap_time if raw_lap_time > 0.0 else 0.0
	car.last_lap_time = lap_time
	car.best_lap_time = min(car.best_lap_time, lap_time)
	car.lap_start_time = crossing_time
	car.lap_count += 1
