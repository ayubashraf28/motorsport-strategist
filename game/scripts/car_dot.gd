extends Node2D
class_name CarDot

@export var radius: float = 6.0
@export var dot_color: Color = Color(0.92, 0.29, 0.16, 1.0)

var car_id: String = ""
var _id_label: Label


func _ready() -> void:
	_id_label = Label.new()
	_id_label.name = "CarIdLabel"
	_id_label.position = Vector2(10.0, -24.0)
	_id_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(_id_label)
	_sync_label()
	queue_redraw()


func configure(id_value: String, color_value: Color, radius_value: float) -> void:
	car_id = id_value
	dot_color = color_value
	radius = maxf(radius_value, 2.0)
	_sync_label()
	queue_redraw()


func set_id_visible(visible_value: bool) -> void:
	if _id_label != null:
		_id_label.visible = visible_value


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, dot_color)
	draw_arc(Vector2.ZERO, radius + 1.5, 0.0, TAU, 16, Color(0.05, 0.05, 0.05, 0.8), 1.0)


func _sync_label() -> void:
	if _id_label != null:
		_id_label.text = car_id
