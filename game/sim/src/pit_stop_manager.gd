extends RefCounted
class_name PitStopManager

const RaceTypes = preload("res://sim/src/race_types.gd")
const FuelModel = preload("res://sim/src/fuel_model.gd")

const _MIN_PHASE_DURATION_SECONDS: float = 0.1

var _config: RaceTypes.PitConfig = null
var _fuel_config: RaceTypes.FuelConfig = null
var _is_enabled: bool = false

var _track_length: float = 0.0
var _pit_lane_distance: float = 0.0
var _entry_distance: float = 0.0
var _exit_distance: float = 0.0
var _pit_box_distance: float = 0.0


func configure(config: RaceTypes.PitConfig, fuel_config: RaceTypes.FuelConfig, track_length: float) -> void:
	_config = config.clone() if config != null else null
	_fuel_config = fuel_config.clone() if fuel_config != null else null
	_is_enabled = _config != null and _config.enabled

	_track_length = maxf(track_length, 0.0)
	_pit_lane_distance = 0.0
	_entry_distance = 0.0
	_exit_distance = 0.0
	_pit_box_distance = 0.0
	if not _is_enabled or _config == null or _track_length <= 0.0:
		return

	_pit_lane_distance = _compute_pit_lane_distance(_config.pit_entry_distance, _config.pit_exit_distance, _track_length)
	_pit_box_distance = _resolve_pit_box_distance(_config)
	_entry_distance = _compute_forward_distance(_config.pit_entry_distance, _pit_box_distance, _track_length)
	_exit_distance = _compute_forward_distance(_pit_box_distance, _config.pit_exit_distance, _track_length)


func reset() -> void:
	# Manager is stateless per-car. Reset exists for API consistency.
	pass


func is_enabled() -> bool:
	return _is_enabled


func should_enter_pit(
	car: RaceTypes.CarState,
	pending_requests: Dictionary,
	previous_distance: float,
	current_distance: float,
	track_length: float,
	race_state: int
) -> bool:
	if not _is_enabled or _config == null:
		return false
	if car == null or car.is_finished or car.is_in_pit:
		return false
	if race_state != RaceTypes.RaceState.RUNNING:
		return false
	if not pending_requests.has(car.id):
		return false
	if car.lap_count < _config.min_stop_lap:
		return false
	if car.pit_stops_completed >= _config.max_stops:
		return false
	if track_length <= 0.0:
		return false
	return _crossed_track_distance(previous_distance, current_distance, _config.pit_entry_distance, track_length)


func begin_pit_entry(car: RaceTypes.CarState, request: Dictionary) -> void:
	if car == null or _config == null:
		return
	car.pit_phase = RaceTypes.PitPhase.ENTRY
	car.pit_time_remaining = _compute_entry_duration_seconds()
	car.is_in_pit = true
	car.pit_target_compound = String(request.get("compound", "")).strip_edges()
	car.pit_target_fuel_kg = float(request.get("fuel_kg", -1.0))
	car.distance_along_track = _config.pit_entry_distance


func process_pit_phase(car: RaceTypes.CarState, chunk_dt: float) -> Dictionary:
	var default_result: Dictionary = {
		"completed": false,
		"new_compound": "",
		"refueled_to_kg": -1.0
	}
	if car == null or _config == null or not car.is_in_pit:
		return default_result

	if car.pit_phase == RaceTypes.PitPhase.ENTRY:
		var entry_duration: float = _compute_entry_duration_seconds()
		var entry_progress: float = 1.0 - (car.pit_time_remaining / maxf(entry_duration, _MIN_PHASE_DURATION_SECONDS))
		entry_progress = clampf(entry_progress, 0.0, 1.0)
		car.distance_along_track = _lerp_track_distance(
			_config.pit_entry_distance,
			_pit_box_distance,
			entry_progress,
			_track_length
		)
	elif car.pit_phase == RaceTypes.PitPhase.EXIT:
		var exit_duration: float = _compute_exit_duration_seconds()
		var exit_progress: float = 1.0 - (car.pit_time_remaining / maxf(exit_duration, _MIN_PHASE_DURATION_SECONDS))
		exit_progress = clampf(exit_progress, 0.0, 1.0)
		car.distance_along_track = _lerp_track_distance(
			_pit_box_distance,
			_config.pit_exit_distance,
			exit_progress,
			_track_length
		)

	car.pit_time_remaining = maxf(car.pit_time_remaining - chunk_dt, 0.0)
	if car.pit_time_remaining > 0.0:
		return default_result

	if car.pit_phase == RaceTypes.PitPhase.ENTRY:
		car.pit_phase = RaceTypes.PitPhase.STOPPED
		car.pit_time_remaining = compute_stop_duration(car)
		car.distance_along_track = _pit_box_distance
		return default_result

	if car.pit_phase == RaceTypes.PitPhase.STOPPED:
		var fuel_after_stop: float = _compute_refueled_fuel(car)
		car.pit_phase = RaceTypes.PitPhase.EXIT
		car.pit_time_remaining = _compute_exit_duration_seconds()
		car.distance_along_track = _pit_box_distance
		return {
			"completed": false,
			"new_compound": car.pit_target_compound,
			"refueled_to_kg": fuel_after_stop
		}

	if car.pit_phase == RaceTypes.PitPhase.EXIT:
		car.is_in_pit = false
		car.pit_phase = RaceTypes.PitPhase.RACING
		car.pit_time_remaining = 0.0
		car.distance_along_track = _config.pit_exit_distance
		car.pit_target_compound = ""
		car.pit_target_fuel_kg = -1.0
		return {
			"completed": true,
			"new_compound": "",
			"refueled_to_kg": -1.0
		}

	return default_result


