extends RefCounted
class_name RaceSimulator

const RaceTypes = preload("res://sim/src/race_types.gd")
const PaceProfile = preload("res://sim/src/pace_profile.gd")
const SpeedProfile = preload("res://sim/src/speed_profile.gd")
const StandingsCalculator = preload("res://sim/src/standings_calculator.gd")
const RaceStateMachine = preload("res://sim/src/race_state_machine.gd")
const DegradationModel = preload("res://sim/src/degradation_model.gd")
const OvertakingManager = preload("res://sim/src/overtaking_manager.gd")
const TyreCompound = preload("res://sim/src/tyre_compound.gd")
const StintTracker = preload("res://sim/src/stint_tracker.gd")
const FuelModel = preload("res://sim/src/fuel_model.gd")
const PitStopManager = preload("res://sim/src/pit_stop_manager.gd")
const PitStrategy = preload("res://sim/src/pit_strategy.gd")
const DriverModeModule = preload("res://sim/src/driver_mode.gd")
const DrsSystemModule = preload("res://sim/src/drs_system.gd")

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
var _stint_tracker: StintTracker = null
var _fuel_config: RaceTypes.FuelConfig = null
var _pit_stop_manager: PitStopManager = PitStopManager.new()
var _pit_strategy: PitStrategy = PitStrategy.new()
var _drs_system: DrsSystemModule = DrsSystemModule.new()


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
	_stint_tracker = null
	_fuel_config = null
	_pit_stop_manager = PitStopManager.new()
	_pit_strategy = PitStrategy.new()

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

	if _config.compounds.is_empty():
		for i in range(_cars.size()):
			var car_config: RaceTypes.CarConfig = _config.cars[i]
			var car_state: RaceTypes.CarState = _cars[i]
			_car_degradation_configs[car_state.id] = _resolve_degradation_config_for_car(car_config, _config.degradation)
	else:
		_stint_tracker = StintTracker.new()
		_stint_tracker.configure(_cars, _config.compounds, _build_starting_compound_map())

	_fuel_config = _config.fuel.clone() if _config.fuel != null and _config.fuel.enabled else null
	_pit_stop_manager.configure(_config.pit, _fuel_config, _runtime.track_length)
	_pit_strategy.reset()

	_race_state_machine.configure(_config.total_laps, _cars.size())
	_overtaking_manager.configure(_config.overtaking)
	_drs_system = DrsSystemModule.new()
	_drs_system.configure(_config.drs, _runtime.track_length)
	_is_ready = true
	reset()


func reset() -> void:
	_race_time = 0.0
	if _race_state_machine != null:
		_race_state_machine.reset()
	if _overtaking_manager != null:
		_overtaking_manager.reset()
	if _stint_tracker != null:
		_stint_tracker.reset()
	if _pit_stop_manager != null:
		_pit_stop_manager.reset()
	if _pit_strategy != null:
		_pit_strategy.reset()
	if _drs_system != null:
		_drs_system.reset()

	for index in range(_cars.size()):
		var car: RaceTypes.CarState = _cars[index]
		car.reset_runtime_state()
		_apply_initial_dynamic_state(index, car)
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
		var pit_processed_ids: Dictionary = {}

		# Phase 0: evaluate DRS detection points.
		if _drs_system != null and _drs_system.is_configured():
			_drs_system.evaluate_detections(_cars, _runtime.track_length)

		# Phase 1: compute each car's natural speed.
		for car in _cars:
			if _race_state_machine != null and not _race_state_machine.is_car_racing(car):
				car.effective_speed_units_per_sec = 0.0
				car.is_held_up = false
				car.held_up_by = ""
				continue

			if car.is_in_pit and _pit_stop_manager != null and _pit_stop_manager.is_enabled():
				var pit_result: Dictionary = _pit_stop_manager.process_pit_phase(car, chunk_dt)
				pit_processed_ids[car.id] = true

				var new_compound: String = String(pit_result.get("new_compound", ""))
				if _stint_tracker != null and not new_compound.is_empty():
					_stint_tracker.on_pit_stop_complete(car.id, new_compound)
					_sync_stint_fields(car)

				var refueled_to_kg: float = float(pit_result.get("refueled_to_kg", -1.0))
				if _fuel_config != null and refueled_to_kg >= 0.0:
					car.fuel_kg = refueled_to_kg

				if bool(pit_result.get("completed", false)):
					car.pit_stops_completed += 1

				car.fuel_multiplier = FuelModel.compute_multiplier(car.fuel_kg, _fuel_config)
				var pit_speed: float = _pit_stop_manager.get_pit_speed(car)
				car.reference_speed_units_per_sec = maxf(pit_speed, 0.0)
				car.strategy_multiplier = 1.0
				car.effective_speed_units_per_sec = maxf(pit_speed, 0.0)
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
			if pit_processed_ids.has(car.id):
				continue
			if car.is_in_pit:
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


