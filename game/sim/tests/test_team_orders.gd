extends GdUnitTestSuite

const RaceTypes = preload("res://sim/src/race_types.gd")
const RaceSimulator = preload("res://sim/src/race_simulator.gd")
const TeamOrders = preload("res://sim/src/team_orders.gd")


func test_let_through_swaps_teammates_and_auto_clears() -> void:
	var simulator := _build_simulator()
	assert(simulator.is_ready())

	_seed_distances(simulator, {
		"A1": 60.0,
		"A2": 58.5,
		"B1": 20.0
	})
	simulator.issue_team_order("A1", TeamOrders.Order.LET_THROUGH, "A2")

	for _i in range(300):
		simulator.step(0.05)
		var snapshot_loop: RaceTypes.RaceSnapshot = simulator.get_snapshot()
		var a1_loop: RaceTypes.CarState = _find_car(snapshot_loop, "A1")
		var a2_loop: RaceTypes.CarState = _find_car(snapshot_loop, "A2")
		if a2_loop.total_distance > a1_loop.total_distance:
			break

	var snapshot: RaceTypes.RaceSnapshot = simulator.get_snapshot()
	var a1: RaceTypes.CarState = _find_car(snapshot, "A1")
	var a2: RaceTypes.CarState = _find_car(snapshot, "A2")
	assert(a2.total_distance > a1.total_distance)
	assert(a1.team_order == TeamOrders.Order.NONE)
	assert(a1.team_order_target.is_empty())


func test_hold_position_prevents_teammate_attack() -> void:
	var simulator := _build_simulator()
	assert(simulator.is_ready())

	_seed_distances(simulator, {
		"A1": 60.0,
		"A2": 59.2,
		"B1": 25.0
	})
	simulator.issue_team_order("A2", TeamOrders.Order.HOLD_POSITION, "A1")

	for _i in range(80):
		simulator.step(0.05)

	var snapshot: RaceTypes.RaceSnapshot = simulator.get_snapshot()
	var a1: RaceTypes.CarState = _find_car(snapshot, "A1")
	var a2: RaceTypes.CarState = _find_car(snapshot, "A2")
	assert(a2.total_distance <= a1.total_distance + 0.01)
	assert(a2.team_order == TeamOrders.Order.HOLD_POSITION)


func test_defend_holds_up_target_rival() -> void:
	var simulator := _build_simulator()
	assert(simulator.is_ready())

	_seed_distances(simulator, {
		"A1": 60.0,
		"A2": 40.0,
		"B1": 58.5
	})
	simulator.issue_team_order("A1", TeamOrders.Order.DEFEND, "B1")
	simulator.step(0.1)

	var snapshot: RaceTypes.RaceSnapshot = simulator.get_snapshot()
	var b1: RaceTypes.CarState = _find_car(snapshot, "B1")
	assert(b1.is_held_up)
	assert(b1.held_up_by == "A1")


func test_invalid_team_order_inputs_are_ignored() -> void:
	var simulator := _build_simulator()
	assert(simulator.is_ready())

	simulator.issue_team_order("A1", TeamOrders.Order.LET_THROUGH, "B1")
	simulator.issue_team_order("A1", TeamOrders.Order.DEFEND, "A2")
	simulator.issue_team_order("A1", TeamOrders.Order.LET_THROUGH, "A1")

	var snapshot: RaceTypes.RaceSnapshot = simulator.get_snapshot()
	var a1: RaceTypes.CarState = _find_car(snapshot, "A1")
	assert(a1.team_order == TeamOrders.Order.NONE)
	assert(a1.team_order_target.is_empty())


func _build_simulator() -> RaceSimulator:
	var config := RaceTypes.RaceConfig.new()
	config.schema_version = "4.0"
	config.track = _constant_track_profile(100.0)
	config.total_laps = 20
	config.seed = 11

	var overtaking := RaceTypes.OvertakingConfig.new()
	overtaking.enabled = true
	overtaking.proximity_distance = 40.0
	overtaking.overtake_speed_threshold = 2.0
	overtaking.held_up_speed_buffer = 0.1
	overtaking.cooldown_seconds = 1.0
	config.overtaking = overtaking

	config.cars.append(_car("A1", 55.0, "team_a"))
	config.cars.append(_car("A2", 58.0, "team_a"))
	config.cars.append(_car("B1", 62.0, "team_b"))

	var runtime := RaceTypes.RaceRuntimeParams.new()
	runtime.track_length = 100.0
	var simulator := RaceSimulator.new()
	simulator.initialize(config, runtime)
	return simulator


func _car(car_id: String, speed: float, team_id: String) -> RaceTypes.CarConfig:
	var car := RaceTypes.CarConfig.new()
	car.id = car_id
	car.display_name = car_id
	car.base_speed_units_per_sec = speed
	car.v_ref = speed
	car.team_id = team_id
	return car


func _constant_track_profile(track_length: float) -> RaceTypes.PaceProfileConfig:
	var profile := RaceTypes.PaceProfileConfig.new()
	var segment := RaceTypes.PaceSegmentConfig.new()
	segment.start_distance = 0.0
	segment.end_distance = track_length
	segment.multiplier = 1.0
	profile.pace_segments.append(segment)
	return profile


func _seed_distances(simulator: RaceSimulator, distance_by_car: Dictionary) -> void:
	for car in simulator._cars:
		if car == null:
			continue
		if not distance_by_car.has(car.id):
			continue
		var distance: float = float(distance_by_car[car.id])
		car.distance_along_track = distance
		car.total_distance = distance


func _find_car(snapshot: RaceTypes.RaceSnapshot, car_id: String) -> RaceTypes.CarState:
	for raw_car in snapshot.cars:
		var car: RaceTypes.CarState = raw_car as RaceTypes.CarState
		if car != null and car.id == car_id:
			return car
	return null
