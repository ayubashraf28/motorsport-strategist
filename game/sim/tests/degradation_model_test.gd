extends GdUnitTestSuite

const RaceTypes = preload("res://sim/src/race_types.gd")
const DegradationModel = preload("res://sim/src/degradation_model.gd")


func test_null_config_returns_1() -> void:
	assert(DegradationModel.compute_multiplier(2, 0.4, null) == 1.0)


func test_optimal_phase_holds_peak() -> void:
	var config := _config(0.0, 1.0, 0.04, 0.7, 0.75, 0.30, 3.0)
	var multiplier: float = DegradationModel.compute_multiplier(1, 0.0, config)
	assert(abs(multiplier - 1.0) < 0.000001)


func test_gradual_phase_linear_decline() -> void:
	var config := _config(0.0, 1.0, 0.04, 0.7, 0.75, 0.30, 3.0)
	var multiplier: float = DegradationModel.compute_multiplier(3, 0.0, config)
	assert(abs(multiplier - 0.88) < 0.000001)


func test_cliff_phase_accelerated_decline() -> void:
	var config := _config(0.0, 1.0, 0.04, 0.7, 0.75, 0.30, 3.0)
	var multiplier: float = DegradationModel.compute_multiplier(5, 0.5, config)
	assert(abs(multiplier - 0.76) < 0.000001)


func test_cliff_reaches_floor_faster() -> void:
	var cliff_config := _config(0.0, 1.0, 0.04, 0.7, 0.75, 0.30, 3.0)
	var linear_config := _config(0.0, 1.0, 0.04, 0.7, 1.0, 0.0, 1.0)
	var cliff_multiplier: float = DegradationModel.compute_multiplier(6, 0.0, cliff_config)
	var linear_multiplier: float = DegradationModel.compute_multiplier(6, 0.0, linear_config)
	assert(cliff_multiplier < linear_multiplier)


func test_soft_degrades_faster_than_hard() -> void:
	var soft := _config(0.0, 1.0, 0.04, 0.70, 0.75, 0.30, 3.0)
	var hard := _config(0.0, 0.976, 0.01, 0.80, 0.75, 0.30, 3.0)
	var soft_multiplier: float = DegradationModel.compute_multiplier(6, 0.0, soft)
	var hard_multiplier: float = DegradationModel.compute_multiplier(6, 0.0, hard)
	assert(soft_multiplier < hard_multiplier)


func test_backward_compat_linear() -> void:
	var config := _config(0.0, 1.0, 0.02, 0.7, 1.0, 0.0, 1.0)
	var multiplier: float = DegradationModel.compute_multiplier(3, 0.0, config)
	assert(abs(multiplier - 0.94) < 0.000001)


func test_default_config_is_linear() -> void:
	var default_config := RaceTypes.DegradationConfig.new()
	default_config.warmup_laps = 0.0
	default_config.peak_multiplier = 1.0
	default_config.degradation_rate = 0.02
	default_config.min_multiplier = 0.7
	var multiplier: float = DegradationModel.compute_multiplier(3, 0.0, default_config)
	assert(abs(multiplier - 0.94) < 0.000001)


func test_warmup_phase_unchanged() -> void:
	var config := _config(1.0, 1.0, 0.1, 0.7, 0.75, 0.30, 3.0)
	var multiplier: float = DegradationModel.compute_multiplier(0, 0.5, config)
	assert(abs(multiplier - 0.95) < 0.000001)


func test_validate_rejects_cliff_above_optimal() -> void:
	var config := _config(0.0, 1.0, 0.02, 0.7, 0.3, 0.7, 3.0)
	var errors: PackedStringArray = DegradationModel.validate_config(config)
	assert(errors.size() > 0)


func test_validate_rejects_cliff_mult_below_1() -> void:
	var config := _config(0.0, 1.0, 0.02, 0.7, 0.75, 0.3, 0.5)
	var errors: PackedStringArray = DegradationModel.validate_config(config)
	assert(errors.size() > 0)


func _config(
	warmup_laps: float,
	peak_multiplier: float,
	degradation_rate: float,
	min_multiplier: float,
	optimal_threshold: float,
	cliff_threshold: float,
	cliff_multiplier: float
) -> RaceTypes.DegradationConfig:
	var config := RaceTypes.DegradationConfig.new()
	config.warmup_laps = warmup_laps
	config.peak_multiplier = peak_multiplier
	config.degradation_rate = degradation_rate
	config.min_multiplier = min_multiplier
	config.optimal_threshold = optimal_threshold
	config.cliff_threshold = cliff_threshold
	config.cliff_multiplier = cliff_multiplier
	return config
