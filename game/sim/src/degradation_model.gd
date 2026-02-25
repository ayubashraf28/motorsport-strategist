extends RefCounted
class_name DegradationModel

const RaceTypes = preload("res://sim/src/race_types.gd")


static func compute_multiplier(
	lap_count: int,
	fractional_lap: float,
	config: RaceTypes.DegradationConfig
) -> float:
	if config == null:
		return 1.0

	var clamped_fractional_lap: float = clampf(fractional_lap, 0.0, 0.999999)
	var race_progress: float = maxf(float(lap_count), 0.0) + clamped_fractional_lap
	var warmup_laps: float = maxf(config.warmup_laps, 0.0)
	var peak: float = config.peak_multiplier
	var floor_mult: float = minf(config.min_multiplier, peak)
	var rate: float = maxf(config.degradation_rate, 0.0)
	var warmup_start: float = maxf(peak - warmup_laps * rate, floor_mult)

	if warmup_laps > 0.0 and race_progress < warmup_laps:
		var t: float = race_progress / warmup_laps
		return clampf(lerpf(warmup_start, peak, t), floor_mult, peak)

	if race_progress <= warmup_laps:
		return clampf(peak, floor_mult, peak)

	var laps_after_warmup: float = race_progress - warmup_laps
	var total_range: float = peak - floor_mult
	if total_range <= 0.0 or rate <= 0.0:
		return clampf(peak, floor_mult, peak)

	var base_life_laps: float = total_range / rate
	var wear_progress: float = clampf(laps_after_warmup / maxf(base_life_laps, 0.000001), 0.0, 1.0)

	var optimal_thresh: float = clampf(config.optimal_threshold, 0.0, 1.0)
	var cliff_thresh: float = clampf(config.cliff_threshold, 0.0, optimal_thresh)
	var cliff_mult: float = maxf(config.cliff_multiplier, 1.0)

	var optimal_wear_end: float = 1.0 - optimal_thresh
	var cliff_wear_start: float = 1.0 - cliff_thresh
	var cliff_mult_value: float = floor_mult + total_range * cliff_thresh

	if wear_progress <= optimal_wear_end:
		return clampf(peak, floor_mult, peak)

	var gradual_denom: float = cliff_wear_start - optimal_wear_end
	if wear_progress <= cliff_wear_start and gradual_denom > 0.0:
		var gradual_t: float = (wear_progress - optimal_wear_end) / gradual_denom
		var gradual_degraded: float = lerpf(peak, cliff_mult_value, clampf(gradual_t, 0.0, 1.0))
		return clampf(gradual_degraded, floor_mult, peak)

	if wear_progress <= cliff_wear_start:
		return clampf(cliff_mult_value, floor_mult, peak)

	var cliff_denom: float = 1.0 - cliff_wear_start
	if cliff_denom <= 0.0:
		return clampf(floor_mult, floor_mult, peak)

	var cliff_t: float = (wear_progress - cliff_wear_start) / cliff_denom
	var cliff_eased: float = 1.0 - pow(1.0 - clampf(cliff_t, 0.0, 1.0), cliff_mult)
	var cliff_degraded: float = lerpf(cliff_mult_value, floor_mult, cliff_eased)
	return clampf(cliff_degraded, floor_mult, peak)


static func compute_life_ratio(multiplier: float, config: RaceTypes.DegradationConfig) -> float:
	if config == null:
		return 1.0
	var peak: float = config.peak_multiplier
	var floor_mult: float = minf(config.min_multiplier, peak)
	var total_range: float = peak - floor_mult
	if total_range <= 0.0:
		return 1.0
	return clampf((multiplier - floor_mult) / total_range, 0.0, 1.0)


static func compute_phase(life_ratio: float, config: RaceTypes.DegradationConfig) -> int:
	var clamped_life: float = clampf(life_ratio, 0.0, 1.0)
	if config == null:
		return RaceTypes.TyrePhase.OPTIMAL
	var optimal_thresh: float = clampf(config.optimal_threshold, 0.0, 1.0)
	var cliff_thresh: float = clampf(config.cliff_threshold, 0.0, optimal_thresh)
	if clamped_life >= optimal_thresh:
		return RaceTypes.TyrePhase.OPTIMAL
	if clamped_life >= cliff_thresh:
		return RaceTypes.TyrePhase.GRADUAL
	return RaceTypes.TyrePhase.CLIFF


static func validate_config(config: RaceTypes.DegradationConfig) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if config == null:
		return errors

	if config.peak_multiplier <= 0.0 or config.peak_multiplier > 2.0:
		errors.append("degradation.peak_multiplier must be > 0 and <= 2.0.")
	if config.min_multiplier <= 0.0:
		errors.append("degradation.min_multiplier must be > 0.")
	if config.min_multiplier > config.peak_multiplier:
		errors.append("degradation.min_multiplier must be <= degradation.peak_multiplier.")
	if config.degradation_rate < 0.0:
		errors.append("degradation.degradation_rate must be >= 0.")
	if config.warmup_laps < 0.0:
		errors.append("degradation.warmup_laps must be >= 0.")
	if config.optimal_threshold < 0.0 or config.optimal_threshold > 1.0:
		errors.append("degradation.optimal_threshold must be in [0, 1].")
	if config.cliff_threshold < 0.0 or config.cliff_threshold > config.optimal_threshold:
		errors.append("degradation.cliff_threshold must be in [0, optimal_threshold].")
	if config.cliff_multiplier < 1.0:
		errors.append("degradation.cliff_multiplier must be >= 1.")
	return errors
