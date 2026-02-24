extends GdUnitTestSuite

const RaceTypes = preload("res://sim/src/race_types.gd")
const RaceSimulator = preload("res://sim/src/race_simulator.gd")


func test_single_car_lap_time_matches_track_length_over_speed() -> void:
	var simulator := _build_simulator([_car("car_1", 50.0)], 200.0)
	assert(simulator.is_ready())

	# Use a value slightly above the theoretical lap boundary to avoid
	# exact-floating-point boundary sensitivity in CI environments.
	simulator.step(4.05)
	var snapshot := simulator.get_snapshot()
	var car: RaceTypes.CarState = snapshot.cars[0]

	assert(car.lap_count == 1)
	assert(abs(car.last_lap_time - 4.0) < 0.001)
	assert(abs(car.best_lap_time - 4.0) < 0.001)


func test_multi_car_timing_is_independent() -> void:
	var simulator := _build_simulator([
		_car("car_1", 25.0),
		_car("car_2", 50.0)
	], 100.0)
	assert(simulator.is_ready())

	simulator.step(4.05)
	var snapshot := simulator.get_snapshot()

	assert(snapshot.cars[0].lap_count == 1)
	assert(snapshot.cars[1].lap_count == 2)
	assert(snapshot.cars[0].id != snapshot.cars[1].id)


func test_first_lap_counted_from_race_start() -> void:
	var simulator := _build_simulator([_car("car_1", 20.0)], 100.0)
	assert(simulator.is_ready())

	simulator.step(5.05)
	var car: RaceTypes.CarState = simulator.get_snapshot().cars[0]

	assert(car.lap_count == 1)
	assert(abs(car.last_lap_time - 5.0) < 0.001)
	assert(abs(car.lap_start_time - 5.0) < 0.001)


func test_best_lap_uses_min_and_starts_as_inf() -> void:
	var simulator := _build_simulator([_car("car_1", 30.0)], 120.0)
	assert(simulator.is_ready())

	var initial_car: RaceTypes.CarState = simulator.get_snapshot().cars[0]
	assert(is_inf(initial_car.best_lap_time))

	# Intentional internal speed changes validate that best lap tracks the minimum
	# observed lap time even when stepping across non-boundary deltas.
	_advance_until_lap_count(simulator, 1, 0.05, 400)
	var lap_1: float = simulator.get_snapshot().cars[0].last_lap_time

	simulator._cars[0].base_speed_units_per_sec = 24.0
	_advance_until_lap_count(simulator, 2, 0.05, 400)
	var lap_2: float = simulator.get_snapshot().cars[0].last_lap_time

	simulator._cars[0].base_speed_units_per_sec = 80.0
	_advance_until_lap_count(simulator, 3, 0.05, 400)
	var lap_3: float = simulator.get_snapshot().cars[0].last_lap_time

	var car: RaceTypes.CarState = simulator.get_snapshot().cars[0]
	assert(car.lap_count == 3)
	assert(lap_1 > 0.0 and lap_2 > 0.0 and lap_3 > 0.0)
	assert(lap_3 < lap_1)
	assert(lap_1 < lap_2)
	assert(abs(car.best_lap_time - minf(lap_1, minf(lap_2, lap_3))) < 0.001)
	assert(abs(car.last_lap_time - lap_3) < 0.001)


func test_high_dt_multi_crossing_counts_each_lap_once() -> void:
	var simulator := _build_simulator([_car("car_1", 60.0)], 100.0)
	assert(simulator.is_ready())

	simulator.step(5.05) # 300 units => 3 crossings, with boundary margin.
	var car: RaceTypes.CarState = simulator.get_snapshot().cars[0]

	assert(car.lap_count == 3)
	assert(abs(car.last_lap_time - (100.0 / 60.0)) < 0.001)
	assert(abs(car.best_lap_time - (100.0 / 60.0)) < 0.001)


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


func test_race_ends_after_total_laps() -> void:
	var simulator := _build_simulator_with_total_laps([
		_car("car_1", 50.0),
		_car("car_2", 50.0)
	], 100.0, 1)
	assert(simulator.is_ready())

	for _i in range(200):
		simulator.step(0.05)
		if simulator.get_snapshot().race_state == RaceTypes.RaceState.FINISHED:
			break

	var snapshot := simulator.get_snapshot()
	assert(snapshot.race_state == RaceTypes.RaceState.FINISHED)
	assert(snapshot.finish_order.size() == 2)


func test_finished_car_speed_is_zero() -> void:
	var simulator := _build_simulator_with_total_laps([_car("car_1", 50.0)], 100.0, 1)
	assert(simulator.is_ready())

	simulator.step(2.05)
	var car: RaceTypes.CarState = simulator.get_snapshot().cars[0]
	assert(car.is_finished)
	assert(car.effective_speed_units_per_sec == 0.0)


func test_step_is_noop_after_finished() -> void:
	var simulator := _build_simulator_with_total_laps([_car("car_1", 50.0)], 100.0, 1)
	assert(simulator.is_ready())

	simulator.step(2.05)
	var finished_snapshot: RaceTypes.RaceSnapshot = simulator.get_snapshot()
	assert(finished_snapshot.race_state == RaceTypes.RaceState.FINISHED)

	var time_before: float = finished_snapshot.race_time
	simulator.step(5.0)
	var time_after: float = simulator.get_snapshot().race_time
	assert(abs(time_after - time_before) < 0.0000001)