func is_pit_enabled() -> bool:
	return _pit_stop_manager != null and _pit_stop_manager.is_enabled()


func is_fuel_enabled() -> bool:
	return _fuel_config != null and _fuel_config.enabled


func get_fuel_capacity_kg() -> float:
	if _fuel_config == null:
		return 0.0
	return _fuel_config.max_capacity_kg


func get_available_compounds() -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	if _config == null:
		return names
	for compound in _config.compounds:
		if compound == null:
			continue
		var name: String = compound.name.strip_edges()
		if not name.is_empty():
			names.append(name)
	return names


func get_pending_pit_requests() -> Dictionary:
	if _pit_strategy == null:
		return {}
	return _pit_strategy.get_pending_requests()


func has_pending_pit_request(car_id: String) -> bool:
	if _pit_strategy == null:
		return false
	return _pit_strategy.has_pending_request(car_id)


func request_pit_stop(car_id: String, compound_name: String, fuel_kg: float = -1.0) -> void:
	if _pit_strategy == null or _pit_stop_manager == null or not _pit_stop_manager.is_enabled():
		return
	if _race_state_machine == null:
		return
	if _race_state_machine.get_state() != RaceTypes.RaceState.RUNNING:
		return

	var car: RaceTypes.CarState = _find_car_state(car_id)
	if car == null or car.is_finished or car.is_in_pit:
		return
	if _config != null and _config.total_laps > 0 and car.lap_count >= _config.total_laps - 1:
		return

	var resolved_compound: String = _resolve_requested_compound(car, compound_name)
	_pit_strategy.request_pit_stop(car_id, resolved_compound, fuel_kg, _race_time)


func cancel_pit_stop(car_id: String) -> void:
	if _pit_strategy == null:
		return
	_pit_strategy.cancel_pit_stop(car_id)


func set_driver_mode(car_id: String, mode: int) -> void:
	if not DriverModeModule.is_valid_mode(mode):
		return
	var car: RaceTypes.CarState = _find_car_state(car_id)
	if car == null or car.is_finished:
		return
	car.driver_mode = mode


func get_driver_mode(car_id: String) -> int:
	var car: RaceTypes.CarState = _find_car_state(car_id)
	if car == null:
		return DriverModeModule.Mode.STANDARD
	return car.driver_mode


func is_drs_enabled() -> bool:
	return _drs_system != null and _drs_system.is_configured()


func get_drs_zones() -> Array:
	if _drs_system == null:
		return []
	return _drs_system.get_zones()


