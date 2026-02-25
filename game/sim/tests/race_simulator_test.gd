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


func test_pit_stop_resets_stint_state_and_changes_compound() -> void:
	var simulator := _build_simulator_v3(_car_v3("car_1", 50.0, "soft", 90.0))
	assert(simulator.is_ready())

	simulator.step(2.05)
	simulator.request_pit_stop("car_1", "hard", -1.0)

	for _i in range(800):
		simulator.step(0.05)
		if simulator.get_snapshot().cars[0].pit_stops_completed >= 1:
			break

	var snapshot_after_pit: RaceTypes.RaceSnapshot = simulator.get_snapshot()
	var car_after_pit: RaceTypes.CarState = snapshot_after_pit.cars[0]
	assert(car_after_pit.pit_stops_completed == 1)
	assert(car_after_pit.current_compound == "hard")
	assert(car_after_pit.stint_number == 2)
	assert(car_after_pit.stint_lap_count == 0)

	simulator.step(2.1)
	var snapshot_after_next_lap: RaceTypes.RaceSnapshot = simulator.get_snapshot()
	assert(snapshot_after_next_lap.cars[0].stint_lap_count >= 1)


func test_fuel_consumes_per_lap_and_multiplier_increases() -> void:
	var simulator := _build_simulator_v3(_car_v3("car_1", 50.0, "soft", 100.0))
	assert(simulator.is_ready())

	var start_car: RaceTypes.CarState = simulator.get_snapshot().cars[0]
	var start_fuel: float = start_car.fuel_kg
	var start_multiplier: float = start_car.fuel_multiplier

	# Fuel is consumed on lap crossing, so wait for lap completion instead of
	# relying on a fixed wall-clock step that can drift with pace multipliers.
	_advance_until_lap_count(simulator, 1, 0.05, 400)
	var car_after_lap: RaceTypes.CarState = simulator.get_snapshot().cars[0]
	assert(car_after_lap.fuel_kg < start_fuel)
	assert(car_after_lap.fuel_multiplier > start_multiplier)


func test_pit_request_ignored_when_pit_disabled() -> void:
	var config := RaceTypes.RaceConfig.new()
	config.track = _constant_track_profile(100.0)
	config.compounds = _v3_compounds()
	config.cars.append(_car_v3("car_1", 50.0, "soft", 100.0))

	var runtime := RaceTypes.RaceRuntimeParams.new()
	runtime.track_length = 100.0

	var simulator := RaceSimulator.new()
	simulator.initialize(config, runtime)
	assert(simulator.is_ready())

	simulator.step(0.1)
	simulator.request_pit_stop("car_1", "hard", -1.0)
	assert(not simulator.has_pending_pit_request("car_1"))


func test_lap_not_counted_when_pit_entry_is_before_finish_line() -> void:
	var config := RaceTypes.RaceConfig.new()
	config.track = _constant_track_profile(100.0)
	config.compounds = _v3_compounds()
	config.fuel = _v3_fuel()
	config.pit = _v3_pit()
	config.pit.min_stop_lap = 0
	config.cars.append(_car_v3("car_1", 50.0, "soft", 100.0))

	var runtime := RaceTypes.RaceRuntimeParams.new()
	runtime.track_length = 100.0

	var simulator := RaceSimulator.new()
	simulator.initialize(config, runtime)
	assert(simulator.is_ready())

	simulator.step(0.05)
	simulator.request_pit_stop("car_1", "hard", -1.0)
	simulator.step(1.9)

	var car: RaceTypes.CarState = simulator.get_snapshot().cars[0]
	assert(car.is_in_pit)
	assert(car.lap_count == 0)


