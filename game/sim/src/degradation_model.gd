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

	var optimal_thresh: float = clampf(config.optimal_threshold, 0.0, 1.0)
	var cliff_thresh: float = clampf(config.cliff_threshold, 0.0, optimal_thresh)
	var cliff_mult: float = maxf(config.cliff_multiplier, 1.0)

	var optimal_mult: float = floor_mult + total_range * optimal_thresh
	var cliff_mult_value: float = floor_mult + total_range * cliff_thresh

	var optimal_laps: float = (peak - optimal_mult) / rate if rate > 0.0 else INF
	if laps_after_warmup <= optimal_laps:
		return clampf(peak, floor_mult, peak)

	var gradual_laps: float = (optimal_mult - cliff_mult_value) / rate if rate > 0.0 else INF
	var laps_into_gradual: float = laps_after_warmup - optimal_laps
	if laps_into_gradual <= gradual_laps:
		var gradual_degraded: float = optimal_mult - laps_into_gradual * rate
		return clampf(gradual_degraded, floor_mult, peak)

	var laps_into_cliff: float = laps_into_gradual - gradual_laps
	var cliff_rate: float = rate * cliff_mult
	var cliff_degraded: float = cliff_mult_value - laps_into_cliff * cliff_rate
	return clampf(cliff_degraded, floor_mult, peak)


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
