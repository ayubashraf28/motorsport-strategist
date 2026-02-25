extends RefCounted
class_name FuelModel

const RaceTypes = preload("res://sim/src/race_types.gd")


static func compute_multiplier(current_fuel_kg: float, config: RaceTypes.FuelConfig) -> float:
	if config == null or not config.enabled:
		return 1.0
	if current_fuel_kg <= 0.0:
		return clampf(config.fuel_empty_penalty, 0.0, 1.0)
	if config.max_capacity_kg <= 0.0:
		return 1.0

	var ratio: float = clampf(current_fuel_kg / config.max_capacity_kg, 0.0, 1.0)
	var multiplier: float = 1.0 - ratio * config.weight_penalty_factor
	return clampf(multiplier, config.fuel_empty_penalty, 1.0)


static func consume_fuel(current_fuel_kg: float, consumption_per_lap_kg: float) -> float:
	return maxf(current_fuel_kg - maxf(consumption_per_lap_kg, 0.0), 0.0)


static func refuel(current_fuel_kg: float, added_fuel_kg: float, max_capacity_kg: float) -> float:
	if max_capacity_kg <= 0.0:
		return maxf(current_fuel_kg, 0.0)
	var next_fuel: float = maxf(current_fuel_kg, 0.0) + maxf(added_fuel_kg, 0.0)
	return minf(next_fuel, max_capacity_kg)


static func compute_refuel_time(
	current_fuel_kg: float,
	target_fuel_kg: float,
	refuel_rate_kg_per_sec: float
) -> float:
	if refuel_rate_kg_per_sec <= 0.0:
		return 0.0
	var fuel_delta: float = maxf(target_fuel_kg - current_fuel_kg, 0.0)
	return fuel_delta / refuel_rate_kg_per_sec


static func validate_config(config: RaceTypes.FuelConfig) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if config == null:
		return errors
	if config.max_capacity_kg <= 0.0:
		errors.append("fuel.max_capacity_kg must be > 0.")
	if config.consumption_per_lap_kg < 0.0:
		errors.append("fuel.consumption_per_lap_kg must be >= 0.")
	if config.weight_penalty_factor < 0.0 or config.weight_penalty_factor > 1.0:
		errors.append("fuel.weight_penalty_factor must be in [0, 1].")
	if config.fuel_empty_penalty <= 0.0 or config.fuel_empty_penalty > 1.0:
		errors.append("fuel.fuel_empty_penalty must be in (0, 1].")
	if config.refuel_rate_kg_per_sec <= 0.0:
		errors.append("fuel.refuel_rate_kg_per_sec must be > 0.")
	return errors
