extends GdUnitTestSuite

const RaceTypes = preload("res://sim/src/race_types.gd")
const RaceStateMachine = preload("res://sim/src/race_state_machine.gd")


func test_initial_state_is_not_started() -> void:
	var machine := RaceStateMachine.new()
	machine.configure(10, 2)
	assert(machine.get_state() == RaceTypes.RaceState.NOT_STARTED)


func test_transitions_to_running() -> void:
	var machine := RaceStateMachine.new()
	machine.configure(10, 2)
	machine.on_race_start()
	assert(machine.get_state() == RaceTypes.RaceState.RUNNING)


func test_leader_finishing_triggers_finishing() -> void:
	var machine := RaceStateMachine.new()
	machine.configure(3, 2)
	machine.on_race_start()
	var leader := _car("leader", 3)

	machine.on_lap_completed(leader, 120.0)
	assert(machine.get_state() == RaceTypes.RaceState.FINISHING)
	assert(leader.is_finished)
	assert(leader.finish_position == 1)


func test_all_cars_finishing_triggers_finished() -> void:
	var machine := RaceStateMachine.new()
	machine.configure(2, 2)
	machine.on_race_start()
	var car_a := _car("a", 2)
	var car_b := _car("b", 1)

	machine.on_lap_completed(car_a, 50.0)
	assert(machine.get_state() == RaceTypes.RaceState.FINISHING)
	car_b.lap_count = 2
	machine.on_lap_completed(car_b, 51.0)
	assert(machine.get_state() == RaceTypes.RaceState.FINISHED)


func test_finished_car_stops_accumulating_laps() -> void:
	var machine := RaceStateMachine.new()
	machine.configure(1, 1)
	machine.on_race_start()
	var car := _car("car_1", 1)

	machine.on_lap_completed(car, 10.0)
	assert(not machine.is_car_racing(car))
	var first_finish_position: int = car.finish_position
	machine.on_lap_completed(car, 20.0)
	assert(car.finish_position == first_finish_position)


func test_unlimited_laps_never_finishes() -> void:
	var machine := RaceStateMachine.new()
	machine.configure(0, 2)
	machine.on_race_start()
	var car := _car("car_1", 20)
	machine.on_lap_completed(car, 100.0)
	assert(machine.get_state() == RaceTypes.RaceState.RUNNING)
	assert(not car.is_finished)


func test_finish_order_matches_crossing_sequence() -> void:
	var machine := RaceStateMachine.new()
	machine.configure(2, 3)
	machine.on_race_start()
	var a := _car("a", 2)
	var b := _car("b", 2)
	var c := _car("c", 2)

	machine.on_lap_completed(b, 60.2)
	machine.on_lap_completed(a, 60.4)
	machine.on_lap_completed(c, 61.0)

	var order: Array[String] = machine.get_finish_order()
	assert(order[0] == "b")
	assert(order[1] == "a")
	assert(order[2] == "c")


func test_finish_time_is_analytical_crossing_time() -> void:
	var machine := RaceStateMachine.new()
	machine.configure(1, 1)
	machine.on_race_start()
	var car := _car("car_1", 1)
	machine.on_lap_completed(car, 12.345)
	assert(abs(car.finish_time - 12.345) < 0.000001)


func test_backmarker_finishes_on_next_crossing() -> void:
	var machine := RaceStateMachine.new()
	machine.configure(3, 2)
	machine.on_race_start()
	var leader := _car("leader", 3)
	var backmarker := _car("backmarker", 2)

	machine.on_lap_completed(leader, 100.0)
	assert(machine.get_state() == RaceTypes.RaceState.FINISHING)
	assert(not backmarker.is_finished)

	backmarker.lap_count = 3
	machine.on_lap_completed(backmarker, 120.0)
	assert(backmarker.is_finished)
	assert(machine.get_state() == RaceTypes.RaceState.FINISHED)


func test_reset_clears_everything() -> void:
	var machine := RaceStateMachine.new()
	machine.configure(1, 1)
	machine.on_race_start()
	var car := _car("car_1", 1)
	machine.on_lap_completed(car, 12.0)

	machine.reset()
	assert(machine.get_state() == RaceTypes.RaceState.NOT_STARTED)
	assert(machine.get_finish_order().is_empty())


func _car(id_value: String, lap_count: int) -> RaceTypes.CarState:
	var car := RaceTypes.CarState.new()
	car.id = id_value
	car.lap_count = lap_count
	return car
