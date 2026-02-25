extends GdUnitTestSuite

const RaceTypes = preload("res://sim/src/race_types.gd")
const FuelModel = preload("res://sim/src/fuel_model.gd")
const RaceSimulator = preload("res://sim/src/race_simulator.gd")


func test_null_config_returns_1() -> void:
	assert(FuelModel.compute_multiplier(50.0, null) == 1.0)


func test_full_tank_penalty() -> void:
	var config := _fuel_config(100.0, 2.0, 0.05, 0.5, 2.0)
	assert(abs(FuelModel.compute_multiplier(100.0, config) - 0.95) < 0.000001)


func test_empty_tank_no_penalty_when_empty_penalty_is_one() -> void:
	var config := _fuel_config(100.0, 2.0, 0.05, 1.0, 2.0)
	assert(abs(FuelModel.compute_multiplier(0.0, config) - 1.0) < 0.000001)


func test_half_tank_intermediate() -> void:
	var config := _fuel_config(100.0, 2.0, 0.05, 0.5, 2.0)
	assert(abs(FuelModel.compute_multiplier(50.0, config) - 0.975) < 0.000001)


func test_fuel_empty_penalty_applied() -> void:
	var config := _fuel_config(100.0, 2.0, 0.05, 0.5, 2.0)
	assert(abs(FuelModel.compute_multiplier(0.0, config) - 0.5) < 0.000001)


func test_consume_reduces_fuel() -> void:
	assert(abs(FuelModel.consume_fuel(50.0, 2.0) - 48.0) < 0.000001)


func test_consume_floors_at_zero() -> void:
	assert(FuelModel.consume_fuel(1.0, 3.0) == 0.0)


func test_refuel_adds_fuel() -> void:
	assert(abs(FuelModel.refuel(10.0, 5.0, 100.0) - 15.0) < 0.000001)


func test_refuel_caps_at_max() -> void:
	assert(abs(FuelModel.refuel(95.0, 10.0, 100.0) - 100.0) < 0.000001)


func test_refuel_time_calculation() -> void:
	assert(abs(FuelModel.compute_refuel_time(50.0, 70.0, 2.0) - 10.0) < 0.000001)


func test_validate_rejects_negative_capacity() -> void:
	var config := _fuel_config(-1.0, 2.0, 0.05, 0.5, 2.0)
	assert(FuelModel.validate_config(config).size() > 0)


func test_validate_rejects_penalty_over_1() -> void:
	var config := _fuel_config(100.0, 2.0, 1.2, 0.5, 2.0)
	assert(FuelModel.validate_config(config).size() > 0)


func test_starting_fuel_respects_config() -> void:
	var simulator := _build_simulator_with_fuel(45.0)
	assert(simulator.is_ready())
	var car: RaceTypes.CarState = simulator.get_snapshot().cars[0]
	assert(abs(car.fuel_kg - 45.0) < 0.000001)


func test_default_starting_fuel_is_max() -> void:
	var simulator := _build_simulator_with_fuel(-1.0)
	assert(simulator.is_ready())
	var car: RaceTypes.CarState = simulator.get_snapshot().cars[0]
	assert(abs(car.fuel_kg - 110.0) < 0.000001)


func _fuel_config(
	max_capacity: float,
	consumption: float,
	weight_penalty: float,
	empty_penalty: float,
	refuel_rate: float
) -> RaceTypes.FuelConfig:
	var config := RaceTypes.FuelConfig.new()
	config.enabled = true
	config.max_capacity_kg = max_capacity
	config.consumption_per_lap_kg = consumption
	config.weight_penalty_factor = weight_penalty
	config.fuel_empty_penalty = empty_penalty
	config.refuel_rate_kg_per_sec = refuel_rate
	return config


func _build_simulator_with_fuel(starting_fuel_kg: float) -> RaceSimulator:
	var config := RaceTypes.RaceConfig.new()
	config.track = _constant_track_profile(100.0)
	config.fuel = _fuel_config(110.0, 2.5, 0.05, 0.5, 2.0)
	config.cars.append(_car("car_1", 40.0, starting_fuel_kg))

	var runtime := RaceTypes.RaceRuntimeParams.new()
	runtime.track_length = 100.0

	var simulator := RaceSimulator.new()
	simulator.initialize(config, runtime)
	return simulator


func _car(id_value: String, speed_value: float, starting_fuel_kg: float) -> RaceTypes.CarConfig:
	var car := RaceTypes.CarConfig.new()
	car.id = id_value
	car.display_name = id_value
	car.base_speed_units_per_sec = speed_value
	car.v_ref = speed_value
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