func test_two_phase_step_produces_same_results_when_overtaking_disabled() -> void:
	var simulator_without_overtaking := _build_simulator_with_overtaking([
		_car("car_1", 40.0),
		_car("car_2", 35.0)
	], 200.0, null)
	var disabled_overtaking_config := RaceTypes.OvertakingConfig.new()
	disabled_overtaking_config.enabled = false
	var simulator_with_disabled_overtaking := _build_simulator_with_overtaking([
		_car("car_1", 40.0),
		_car("car_2", 35.0)
	], 200.0, disabled_overtaking_config)

	assert(simulator_without_overtaking.is_ready())
	assert(simulator_with_disabled_overtaking.is_ready())

	for _i in range(40):
		simulator_without_overtaking.step(0.05)
		simulator_with_disabled_overtaking.step(0.05)

	var snapshot_a: RaceTypes.RaceSnapshot = simulator_without_overtaking.get_snapshot()
	var snapshot_b: RaceTypes.RaceSnapshot = simulator_with_disabled_overtaking.get_snapshot()
	assert(abs(snapshot_a.cars[0].total_distance - snapshot_b.cars[0].total_distance) < 0.000001)
	assert(abs(snapshot_a.cars[1].total_distance - snapshot_b.cars[1].total_distance) < 0.000001)
	assert(snapshot_a.cars[0].lap_count == snapshot_b.cars[0].lap_count)
	assert(snapshot_a.cars[1].lap_count == snapshot_b.cars[1].lap_count)


func test_held_up_car_does_not_phase_through() -> void:
	var overtaking := RaceTypes.OvertakingConfig.new()
	overtaking.enabled = true
	overtaking.proximity_distance = 10.0
	overtaking.overtake_speed_threshold = 10.0
	overtaking.held_up_speed_buffer = 0.0
	overtaking.cooldown_seconds = 3.0

	var simulator := _build_simulator_with_overtaking([
		_car("ahead", 50.0),
		_car("behind", 55.0)
	], 200.0, overtaking)
	assert(simulator.is_ready())

	# Seed a close gap so the behind car is immediately in interaction range.
	simulator._cars[0].distance_along_track = 40.0
	simulator._cars[1].distance_along_track = 35.0
	simulator._cars[0].total_distance = 40.0
	simulator._cars[1].total_distance = 35.0

	simulator.step(1.0)
	var snapshot: RaceTypes.RaceSnapshot = simulator.get_snapshot()
	var ahead: RaceTypes.CarState = snapshot.cars[0]
	var behind: RaceTypes.CarState = snapshot.cars[1]
	assert(behind.total_distance <= ahead.total_distance)
	assert(behind.is_held_up)


func test_per_car_config_overrides_global_degradation() -> void:
	var global_degradation := RaceTypes.DegradationConfig.new()
	global_degradation.warmup_laps = 0.0
	global_degradation.peak_multiplier = 1.0
	global_degradation.degradation_rate = 0.20
	global_degradation.min_multiplier = 0.50

	var car_override := RaceTypes.DegradationConfig.new()
	car_override.warmup_laps = 0.0
	car_override.peak_multiplier = 1.0
	car_override.degradation_rate = 0.0
	car_override.min_multiplier = 0.80

	var car_1 := _car("car_1", 40.0)
	car_1.degradation = car_override
	var car_2 := _car("car_2", 40.0)

	var simulator := _build_simulator_with_degradation([car_1, car_2], 100.0, global_degradation)
	assert(simulator.is_ready())
	simulator.step(6.0)

	var snapshot: RaceTypes.RaceSnapshot = simulator.get_snapshot()
	assert(snapshot.cars[0].degradation_multiplier > snapshot.cars[1].degradation_multiplier)


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


func _build_simulator_with_total_laps(
	car_configs: Array,
	track_length: float,
	total_laps: int
) -> RaceSimulator:
	var config := RaceTypes.RaceConfig.new()
	config.track = _constant_track_profile(track_length)
	config.total_laps = total_laps
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


func _build_simulator_with_overtaking(
	car_configs: Array,
	track_length: float,
	overtaking_config: RaceTypes.OvertakingConfig
) -> RaceSimulator:
	var config := RaceTypes.RaceConfig.new()
	config.track = _constant_track_profile(track_length)
	config.overtaking = overtaking_config.clone() if overtaking_config != null else null
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


func _build_simulator_with_degradation(
	car_configs: Array,
	track_length: float,
	degradation_config: RaceTypes.DegradationConfig
) -> RaceSimulator:
	var config := RaceTypes.RaceConfig.new()
	config.track = _constant_track_profile(track_length)
	config.degradation = degradation_config.clone() if degradation_config != null else null
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


func _advance_until_lap_count(
	simulator: RaceSimulator,
	target_lap_count: int,
	step_dt: float,
	max_steps: int
) -> void:
	for _step in range(max_steps):
		if simulator.get_snapshot().cars[0].lap_count >= target_lap_count:
			return
		simulator.step(step_dt)
	assert(false)
