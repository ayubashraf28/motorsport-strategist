extends GdUnitTestSuite

const RaceTypes = preload("res://sim/src/race_types.gd")
const PitStopManager = preload("res://sim/src/pit_stop_manager.gd")

const TRACK_LENGTH: float = 2025.5


func test_disabled_when_no_config() -> void:
	var manager := PitStopManager.new()
	manager.configure(null, null, TRACK_LENGTH)
	assert(not manager.is_enabled())


func test_entry_triggered_at_entry_distance() -> void:
	var manager := _manager(_pit_config(), _fuel_config())
	var car := _car("car_1", 1, 0)
	assert(manager.should_enter_pit(car, {"car_1": {}}, 1940.0, 1950.0, TRACK_LENGTH, RaceTypes.RaceState.RUNNING))


func test_no_entry_before_entry_distance() -> void:
	var manager := _manager(_pit_config(), _fuel_config())
	var car := _car("car_1", 1, 0)
	assert(not manager.should_enter_pit(car, {"car_1": {}}, 1800.0, 1900.0, TRACK_LENGTH, RaceTypes.RaceState.RUNNING))


func test_entry_sets_pit_phase_and_flags() -> void:
	var manager := _manager(_pit_config(), _fuel_config())
	var car := _car("car_1", 1, 0)
	manager.begin_pit_entry(car, {"compound": "hard", "fuel_kg": 90.0})
	assert(car.is_in_pit)
	assert(car.pit_phase == RaceTypes.PitPhase.ENTRY)


func test_entry_duration_computed_from_distance() -> void:
	var manager := _manager(_pit_config(), _fuel_config())
	var car := _car("car_1", 1, 0)
	manager.begin_pit_entry(car, {"compound": "hard", "fuel_kg": 90.0})
	assert(abs(car.pit_time_remaining - 3.875) < 0.000001)


func test_exit_duration_computed_from_distance() -> void:
	var manager := _manager(_pit_config(), _fuel_config())
	var car := _car("car_1", 1, 0)
	manager.begin_pit_entry(car, {"compound": "hard", "fuel_kg": 90.0})
	manager.process_pit_phase(car, 10.0) # entry -> stopped
	manager.process_pit_phase(car, 3.0) # stopped -> exit
	assert(car.pit_phase == RaceTypes.PitPhase.EXIT)
	assert(abs(car.pit_time_remaining - 3.9) < 0.000001)


func test_position_interpolates_during_entry() -> void:
	var manager := _manager(_pit_config(), _fuel_config())
	var car := _car("car_1", 1, 0)
	manager.begin_pit_entry(car, {"compound": "hard", "fuel_kg": 90.0})
	manager.process_pit_phase(car, 0.5)
	manager.process_pit_phase(car, 0.5)
	assert(car.distance_along_track != _pit_config().pit_entry_distance)


func test_position_interpolates_during_exit() -> void:
	var manager := _manager(_pit_config(), _fuel_config())
	var car := _car("car_1", 1, 0)
	manager.begin_pit_entry(car, {"compound": "hard", "fuel_kg": 90.0})
	manager.process_pit_phase(car, 10.0) # entry -> stopped
	manager.process_pit_phase(car, 3.0) # stopped -> exit
	manager.process_pit_phase(car, 0.5)
	manager.process_pit_phase(car, 0.5)
	assert(car.distance_along_track != _pit_config().pit_box_distance)


func test_position_wraps_around_sf_line() -> void:
	var manager := _manager(_pit_config(), _fuel_config())
	var car := _car("car_1", 1, 0)
	manager.begin_pit_entry(car, {"compound": "hard", "fuel_kg": 90.0})
	car.pit_time_remaining = 0.05
	manager.process_pit_phase(car, 0.01)
	assert(car.distance_along_track < 10.0)


func test_pit_box_at_midpoint_when_auto() -> void:
	var pit := _pit_config()
	pit.pit_box_distance = -1.0
	var manager := _manager(pit, _fuel_config())
	var car := _car("car_1", 1, 0)
	manager.begin_pit_entry(car, {"compound": "hard", "fuel_kg": 90.0})
	manager.process_pit_phase(car, 10.0)
	assert(car.pit_phase == RaceTypes.PitPhase.STOPPED)
	assert(abs(car.distance_along_track - 2.25) < 0.000001)


