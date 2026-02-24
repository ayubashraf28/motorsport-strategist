extends GdUnitTestSuite

const RaceTypes = preload("res://sim/src/race_types.gd")
const RaceSimulator = preload("res://sim/src/race_simulator.gd")


func test_single_car_lap_time_matches_track_length_over_speed() -> void:
	var simulator := _build_simulator([_car("car_1", 50.0)], 200.0)
	assert(simulator.is_ready())

	simulator.step(4.0)
	var snapshot := simulator.get_snapshot()
	var car: RaceTypes.CarState = snapshot.cars[0]

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
	var car: RaceTypes.CarState = simulator.get_snapshot().cars[0]

	assert(car.lap_count == 1)
	assert(abs(car.last_lap_time - 5.0) < 0.0001)
	assert(abs(car.lap_start_time - 5.0) < 0.0001)


func test_best_lap_uses_min_and_starts_as_inf() -> void:
	var simulator := _build_simulator([_car("car_1", 50.0)], 100.0)
	assert(simulator.is_ready())

	var initial_car: RaceTypes.CarState = simulator.get_snapshot().cars[0]
	assert(is_inf(initial_car.best_lap_time))

	simulator.step(2.0) # lap 1 = 2.0s
	# Intentional internal change to validate best-lap min behavior under varied lap times.
	simulator._cars[0].base_speed_units_per_sec = 40.0
	simulator.step(2.5) # lap 2 = 2.5s (best should stay 2.0)
	simulator._cars[0].base_speed_units_per_sec = 80.0
	simulator.step(1.25) # lap 3 = 1.25s (best should update)

	var car: RaceTypes.CarState = simulator.get_snapshot().cars[0]
	assert(car.lap_count == 3)
	assert(abs(car.best_lap_time - 1.25) < 0.0001)
	assert(abs(car.last_lap_time - 1.25) < 0.0001)


func test_high_dt_multi_crossing_counts_each_lap_once() -> void:
	var simulator := _build_simulator([_car("car_1", 60.0)], 100.0)
	assert(simulator.is_ready())

	simulator.step(5.0) # 300 units => 3 crossings.
	var car: RaceTypes.CarState = simulator.get_snapshot().cars[0]

	assert(car.lap_count == 3)
	assert(abs(car.last_lap_time - (100.0 / 60.0)) < 0.0001)
	assert(abs(car.best_lap_time - (100.0 / 60.0)) < 0.0001)


func test_faster_base_pace_car_stays_ahead() -> void:
	var simulator := _build_simulator([
		_car("car_fast", 80.0),
		_car("car_slow", 60.0)
	], 100.0)
	assert(simulator.is_ready())

	simulator.step(1.0)
	var snapshot := simulator.get_snapshot()
	var fast_car: RaceTypes.CarState = snapshot.cars[0]
	var slow_car: RaceTypes.CarState = snapshot.cars[1]
	assert(fast_car.distance_along_track > slow_car.distance_along_track)


func test_reset_restores_initial_runtime_state() -> void:
	var simulator := _build_simulator([_car("car_1", 50.0)], 100.0)
	assert(simulator.is_ready())

	simulator.step(4.0)
	simulator.reset()

	var car: RaceTypes.CarState = simulator.get_snapshot().cars[0]
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
	speed_config.track = _constant_track_profile(100.0)
	var runtime := RaceTypes.RaceRuntimeParams.new()
	runtime.track_length = 100.0
	invalid_speed_sim.initialize(speed_config, runtime)
	assert(not invalid_speed_sim.is_ready())

	var invalid_track_profile_sim := RaceSimulator.new()
	var invalid_profile_config := RaceTypes.RaceConfig.new()
	invalid_profile_config.cars.append(_car("car_1", 20.0))
	invalid_profile_config.track = RaceTypes.PaceProfileConfig.new()
	var runtime_profile := RaceTypes.RaceRuntimeParams.new()
	runtime_profile.track_length = 100.0
	invalid_track_profile_sim.initialize(invalid_profile_config, runtime_profile)
	assert(not invalid_track_profile_sim.is_ready())


func test_v1_1_straight_track_uses_v_ref_scaled_speed() -> void:
	var simulator := _build_simulator_v1_1([_car_v1_1("car_1", 83.0)], _straight_geometry(300.0, 4.0), 83.0)
	assert(simulator.is_ready())

	simulator.step(1.0)
	var car: RaceTypes.CarState = simulator.get_snapshot().cars[0]
	assert(abs(car.effective_speed_units_per_sec - 83.0) < 0.0001)