func test_compound_ordering_and_crossover_window() -> void:
	var config := RaceTypes.RaceConfig.new()
	config.schema_version = "3.0"
	config.track = _constant_track_profile(100.0)
	config.compounds = _v3_compounds()
	var overtaking := RaceTypes.OvertakingConfig.new()
	overtaking.enabled = false
	config.overtaking = overtaking
	config.cars.append(_car_v3("soft_car", 50.0, "soft", -1.0))
	config.cars.append(_car_v3("medium_car", 50.0, "medium", -1.0))
	config.cars.append(_car_v3("hard_car", 50.0, "hard", -1.0))

	var runtime := RaceTypes.RaceRuntimeParams.new()
	runtime.track_length = 100.0

	var simulator := RaceSimulator.new()
	simulator.initialize(config, runtime)
	assert(simulator.is_ready())

	var lap_times: Dictionary = _collect_lap_times(simulator, 7, 0.02, 20000)
	var soft_laps: Array = lap_times.get("soft_car", [])
	var medium_laps: Array = lap_times.get("medium_car", [])
	var hard_laps: Array = lap_times.get("hard_car", [])

	assert(soft_laps.size() >= 7)
	assert(medium_laps.size() >= 7)
	assert(hard_laps.size() >= 7)
	assert(float(soft_laps[0]) < float(medium_laps[0]))
	assert(float(medium_laps[0]) < float(hard_laps[0]))
	assert(float(soft_laps[1]) < float(medium_laps[1]))
	assert(float(soft_laps[2]) < float(medium_laps[2]))

	var crossover_lap: int = -1
	for lap_index in range(soft_laps.size()):
		if float(soft_laps[lap_index]) > float(medium_laps[lap_index]):
			crossover_lap = lap_index + 1
			break
	assert(crossover_lap >= 5 and crossover_lap <= 7)


func test_normalized_pace_stays_consistent_across_track_segments() -> void:
	var config := RaceTypes.RaceConfig.new()
	config.track = _two_segment_track_profile(100.0, 50.0, 1.0, 0.5)
	var overtaking := RaceTypes.OvertakingConfig.new()
	overtaking.enabled = false
	config.overtaking = overtaking

	var degradation := RaceTypes.DegradationConfig.new()
	degradation.warmup_laps = 0.0
	degradation.peak_multiplier = 1.0
	degradation.degradation_rate = 0.0
	degradation.min_multiplier = 0.7
	config.degradation = degradation

	config.cars.append(_car("car_fast_segment", 50.0))
	config.cars.append(_car("car_slow_segment", 50.0))

	var runtime := RaceTypes.RaceRuntimeParams.new()
	runtime.track_length = 100.0

	var simulator := RaceSimulator.new()
	simulator.initialize(config, runtime)
	assert(simulator.is_ready())

	simulator._cars[0].distance_along_track = 10.0
	simulator._cars[1].distance_along_track = 60.0
	simulator.step(0.05)

	var snapshot: RaceTypes.RaceSnapshot = simulator.get_snapshot()
	var fast_segment_car: RaceTypes.CarState = _find_car(snapshot.cars, "car_fast_segment")
	var slow_segment_car: RaceTypes.CarState = _find_car(snapshot.cars, "car_slow_segment")
	assert(fast_segment_car != null)
	assert(slow_segment_car != null)

	assert(abs(fast_segment_car.effective_speed_units_per_sec - slow_segment_car.effective_speed_units_per_sec) > 5.0)
	var fast_normalized: float = fast_segment_car.effective_speed_units_per_sec / maxf(fast_segment_car.reference_speed_units_per_sec, 0.001)
	var slow_normalized: float = slow_segment_car.effective_speed_units_per_sec / maxf(slow_segment_car.reference_speed_units_per_sec, 0.001)
	assert(abs(fast_normalized - slow_normalized) < 0.001)


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


func _build_simulator_v3(car_config: RaceTypes.CarConfig) -> RaceSimulator:
	var config := RaceTypes.RaceConfig.new()
	config.schema_version = "3.0"
	config.track = _constant_track_profile(100.0)
	config.compounds = _v3_compounds()
	config.fuel = _v3_fuel()
	config.pit = _v3_pit()
	config.cars.append(car_config)
	config.count_first_lap_from_start = true
	config.seed = 0
	config.default_time_scale = 1.0

	var runtime := RaceTypes.RaceRuntimeParams.new()
	runtime.track_length = 100.0

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


func _car_v3(
	id_value: String,
	speed_value: float,
	starting_compound: String,
	starting_fuel_kg: float
) -> RaceTypes.CarConfig:
	var car := RaceTypes.CarConfig.new()
	car.id = id_value
	car.display_name = id_value
	car.base_speed_units_per_sec = speed_value
	car.v_ref = speed_value
	car.starting_compound = starting_compound
	car.starting_fuel_kg = starting_fuel_kg
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


func _two_segment_track_profile(
	track_length: float,
	split_distance: float,
	first_multiplier: float,
	second_multiplier: float
) -> RaceTypes.PaceProfileConfig:
	var profile := RaceTypes.PaceProfileConfig.new()
	profile.blend_distance = 0.0

	var first := RaceTypes.PaceSegmentConfig.new()
	first.start_distance = 0.0
	first.end_distance = split_distance
	first.multiplier = first_multiplier
	profile.pace_segments.append(first)

	var second := RaceTypes.PaceSegmentConfig.new()
	second.start_distance = split_distance
	second.end_distance = track_length
	second.multiplier = second_multiplier
	profile.pace_segments.append(second)
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


