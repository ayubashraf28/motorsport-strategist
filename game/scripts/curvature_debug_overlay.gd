extends Node2D
class_name CurvatureDebugOverlay

const _LINE_WIDTH: float = 10.0

var _track_sampler: TrackSampler = null
var _track_length: float = 0.0
var _curvatures: PackedFloat64Array = PackedFloat64Array()
var _is_ready: bool = false


func configure(
	track_sampler: TrackSampler,
	track_length: float,
	curvatures: PackedFloat64Array
) -> void:
	_track_sampler = track_sampler
	_track_length = track_length
	_curvatures = curvatures.duplicate()
	_is_ready = _track_sampler != null and _track_sampler.is_valid() and _track_length > 0.0 and not _curvatures.is_empty()
	queue_redraw()


func _draw() -> void:
	if not visible or not _is_ready:
		return

	var sample_count: int = _curvatures.size()
	for i in range(sample_count):
		var d0: float = _track_length * float(i) / float(sample_count)
		var d1: float = _track_length * float(i + 1) / float(sample_count)
		var p0: Vector2 = _track_sampler.sample_position(d0)
		var p1: Vector2 = _track_sampler.sample_position(d1)
		var color: Color = _color_for_curvature(abs(_curvatures[i]))
		draw_line(p0, p1, color, _LINE_WIDTH, true)


func _color_for_curvature(abs_curvature: float) -> Color:
	if abs_curvature >= 0.01:
		return Color(0.92, 0.28, 0.24, 0.95)
	if abs_curvature >= 0.002:
		return Color(0.95, 0.79, 0.21, 0.95)
	return Color(0.30, 0.83, 0.36, 0.95)
