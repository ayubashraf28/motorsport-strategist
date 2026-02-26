extends RefCounted
class_name DriverMode

enum Mode {
	PUSH = 0,
	STANDARD = 1,
	CONSERVE = 2
}

const _MODE_EFFECTS: Dictionary = {
	Mode.PUSH: {
		"pace_multiplier": 1.02,
		"deg_rate_scale": 1.50,
		"fuel_consumption_scale": 1.20,
	},
	Mode.STANDARD: {
		"pace_multiplier": 1.0,
		"deg_rate_scale": 1.0,
		"fuel_consumption_scale": 1.0,
	},
	Mode.CONSERVE: {
		"pace_multiplier": 0.985,
		"deg_rate_scale": 0.65,
		"fuel_consumption_scale": 0.82,
	},
}


static func get_mode_effects(mode: int) -> Dictionary:
	if _MODE_EFFECTS.has(mode):
		return _MODE_EFFECTS[mode]
	return _MODE_EFFECTS[Mode.STANDARD]


static func get_pace_multiplier(mode: int) -> float:
	return float(get_mode_effects(mode).get("pace_multiplier", 1.0))


static func get_deg_rate_scale(mode: int) -> float:
	return float(get_mode_effects(mode).get("deg_rate_scale", 1.0))


static func get_fuel_consumption_scale(mode: int) -> float:
	return float(get_mode_effects(mode).get("fuel_consumption_scale", 1.0))


static func is_valid_mode(mode: int) -> bool:
	return mode == Mode.PUSH or mode == Mode.STANDARD or mode == Mode.CONSERVE


static func get_mode_name(mode: int) -> String:
	match mode:
		Mode.PUSH:
			return "PUSH"
		Mode.STANDARD:
			return "STD"
		Mode.CONSERVE:
			return "CONSERVE"
		_:
			return "STD"


static func get_mode_short(mode: int) -> String:
	match mode:
		Mode.PUSH:
			return "P"
		Mode.STANDARD:
			return "S"
		Mode.CONSERVE:
			return "C"
		_:
			return "S"
