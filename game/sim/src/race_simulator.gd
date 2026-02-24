extends RefCounted
class_name RaceSimulator

const RaceTypes = preload("res://sim/src/race_types.gd")
const PaceProfile = preload("res://sim/src/pace_profile.gd")
const SpeedProfile = preload("res://sim/src/speed_profile.gd")
const StandingsCalculator = preload("res://sim/src/standings_calculator.gd")
const RaceStateMachine = preload("res://sim/src/race_state_machine.gd")
const DegradationModel = preload("res://sim/src/degradation_model.gd")
const OvertakingManager = preload("res://sim/src/overtaking_manager.gd")

const _INTERNAL_INTEGRATION_STEP: float = 1.0 / 120.0
const _LAP_CROSS_EPSILON: float = 0.000001

var _config: RaceTypes.RaceConfig
var _runtime: RaceTypes.RaceRuntimeParams
var _cars: Array[RaceTypes.CarState] = []
var _race_time: float = 0.0
var _pace_profile: PaceProfile = null
var _speed_profile: SpeedProfile = null
var _physics_config: RaceTypes.PhysicsVehicleConfig = null
var _is_ready: bool = false
var _validation_errors: PackedStringArray = PackedStringArray()
var _race_state_machine: RaceStateMachine = RaceStateMachine.new()
var _car_degradation_configs: Dictionary = {}
var _overtaking_manager: OvertakingManager = OvertakingManager.new()


func initialize(config: RaceTypes.RaceConfig, runtime: RaceTypes.RaceRuntimeParams) -> void:
	_validation_errors = PackedStringArray()
	_is_ready = false
	_cars.clear()
	_pace_profile = null
	_speed_profile = null
	_physics_config = null
	_race_state_machine = RaceStateMachine.new()
	_car_degradation_configs.clear()
	_overtaking_manager = OvertakingManager.new()

	_validate_inputs(config, runtime)
	if not _validation_errors.is_empty():
		return

	_config = config.clone()
	_runtime = runtime.clone()
	if _config.is_physics_profile():
		_initialize_speed_profile()
	else:
		_initialize_pace_profile()

	if not _validation_errors.is_empty():
		return

	for car_config in _config.cars:
		var state: RaceTypes.CarState = RaceTypes.CarState.new()
		state.id = car_config.id
		state.display_name = car_config.display_name
		state.base_speed_units_per_sec = car_config.base_speed_units_per_sec
		state.v_ref = car_config.v_ref if car_config.v_ref > 0.0 else car_config.base_speed_units_per_sec
		state.reset_runtime_state()
		_cars.append(state)
		_car_degradation_configs[state.id] = _resolve_degradation_config_for_car(car_config, _config.degradation)

	_race_state_machine.configure(_config.total_laps, _cars.size())
	_overtaking_manager.configure(_config.overtaking)
	_is_ready = true
	reset()


func reset() -> void:
	_race_time = 0.0
	if _race_state_machine != null:
		_race_state_machine.reset()
	if _overtaking_manager != null:
		_overtaking_manager.reset()
	for car in _cars:
		car.reset_runtime_state()
	_update_standings()


func step(dt_seconds: float) -> void:
	if not _is_ready or dt_seconds <= 0.0:
		return
	if _race_state_machine != null and _race_state_machine.get_state() == RaceTypes.RaceState.FINISHED:
		return
	if _race_state_machine != null and _race_state_machine.get_state() == RaceTypes.RaceState.NOT_STARTED:
		_race_state_machine.on_race_start()

	var remaining_dt: float = dt_seconds
	while remaining_dt > 0.0000001:
		var chunk_dt: float = minf(remaining_dt, _INTERNAL_INTEGRATION_STEP)
		var chunk_start_time: float = _race_time

		# Phase 1: compute each car's natural speed.
		for car in _cars:
			if _race_state_machine != null and not _race_state_machine.is_car_racing(car):
				car.effective_speed_units_per_sec = 0.0
				car.is_held_up = false
				car.held_up_by = ""
				continue
			_compute_car_speed(car)

		# Phase 2: resolve overtaking interactions against precomputed speeds.
		if _overtaking_manager != null and _overtaking_manager.is_enabled():
			_overtaking_manager.process_interactions(_cars, _runtime.track_length, _race_time)

		# Phase 3: apply movement and lap-crossing updates.
		for car in _cars:
			if _race_state_machine != null and not _race_state_machine.is_car_racing(car):
				continue
			_apply_car_movement(car, chunk_start_time, chunk_dt)

		# Phase 4: update standings from latest distances.
		_update_standings()

		_race_time += chunk_dt
		remaining_dt -= chunk_dt
		if _race_state_machine != null and _race_state_machine.get_state() == RaceTypes.RaceState.FINISHED:
			break


