extends RefCounted
class_name FixedStepRunner

var fixed_dt: float = 1.0 / 120.0
var max_steps_per_frame: int = 16
var _accumulator: float = 0.0


func _init(p_fixed_dt: float = 1.0 / 120.0, p_max_steps_per_frame: int = 16) -> void:
	fixed_dt = max(p_fixed_dt, 0.000001)
	max_steps_per_frame = max(p_max_steps_per_frame, 1)


func reset() -> void:
	_accumulator = 0.0


func advance(frame_delta: float, time_scale: float, step_callback: Callable) -> Dictionary:
	if frame_delta <= 0.0 or time_scale <= 0.0:
		return {
			"steps": 0,
			"capped": false,
			"accumulator": _accumulator
		}

	_accumulator += frame_delta * time_scale

	var steps := 0
	while _accumulator >= fixed_dt and steps < max_steps_per_frame:
		step_callback.call(fixed_dt)
		_accumulator -= fixed_dt
		steps += 1

	return {
		"steps": steps,
		"capped": _accumulator >= fixed_dt,
		"accumulator": _accumulator
	}


func get_accumulator() -> float:
	return _accumulator