func get_next_compound_for_car(car_id: String) -> String:
	var compounds: PackedStringArray = get_available_compounds()
	if compounds.is_empty():
		return ""

	var current_compound: String = ""
	var car: RaceTypes.CarState = _find_car_state(car_id)
	if car != null:
		current_compound = car.current_compound.strip_edges().to_lower()

	for index in range(compounds.size()):
		if compounds[index].to_lower() == current_compound:
			return compounds[(index + 1) % compounds.size()]
	return compounds[0]


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

	var compounds_active: bool = not config.compounds.is_empty()
	if compounds_active:
		var compound_errors: PackedStringArray = TyreCompound.validate_compounds(config.compounds)
		for compound_error in compound_errors:
			_validation_errors.append(compound_error)

	var global_deg_errors: PackedStringArray = DegradationModel.validate_config(config.degradation)
	for err in global_deg_errors:
		_validation_errors.append("Global %s" % err)

	var fuel_errors: PackedStringArray = FuelModel.validate_config(config.fuel)
	for fuel_error in fuel_errors:
		_validation_errors.append(fuel_error)

	if config.overtaking != null:
		if config.overtaking.proximity_distance < 0.0:
			_validation_errors.append("overtaking.proximity_distance must be >= 0.")
		if config.overtaking.overtake_speed_threshold < 0.0:
			_validation_errors.append("overtaking.overtake_speed_threshold must be >= 0.")
		if config.overtaking.held_up_speed_buffer < 0.0:
			_validation_errors.append("overtaking.held_up_speed_buffer must be >= 0.")
		if config.overtaking.cooldown_seconds < 0.0:
			_validation_errors.append("overtaking.cooldown_seconds must be >= 0.")

	if config.pit != null and config.pit.enabled:
		if config.pit.pit_lane_speed_limit <= 0.0:
			_validation_errors.append("pit.pit_lane_speed_limit must be > 0.")
		if config.pit.base_pit_stop_duration < 1.0:
			_validation_errors.append("pit.base_pit_stop_duration must be >= 1.0.")
		if config.pit.min_stop_lap < 0:
			_validation_errors.append("pit.min_stop_lap must be >= 0.")
		if config.pit.max_stops <= 0:
			_validation_errors.append("pit.max_stops must be > 0.")
		if config.pit.pit_entry_distance < 0.0 or config.pit.pit_entry_distance >= runtime.track_length:
			_validation_errors.append("pit.pit_entry_distance must be in [0, track_length).")
		if config.pit.pit_exit_distance < 0.0 or config.pit.pit_exit_distance >= runtime.track_length:
			_validation_errors.append("pit.pit_exit_distance must be in [0, track_length).")
		if is_equal_approx(config.pit.pit_entry_distance, config.pit.pit_exit_distance):
			_validation_errors.append("pit.pit_entry_distance must differ from pit.pit_exit_distance.")
		if config.pit.pit_box_distance >= 0.0:
			if config.pit.pit_box_distance >= runtime.track_length:
				_validation_errors.append("pit.pit_box_distance must be in [0, track_length) when provided.")
			if is_equal_approx(config.pit.pit_box_distance, config.pit.pit_entry_distance):
				_validation_errors.append("pit.pit_box_distance must differ from pit.pit_entry_distance.")
			if is_equal_approx(config.pit.pit_box_distance, config.pit.pit_exit_distance):
				_validation_errors.append("pit.pit_box_distance must differ from pit.pit_exit_distance.")

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

		if not compounds_active:
			var car_deg_errors: PackedStringArray = DegradationModel.validate_config(car.degradation)
			for car_deg_error in car_deg_errors:
				_validation_errors.append("Car '%s' %s" % [clean_id, car_deg_error])
		else:
			var requested_compound: String = car.starting_compound.strip_edges()
			if not requested_compound.is_empty() and TyreCompound.find_compound(config.compounds, requested_compound) == null:
				_validation_errors.append("Car '%s' starting_compound '%s' is not defined in compounds." % [clean_id, requested_compound])

		if car.starting_fuel_kg < -1.0:
			_validation_errors.append("Car '%s' starting_fuel_kg must be >= -1." % clean_id)

	if config.is_physics_profile() and runtime.geometry == null:
		_validation_errors.append("Track geometry runtime data is required for schema 1.1.")


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

	car.reference_speed_units_per_sec = maxf(speed, 0.001)

	var degradation_inputs: Dictionary = _get_degradation_inputs(car)
	var degradation_config_variant: Variant = degradation_inputs.get("config", null)
	var degradation_config: RaceTypes.DegradationConfig = degradation_config_variant as RaceTypes.DegradationConfig
	car.degradation_multiplier = DegradationModel.compute_multiplier(
		int(degradation_inputs.get("lap_count", car.lap_count)),
		float(degradation_inputs.get("fractional_lap", 0.0)),
		degradation_config
	)
	car.tyre_life_ratio = DegradationModel.compute_life_ratio(car.degradation_multiplier, degradation_config)
	car.tyre_phase = DegradationModel.compute_phase(car.tyre_life_ratio, degradation_config)
	speed *= car.degradation_multiplier

	car.fuel_multiplier = FuelModel.compute_multiplier(car.fuel_kg, _fuel_config)
	speed *= car.fuel_multiplier

	var mode_pace: float = DriverModeModule.get_pace_multiplier(car.driver_mode)
	speed *= mode_pace

	var drs_mult: float = 1.0
	if _drs_system != null:
		drs_mult = _drs_system.get_drs_multiplier(car)
	speed *= drs_mult

	car.strategy_multiplier = car.degradation_multiplier * car.fuel_multiplier * mode_pace * drs_mult

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

	if _should_enter_pit(car, previous_distance, car.distance_along_track):
		var request: Dictionary = _pit_strategy.consume_request(car.id)
		_pit_stop_manager.begin_pit_entry(car, request)
		car.effective_speed_units_per_sec = maxf(_pit_stop_manager.get_pit_speed(car), 0.0)
		return

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

	if _stint_tracker != null:
		_stint_tracker.on_lap_completed(car.id)
		_sync_stint_fields(car)

	if _fuel_config != null:
		var fuel_scale: float = DriverModeModule.get_fuel_consumption_scale(car.driver_mode)
		var consumption: float = _fuel_config.consumption_per_lap_kg * fuel_scale
		car.fuel_kg = FuelModel.consume_fuel(car.fuel_kg, consumption)
		car.fuel_multiplier = FuelModel.compute_multiplier(car.fuel_kg, _fuel_config)

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