func get_snapshot() -> RaceTypes.RaceSnapshot:
	var snapshot: RaceTypes.RaceSnapshot = RaceTypes.RaceSnapshot.new()
	snapshot.race_time = _race_time
	snapshot.total_laps = _config.total_laps if _config != null else 0
	if _race_state_machine != null:
		snapshot.race_state = _race_state_machine.get_state()
		snapshot.finish_order = _race_state_machine.get_finish_order()
	for car in _cars:
		snapshot.cars.append(car.clone())
	return snapshot


func get_speed_profile_array() -> PackedFloat64Array:
	if _speed_profile == null:
		return PackedFloat64Array()
	return _speed_profile.get_speed_array()


func get_physics_config() -> RaceTypes.PhysicsVehicleConfig:
	return _physics_config.clone() if _physics_config != null else null


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
	if config.track == null:
		_validation_errors.append("Track configuration is required.")
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

		if config.is_physics_profile():
			if car.v_ref <= 0.0:
				_validation_errors.append("Car '%s' v_ref must be greater than zero." % clean_id)
		else:
			if car.base_speed_units_per_sec <= 0.0:
				_validation_errors.append("Car '%s' base_speed_units_per_sec must be > 0." % clean_id)

		var car_deg_errors: PackedStringArray = DegradationModel.validate_config(car.degradation)
		for err in car_deg_errors:
			_validation_errors.append("Car '%s' %s" % [clean_id, err])

	if config.is_physics_profile() and runtime.geometry == null:
		_validation_errors.append("Track geometry runtime data is required for schema 1.1.")

	var global_deg_errors: PackedStringArray = DegradationModel.validate_config(config.degradation)
	for err in global_deg_errors:
		_validation_errors.append("Global %s" % err)
	if config.overtaking != null:
		if config.overtaking.proximity_distance < 0.0:
			_validation_errors.append("overtaking.proximity_distance must be >= 0.")
		if config.overtaking.overtake_speed_threshold < 0.0:
			_validation_errors.append("overtaking.overtake_speed_threshold must be >= 0.")
		if config.overtaking.held_up_speed_buffer < 0.0:
			_validation_errors.append("overtaking.held_up_speed_buffer must be >= 0.")
		if config.overtaking.cooldown_seconds < 0.0:
			_validation_errors.append("overtaking.cooldown_seconds must be >= 0.")


func _initialize_pace_profile() -> void:
	var track_config: RaceTypes.PaceProfileConfig = _config.track as RaceTypes.PaceProfileConfig
	if track_config == null:
		_validation_errors.append("Schema 1.0 requires PaceProfileConfig.")
		return

	_pace_profile = PaceProfile.new()
	_pace_profile.configure(
		_runtime.track_length,
		track_config.blend_distance,
		track_config.pace_segments
	)
	if not _pace_profile.is_valid():
		for pace_error in _pace_profile.get_validation_errors():
			_validation_errors.append(pace_error)


func _initialize_speed_profile() -> void:
	var track_config: RaceTypes.SpeedProfileConfig = _config.track as RaceTypes.SpeedProfileConfig
	if track_config == null:
		_validation_errors.append("Schema 1.1 requires SpeedProfileConfig.")
		return

	_physics_config = track_config.physics.clone() if track_config.physics != null else null
	if _physics_config == null:
		_validation_errors.append("SpeedProfileConfig.physics is required.")
		return

	_speed_profile = SpeedProfile.new()
	_speed_profile.configure(_runtime.geometry, _physics_config)
	if not _speed_profile.is_valid():
		for speed_error in _speed_profile.get_validation_errors():
			_validation_errors.append(speed_error)


func _compute_car_speed(car: RaceTypes.CarState) -> void:
	if car == null:
		return

	car.is_held_up = false
	car.held_up_by = ""

	var speed: float = 0.0
	if _speed_profile != null:
		var raw_speed: float = _speed_profile.sample_speed(car.distance_along_track)
		if _physics_config == null or _physics_config.v_top_speed <= 0.0:
			return
		var scale: float = car.v_ref / _physics_config.v_top_speed
		speed = raw_speed * scale
		car.current_multiplier = speed / _physics_config.v_top_speed
	else:
		if _pace_profile == null:
			return
		var pace_multiplier: float = _pace_profile.sample_multiplier(car.distance_along_track)
		speed = car.base_speed_units_per_sec * pace_multiplier
		car.current_multiplier = pace_multiplier

	car.effective_speed_units_per_sec = speed
	var deg_config: RaceTypes.DegradationConfig = _car_degradation_configs.get(car.id, null)
	var fractional_lap: float = car.distance_along_track / _runtime.track_length if _runtime.track_length > 0.0 else 0.0
	car.degradation_multiplier = DegradationModel.compute_multiplier(car.lap_count, fractional_lap, deg_config)
	speed *= car.degradation_multiplier
	speed = maxf(speed, 0.001)
	car.effective_speed_units_per_sec = speed


