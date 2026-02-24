extends GdUnitTestSuite

const RaceTypes = preload("res://sim/src/race_types.gd")
const RaceSimulator = preload("res://sim/src/race_simulator.gd")


func test_single_car_lap_time_matches_track_length_over_speed() -> void:
	var simulator := _build_simulator([_car("car_1", 50.0)], 200.0)
	assert(simulator.is_ready())

	simulator.step(4.0)
	var snapshot := simulator.get_snapshot()
	var car := snapshot.cars[0]

	assert(car.lap_count == 1)
	assert(abs(car.last_lap_time - 4.0) < 0.0001)
	assert(abs(car.best_lap_time - 4.0) < 0.0001)


func test_multi_car_timing_is_independent() -> void:
	var simulator := _build_simulator([
		_car("car_1", 25.0),
		_car("car_2", 50.0)
	], 100.0)
	assert(simulator.is_ready())

	simulator.step(4.0)
	var snapshot := simulator.get_snapshot()

	assert(snapshot.cars[0].lap_count == 1)
	assert(snapshot.cars[1].lap_count == 2)
	assert(snapshot.cars[0].id != snapshot.cars[1].id)


func test_first_lap_counted_from_race_start() -> void:
	var simulator := _build_simulator([_car("car_1", 20.0)], 100.0)
	assert(simulator.is_ready())

	simulator.step(5.0)
	var car := simulator.get_snapshot().cars[0]

	assert(car.lap_count == 1)
	assert(abs(car.last_lap_time - 5.0) < 0.0001)
	assert(abs(car.lap_start_time - 5.0) < 0.0001)


func test_best_lap_uses_min_and_starts_as_inf() -> void:
	var simulator := _build_simulator([_car("car_1", 50.0)], 100.0)
	assert(simulator.is_ready())

	var initial_car := simulator.get_snapshot().cars[0]
	assert(is_inf(initial_car.best_lap_time))

	simulator.step(2.0) # lap 1 = 2.0s
	# Intentional internal change to validate best-lap min behavior under varied lap times.
	simulator._cars[0].speed_units_per_sec = 40.0
	simulator.step(2.5) # lap 2 = 2.5s (best should stay 2.0)
	simulator._cars[0].speed_units_per_sec = 80.0
	simulator.step(1.25) # lap 3 = 1.25s (best should update)

	var car := simulator.get_snapshot().cars[0]
	assert(car.lap_count == 3)
	assert(abs(car.best_lap_time - 1.25) < 0.0001)
	assert(abs(car.last_lap_time - 1.25) < 0.0001)


func test_high_dt_multi_crossing_counts_each_lap_once() -> void:
	var simulator := _build_simulator([_car("car_1", 60.0)], 100.0)
	assert(simulator.is_ready())

	simulator.step(5.0) # 300 units => 3 crossings.
	var car := simulator.get_snapshot().cars[0]

	assert(car.lap_count == 3)
	assert(abs(car.last_lap_time - (100.0 / 60.0)) < 0.0001)
	assert(abs(car.best_lap_time - (100.0 / 60.0)) < 0.0001)


func test_reset_restores_initial_runtime_state() -> void:
	var simulator := _build_simulator([_car("car_1", 50.0)], 100.0)
	assert(simulator.is_ready())

	simulator.step(4.0)
	simulator.reset()

	var car := simulator.get_snapshot().cars[0]
	assert(car.lap_count == 0)
	assert(car.distance_along_track == 0.0)
	assert(car.last_lap_time == -1.0)
	assert(is_inf(car.best_lap_time))
	assert(simulator.get_snapshot().race_time == 0.0)


func test_validation_rejects_zero_or_negative_values() -> void:
	var invalid_track_sim := RaceSimulator.new()
	var track_config := RaceTypes.RaceConfig.new()
	track_config.cars.append(_car("car_1", 10.0))
	var bad_runtime := RaceTypes.RaceRuntimeParams.new()
	bad_runtime.track_length = 0.0
	invalid_track_sim.initialize(track_config, bad_runtime)
	assert(not invalid_track_sim.is_ready())

	var invalid_speed_sim := RaceSimulator.new()
	var speed_config := RaceTypes.RaceConfig.new()
	speed_config.cars.append(_car("car_1", 0.0))
	var runtime := RaceTypes.RaceRuntimeParams.new()
	runtime.track_length = 100.0
	invalid_speed_sim.initialize(speed_config, runtime)
	assert(not invalid_speed_sim.is_ready())


func _build_simulator(car_configs: Array, track_length: float) -> RaceSimulator:
	var config := RaceTypes.RaceConfig.new()
	for car_config in car_configs:
		config.cars.append(car_config)
	config.count_first_lap_from_start = true
	config.seed = 0
	config.default_time_scale = 1.0

	var runtime := RaceTypes.RaceRuntimeParams.new()
	runtime.track_length = track_length

	var simulator := RaceSimulator.new()
	simulator.initialize(config, runtime)
	return simulator


func _car(id_value: String, speed_value: float) -> RaceTypes.CarConfig:
	var car := RaceTypes.CarConfig.new()
	car.id = id_value
	car.display_name = id_value
	car.speed_units_per_sec = speed_value
	return car
