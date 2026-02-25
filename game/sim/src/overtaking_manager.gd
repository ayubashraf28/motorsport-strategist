extends RefCounted
class_name OvertakingManager

const RaceTypes = preload("res://sim/src/race_types.gd")

const _COOLDOWN_CLEANUP_INTERVAL_STEPS: int = 120

var _config: RaceTypes.OvertakingConfig = null
var _cooldowns: Dictionary = {}
var _is_enabled: bool = false
var _step_counter: int = 0


func configure(config: RaceTypes.OvertakingConfig) -> void:
	_config = config.clone() if config != null else null
	_is_enabled = _config != null and _config.enabled
	reset()


func reset() -> void:
	_cooldowns.clear()
	_step_counter = 0


func is_enabled() -> bool:
	return _is_enabled


func process_interactions(
	cars: Array[RaceTypes.CarState],
	track_length: float,
	race_time: float
) -> void:
	for car in cars:
		if car == null:
			continue
		car.is_held_up = false
		car.held_up_by = ""

	if not _is_enabled or _config == null or cars.is_empty() or track_length <= 0.0:
		return

	_step_counter += 1
	if _step_counter % _COOLDOWN_CLEANUP_INTERVAL_STEPS == 0:
		_expire_cooldowns(race_time)

	var sorted_indices: Array[int] = []
	for index in range(cars.size()):
		sorted_indices.append(index)

	sorted_indices.sort_custom(func(a: int, b: int) -> bool:
		var car_a: RaceTypes.CarState = cars[a]
		var car_b: RaceTypes.CarState = cars[b]
		if car_a.total_distance > car_b.total_distance:
			return true
		if car_a.total_distance < car_b.total_distance:
			return false
		return a < b
	)

	for order_index in range(1, sorted_indices.size()):
		var ahead: RaceTypes.CarState = cars[sorted_indices[order_index - 1]]
		var behind: RaceTypes.CarState = cars[sorted_indices[order_index]]
		if ahead == null or behind == null:
			continue
		if ahead.is_in_pit or behind.is_in_pit:
			continue
		if ahead.is_finished or behind.is_finished:
			continue

		var track_gap: float = fposmod(ahead.distance_along_track - behind.distance_along_track, track_length)
		if track_gap <= 0.0 or track_gap > _config.proximity_distance:
			continue

		var speed_delta: float = behind.effective_speed_units_per_sec - ahead.effective_speed_units_per_sec
		if speed_delta <= 0.0:
			continue
		if _is_in_cooldown(ahead.id, behind.id, race_time):
			continue

		if speed_delta >= _config.overtake_speed_threshold:
			_register_cooldown(ahead.id, behind.id, race_time)
			continue

		var capped_speed: float = ahead.effective_speed_units_per_sec + _config.held_up_speed_buffer
		behind.effective_speed_units_per_sec = minf(capped_speed, behind.effective_speed_units_per_sec)
		behind.is_held_up = true
		behind.held_up_by = ahead.id


func _get_cooldown_key(id_a: String, id_b: String) -> String:
	return "%s:%s" % [id_a, id_b] if id_a < id_b else "%s:%s" % [id_b, id_a]


func _is_in_cooldown(id_a: String, id_b: String, race_time: float) -> bool:
	var key: String = _get_cooldown_key(id_a, id_b)
	return _cooldowns.has(key) and race_time < _cooldowns[key]


func _register_cooldown(id_a: String, id_b: String, race_time: float) -> void:
	_cooldowns[_get_cooldown_key(id_a, id_b)] = race_time + _config.cooldown_seconds


func _expire_cooldowns(race_time: float) -> void:
	var expired_keys: Array[String] = []
	for raw_key in _cooldowns.keys():
		var key: String = String(raw_key)
		if race_time >= float(_cooldowns[key]):
			expired_keys.append(key)
	for key in expired_keys:
		_cooldowns.erase(key)