func test_pit_box_explicit_value() -> void:
	var pit := _pit_config()
	pit.pit_box_distance = 10.0
	var manager := _manager(pit, _fuel_config())
	var car := _car("car_1", 1, 0)
	manager.begin_pit_entry(car, {"compound": "hard", "fuel_kg": 90.0})
	manager.process_pit_phase(car, 10.0)
	assert(car.pit_phase == RaceTypes.PitPhase.STOPPED)
	assert(abs(car.distance_along_track - 10.0) < 0.000001)


func test_stopped_phase_at_pit_box_position() -> void:
	var manager := _manager(_pit_config(), _fuel_config())
	var car := _car("car_1", 1, 0)
	manager.begin_pit_entry(car, {"compound": "hard", "fuel_kg": 90.0})
	manager.process_pit_phase(car, 10.0)
	var box_position: float = car.distance_along_track
	manager.process_pit_phase(car, 1.0)
	assert(abs(car.distance_along_track - box_position) < 0.000001)


func test_stopped_transitions_to_exit() -> void:
	var manager := _manager(_pit_config(), null)
	var car := _car("car_1", 1, 0)
	manager.begin_pit_entry(car, {"compound": "hard", "fuel_kg": -1.0})
	manager.process_pit_phase(car, 10.0)
	var result: Dictionary = manager.process_pit_phase(car, 3.0)
	assert(car.pit_phase == RaceTypes.PitPhase.EXIT)
	assert(result.get("new_compound", "") == "hard")


func test_exit_transitions_to_racing() -> void:
	var manager := _manager(_pit_config(), null)
	var car := _car("car_1", 1, 0)
	manager.begin_pit_entry(car, {"compound": "hard", "fuel_kg": -1.0})
	manager.process_pit_phase(car, 10.0)
	manager.process_pit_phase(car, 3.0)
	var result: Dictionary = manager.process_pit_phase(car, 10.0)
	assert(not car.is_in_pit)
	assert(car.pit_phase == RaceTypes.PitPhase.RACING)
	assert(bool(result.get("completed", false)))


func test_exit_sets_distance_to_exit_point() -> void:
	var manager := _manager(_pit_config(), null)
	var car := _car("car_1", 1, 0)
	manager.begin_pit_entry(car, {"compound": "hard", "fuel_kg": -1.0})
	manager.process_pit_phase(car, 10.0)
	manager.process_pit_phase(car, 3.0)
	manager.process_pit_phase(car, 10.0)
	assert(abs(car.distance_along_track - 80.0) < 0.000001)


func test_full_pit_stop_total_duration() -> void:
	var pit := _pit_config()
	pit.base_pit_stop_duration = 3.0
	var fuel := _fuel_config()
	fuel.refuel_rate_kg_per_sec = 10.0
	fuel.max_capacity_kg = 100.0
	var manager := _manager(pit, fuel)

	var car := _car("car_1", 1, 0)
	car.fuel_kg = 80.0
	manager.begin_pit_entry(car, {"compound": "hard", "fuel_kg": -1.0})

	var elapsed: float = 0.0
	for _i in range(80):
		var result: Dictionary = manager.process_pit_phase(car, 0.25)
		elapsed += 0.25
		if bool(result.get("completed", false)):
			break

	assert(abs(elapsed - 12.75) < 0.26)


func test_stop_duration_includes_refuel_time() -> void:
	var manager := _manager(_pit_config(), _fuel_config())
	var car := _car("car_1", 1, 0)
	car.fuel_kg = 50.0
	car.pit_target_fuel_kg = 90.0
	var stop_duration: float = manager.compute_stop_duration(car)
	assert(abs(stop_duration - 23.0) < 0.000001)


func test_no_refuel_when_fuel_disabled() -> void:
	var manager := _manager(_pit_config(), null)
	var car := _car("car_1", 1, 0)
	car.fuel_kg = 20.0
	car.pit_target_fuel_kg = 90.0
	assert(abs(manager.compute_stop_duration(car) - 3.0) < 0.000001)


