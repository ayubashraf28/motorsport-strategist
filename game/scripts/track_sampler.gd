extends RefCounted
class_name TrackSampler

var _polyline: PackedVector2Array = PackedVector2Array()
var _cumulative_lengths: PackedFloat32Array = PackedFloat32Array()
var _track_length: float = 0.0


func configure(curve: Curve2D, bake_interval: float = 8.0) -> void:
	_polyline = PackedVector2Array()
	_cumulative_lengths = PackedFloat32Array()
	_track_length = 0.0

	if curve == null:
		return

	curve.bake_interval = maxf(0.1, bake_interval)
	var baked_points := curve.get_baked_points()
	if baked_points.size() < 2:
		return

	_polyline = baked_points
	if _polyline[0].distance_to(_polyline[_polyline.size() - 1]) > 0.001:
		_polyline.append(_polyline[0])

	_cumulative_lengths.append(0.0)
	var running_total := 0.0
	for i in range(1, _polyline.size()):
		running_total += _polyline[i - 1].distance_to(_polyline[i])
		_cumulative_lengths.append(running_total)

	_track_length = running_total


func is_valid() -> bool:
	return _track_length > 0.0 and _polyline.size() >= 2


func get_total_length() -> float:
	return _track_length


func get_polyline() -> PackedVector2Array:
	return _polyline


func sample_position(distance_along_track: float) -> Vector2:
	if not is_valid():
		return Vector2.ZERO

	var wrapped_distance := fposmod(distance_along_track, _track_length)
	for i in range(1, _cumulative_lengths.size()):
		var segment_end_distance := _cumulative_lengths[i]
		if wrapped_distance > segment_end_distance:
			continue

		var segment_start_distance := _cumulative_lengths[i - 1]
		var segment_distance := segment_end_distance - segment_start_distance
		if segment_distance <= 0.000001:
			return _polyline[i]

		var alpha := (wrapped_distance - segment_start_distance) / segment_distance
		return _polyline[i - 1].lerp(_polyline[i], alpha)

	return _polyline[_polyline.size() - 1]


func sample_tangent(distance_along_track: float) -> Vector2:
	if not is_valid():
		return Vector2.RIGHT

	var probe_distance: float = minf(2.0, _track_length * 0.002)
	var previous_point: Vector2 = sample_position(distance_along_track - probe_distance)
	var next_point: Vector2 = sample_position(distance_along_track + probe_distance)
	var tangent: Vector2 = next_point - previous_point
	if tangent.length_squared() <= 0.000001:
		return Vector2.RIGHT
	return tangent.normalized()
