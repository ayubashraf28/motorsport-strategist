extends GdUnitTestSuite

const RaceTypes = preload("res://sim/src/race_types.gd")
const OvertakingManager = preload("res://sim/src/overtaking_manager.gd")


func test_no_interaction_when_disabled() -> void:
	var manager := _manager(false, 50.0, 2.0, 0.1, 3.0)
	var ahead := _car("a", 100.0, 100.0, 5.0)
	var behind := _car("b", 90.0, 90.0, 6.0)
	manager.process_interactions([ahead, behind], 1000.0, 0.0)
	assert(behind.effective_speed_units_per_sec == 6.0)
	assert(not behind.is_held_up)


func test_no_interaction_when_far_apart() -> void:
	var manager := _manager(true, 5.0, 2.0, 0.1, 3.0)
	var ahead := _car("a", 100.0, 100.0, 5.0)
	var behind := _car("b", 90.0, 50.0, 6.0)
	manager.process_interactions([ahead, behind], 1000.0, 0.0)
	assert(not behind.is_held_up)


func test_held_up_below_threshold() -> void:
	var manager := _manager(true, 50.0, 2.0, 0.1, 3.0)
	var ahead := _car("a", 100.0, 100.0, 5.0)
	var behind := _car("b", 90.0, 90.0, 6.0)
	manager.process_interactions([ahead, behind], 1000.0, 0.0)
	assert(behind.is_held_up)
	assert(abs(behind.effective_speed_units_per_sec - 5.1) < 0.000001)


func test_overtake_above_threshold() -> void:
	var manager := _manager(true, 50.0, 2.0, 0.1, 3.0)
	var ahead := _car("a", 100.0, 100.0, 5.0)
	var behind := _car("b", 90.0, 90.0, 8.0)
	manager.process_interactions([ahead, behind], 1000.0, 0.0)
	assert(not behind.is_held_up)
	assert(behind.effective_speed_units_per_sec == 8.0)


func test_cooldown_prevents_re_interaction() -> void:
	var manager := _manager(true, 50.0, 2.0, 0.1, 3.0)
	var ahead := _car("a", 100.0, 100.0, 5.0)
	var behind := _car("b", 90.0, 90.0, 8.0)
	manager.process_interactions([ahead, behind], 1000.0, 0.0)

	behind.effective_speed_units_per_sec = 6.0
	manager.process_interactions([ahead, behind], 1000.0, 1.0)
	assert(not behind.is_held_up)
	assert(behind.effective_speed_units_per_sec == 6.0)


func test_cooldown_expires() -> void:
	var manager := _manager(true, 50.0, 2.0, 0.1, 3.0)
	var ahead := _car("a", 100.0, 100.0, 5.0)
	var behind := _car("b", 90.0, 90.0, 8.0)
	manager.process_interactions([ahead, behind], 1000.0, 0.0)

	behind.effective_speed_units_per_sec = 6.0
	manager.process_interactions([ahead, behind], 1000.0, 3.5)
	assert(behind.is_held_up)


func test_three_car_train() -> void:
	var manager := _manager(true, 50.0, 2.0, 0.1, 3.0)
	var car_a := _car("a", 100.0, 100.0, 5.0)
	var car_b := _car("b", 90.0, 90.0, 6.5)
	var car_c := _car("c", 80.0, 80.0, 6.8)
	manager.process_interactions([car_a, car_b, car_c], 1000.0, 0.0)
	assert(car_b.is_held_up)
	assert(car_c.is_held_up)
	assert(abs(car_b.effective_speed_units_per_sec - 5.1) < 0.000001)
	assert(abs(car_c.effective_speed_units_per_sec - 5.2) < 0.000001)


func test_lapped_traffic() -> void:
	var manager := _manager(true, 12.0, 2.0, 0.1, 3.0)
	var leader := _car("leader", 1010.0, 10.0, 5.0)
	var backmarker := _car("backmarker", 990.0, 998.0, 6.0)
	manager.process_interactions([leader, backmarker], 1000.0, 0.0)
	assert(backmarker.is_held_up)


func test_same_total_distance_no_crash() -> void:
	var manager := _manager(true, 50.0, 2.0, 0.1, 3.0)
	var car_a := _car("a", 100.0, 100.0, 5.0)
	var car_b := _car("b", 100.0, 100.0, 6.0)
	manager.process_interactions([car_a, car_b], 1000.0, 0.0)
	assert(true)


func test_held_up_speed_matches_car_ahead() -> void:
	var manager := _manager(true, 50.0, 2.0, 0.2, 3.0)
	var ahead := _car("a", 100.0, 100.0, 7.0)
	var behind := _car("b", 90.0, 95.0, 8.0)
	manager.process_interactions([ahead, behind], 1000.0, 0.0)
	assert(abs(behind.effective_speed_units_per_sec - 7.2) < 0.000001)


func test_finished_car_does_not_block() -> void:
	var manager := _manager(true, 50.0, 2.0, 0.1, 3.0)
	var ahead := _car("a", 100.0, 100.0, 5.0, true)
	var behind := _car("b", 90.0, 90.0, 6.0)
	manager.process_interactions([ahead, behind], 1000.0, 0.0)
	assert(not behind.is_held_up)
	assert(behind.effective_speed_units_per_sec == 6.0)


func test_car_in_pit_is_skipped() -> void:
	var manager := _manager(true, 50.0, 2.0, 0.1, 3.0)
	var ahead := _car("a", 100.0, 100.0, 5.0)
	var behind := _car("b", 90.0, 90.0, 6.0)
	ahead.is_in_pit = true
	manager.process_interactions([ahead, behind], 1000.0, 0.0)
	assert(not behind.is_held_up)
	assert(behind.effective_speed_units_per_sec == 6.0)


func test_cooldown_key_is_symmetric() -> void:
	var manager := _manager(true, 50.0, 2.0, 0.1, 3.0)
	var key_a: String = manager._get_cooldown_key("car_a", "car_b")
	var key_b: String = manager._get_cooldown_key("car_b", "car_a")
	assert(key_a == key_b)


func test_reset_clears_cooldowns() -> void:
	var manager := _manager(true, 50.0, 2.0, 0.1, 3.0)
	var ahead := _car("a", 100.0, 100.0, 5.0)
	var behind := _car("b", 90.0, 90.0, 8.0)
	manager.process_interactions([ahead, behind], 1000.0, 0.0)

	manager.reset()
	behind.effective_speed_units_per_sec = 6.0
	manager.process_interactions([ahead, behind], 1000.0, 1.0)
	assert(behind.is_held_up)


func _manager(
	enabled: bool,
	proximity: float,
	threshold: float,
	buffer: float,
	cooldown: float
) -> OvertakingManager:
	var config := RaceTypes.OvertakingConfig.new()
	config.enabled = enabled
	config.proximity_distance = proximity
	config.overtake_speed_threshold = threshold
	config.held_up_speed_buffer = buffer
	config.cooldown_seconds = cooldown
	var manager := OvertakingManager.new()
	manager.configure(config)
	return manager


func _car(
	id_value: String,
	total_distance: float,
	distance_along_track: float,
	speed: float,
	is_finished: bool = false
) -> RaceTypes.CarState:
	var car := RaceTypes.CarState.new()
	car.id = id_value
	car.total_distance = total_distance
	car.distance_along_track = distance_along_track
	car.effective_speed_units_per_sec = speed
	car.is_finished = is_finished
	return car