func compute_stop_duration(car: RaceTypes.CarState) -> float:
	if _config == null:
		return 0.0
	var duration: float = _config.base_pit_stop_duration
	if _fuel_config == null or not _fuel_config.enabled:
		return duration

	var target_fuel: float = _resolve_target_fuel(car)
	duration += FuelModel.compute_refuel_time(car.fuel_kg, target_fuel, _fuel_config.refuel_rate_kg_per_sec)
	return duration


func get_pit_speed(car: RaceTypes.CarState) -> float:
	if car == null or _config == null:
		return -1.0
	if car.pit_phase == RaceTypes.PitPhase.ENTRY or car.pit_phase == RaceTypes.PitPhase.EXIT:
		return _config.pit_lane_speed_limit
	if car.pit_phase == RaceTypes.PitPhase.STOPPED:
		return 0.0
	return -1.0


func _compute_refueled_fuel(car: RaceTypes.CarState) -> float:
	if _fuel_config == null or not _fuel_config.enabled:
		return -1.0
	var target_fuel: float = _resolve_target_fuel(car)
	var added_fuel: float = maxf(target_fuel - car.fuel_kg, 0.0)
	return FuelModel.refuel(car.fuel_kg, added_fuel, _fuel_config.max_capacity_kg)


func _resolve_target_fuel(car: RaceTypes.CarState) -> float:
	if _fuel_config == null:
		return maxf(car.fuel_kg, 0.0)
	if car.pit_target_fuel_kg < 0.0:
		return _fuel_config.max_capacity_kg
	return clampf(car.pit_target_fuel_kg, 0.0, _fuel_config.max_capacity_kg)


func _crossed_track_distance(
	previous_distance: float,
	current_distance: float,
	target_distance: float,
	track_length: float
) -> bool:
	if track_length <= 0.0:
		return false

	if previous_distance <= current_distance:
		return target_distance > previous_distance and target_distance <= current_distance
	return target_distance > previous_distance or target_distance <= current_distance


func _compute_pit_lane_distance(entry: float, exit: float, track_length: float) -> float:
	if track_length <= 0.0:
		return 0.0
	return fposmod(exit - entry, track_length)


func _resolve_pit_box_distance(config: RaceTypes.PitConfig) -> float:
	if _track_length <= 0.0 or config == null:
		return 0.0
	if config.pit_box_distance >= 0.0:
		return fposmod(config.pit_box_distance, _track_length)
	return fposmod(config.pit_entry_distance + _pit_lane_distance * 0.5, _track_length)


func _compute_forward_distance(from_dist: float, to_dist: float, track_length: float) -> float:
	if track_length <= 0.0:
		return 0.0
	return fposmod(to_dist - from_dist, track_length)


func _lerp_track_distance(from_d: float, to_d: float, t: float, track_length: float) -> float:
	if track_length <= 0.0:
		return from_d
	var forward_dist: float = fposmod(to_d - from_d, track_length)
	return fposmod(from_d + forward_dist * clampf(t, 0.0, 1.0), track_length)


func _compute_entry_duration_seconds() -> float:
	if _config == null:
		return _MIN_PHASE_DURATION_SECONDS
	var speed: float = maxf(_config.pit_lane_speed_limit, 0.001)
	return maxf(_entry_distance / speed, _MIN_PHASE_DURATION_SECONDS)


func _compute_exit_duration_seconds() -> float:
	if _config == null:
		return _MIN_PHASE_DURATION_SECONDS
	var speed: float = maxf(_config.pit_lane_speed_limit, 0.001)
	return maxf(_exit_distance / speed, _MIN_PHASE_DURATION_SECONDS)
