extends RefCounted
class_name RaceEngineer

const RaceTypes = preload("res://sim/src/race_types.gd")
const DriverModeModule = preload("res://sim/src/driver_mode.gd")

# Message priorities (higher = more urgent)
enum Priority { LOW = 0, MEDIUM = 1, HIGH = 2 }

# Cooldowns to avoid spamming the same message type per car (in race-time seconds)
const TYRE_WARN_COOLDOWN: float = 15.0
const PIT_SUGGEST_COOLDOWN: float = 25.0
const MODE_SUGGEST_COOLDOWN: float = 12.0
const DRS_ALERT_COOLDOWN: float = 10.0

# Thresholds
const TYRE_CRITICAL_THRESHOLD: float = 0.30
const TYRE_WARNING_THRESHOLD: float = 0.45
const DRS_NEAR_MISS_DISTANCE: float = 15.0  # Within this much of DRS threshold = "close"
const PUSH_GAP_SUGGEST_THRESHOLD: float = 80.0

# State tracking per car
var _last_tyre_warn_time: Dictionary = {}
var _last_pit_suggest_time: Dictionary = {}
var _last_mode_suggest_time: Dictionary = {}
var _last_drs_alert_time: Dictionary = {}


func reset() -> void:
	_last_tyre_warn_time.clear()
	_last_pit_suggest_time.clear()
	_last_mode_suggest_time.clear()
	_last_drs_alert_time.clear()


func evaluate(snapshot: RaceTypes.RaceSnapshot, drs_detection_threshold: float) -> Array:
	var messages: Array = []

	if snapshot.race_state != RaceTypes.RaceState.RUNNING:
		return messages

	var race_time: float = snapshot.race_time

	for car in snapshot.cars:
		if car.is_finished or car.is_in_pit:
			continue

		_check_tyre_warnings(car, race_time, messages)
		_check_pit_suggestions(car, snapshot, race_time, messages)
		_check_mode_suggestions(car, snapshot, race_time, messages)
		_check_drs_opportunities(car, snapshot, race_time, drs_detection_threshold, messages)

	# Sort by priority descending, then by race_time
	messages.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["priority"]) != int(b["priority"]):
			return int(a["priority"]) > int(b["priority"])
		return float(a["time"]) < float(b["time"])
	)

	return messages


func _check_tyre_warnings(car: RaceTypes.CarState, race_time: float, messages: Array) -> void:
	var last_time: float = _last_tyre_warn_time.get(car.id, -999.0)
	if race_time - last_time < TYRE_WARN_COOLDOWN:
		return

	if car.tyre_life_ratio < TYRE_CRITICAL_THRESHOLD:
		messages.append(_make_message(
			car.id,
			"Tyres critical on %s — recommend pit ASAP" % car.id,
			Priority.HIGH,
			race_time
		))
		_last_tyre_warn_time[car.id] = race_time
	elif car.tyre_life_ratio < TYRE_WARNING_THRESHOLD:
		messages.append(_make_message(
			car.id,
			"%s tyres wearing — consider pit window" % car.id,
			Priority.MEDIUM,
			race_time
		))
		_last_tyre_warn_time[car.id] = race_time


func _check_pit_suggestions(
	car: RaceTypes.CarState,
	snapshot: RaceTypes.RaceSnapshot,
	race_time: float,
	messages: Array
) -> void:
	var last_time: float = _last_pit_suggest_time.get(car.id, -999.0)
	if race_time - last_time < PIT_SUGGEST_COOLDOWN:
		return

	# Suggest pit when tyres are degraded and we're past the first few laps
	if car.tyre_life_ratio < TYRE_WARNING_THRESHOLD and car.lap_count >= 3:
		var compound_suggestion: String = _suggest_compound(car.current_compound)
		if not compound_suggestion.is_empty():
			messages.append(_make_message(
				car.id,
				"%s — pit window open, recommend %s" % [car.id, compound_suggestion],
				Priority.MEDIUM,
				race_time
			))
			_last_pit_suggest_time[car.id] = race_time