func _apply_car_movement(car: RaceTypes.CarState, chunk_start_time: float, chunk_dt: float) -> void:
	if car == null:
		return

	var speed: float = car.effective_speed_units_per_sec
	var track_length: float = _runtime.track_length
	if track_length <= 0.0 or speed <= 0.0:
		return

	var previous_distance: float = car.distance_along_track
	var raw_distance: float = previous_distance + speed * chunk_dt
	var lap_epsilon: float = maxf(_LAP_CROSS_EPSILON, track_length * 0.000000001)
	var laps_crossed: int = int(floor(raw_distance / track_length))
	var wrapped_distance: float = raw_distance - (float(laps_crossed) * track_length)
	var forced_boundary_cross: bool = false

	# Handle near-boundary floating-point cases while keeping lap count and
	# wrapped distance coherent in the same chunk.
	if laps_crossed == 0 and (track_length - raw_distance) <= lap_epsilon:
		laps_crossed = 1
		wrapped_distance = 0.0
		forced_boundary_cross = true
	elif laps_crossed > 0 and abs(wrapped_distance) <= lap_epsilon:
		wrapped_distance = 0.0
	elif laps_crossed > 0 and (track_length - wrapped_distance) <= lap_epsilon:
		laps_crossed += 1
		wrapped_distance = 0.0
		forced_boundary_cross = true

	car.distance_along_track = fposmod(wrapped_distance, track_length)
	if laps_crossed <= 0:
		return

	# Guard division points even though speed is validated. This keeps crossing
	# math safe against future runtime mutation or partial config edits.
	if speed <= 0.0:
		return

	var time_to_first_cross: float = (track_length - previous_distance) / speed
	var clamped_time_to_first_cross: float = maxf(time_to_first_cross, 0.0)
	var chunk_end_time: float = chunk_start_time + chunk_dt
	var first_cross_time: float = minf(chunk_start_time + clamped_time_to_first_cross, chunk_end_time)
	if forced_boundary_cross and first_cross_time < chunk_end_time:
		first_cross_time = chunk_end_time
	var lap_duration: float = track_length / speed
	for crossing_index in range(laps_crossed):
		var crossing_time: float = first_cross_time + float(crossing_index) * lap_duration
		crossing_time = minf(crossing_time, chunk_end_time)
		_register_lap_crossing(car, crossing_time)
		if car.is_finished:
			break


func _register_lap_crossing(car: RaceTypes.CarState, crossing_time: float) -> void:
	if car == null or car.is_finished:
		return

	# Out-lap handling is explicit so race modes can adjust policy later without
	# touching crossing detection and accumulation logic.
	if not _config.count_first_lap_from_start and car.last_lap_time < 0.0 and car.lap_count == 0:
		car.lap_start_time = crossing_time
		return

	var raw_lap_time: float = crossing_time - car.lap_start_time
	var lap_time: float = maxf(raw_lap_time, 0.0)
	car.last_lap_time = lap_time
	car.best_lap_time = minf(car.best_lap_time, lap_time)
	car.lap_start_time = crossing_time
	car.lap_count += 1
	if _race_state_machine != null:
		_race_state_machine.on_lap_completed(car, crossing_time)
		if car.is_finished:
			car.distance_along_track = 0.0
			car.effective_speed_units_per_sec = 0.0


func _update_standings() -> void:
	var track_length: float = _runtime.track_length if _runtime != null else 0.0
	for car in _cars:
		car.total_distance = float(car.lap_count) * track_length + car.distance_along_track
	StandingsCalculator.update_positions(_cars)


func _resolve_degradation_config_for_car(
	car_config: RaceTypes.CarConfig,
	global_config: RaceTypes.DegradationConfig
) -> RaceTypes.DegradationConfig:
	if car_config != null and car_config.degradation != null:
		return car_config.degradation.clone()
	if global_config != null:
		return global_config.clone()
	return null
