extends RefCounted
class_name SpeedProfile

const RaceTypes = preload("res://sim/src/race_types.gd")

const _NUMERIC_EPSILON: float = 0.0000001
const _CIRCULAR_PASSES: int = 2

var _geometry: RaceTypes.TrackGeometryData = null
var _physics: RaceTypes.PhysicsVehicleConfig = null
var _speed_profile: PackedFloat64Array = PackedFloat64Array()
var _validation_errors: PackedStringArray = PackedStringArray()
var _is_valid: bool = false


func configure(
	geometry: RaceTypes.TrackGeometryData,
	physics: RaceTypes.PhysicsVehicleConfig
) -> void:
	_validation_errors = PackedStringArray()
	_is_valid = false
	_speed_profile = PackedFloat64Array()
	_geometry = null
	_physics = null

	_validate_inputs(geometry, physics)
	if not _validation_errors.is_empty():
		return

	_geometry = geometry.clone()
	_physics = physics.clone()
	_speed_profile = _build_profile()
	if _speed_profile.size() != _geometry.sample_count:
		_validation_errors.append("SpeedProfile failed to build profile for all geometry samples.")
		return
	_is_valid = true


func is_valid() -> bool:
	return _is_valid


func get_validation_errors() -> PackedStringArray:
	return _validation_errors


func sample_speed(distance: float) -> float:
	if not _is_valid:
		return 0.0
	if _speed_profile.is_empty():
		return 0.0

	var wrapped_distance: float = fposmod(distance, _geometry.track_length)
	var index_float: float = wrapped_distance / _geometry.ds
	var base_index: int = int(floor(index_float))
	var i0: int = _wrap_index(base_index, _speed_profile.size())
	var i1: int = _wrap_index(base_index + 1, _speed_profile.size())
	var t: float = index_float - floor(index_float)
	return lerp(_speed_profile[i0], _speed_profile[i1], t)


func get_speed_array() -> PackedFloat64Array:
	return _speed_profile.duplicate()


func _validate_inputs(
	geometry: RaceTypes.TrackGeometryData,
	physics: RaceTypes.PhysicsVehicleConfig
) -> void:
	if geometry == null:
		_validation_errors.append("SpeedProfile requires TrackGeometryData.")
		return
	if physics == null:
		_validation_errors.append("SpeedProfile requires PhysicsVehicleConfig.")
		return
	if geometry.sample_count < 3:
		_validation_errors.append("SpeedProfile geometry sample_count must be >= 3.")
	if geometry.ds <= 0.0:
		_validation_errors.append("SpeedProfile geometry ds must be > 0.")
	if geometry.track_length <= 0.0:
		_validation_errors.append("SpeedProfile geometry track_length must be > 0.")
	if geometry.curvatures.size() != geometry.sample_count:
		_validation_errors.append("SpeedProfile geometry curvatures length mismatch.")

	if physics.a_lat_max <= 0.0:
		_validation_errors.append("physics.a_lat_max must be > 0.")
	if physics.a_long_accel <= 0.0:
		_validation_errors.append("physics.a_long_accel must be > 0.")
	if physics.a_long_brake <= 0.0:
		_validation_errors.append("physics.a_long_brake must be > 0.")
	if physics.v_top_speed <= 0.0:
		_validation_errors.append("physics.v_top_speed must be > 0.")
	if physics.curvature_epsilon <= 0.0:
		_validation_errors.append("physics.curvature_epsilon must be > 0.")


func _build_profile() -> PackedFloat64Array:
	var sample_count: int = _geometry.sample_count
	var corner_speeds: PackedFloat64Array = PackedFloat64Array()
	corner_speeds.resize(sample_count)
	for i in range(sample_count):
		var curvature: float = abs(_geometry.curvatures[i])
		var effective_curvature: float = maxf(curvature, _physics.curvature_epsilon)
		var corner_limit: float = sqrt(_physics.a_lat_max / effective_curvature)
		corner_speeds[i] = minf(corner_limit, _physics.v_top_speed)

	var forward: PackedFloat64Array = corner_speeds.duplicate()
	for _pass_index in range(_CIRCULAR_PASSES):
		for i in range(sample_count):
			var next_index: int = _wrap_index(i + 1, sample_count)
			var reachable_sq: float = forward[i] * forward[i] + (2.0 * _physics.a_long_accel * _geometry.ds)
			var reachable: float = sqrt(maxf(reachable_sq, 0.0))
			forward[next_index] = minf(forward[next_index], reachable)

	var backward: PackedFloat64Array = corner_speeds.duplicate()
	for _pass_index in range(_CIRCULAR_PASSES):
		for i in range(sample_count):
			var source_index: int = sample_count - 1 - i
			var previous_index: int = _wrap_index(source_index - 1, sample_count)
			var reachable_sq: float = backward[source_index] * backward[source_index] + (2.0 * _physics.a_long_brake * _geometry.ds)
			var reachable: float = sqrt(maxf(reachable_sq, 0.0))
			backward[previous_index] = minf(backward[previous_index], reachable)

	var profile: PackedFloat64Array = PackedFloat64Array()
	profile.resize(sample_count)
	for i in range(sample_count):
		profile[i] = minf(corner_speeds[i], minf(forward[i], backward[i]))
		if profile[i] < _NUMERIC_EPSILON:
			profile[i] = 0.0

	return profile


func _wrap_index(index: int, count: int) -> int:
	return (index % count + count) % count
