extends GdUnitTestSuite

const RaceTypes = preload("res://sim/src/race_types.gd")
const RaceEngineer = preload("res://scripts/race_engineer.gd")


func test_safety_car_phase_change_emits_high_priority_prompt() -> void:
	var engineer := RaceEngineer.new()
	var snapshot := _snapshot_with_cars([
		_car("A1", "team_a", 1, 120.0, 0.9)
	], 20.0)

	var messages: Array = engineer.evaluate(
		snapshot,
		50.0,
		RaceTypes.SafetyCarPhase.SC_DEPLOYED,
		3
	)
	assert(_contains_text(messages, "Safety Car deployed"))


func test_team_order_opportunity_message_when_teammates_close() -> void:
	var engineer := RaceEngineer.new()
	var snapshot := _snapshot_with_cars([
		_car("A1", "team_a", 3, 300.0, 0.8),
		_car("A2", "team_a", 4, 272.0, 0.82),
		_car("B1", "team_b", 2, 340.0, 0.8)
	], 45.0)

	var messages: Array = engineer.evaluate(
		snapshot,
		50.0,
		RaceTypes.SafetyCarPhase.GREEN,
		0
	)
	assert(_contains_text(messages, "team order opportunity"))


func _snapshot_with_cars(cars: Array, race_time: float) -> RaceTypes.RaceSnapshot:
	var snapshot := RaceTypes.RaceSnapshot.new()
	snapshot.race_state = RaceTypes.RaceState.RUNNING
	snapshot.race_time = race_time
	snapshot.total_laps = 15
	for raw_car in cars:
		var car: RaceTypes.CarState = raw_car as RaceTypes.CarState
		if car != null:
			snapshot.cars.append(car)
	return snapshot


func _car(
	car_id: String,
	team_id: String,
	position: int,
	total_distance: float,
	tyre_life_ratio: float
) -> RaceTypes.CarState:
	var car := RaceTypes.CarState.new()
	car.id = car_id
	car.display_name = car_id
	car.team_id = team_id
	car.position = position
	car.total_distance = total_distance
	car.tyre_life_ratio = tyre_life_ratio
	car.driver_mode = 1
	car.effective_speed_units_per_sec = 50.0
	car.current_compound = "medium"
	return car


func _contains_text(messages: Array, part: String) -> bool:
	for raw_message in messages:
		if typeof(raw_message) != TYPE_DICTIONARY:
			continue
		var message: Dictionary = raw_message
		if String(message.get("text", "")).findn(part) >= 0:
			return true
	return false