func test_compound_change_on_stop_to_exit() -> void:
	var manager := _manager(_pit_config(), null)
	var car := _car("car_1", 1, 0)
	manager.begin_pit_entry(car, {"compound": "medium", "fuel_kg": -1.0})
	manager.process_pit_phase(car, 10.0)
	var result: Dictionary = manager.process_pit_phase(car, 3.0)
	assert(result.get("new_compound", "") == "medium")


func test_pit_speed_during_entry() -> void:
	var manager := _manager(_pit_config(), null)
	var car := _car("car_1", 1, 0)
	car.pit_phase = RaceTypes.PitPhase.ENTRY
	assert(abs(manager.get_pit_speed(car) - 20.0) < 0.000001)


func test_pit_speed_during_stopped() -> void:
	var manager := _manager(_pit_config(), null)
	var car := _car("car_1", 1, 0)
	car.pit_phase = RaceTypes.PitPhase.STOPPED
	assert(abs(manager.get_pit_speed(car) - 0.0) < 0.000001)


func test_pit_speed_during_exit() -> void:
	var manager := _manager(_pit_config(), null)
	var car := _car("car_1", 1, 0)
	car.pit_phase = RaceTypes.PitPhase.EXIT
	assert(abs(manager.get_pit_speed(car) - 20.0) < 0.000001)


func test_min_stop_lap_enforced() -> void:
	var manager := _manager(_pit_config(), null)
	var car := _car("car_1", 0, 0)
	assert(not manager.should_enter_pit(car, {"car_1": {}}, 1940.0, 1950.0, TRACK_LENGTH, RaceTypes.RaceState.RUNNING))


func test_max_stops_enforced() -> void:
	var manager := _manager(_pit_config(), null)
	var car := _car("car_1", 2, 5)
	assert(not manager.should_enter_pit(car, {"car_1": {}}, 1940.0, 1950.0, TRACK_LENGTH, RaceTypes.RaceState.RUNNING))


func test_no_pit_without_request() -> void:
	var manager := _manager(_pit_config(), null)
	var car := _car("car_1", 2, 0)
	assert(not manager.should_enter_pit(car, {}, 1940.0, 1950.0, TRACK_LENGTH, RaceTypes.RaceState.RUNNING))


func test_no_pit_during_finishing() -> void:
	var manager := _manager(_pit_config(), null)
	var car := _car("car_1", 2, 0)
	assert(not manager.should_enter_pit(car, {"car_1": {}}, 1940.0, 1950.0, TRACK_LENGTH, RaceTypes.RaceState.FINISHING))


func test_lap_not_counted_when_entering_pit() -> void:
	var manager := _manager(_pit_config(), null)
	var car := _car("car_1", 3, 0)
	manager.begin_pit_entry(car, {"compound": "hard", "fuel_kg": -1.0})
	manager.process_pit_phase(car, 1.0)
	assert(car.lap_count == 3)


func _manager(pit: RaceTypes.PitConfig, fuel: RaceTypes.FuelConfig) -> PitStopManager:
	var manager := PitStopManager.new()
	manager.configure(pit, fuel, TRACK_LENGTH)
	return manager


func _pit_config() -> RaceTypes.PitConfig:
	var config := RaceTypes.PitConfig.new()
	config.enabled = true
	config.pit_entry_distance = 1950.0
	config.pit_exit_distance = 80.0
	config.pit_box_distance = 2.0
	config.pit_lane_speed_limit = 20.0
	config.base_pit_stop_duration = 3.0
	config.pit_entry_duration = 8.0
	config.pit_exit_duration = 8.0
	config.min_stop_lap = 1
	config.max_stops = 5
	return config


func _fuel_config() -> RaceTypes.FuelConfig:
	var config := RaceTypes.FuelConfig.new()
	config.enabled = true
	config.max_capacity_kg = 100.0
	config.consumption_per_lap_kg = 2.5
	config.weight_penalty_factor = 0.05
	config.fuel_empty_penalty = 0.5
	config.refuel_rate_kg_per_sec = 2.0
	return config


func _car(id_value: String, lap_count: int, pit_stops_completed: int) -> RaceTypes.CarState:
	var car := RaceTypes.CarState.new()
	car.id = id_value
	car.lap_count = lap_count
	car.pit_stops_completed = pit_stops_completed
	car.fuel_kg = 50.0
	return car