func _check_mode_suggestions(
	car: RaceTypes.CarState,
	snapshot: RaceTypes.RaceSnapshot,
	race_time: float,
	messages: Array
) -> void:
	var last_time: float = _last_mode_suggest_time.get(car.id, -999.0)
	if race_time - last_time < MODE_SUGGEST_COOLDOWN:
		return

	# Suggest push when close to car ahead and in standard mode
	if car.driver_mode == DriverModeModule.Mode.STANDARD and car.tyre_life_ratio > 0.55:
		var gap: float = _get_gap_to_car_ahead(car, snapshot)
		if gap > 0.0 and gap < PUSH_GAP_SUGGEST_THRESHOLD:
			var ahead_id: String = _get_car_ahead_id(car, snapshot)
			messages.append(_make_message(
				car.id,
				"Gap to %s is closing — push mode to attack?" % ahead_id,
				Priority.LOW,
				race_time
			))
			_last_mode_suggest_time[car.id] = race_time

	# Suggest conserve when pushing with worn tyres
	if car.driver_mode == DriverModeModule.Mode.PUSH and car.tyre_life_ratio < 0.50:
		messages.append(_make_message(
			car.id,
			"%s pushing on worn tyres — consider backing off" % car.id,
			Priority.MEDIUM,
			race_time
		))
		_last_mode_suggest_time[car.id] = race_time


func _check_drs_opportunities(
	car: RaceTypes.CarState,
	snapshot: RaceTypes.RaceSnapshot,
	race_time: float,
	drs_threshold: float,
	messages: Array
) -> void:
	if drs_threshold <= 0.0:
		return

	var last_time: float = _last_drs_alert_time.get(car.id, -999.0)
	if race_time - last_time < DRS_ALERT_COOLDOWN:
		return

	# Alert when car just got DRS
	if car.drs_active:
		var ahead_id: String = _get_car_ahead_id(car, snapshot)
		if not ahead_id.is_empty():
			messages.append(_make_message(
				car.id,
				"%s has DRS on %s" % [car.id, ahead_id],
				Priority.LOW,
				race_time
			))
			_last_drs_alert_time[car.id] = race_time

	# Alert when car is close to DRS range but not quite there
	elif car.drs_eligible == false and car.tyre_life_ratio > 0.5:
		var gap: float = _get_gap_to_car_ahead(car, snapshot)
		if gap > 0.0 and gap > drs_threshold and gap < drs_threshold + DRS_NEAR_MISS_DISTANCE:
			var ahead_id: String = _get_car_ahead_id(car, snapshot)
			messages.append(_make_message(
				car.id,
				"%s within %.0fm of DRS range on %s" % [car.id, gap - drs_threshold, ahead_id],
				Priority.LOW,
				race_time
			))
			_last_drs_alert_time[car.id] = race_time


# --- Helpers ---

func _make_message(car_id: String, text: String, priority: int, time: float) -> Dictionary:
	return {
		"car_id": car_id,
		"text": text,
		"priority": priority,
		"time": time,
	}


func _get_gap_to_car_ahead(car: RaceTypes.CarState, snapshot: RaceTypes.RaceSnapshot) -> float:
	if car.position <= 1:
		return -1.0
	for other in snapshot.cars:
		if other.position == car.position - 1 and not other.is_finished:
			return other.total_distance - car.total_distance
	return -1.0


func _get_car_ahead_id(car: RaceTypes.CarState, snapshot: RaceTypes.RaceSnapshot) -> String:
	if car.position <= 1:
		return ""
	for other in snapshot.cars:
		if other.position == car.position - 1 and not other.is_finished:
			return other.id
	return ""


func _suggest_compound(current: String) -> String:
	match current.to_lower():
		"soft":
			return "mediums"
		"medium":
			return "hards"
		"hard":
			return "mediums"
	return ""
