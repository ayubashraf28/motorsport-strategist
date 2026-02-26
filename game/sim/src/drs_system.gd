extends RefCounted
class_name DrsSystem

const RaceTypes = preload("res://sim/src/race_types.gd")


var _zones: Array = []  # Array of DrsZoneConfig
var _detection_threshold: float = 50.0
var _speed_boost: float = 1.06
var _min_activation_lap: int = 3
var _enabled: bool = true
var _is_configured: bool = false
var _track_length: float = 0.0

# Per-car DRS state: car_id -> bool (eligible at last detection point)
var _car_drs_eligible: Dictionary = {}
# Per-car: which zone index they were last detected eligible for
var _car_last_detection_zone: Dictionary = {}


func configure(config: Dictionary, track_length: float) -> void:
	_is_configured = false
	_zones.clear()
	_car_drs_eligible.clear()
	_car_last_detection_zone.clear()
	_track_length = track_length

	if config.is_empty():
		return
	if not bool(config.get("enabled", false)):
		return

	_detection_threshold = float(config.get("detection_threshold", 50.0))
	_speed_boost = float(config.get("speed_boost", 1.06))
	_min_activation_lap = int(config.get("min_activation_lap", 3))

	var raw_zones: Array = config.get("zones", [])
	for raw_zone in raw_zones:
		if raw_zone is Dictionary:
			var zone := {}
			zone["detection_distance"] = float(raw_zone.get("detection_distance", 0.0))
			zone["zone_start"] = float(raw_zone.get("zone_start", 0.0))
			zone["zone_end"] = float(raw_zone.get("zone_end", 0.0))
			_zones.append(zone)

	_is_configured = not _zones.is_empty() and _track_length > 0.0
	_enabled = true


func reset() -> void:
	_car_drs_eligible.clear()
	_car_last_detection_zone.clear()
	_enabled = true


func is_configured() -> bool:
	return _is_configured


func set_enabled(value: bool) -> void:
	_enabled = value
	if not _enabled:
		_car_drs_eligible.clear()
		_car_last_detection_zone.clear()


func is_enabled() -> bool:
	return _enabled and _is_configured


func evaluate_detections(cars: Array[RaceTypes.CarState], track_length: float) -> void:
	if not _is_configured or not _enabled or cars.is_empty() or track_length <= 0.0:
		for car in cars:
			car.drs_active = false
			car.drs_eligible = false
		return

	# Sort cars by total_distance descending (leader first)
	var sorted_cars: Array[RaceTypes.CarState] = cars.duplicate()
	sorted_cars.sort_custom(func(a: RaceTypes.CarState, b: RaceTypes.CarState) -> bool:
		return a.total_distance > b.total_distance
	)

	# For each car, check detection points and zone activation
	for car_idx in range(sorted_cars.size()):
		var car: RaceTypes.CarState = sorted_cars[car_idx]
		car.drs_active = false
		car.drs_eligible = false

		if car.is_finished or car.is_in_pit:
			_car_drs_eligible.erase(car.id)
			continue

		# DRS disabled for first N laps
		if car.lap_count < _min_activation_lap - 1:
			_car_drs_eligible.erase(car.id)
			continue

		# Find car ahead in sorted order
		var car_ahead: RaceTypes.CarState = null
		if car_idx > 0:
			car_ahead = sorted_cars[car_idx - 1]

		# Check each zone
		for zone_idx in range(_zones.size()):
			var zone: Dictionary = _zones[zone_idx]
			var detection_dist: float = float(zone["detection_distance"])
			var zone_start: float = float(zone["zone_start"])
			var zone_end: float = float(zone["zone_end"])

			# Check if car is near a detection point
			if _is_near_distance(car.distance_along_track, detection_dist, 2.0, track_length):
				if car_ahead != null and not car_ahead.is_in_pit:
					var gap: float = _compute_track_gap(car_ahead, car, track_length)
					if gap > 0.0 and gap <= _detection_threshold:
						_car_drs_eligible[car.id] = true
						_car_last_detection_zone[car.id] = zone_idx
					else:
						# Only clear if this is the detection for the zone we were eligible in
						var last_zone: int = _car_last_detection_zone.get(car.id, -1)
						if last_zone == zone_idx or last_zone < 0:
							_car_drs_eligible[car.id] = false
				else:
					var last_zone: int = _car_last_detection_zone.get(car.id, -1)
					if last_zone == zone_idx or last_zone < 0:
						_car_drs_eligible[car.id] = false

			# Check if car is in DRS zone and eligible
			if bool(_car_drs_eligible.get(car.id, false)):
				var eligible_zone: int = _car_last_detection_zone.get(car.id, -1)
				if eligible_zone == zone_idx:
					if _is_in_zone(car.distance_along_track, zone_start, zone_end, track_length):
						car.drs_active = true
						car.drs_eligible = true

		if not car.drs_active:
			car.drs_eligible = bool(_car_drs_eligible.get(car.id, false))


func get_drs_multiplier(car: RaceTypes.CarState) -> float:
	if car == null or not car.drs_active:
		return 1.0
	return _speed_boost


func get_zones() -> Array:
	return _zones.duplicate()


func get_speed_boost() -> float:
	return _speed_boost


func get_detection_threshold() -> float:
	return _detection_threshold


# --- Internal Helpers ---

func _compute_track_gap(ahead: RaceTypes.CarState, behind: RaceTypes.CarState, track_length: float) -> float:
	# Gap in track distance (handles lapping)
	return ahead.total_distance - behind.total_distance


func _is_near_distance(car_distance: float, target_distance: float, tolerance: float, track_length: float) -> bool:
	var diff: float = absf(fposmod(car_distance - target_distance, track_length))
	if diff > track_length * 0.5:
		diff = track_length - diff
	return diff <= tolerance


func _is_in_zone(car_distance: float, zone_start: float, zone_end: float, track_length: float) -> bool:
	if zone_start < zone_end:
		# Normal zone (doesn't wrap)
		return car_distance >= zone_start and car_distance <= zone_end
	else:
		# Wrapping zone (crosses start/finish line)
		return car_distance >= zone_start or car_distance <= zone_end
