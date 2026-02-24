extends RefCounted
class_name PaceProfile

const RaceTypes = preload("res://sim/src/race_types.gd")

const _COVERAGE_EPSILON: float = 2.0
const _NUMERIC_EPSILON: float = 0.0001

var _track_length: float = 0.0
var _blend_distance: float = 0.0
var _segments: Array[RaceTypes.PaceSegmentConfig] = []
var _validation_errors: PackedStringArray = PackedStringArray()
var _is_valid: bool = false


func configure(track_length: float, blend_distance: float, segments: Array[RaceTypes.PaceSegmentConfig]) -> void:
	_validation_errors = PackedStringArray()
	_is_valid = false
	_track_length = track_length
	_blend_distance = blend_distance
	_segments.clear()

	if _track_length <= 0.0:
		_validation_errors.append("Pace profile track length must be greater than zero.")
		return
	if _blend_distance < 0.0:
		_validation_errors.append("Pace profile blend_distance must be >= 0.")
		return
	if segments.is_empty():
		_validation_errors.append("Pace profile must contain at least one segment.")
		return

	for segment in segments:
		if segment == null:
			_validation_errors.append("Pace segment entries cannot be null.")
			continue
		_segments.append(segment.clone())

	if _segments.is_empty():
		_validation_errors.append("Pace profile contains no valid segments.")
		return

	_validate_segments()
	if _validation_errors.is_empty():
		_is_valid = true


func is_valid() -> bool:
	return _is_valid


func get_validation_errors() -> PackedStringArray:
	return _validation_errors


func sample_multiplier(distance_along_track: float) -> float:
	if not _is_valid:
		return 1.0

	var wrapped_distance: float = fposmod(distance_along_track, _track_length)
	var owner_index: int = _find_segment_index(wrapped_distance)
	if owner_index < 0:
		return 1.0

	var owner_segment: RaceTypes.PaceSegmentConfig = _segments[owner_index]
	var base_multiplier: float = owner_segment.multiplier
	if _blend_distance <= _NUMERIC_EPSILON:
		return base_multiplier

	var half_window: float = _blend_distance * 0.5
	for boundary_index in range(_segments.size()):
		var boundary_distance: float = _segments[boundary_index].start_distance
		var delta_from_boundary: float = _wrapped_signed_delta(wrapped_distance, boundary_distance)
		if abs(delta_from_boundary) > half_window:
			continue

		var previous_index: int = _wrap_index(boundary_index - 1)
		var previous_multiplier: float = _segments[previous_index].multiplier
		var next_multiplier: float = _segments[boundary_index].multiplier
		var t: float = (delta_from_boundary + half_window) / _blend_distance
		var smooth_t: float = _smoothstep(t)
		return lerp(previous_multiplier, next_multiplier, smooth_t)

	return base_multiplier


func get_segments() -> Array[RaceTypes.PaceSegmentConfig]:
	var copied: Array[RaceTypes.PaceSegmentConfig] = []
	for segment in _segments:
		copied.append(segment.clone())
	return copied


func get_blend_distance() -> float:
	return _blend_distance


func _validate_segments() -> void:
	var first_segment: RaceTypes.PaceSegmentConfig = _segments[0]
	if abs(first_segment.start_distance) > _COVERAGE_EPSILON:
		_validation_errors.append(
			"First pace segment must start at 0.0 (got %.5f)." % first_segment.start_distance
		)

	for i in range(_segments.size()):
		var segment: RaceTypes.PaceSegmentConfig = _segments[i]
		if segment.end_distance <= segment.start_distance:
			_validation_errors.append(
				"Segment %d has non-positive length (start=%.5f, end=%.5f)." %
				[i, segment.start_distance, segment.end_distance]
			)

		if segment.multiplier <= 0.0:
			_validation_errors.append("Segment %d multiplier must be > 0." % i)

		var segment_length: float = segment.end_distance - segment.start_distance
		if _blend_distance > _NUMERIC_EPSILON and segment_length + _NUMERIC_EPSILON < _blend_distance:
			_validation_errors.append(
				"Segment %d length %.5f is shorter than blend_distance %.5f." %
				[i, segment_length, _blend_distance]
			)

		if i == 0:
			continue

		var previous_segment: RaceTypes.PaceSegmentConfig = _segments[i - 1]
		var delta: float = segment.start_distance - previous_segment.end_distance
		if abs(delta) <= _COVERAGE_EPSILON:
			continue
		if delta > 0.0:
			_validation_errors.append(
				"Gap detected between segment %d and %d (gap=%.5f)." % [i - 1, i, delta]
			)
		else:
			_validation_errors.append(
				"Overlap detected between segment %d and %d (overlap=%.5f)." % [i - 1, i, abs(delta)]
			)

	var last_segment: RaceTypes.PaceSegmentConfig = _segments[_segments.size() - 1]
	if abs(last_segment.end_distance - _track_length) > _COVERAGE_EPSILON:
		_validation_errors.append(
			"Last segment must end at track length %.5f (got %.5f)." %
			[_track_length, last_segment.end_distance]
		)


func _find_segment_index(distance_along_track: float) -> int:
	for i in range(_segments.size()):
		var segment: RaceTypes.PaceSegmentConfig = _segments[i]
		var is_last_segment: bool = i == _segments.size() - 1
		if distance_along_track >= segment.start_distance and distance_along_track < segment.end_distance:
			return i
		if is_last_segment and is_equal_approx(distance_along_track, segment.end_distance):
			return i
	return -1


func _wrap_index(index: int) -> int:
	return (index % _segments.size() + _segments.size()) % _segments.size()


func _wrapped_signed_delta(distance_value: float, boundary_value: float) -> float:
	var raw_delta: float = distance_value - boundary_value
	return fposmod(raw_delta + (_track_length * 0.5), _track_length) - (_track_length * 0.5)


func _smoothstep(t: float) -> float:
	var clamped_t: float = clampf(t, 0.0, 1.0)
	return clamped_t * clamped_t * (3.0 - (2.0 * clamped_t))