func test_v1_1_reset_restores_initial_state() -> void:
	var simulator := _build_simulator_v1_1([_car_v1_1("car_1", 83.0)], _straight_geometry(300.0, 4.0), 83.0)
	assert(simulator.is_ready())

	simulator.step(2.0)
	simulator.reset()
	var car: RaceTypes.CarState = simulator.get_snapshot().cars[0]
	assert(car.lap_count == 0)
	assert(car.distance_along_track == 0.0)
	assert(car.last_lap_time == -1.0)
	assert(is_inf(car.best_lap_time))
	assert(simulator.get_snapshot().race_time == 0.0)


func test_v1_1_null_geometry_is_rejected() -> void:
	var config := RaceTypes.RaceConfig.new()
	config.schema_version = "1.1"
	config.track = _speed_track_config(83.0)
	config.cars.append(_car_v1_1("car_1", 83.0))

	var runtime := RaceTypes.RaceRuntimeParams.new()
	runtime.track_length = 300.0
	runtime.geometry = null

	var simulator := RaceSimulator.new()
	simulator.initialize(config, runtime)
	assert(not simulator.is_ready())


func _build_simulator(car_configs: Array, track_length: float) -> RaceSimulator:
	var config := RaceTypes.RaceConfig.new()
	config.track = _constant_track_profile(track_length)
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


func _build_simulator_v1_1(
	car_configs: Array,
	geometry: RaceTypes.TrackGeometryData,
	v_top_speed: float
) -> RaceSimulator:
	var config := RaceTypes.RaceConfig.new()
	config.schema_version = "1.1"
	config.track = _speed_track_config(v_top_speed)
	for car_config in car_configs:
		config.cars.append(car_config)
	config.count_first_lap_from_start = true
	config.seed = 0
	config.default_time_scale = 1.0

	var runtime := RaceTypes.RaceRuntimeParams.new()
	runtime.track_length = geometry.track_length
	runtime.geometry = geometry

	var simulator := RaceSimulator.new()
	simulator.initialize(config, runtime)
	return simulator


func _car(id_value: String, speed_value: float) -> RaceTypes.CarConfig:
	var car := RaceTypes.CarConfig.new()
	car.id = id_value
	car.display_name = id_value
	car.base_speed_units_per_sec = speed_value
	car.v_ref = speed_value
	return car


func _car_v1_1(id_value: String, v_ref_value: float) -> RaceTypes.CarConfig:
	var car := RaceTypes.CarConfig.new()
	car.id = id_value
	car.display_name = id_value
	car.v_ref = v_ref_value
	car.base_speed_units_per_sec = v_ref_value
	return car


func _constant_track_profile(track_length: float) -> RaceTypes.PaceProfileConfig:
	var profile := RaceTypes.PaceProfileConfig.new()
	profile.blend_distance = 0.0
	var segment := RaceTypes.PaceSegmentConfig.new()
	segment.start_distance = 0.0
	segment.end_distance = track_length
	segment.multiplier = 1.0
	profile.pace_segments.append(segment)
	return profile


func _speed_track_config(v_top_speed: float) -> RaceTypes.SpeedProfileConfig:
	var speed_track := RaceTypes.SpeedProfileConfig.new()
	speed_track.geometry_asset_path = "unused-in-tests"
	speed_track.physics = RaceTypes.PhysicsVehicleConfig.new()
	speed_track.physics.a_lat_max = 25.0
	speed_track.physics.a_long_accel = 8.0
	speed_track.physics.a_long_brake = 20.0
	speed_track.physics.v_top_speed = v_top_speed
	speed_track.physics.curvature_epsilon = 0.0001
	return speed_track


func _straight_geometry(track_length: float, ds: float) -> RaceTypes.TrackGeometryData:
	var sample_count: int = int(round(track_length / ds))
	var geometry := RaceTypes.TrackGeometryData.new()
	geometry.sample_count = sample_count
	geometry.ds = ds
	geometry.track_length = float(sample_count) * ds
	geometry.curvatures = PackedFloat64Array()
	geometry.curvatures.resize(sample_count)
	for i in range(sample_count):
		geometry.curvatures[i] = 0.0
	return geometry