func _build_starting_compound_map() -> Dictionary:
	var starting_compounds: Dictionary = {}
	for car in _config.cars:
		if car == null or car.id.is_empty():
			continue
		starting_compounds[car.id] = car.starting_compound
	return starting_compounds


func _apply_initial_dynamic_state(index: int, car: RaceTypes.CarState) -> void:
	if car == null:
		return

	if _stint_tracker != null:
		_sync_stint_fields(car)

	if _fuel_config != null:
		var car_config: RaceTypes.CarConfig = _config.cars[index]
		if car_config.starting_fuel_kg > 0.0:
			car.fuel_kg = minf(car_config.starting_fuel_kg, _fuel_config.max_capacity_kg)
		else:
			car.fuel_kg = _fuel_config.max_capacity_kg
	else:
		car.fuel_kg = 0.0
	car.fuel_multiplier = FuelModel.compute_multiplier(car.fuel_kg, _fuel_config)


func _sync_stint_fields(car: RaceTypes.CarState) -> void:
	if _stint_tracker == null or car == null:
		return
	car.current_compound = _stint_tracker.get_compound_name(car.id)
	car.stint_lap_count = _stint_tracker.get_stint_lap_count(car.id)
	car.stint_number = _stint_tracker.get_stint_number(car.id)


func _get_degradation_inputs(car: RaceTypes.CarState) -> Dictionary:
	var fractional_lap: float = car.distance_along_track / _runtime.track_length if _runtime.track_length > 0.0 else 0.0
	var base_config: RaceTypes.DegradationConfig = null
	var lap_count: int = car.lap_count

	if _stint_tracker != null:
		_sync_stint_fields(car)
		lap_count = _stint_tracker.get_stint_lap_count(car.id)
		base_config = _stint_tracker.get_degradation_config(car.id)
	else:
		base_config = _car_degradation_configs.get(car.id, null) as RaceTypes.DegradationConfig

	var deg_scale: float = DriverModeModule.get_deg_rate_scale(car.driver_mode)
	var config: RaceTypes.DegradationConfig = _apply_deg_rate_scale(base_config, deg_scale)

	return {
		"lap_count": lap_count,
		"fractional_lap": fractional_lap,
		"config": config
	}


func _apply_deg_rate_scale(config: RaceTypes.DegradationConfig, scale: float) -> RaceTypes.DegradationConfig:
	if config == null or absf(scale - 1.0) < 0.0001:
		return config
	var scaled := config.clone()
	scaled.degradation_rate = config.degradation_rate * scale
	return scaled


func _find_car_state(car_id: String) -> RaceTypes.CarState:
	for car in _cars:
		if car != null and car.id == car_id:
			return car
	return null


func _resolve_requested_compound(car: RaceTypes.CarState, requested_compound: String) -> String:
	if _config == null or _config.compounds.is_empty():
		return ""
	var cleaned_request: String = requested_compound.strip_edges()
	var requested: RaceTypes.TyreCompoundConfig = TyreCompound.find_compound(_config.compounds, cleaned_request)
	if requested != null:
		return requested.name
	if car != null:
		var current: RaceTypes.TyreCompoundConfig = TyreCompound.find_compound(_config.compounds, car.current_compound)
		if current != null:
			return current.name
	return TyreCompound.get_default_compound_name(_config.compounds)


func _should_enter_pit(car: RaceTypes.CarState, previous_distance: float, current_distance: float) -> bool:
	if _pit_stop_manager == null or _pit_strategy == null:
		return false
	if not _pit_stop_manager.is_enabled() or not _pit_strategy.has_pending_request(car.id):
		return false
	if _race_state_machine == null:
		return false
	if _config != null and _config.total_laps > 0 and car.lap_count >= _config.total_laps - 1:
		return false
	var pending_requests: Dictionary = _pit_strategy.get_pending_requests()
	return _pit_stop_manager.should_enter_pit(
		car,
		pending_requests,
		previous_distance,
		current_distance,
		_runtime.track_length,
		_race_state_machine.get_state()
	)
