extends GdUnitTestSuite

const RaceTypes = preload("res://sim/src/race_types.gd")
const RaceSimulator = preload("res://sim/src/race_simulator.gd")
const FixedStepRunner = preload("res://sim/src/fixed_step_runner.gd")


class StepCounter extends RefCounted:
	var count: int = 0

	func on_step(_dt: float) -> void:
		count += 1


func test_fixed_step_runner_caps_step_iterations() -> void:
	var runner := FixedStepRunner.new(0.1, 2)
	var counter := StepCounter.new()

	var result := runner.advance(1.0, 1.0, Callable(counter, "on_step"))
	assert(counter.count == 2)
	assert(result["capped"] == true)
	assert(result["steps"] == 2)


func test_identical_input_dt_sequence_produces_identical_snapshots() -> void:
	var simulator_a := _build_simulator("car_1", 35.0, 140.0)
	var simulator_b := _build_simulator("car_1", 35.0, 140.0)

	var runner_a := FixedStepRunner.new(1.0 / 120.0, 16)
	var runner_b := FixedStepRunner.new(1.0 / 120.0, 16)

	var frame_deltas := [0.016, 0.033, 0.041, 0.008, 0.050, 0.016, 0.027]
	for frame_delta in frame_deltas:
		runner_a.advance(frame_delta, 2.0, Callable(simulator_a, "step"))
		runner_b.advance(frame_delta, 2.0, Callable(simulator_b, "step"))

	var snapshot_a := simulator_a.get_snapshot()
	var snapshot_b := simulator_b.get_snapshot()

	assert(abs(snapshot_a.race_time - snapshot_b.race_time) < 0.0000001)
	assert(snapshot_a.cars.size() == snapshot_b.cars.size())
	assert(snapshot_a.cars[0].lap_count == snapshot_b.cars[0].lap_count)
	assert(abs(snapshot_a.cars[0].distance_along_track - snapshot_b.cars[0].distance_along_track) < 0.0000001)
	assert(abs(snapshot_a.cars[0].best_lap_time - snapshot_b.cars[0].best_lap_time) < 0.0000001)


func test_identical_input_with_pace_profile_is_deterministic() -> void:
	var simulator_a := _build_simulator_with_profile("car_1", 35.0, 140.0)
	var simulator_b := _build_simulator_with_profile("car_1", 35.0, 140.0)

	var runner_a := FixedStepRunner.new(1.0 / 120.0, 16)
	var runner_b := FixedStepRunner.new(1.0 / 120.0, 16)

	var frame_deltas := [0.016, 0.020, 0.041, 0.011, 0.050, 0.015, 0.019]
	for frame_delta in frame_deltas:
		runner_a.advance(frame_delta, 2.0, Callable(simulator_a, "step"))
		runner_b.advance(frame_delta, 2.0, Callable(simulator_b, "step"))

	var snapshot_a := simulator_a.get_snapshot()
	var snapshot_b := simulator_b.get_snapshot()
	assert(abs(snapshot_a.race_time - snapshot_b.race_time) < 0.0000001)
	assert(snapshot_a.cars[0].lap_count == snapshot_b.cars[0].lap_count)
	assert(abs(snapshot_a.cars[0].distance_along_track - snapshot_b.cars[0].distance_along_track) < 0.0000001)
	assert(abs(snapshot_a.cars[0].effective_speed_units_per_sec - snapshot_b.cars[0].effective_speed_units_per_sec) < 0.0000001)


func _build_simulator(car_id: String, speed: float, track_length: float) -> RaceSimulator:
	var car := RaceTypes.CarConfig.new()
	car.id = car_id
	car.display_name = car_id
	car.base_speed_units_per_sec = speed

	var config := RaceTypes.RaceConfig.new()
	config.track = _constant_track_profile(track_length)
	config.cars.append(car)

	var runtime := RaceTypes.RaceRuntimeParams.new()
	runtime.track_length = track_length

	var simulator := RaceSimulator.new()
	simulator.initialize(config, runtime)
	return simulator


func _build_simulator_with_profile(car_id: String, speed: float, track_length: float) -> RaceSimulator:
	var car := RaceTypes.CarConfig.new()
	car.id = car_id
	car.display_name = car_id
	car.base_speed_units_per_sec = speed

	var config := RaceTypes.RaceConfig.new()
	config.track = _paced_track_profile(track_length)
	config.cars.append(car)

	var runtime := RaceTypes.RaceRuntimeParams.new()
	runtime.track_length = track_length

	var simulator := RaceSimulator.new()
	simulator.initialize(config, runtime)
	return simulator


func _constant_track_profile(track_length: float) -> RaceTypes.PaceProfileConfig:
	var profile := RaceTypes.PaceProfileConfig.new()
	profile.blend_distance = 0.0
	var segment := RaceTypes.PaceSegmentConfig.new()
	segment.start_distance = 0.0
	segment.end_distance = track_length
	segment.multiplier = 1.0
	profile.pace_segments.append(segment)
	return profile


func _paced_track_profile(track_length: float) -> RaceTypes.PaceProfileConfig:
	var profile := RaceTypes.PaceProfileConfig.new()
	profile.blend_distance = 20.0

	var segment_a := RaceTypes.PaceSegmentConfig.new()
	segment_a.start_distance = 0.0
	segment_a.end_distance = track_length * 0.5
	segment_a.multiplier = 1.0
	profile.pace_segments.append(segment_a)

	var segment_b := RaceTypes.PaceSegmentConfig.new()
	segment_b.start_distance = track_length * 0.5
	segment_b.end_distance = track_length
	segment_b.multiplier = 0.8
	profile.pace_segments.append(segment_b)

	return profile
