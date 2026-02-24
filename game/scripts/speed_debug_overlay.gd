extends Node2D
class_name SpeedDebugOverlay

const _LINE_WIDTH: float = 10.0

var _track_sampler: TrackSampler = null
var _track_length: float = 0.0
var _speed_profile: PackedFloat64Array = PackedFloat64Array()
var _v_top_speed: float = 0.0
var _is_ready: bool = false


func configure(
	track_sampler: TrackSampler,
	track_length: float,
	speed_profile: PackedFloat64Array,
	v_top_speed: float
) -> void:
	_track_sampler = track_sampler
	_track_length = track_length
	_speed_profile = speed_profile.duplicate()
	_v_top_speed = v_top_speed
	_is_ready = (
		_track_sampler != null and
		_track_sampler.is_valid() and
		_track_length > 0.0 and
		not _speed_profile.is_empty() and
		_v_top_speed > 0.0
	)
	queue_redraw()


func _draw() -> void:
	if not visible or not _is_ready:
		return

	var sample_count: int = _speed_profile.size()
	for i in range(sample_count):
		var d0: float = _track_length * float(i) / float(sample_count)
		var d1: float = _track_length * float(i + 1) / float(sample_count)
		var p0: Vector2 = _track_sampler.sample_position(d0)
		var p1: Vector2 = _track_sampler.sample_position(d1)
		var speed_ratio: float = _speed_profile[i] / _v_top_speed
		var color: Color = _color_for_speed_ratio(speed_ratio)
		draw_line(p0, p1, color, _LINE_WIDTH, true)


func _color_for_speed_ratio(ratio: float) -> Color:
	if ratio >= 0.90:
		return Color(0.30, 0.83, 0.36, 0.95)
	if ratio >= 0.70:
		return Color(0.95, 0.79, 0.21, 0.95)
	return Color(0.92, 0.28, 0.24, 0.95)