func _v3_compounds() -> Array[RaceTypes.TyreCompoundConfig]:
	var soft := RaceTypes.TyreCompoundConfig.new()
	soft.name = "soft"
	soft.degradation = RaceTypes.DegradationConfig.new()
	soft.degradation.warmup_laps = 0.3
	soft.degradation.peak_multiplier = 1.0
	soft.degradation.degradation_rate = 0.025
	soft.degradation.min_multiplier = 0.72
	soft.degradation.optimal_threshold = 0.75
	soft.degradation.cliff_threshold = 0.30
	soft.degradation.cliff_multiplier = 2.5

	var medium := RaceTypes.TyreCompoundConfig.new()
	medium.name = "medium"
	medium.degradation = RaceTypes.DegradationConfig.new()
	medium.degradation.warmup_laps = 0.5
	medium.degradation.peak_multiplier = 0.988
	medium.degradation.degradation_rate = 0.02
	medium.degradation.min_multiplier = 0.75
	medium.degradation.optimal_threshold = 0.75
	medium.degradation.cliff_threshold = 0.30
	medium.degradation.cliff_multiplier = 2.5

	var hard := RaceTypes.TyreCompoundConfig.new()
	hard.name = "hard"
	hard.degradation = RaceTypes.DegradationConfig.new()
	hard.degradation.warmup_laps = 0.8
	hard.degradation.peak_multiplier = 0.976
	hard.degradation.degradation_rate = 0.012
	hard.degradation.min_multiplier = 0.80
	hard.degradation.optimal_threshold = 0.75
	hard.degradation.cliff_threshold = 0.30
	hard.degradation.cliff_multiplier = 2.5

	return [soft, medium, hard]


func _v3_fuel() -> RaceTypes.FuelConfig:
	var fuel := RaceTypes.FuelConfig.new()
	fuel.enabled = true
	fuel.max_capacity_kg = 100.0
	fuel.consumption_per_lap_kg = 10.0
	fuel.weight_penalty_factor = 0.1
	fuel.fuel_empty_penalty = 0.5
	fuel.refuel_rate_kg_per_sec = 5.0
	return fuel


func _v3_pit() -> RaceTypes.PitConfig:
	var pit := RaceTypes.PitConfig.new()
	pit.enabled = true
	pit.pit_entry_distance = 75.0
	pit.pit_exit_distance = 10.0
	pit.pit_box_distance = 92.5
	pit.pit_lane_speed_limit = 20.0
	pit.base_pit_stop_duration = 1.0
	pit.pit_entry_duration = 0.2
	pit.pit_exit_duration = 0.2
	pit.min_stop_lap = 1
	pit.max_stops = 3
	return pit


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


func _collect_lap_times(
	simulator: RaceSimulator,
	target_laps: int,
	step_dt: float,
	max_steps: int
) -> Dictionary:
	var lap_times: Dictionary = {}
	var previous_laps: Dictionary = {}
	for raw_car in simulator.get_snapshot().cars:
		var car: RaceTypes.CarState = raw_car as RaceTypes.CarState
		if car == null:
			continue
		lap_times[car.id] = []
		previous_laps[car.id] = car.lap_count

	for _step in range(max_steps):
		simulator.step(step_dt)
		var snapshot: RaceTypes.RaceSnapshot = simulator.get_snapshot()
		var completed: bool = true
		for raw_car in snapshot.cars:
			var car: RaceTypes.CarState = raw_car as RaceTypes.CarState
			if car == null or not lap_times.has(car.id):
				continue
			if car.lap_count > int(previous_laps[car.id]):
				var history: Array = lap_times[car.id]
				history.append(car.last_lap_time)
				lap_times[car.id] = history
				previous_laps[car.id] = car.lap_count
			if (lap_times[car.id] as Array).size() < target_laps:
				completed = false
		if completed:
			return lap_times

	assert(false)
	return lap_times


func _find_car(cars: Array, car_id: String) -> RaceTypes.CarState:
	for raw_car in cars:
		var car: RaceTypes.CarState = raw_car as RaceTypes.CarState
		if car != null and car.id == car_id:
			return car
	return null
