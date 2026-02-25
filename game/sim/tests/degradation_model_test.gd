extends GdUnitTestSuite

const RaceTypes = preload("res://sim/src/race_types.gd")
const DegradationModel = preload("res://sim/src/degradation_model.gd")


func test_null_config_returns_1() -> void:
	assert(DegradationModel.compute_multiplier(2, 0.4, null) == 1.0)


func test_warmup_phase_unchanged() -> void:
	var config := _config(1.0, 1.0, 0.1, 0.7, 0.75, 0.30, 2.5)
	var multiplier: float = DegradationModel.compute_multiplier(0, 0.5, config)
	assert(abs(multiplier - 0.95) < 0.000001)


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


func test_optimal_boundary_is_continuous() -> void:
	var config := _config(0.3, 1.0, 0.025, 0.72, 0.75, 0.30, 2.5)
	var base_life_laps: float = (config.peak_multiplier - config.min_multiplier) / config.degradation_rate
	var boundary_progress: float = config.warmup_laps + base_life_laps * (1.0 - config.optimal_threshold)
	var epsilon: float = 0.0001
	var below: float = _compute_at_progress(boundary_progress - epsilon, config)
	var above: float = _compute_at_progress(boundary_progress + epsilon, config)
	assert(abs(above - below) < 0.005)


func test_cliff_boundary_is_continuous() -> void:
	var config := _config(0.3, 1.0, 0.025, 0.72, 0.75, 0.30, 2.5)
	var base_life_laps: float = (config.peak_multiplier - config.min_multiplier) / config.degradation_rate
	var boundary_progress: float = config.warmup_laps + base_life_laps * (1.0 - config.cliff_threshold)
	var epsilon: float = 0.0001
	var below: float = _compute_at_progress(boundary_progress - epsilon, config)
	var above: float = _compute_at_progress(boundary_progress + epsilon, config)
	assert(abs(above - below) < 0.005)


func test_cliff_mult_above_1_drops_faster_than_linear_cliff() -> void:
	var accelerated := _config(0.3, 1.0, 0.025, 0.72, 0.75, 0.30, 2.5)
	var linear := _config(0.3, 1.0, 0.025, 0.72, 0.75, 0.30, 1.0)
	var base_life_laps: float = (accelerated.peak_multiplier - accelerated.min_multiplier) / accelerated.degradation_rate
	var cliff_start: float = accelerated.warmup_laps + base_life_laps * (1.0 - accelerated.cliff_threshold)
	var cliff_span: float = base_life_laps * accelerated.cliff_threshold
	var sample_progress: float = cliff_start + cliff_span * 0.5
	var accelerated_value: float = _compute_at_progress(sample_progress, accelerated)
	var linear_value: float = _compute_at_progress(sample_progress, linear)
	assert(accelerated_value < linear_value)


func test_soft_degrades_faster_than_hard() -> void:
	var soft := _config(0.3, 1.0, 0.025, 0.72, 0.75, 0.30, 2.5)
	var hard := _config(0.8, 0.976, 0.012, 0.80, 0.75, 0.30, 2.5)
	var soft_multiplier: float = DegradationModel.compute_multiplier(8, 0.0, soft)
	var hard_multiplier: float = DegradationModel.compute_multiplier(8, 0.0, hard)
	assert(soft_multiplier < hard_multiplier)


func test_compute_life_ratio_maps_peak_and_floor() -> void:
	var config := _config(0.0, 1.0, 0.02, 0.7, 0.75, 0.30, 2.5)
	assert(abs(DegradationModel.compute_life_ratio(1.0, config) - 1.0) < 0.000001)
	assert(abs(DegradationModel.compute_life_ratio(0.7, config) - 0.0) < 0.000001)


func test_compute_phase_classifies_ranges() -> void:
	var config := _config(0.0, 1.0, 0.02, 0.7, 0.75, 0.30, 2.5)
	assert(DegradationModel.compute_phase(0.90, config) == RaceTypes.TyrePhase.OPTIMAL)
	assert(DegradationModel.compute_phase(0.50, config) == RaceTypes.TyrePhase.GRADUAL)
	assert(DegradationModel.compute_phase(0.20, config) == RaceTypes.TyrePhase.CLIFF)


func test_validate_rejects_cliff_above_optimal() -> void:
	var config := _config(0.0, 1.0, 0.02, 0.7, 0.3, 0.7, 2.5)
	var errors: PackedStringArray = DegradationModel.validate_config(config)
	assert(errors.size() > 0)


func test_validate_rejects_cliff_mult_below_1() -> void:
	var config := _config(0.0, 1.0, 0.02, 0.7, 0.75, 0.3, 0.5)
	var errors: PackedStringArray = DegradationModel.validate_config(config)
	assert(errors.size() > 0)


func _compute_at_progress(progress: float, config: RaceTypes.DegradationConfig) -> float:
	var clamped_progress: float = maxf(progress, 0.0)
	var lap_count: int = int(floor(clamped_progress))
	var fractional: float = clamped_progress - float(lap_count)
	fractional = clampf(fractional, 0.0, 0.999999)
	return DegradationModel.compute_multiplier(lap_count, fractional, config)


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
