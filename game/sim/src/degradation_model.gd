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
	var peak_multiplier: float = config.peak_multiplier
	var min_multiplier: float = minf(config.min_multiplier, peak_multiplier)
	var degradation_rate: float = maxf(config.degradation_rate, 0.0)
	var warmup_start: float = maxf(peak_multiplier - warmup_laps * degradation_rate, min_multiplier)

	if warmup_laps > 0.0 and race_progress < warmup_laps:
		var t: float = race_progress / warmup_laps
		return clampf(lerpf(warmup_start, peak_multiplier, t), min_multiplier, peak_multiplier)

	if race_progress <= warmup_laps:
		return clampf(peak_multiplier, min_multiplier, peak_multiplier)

	var degraded: float = peak_multiplier - (race_progress - warmup_laps) * degradation_rate
	return clampf(degraded, min_multiplier, peak_multiplier)


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
	return errors
