extends RefCounted
class_name SafetyCarController

const RaceTypes = preload("res://sim/src/race_types.gd")

enum Phase {
	GREEN = 0,
	SC_DEPLOYED = 1,
	SC_ENDING = 2,
	VSC = 3,
}

var _config: RaceTypes.SafetyCarConfig = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _phase: int = Phase.GREEN
var _laps_remaining: int = 0
var _events_triggered: int = 0
var _last_trigger_lap: int = -999
var _restart_drs_lock_laps_remaining: int = 0


func configure(config: RaceTypes.SafetyCarConfig, seed: int) -> void:
	_config = config.clone() if config != null else null
	_rng = RandomNumberGenerator.new()
	_rng.seed = int(seed)
	reset()


func reset() -> void:
	_phase = Phase.GREEN
	_laps_remaining = 0
	_events_triggered = 0
	_last_trigger_lap = -999
	_restart_drs_lock_laps_remaining = 0


func on_leader_lap_started(current_lap: int, total_laps: int = 0) -> void:
	if not is_enabled():
		return

	var restart_lock_set_this_lap: bool = false

	match _phase:
		Phase.GREEN:
			if _should_trigger_event(current_lap, total_laps):
				_start_random_event(current_lap)
		Phase.SC_DEPLOYED:
			_laps_remaining -= 1
			if _laps_remaining <= 0:
				_phase = Phase.SC_ENDING
				_laps_remaining = 1
		Phase.SC_ENDING:
			_laps_remaining -= 1
			if _laps_remaining <= 0:
				_phase = Phase.GREEN
				_laps_remaining = 0
				_set_restart_drs_lock()
				restart_lock_set_this_lap = true
		Phase.VSC:
			_laps_remaining -= 1
			if _laps_remaining <= 0:
				_phase = Phase.GREEN
				_laps_remaining = 0
				_set_restart_drs_lock()
				restart_lock_set_this_lap = true

	if _phase == Phase.GREEN and not restart_lock_set_this_lap and _restart_drs_lock_laps_remaining > 0:
		_restart_drs_lock_laps_remaining -= 1


func is_enabled() -> bool:
	return _config != null and _config.enabled


func get_phase() -> int:
	return _phase


func get_laps_remaining() -> int:
	return maxi(_laps_remaining, 0)


func is_overtaking_allowed() -> bool:
	return _phase == Phase.GREEN


func is_drs_allowed() -> bool:
	return _phase == Phase.GREEN and _restart_drs_lock_laps_remaining <= 0


func get_speed_multiplier() -> float:
	if _phase == Phase.VSC and _config != null:
		return _config.vsc_speed_multiplier
	return 1.0


func get_speed_cap_for_car(position: int) -> float:
	if (_phase == Phase.SC_DEPLOYED or _phase == Phase.SC_ENDING) and _config != null:
		var cap: float = _config.sc_speed_cap
		if position == 1:
			cap *= _config.sc_leader_pace_ratio
		return cap
	return INF


func _set_restart_drs_lock() -> void:
	if _config == null:
		_restart_drs_lock_laps_remaining = 0
		return
	var lock_laps: int = maxi(_config.restart_drs_lock_laps, 0)
	# The lock is decremented on each future lap start; add one so lock_laps
	# full restart laps are covered before DRS is re-enabled.
	_restart_drs_lock_laps_remaining = lock_laps + 1 if lock_laps > 0 else 0


func _should_trigger_event(current_lap: int, total_laps: int) -> bool:
	if _config == null or not _config.enabled:
		return false
	if _events_triggered >= _config.max_events:
		return false
	if current_lap < _config.min_lap:
		return false
	if current_lap - _last_trigger_lap <= _config.cooldown_laps:
		return false
	if total_laps > 0:
		var min_event_laps: int = mini(_config.sc_laps_min, _config.vsc_laps_min)
		if current_lap >= total_laps - maxi(min_event_laps, 1):
			return false

	var roll: float = _rng.randf()
	return roll < _config.trigger_probability_per_lap


func _start_random_event(current_lap: int) -> void:
	if _config == null:
		return

	_events_triggered += 1
	_last_trigger_lap = current_lap
	var use_vsc: bool = _rng.randf() < _config.vsc_probability
	if use_vsc:
		_phase = Phase.VSC
		_laps_remaining = _rng.randi_range(_config.vsc_laps_min, _config.vsc_laps_max)
	else:
		_phase = Phase.SC_DEPLOYED
		_laps_remaining = _rng.randi_range(_config.sc_laps_min, _config.sc_laps_max)
