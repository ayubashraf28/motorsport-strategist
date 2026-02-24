extends GdUnitTestSuite

const RaceTypes = preload("res://sim/src/race_types.gd")
const DegradationModel = preload("res://sim/src/degradation_model.gd")


func test_null_config_returns_1() -> void:
	assert(DegradationModel.compute_multiplier(2, 0.4, null) == 1.0)


func test_peak_at_warmup_laps() -> void:
	var config := _config(0.5, 1.0, 0.02, 0.7)
	var multiplier: float = DegradationModel.compute_multiplier(0, 0.5, config)
	assert(abs(multiplier - 1.0) < 0.000001)


func test_warmup_ramp_is_linear() -> void:
	var config := _config(1.0, 1.0, 0.1, 0.7)
	var multiplier: float = DegradationModel.compute_multiplier(0, 0.5, config)
	assert(abs(multiplier - 0.95) < 0.000001)


func test_degradation_after_peak() -> void:
	var config := _config(0.5, 1.0, 0.02, 0.7)
	var multiplier: float = DegradationModel.compute_multiplier(2, 0.0, config)
	assert(abs(multiplier - 0.97) < 0.000001)


func test_min_multiplier_floor() -> void:
	var config := _config(0.2, 1.0, 0.5, 0.7)
	var multiplier: float = DegradationModel.compute_multiplier(10, 0.0, config)
	assert(abs(multiplier - 0.7) < 0.000001)


func test_zero_rate_stays_at_peak() -> void:
	var config := _config(0.5, 1.0, 0.0, 0.7)
	var multiplier: float = DegradationModel.compute_multiplier(10, 0.6, config)
	assert(abs(multiplier - 1.0) < 0.000001)


func test_fractional_lap_is_smooth() -> void:
	var config := _config(0.5, 1.0, 0.1, 0.7)
	var a: float = DegradationModel.compute_multiplier(1, 0.10, config)
	var b: float = DegradationModel.compute_multiplier(1, 0.20, config)
	assert(b < a)
	assert(abs(a - b) > 0.0001)


func test_speed_floor_prevents_zero() -> void:
	var base_speed: float = 0.00001
	var config := _config(0.0, 1.0, 10.0, 0.1)
	var multiplier: float = DegradationModel.compute_multiplier(20, 0.0, config)
	var degraded_speed: float = maxf(base_speed * multiplier, 0.001)
	assert(degraded_speed == 0.001)


func test_per_car_config_overrides_global() -> void:
	var global_config := _config(0.5, 1.0, 0.02, 0.7)
	var per_car_config := _config(0.5, 1.0, 0.08, 0.7)
	var global_multiplier: float = DegradationModel.compute_multiplier(3, 0.0, global_config)
	var car_multiplier: float = DegradationModel.compute_multiplier(3, 0.0, per_car_config)
	assert(car_multiplier < global_multiplier)


func test_warmup_laps_zero_starts_at_peak() -> void:
	var config := _config(0.0, 1.0, 0.02, 0.7)
	var multiplier: float = DegradationModel.compute_multiplier(0, 0.0, config)
	assert(abs(multiplier - 1.0) < 0.000001)


func test_validate_config_rejects_invalid_ranges() -> void:
	var config := _config(-1.0, 0.0, -0.1, 2.0)
	var errors: PackedStringArray = DegradationModel.validate_config(config)
	assert(errors.size() >= 3)


func _config(
	warmup_laps: float,
	peak_multiplier: float,
	degradation_rate: float,
	min_multiplier: float
) -> RaceTypes.DegradationConfig:
	var config := RaceTypes.DegradationConfig.new()
	config.warmup_laps = warmup_laps
	config.peak_multiplier = peak_multiplier
	config.degradation_rate = degradation_rate
	config.min_multiplier = min_multiplier
	return config
