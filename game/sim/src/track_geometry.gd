extends RefCounted
class_name TrackGeometry

const RaceTypes = preload("res://sim/src/race_types.gd")

const _EPSILON: float = 0.000001

var _data: RaceTypes.TrackGeometryData = RaceTypes.TrackGeometryData.new()
var _validation_errors: PackedStringArray = PackedStringArray()
var _is_valid: bool = false


func configure_from_asset(data: RaceTypes.TrackGeometryData) -> void:
	_reset_state()
	if data == null:
		_validation_errors.append("TrackGeometryData is required.")
		return

	_data = data.clone()
	_validate_data()


func configure_from_polyline(polyline: PackedVector2Array, ds: float) -> void:
	_reset_state()
	if ds <= 0.0:
		_validation_errors.append("TrackGeometry polyline ds must be > 0.")
		return
	if polyline.size() < 2:
		_validation_errors.append("TrackGeometry polyline must contain at least 2 points.")
		return

	var points: PackedVector2Array = _sanitize_polyline(polyline)
	if points.size() < 3:
		_validation_errors.append("TrackGeometry polyline must contain at least 3 unique points.")
		return

	var cumulative: PackedFloat64Array = PackedFloat64Array()
	cumulative.resize(points.size() + 1)
	cumulative[0] = 0.0
	for i in range(1, points.size()):
		cumulative[i] = cumulative[i - 1] + points[i - 1].distance_to(points[i])
	cumulative[points.size()] = cumulative[points.size() - 1] + points[points.size() - 1].distance_to(points[0])

	var track_length: float = cumulative[points.size()]
	if track_length <= _EPSILON:
		_validation_errors.append("TrackGeometry track length must be > 0.")
		return

	var sample_count: int = maxi(3, int(round(track_length / ds)))
	var uniform_ds: float = track_length / float(sample_count)

	var sampled_positions: PackedVector2Array = PackedVector2Array()
	sampled_positions.resize(sample_count)
	for i in range(sample_count):
		var distance: float = uniform_ds * float(i)
		sampled_positions[i] = _sample_polyline_closed(points, cumulative, distance)

	var curvatures: PackedFloat64Array = PackedFloat64Array()
	curvatures.resize(sample_count)
	for i in range(sample_count):
		var previous_point: Vector2 = sampled_positions[(i - 1 + sample_count) % sample_count]
		var current_point: Vector2 = sampled_positions[i]
		var next_point: Vector2 = sampled_positions[(i + 1) % sample_count]
		curvatures[i] = _compute_signed_curvature(previous_point, current_point, next_point)

	_data = RaceTypes.TrackGeometryData.new()
	_data.sample_count = sample_count
	_data.ds = uniform_ds
	_data.track_length = track_length
	_data.curvatures = curvatures
	_data.positions_x.resize(sample_count)
	_data.positions_y.resize(sample_count)
	for i in range(sample_count):
		_data.positions_x[i] = sampled_positions[i].x
		_data.positions_y[i] = sampled_positions[i].y

	_validate_data()


func is_valid() -> bool:
	return _is_valid


func get_validation_errors() -> PackedStringArray:
	return _validation_errors


func get_data() -> RaceTypes.TrackGeometryData:
	return _data.clone() if _is_valid else RaceTypes.TrackGeometryData.new()


func _reset_state() -> void:
	_data = RaceTypes.TrackGeometryData.new()
	_validation_errors = PackedStringArray()
	_is_valid = false


func _sanitize_polyline(polyline: PackedVector2Array) -> PackedVector2Array:
	var points: PackedVector2Array = polyline
	if points.size() > 2 and points[0].distance_to(points[points.size() - 1]) <= _EPSILON:
		points = points.duplicate()
		points.resize(points.size() - 1)
	return points


func _sample_polyline_closed(
	points: PackedVector2Array,
	cumulative: PackedFloat64Array,
	distance: float
) -> Vector2:
	var track_length: float = cumulative[cumulative.size() - 1]
	var wrapped_distance: float = fposmod(distance, track_length)

	var segment_start_index: int = 0
	for i in range(1, cumulative.size()):
		if wrapped_distance > cumulative[i]:
			continue
		segment_start_index = i - 1
		break

	var segment_end_index: int = (segment_start_index + 1) % points.size()
	var segment_start_distance: float = cumulative[segment_start_index]
	var segment_end_distance: float = cumulative[segment_start_index + 1]
	var segment_length: float = segment_end_distance - segment_start_distance
	if segment_length <= _EPSILON:
		return points[segment_end_index]

	var alpha: float = (wrapped_distance - segment_start_distance) / segment_length
	return points[segment_start_index].lerp(points[segment_end_index], alpha)


func _compute_signed_curvature(previous_point: Vector2, current_point: Vector2, next_point: Vector2) -> float:
	var a: float = previous_point.distance_to(current_point)
	var b: float = current_point.distance_to(next_point)
	var c: float = previous_point.distance_to(next_point)
	var denominator: float = a * b * c
	if denominator <= _EPSILON:
		return 0.0

	var area2: float = (current_point - previous_point).cross(next_point - previous_point)
	return (2.0 * area2) / denominator


func _validate_data() -> void:
	if _data.sample_count < 3:
		_validation_errors.append("TrackGeometry sample_count must be >= 3.")
	if _data.ds <= 0.0:
		_validation_errors.append("TrackGeometry ds must be > 0.")
	if _data.track_length <= 0.0:
		_validation_errors.append("TrackGeometry track_length must be > 0.")
	if _data.curvatures.size() != _data.sample_count:
		_validation_errors.append("TrackGeometry curvatures length must match sample_count.")
	if _data.positions_x.size() != _data.sample_count:
		_validation_errors.append("TrackGeometry positions_x length must match sample_count.")
	if _data.positions_y.size() != _data.sample_count:
		_validation_errors.append("TrackGeometry positions_y length must match sample_count.")

	if _validation_errors.is_empty():
		_is_valid = true
