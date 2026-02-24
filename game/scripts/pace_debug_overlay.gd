extends Node2D
class_name PaceDebugOverlay

const RaceTypes = preload("res://sim/src/race_types.gd")

const _BASE_LINE_WIDTH: float = 10.0
const _BLEND_MARKER_WIDTH: float = 2.0

var _track_sampler: TrackSampler
var _track_length: float = 0.0
var _blend_distance: float = 0.0
var _segments: Array[RaceTypes.PaceSegmentConfig] = []
var _is_ready: bool = false


func configure(
	track_sampler: TrackSampler,
	track_length: float,
	blend_distance: float,
	segments: Array[RaceTypes.PaceSegmentConfig]
) -> void:
	_track_sampler = track_sampler
	_track_length = track_length
	_blend_distance = blend_distance
	_segments.clear()
	for segment in segments:
		_segments.append(segment.clone())

	_is_ready = _track_sampler != null and _track_sampler.is_valid() and _track_length > 0.0 and not _segments.is_empty()
	queue_redraw()


func _draw() -> void:
	if not visible or not _is_ready:
		return

	_draw_segment_colors()
	_draw_blend_markers()


func _draw_segment_colors() -> void:
	var sample_count: int = maxi(120, int(_track_length / 8.0))
	for i in range(sample_count):
		var d0: float = _track_length * float(i) / float(sample_count)
		var d1: float = _track_length * float(i + 1) / float(sample_count)
		var p0: Vector2 = _track_sampler.sample_position(d0)
		var p1: Vector2 = _track_sampler.sample_position(d1)
		var multiplier: float = _base_multiplier_for_distance(d0)
		draw_line(p0, p1, _color_for_multiplier(multiplier), _BASE_LINE_WIDTH, true)


func _draw_blend_markers() -> void:
	if _blend_distance <= 0.0:
		return

	var half_window: float = _blend_distance * 0.5
	for segment in _segments:
		var boundary_distance: float = segment.start_distance
		var boundary_position: Vector2 = _track_sampler.sample_position(boundary_distance)
		draw_circle(boundary_position, 4.0, Color(0.98, 0.98, 0.98, 0.9))

		var start_distance: float = boundary_distance - half_window
		var end_distance: float = boundary_distance + half_window
		_draw_window_tick(start_distance, Color(0.40, 0.93, 1.0, 0.95))
		_draw_window_tick(end_distance, Color(0.40, 0.93, 1.0, 0.95))


func _draw_window_tick(distance_along_track: float, color: Color) -> void:
	var position_on_track: Vector2 = _track_sampler.sample_position(distance_along_track)
	var tangent: Vector2 = _track_sampler.sample_tangent(distance_along_track)
	var normal: Vector2 = Vector2(-tangent.y, tangent.x).normalized()
	var half_length: float = 8.0
	var start_point: Vector2 = position_on_track - normal * half_length
	var end_point: Vector2 = position_on_track + normal * half_length
	draw_line(start_point, end_point, color, _BLEND_MARKER_WIDTH, true)


func _base_multiplier_for_distance(distance_along_track: float) -> float:
	var wrapped_distance: float = fposmod(distance_along_track, _track_length)
	for i in range(_segments.size()):
		var segment: RaceTypes.PaceSegmentConfig = _segments[i]
		var is_last_segment: bool = i == _segments.size() - 1
		if wrapped_distance >= segment.start_distance and wrapped_distance < segment.end_distance:
			return segment.multiplier
		if is_last_segment and is_equal_approx(wrapped_distance, segment.end_distance):
			return segment.multiplier
	return 1.0


func _color_for_multiplier(multiplier: float) -> Color:
	if multiplier <= 0.80:
		return Color(0.93, 0.33, 0.22, 0.95)
	if multiplier <= 0.90:
		return Color(0.95, 0.60, 0.18, 0.95)
	if multiplier < 1.0:
		return Color(0.97, 0.83, 0.20, 0.95)
	return Color(0.30, 0.83, 0.36, 0.95)
