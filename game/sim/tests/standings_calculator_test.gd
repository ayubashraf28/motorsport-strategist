extends GdUnitTestSuite

const RaceTypes = preload("res://sim/src/race_types.gd")
const StandingsCalculator = preload("res://sim/src/standings_calculator.gd")


func test_single_car_is_position_1() -> void:
	var cars: Array[RaceTypes.CarState] = [_car_state("car_1", 100.0)]
	StandingsCalculator.update_positions(cars)
	assert(cars[0].position == 1)


func test_faster_car_has_lower_position() -> void:
	var cars: Array[RaceTypes.CarState] = [
		_car_state("car_fast", 120.0),
		_car_state("car_slow", 90.0)
	]
	StandingsCalculator.update_positions(cars)
	assert(cars[0].position == 1)
	assert(cars[1].position == 2)


func test_lapped_car_is_behind() -> void:
	var leading_car := _car_state("lead", 0.0)
	leading_car.lap_count = 4
	leading_car.distance_along_track = 5000.0
	leading_car.total_distance = 25000.0

	var lapped_car := _car_state("lapped", 0.0)
	lapped_car.lap_count = 3
	lapped_car.distance_along_track = 5200.0
	lapped_car.total_distance = 20200.0

	var cars: Array[RaceTypes.CarState] = [leading_car, lapped_car]
	StandingsCalculator.update_positions(cars)
	assert(leading_car.position == 1)
	assert(lapped_car.position == 2)


func test_same_distance_preserves_config_order() -> void:
	var first := _car_state("car_1", 100.0)
	var second := _car_state("car_2", 100.0)
	var cars: Array[RaceTypes.CarState] = [first, second]

	StandingsCalculator.update_positions(cars)
	assert(first.position == 1)
	assert(second.position == 2)


func test_positions_update_after_pass() -> void:
	var car_a := _car_state("a", 100.0)
	var car_b := _car_state("b", 110.0)
	var cars: Array[RaceTypes.CarState] = [car_a, car_b]

	StandingsCalculator.update_positions(cars)
	assert(car_b.position == 1)
	assert(car_a.position == 2)

	car_a.total_distance = 140.0
	StandingsCalculator.update_positions(cars)
	assert(car_a.position == 1)
	assert(car_b.position == 2)


func test_interval_is_correct() -> void:
	var cars: Array[RaceTypes.CarState] = [
		_car_state("car_1", 300.0),
		_car_state("car_2", 250.0),
		_car_state("car_3", 190.0)
	]
	StandingsCalculator.update_positions(cars)
	var intervals: Dictionary = StandingsCalculator.compute_interval_to_car_ahead(cars)

	assert(intervals["car_2"] == 50.0)
	assert(intervals["car_3"] == 60.0)


func test_leader_interval_is_zero() -> void:
	var cars: Array[RaceTypes.CarState] = [
		_car_state("car_1", 150.0),
		_car_state("car_2", 120.0)
	]
	StandingsCalculator.update_positions(cars)
	var intervals: Dictionary = StandingsCalculator.compute_interval_to_car_ahead(cars)
	assert(intervals["car_1"] == 0.0)


func test_empty_cars_array_is_noop() -> void:
	var cars: Array[RaceTypes.CarState] = []
	StandingsCalculator.update_positions(cars)
	var intervals: Dictionary = StandingsCalculator.compute_interval_to_car_ahead(cars)
	assert(intervals.is_empty())


func _car_state(id_value: String, total_distance: float) -> RaceTypes.CarState:
	var car := RaceTypes.CarState.new()
	car.id = id_value
	car.display_name = id_value
	car.total_distance = total_distance
	return car
