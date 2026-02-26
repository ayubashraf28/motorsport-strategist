extends RefCounted
class_name AiStrategyController

const RaceTypes = preload("res://sim/src/race_types.gd")
const RaceSimulator = preload("res://sim/src/race_simulator.gd")
const DriverModeModule = preload("res://sim/src/driver_mode.gd")

var _pit_thresholds: Dictionary = {}
var _available_compounds: PackedStringArray = PackedStringArray()
var _stint_at_last_request: Dictionary = {}

const _MODE_PUSH_GAP_THRESHOLD: float = 80.0  # Push when within this distance of car ahead
const _MODE_CONSERVE_TYRE_THRESHOLD: float = 0.45  # Conserve when tyre life below this
const _MODE_CONSERVE_FUEL_THRESHOLD: float = 0.15  # Conserve when fuel ratio below this


func configure(pit_thresholds: Dictionary, available_compounds: PackedStringArray) -> void:
	_pit_thresholds = pit_thresholds
	_available_compounds = available_compounds
	_stint_at_last_request = {}


func reset() -> void:
	_stint_at_last_request = {}


func evaluate(snapshot: RaceTypes.RaceSnapshot, simulator: RaceSimulator) -> void:
	if snapshot.race_state == RaceTypes.RaceState.FINISHED:
		return
	if snapshot.race_state == RaceTypes.RaceState.NOT_STARTED:
		return

	for car in snapshot.cars:
		_evaluate_pit(car, simulator)
		_evaluate_driver_mode(car, snapshot, simulator)


func _evaluate_pit(car: RaceTypes.CarState, simulator: RaceSimulator) -> void:
	if not simulator.is_pit_enabled():
		return
	if car.is_finished:
		return
	if car.is_in_pit:
		return
	if simulator.has_pending_pit_request(car.id):
		return

	var threshold: float = _pit_thresholds.get(car.id, 0.35)

	# Don't re-request if we already requested this stint
	var last_stint: int = _stint_at_last_request.get(car.id, -1)
	if last_stint == car.stint_number:
		return

	if car.tyre_life_ratio > threshold:
		return

	var next_compound: String = _get_next_compound(car.current_compound)
	if next_compound.is_empty():
		return

	simulator.request_pit_stop(car.id, next_compound, -1.0)
	_stint_at_last_request[car.id] = car.stint_number


func _evaluate_driver_mode(
	car: RaceTypes.CarState,
	snapshot: RaceTypes.RaceSnapshot,
	simulator: RaceSimulator
) -> void:
	if car.is_finished or car.is_in_pit:
		return

	var target_mode: int = DriverModeModule.Mode.STANDARD

	# Conserve when tyres are worn
	if car.tyre_life_ratio < _MODE_CONSERVE_TYRE_THRESHOLD:
		target_mode = DriverModeModule.Mode.CONSERVE
	# Conserve when fuel is critically low
	elif simulator.is_fuel_enabled() and simulator.get_fuel_capacity_kg() > 0.0:
		var fuel_ratio: float = car.fuel_kg / simulator.get_fuel_capacity_kg()
		if fuel_ratio < _MODE_CONSERVE_FUEL_THRESHOLD:
			target_mode = DriverModeModule.Mode.CONSERVE
	# Push when close to car ahead and tyres are healthy
	elif car.tyre_life_ratio > 0.55:
		var gap: float = _get_gap_to_car_ahead(car, snapshot)
		if gap > 0.0 and gap < _MODE_PUSH_GAP_THRESHOLD:
			target_mode = DriverModeModule.Mode.PUSH

	if car.driver_mode != target_mode:
		simulator.set_driver_mode(car.id, target_mode)


func _get_gap_to_car_ahead(car: RaceTypes.CarState, snapshot: RaceTypes.RaceSnapshot) -> float:
	if car.position <= 1:
		return -1.0  # Already in first, no car ahead
	for other in snapshot.cars:
		if other.position == car.position - 1 and not other.is_finished:
			return other.total_distance - car.total_distance
	return -1.0


func _get_next_compound(current_compound: String) -> String:
	if _available_compounds.is_empty():
		return ""
	var current_lower: String = current_compound.to_lower()
	var current_idx: int = -1
	for i in range(_available_compounds.size()):
		if _available_compounds[i].to_lower() == current_lower:
			current_idx = i
			break
	# Pick next compound in the cycle, skipping current
	var next_idx: int = (current_idx + 1) % _available_compounds.size()
	return _available_compounds[next_idx]
