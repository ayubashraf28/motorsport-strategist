extends Control
class_name RaceHud

signal pause_toggled(is_paused: bool)
signal reset_requested()
signal speed_selected(speed_scale: float)

const RaceTypes = preload("res://sim/src/race_types.gd")

@onready var _state_label: Label = %StateLabel
@onready var _body_grid: GridContainer = %BodyGrid
@onready var _pause_button: Button = %PauseButton
@onready var _reset_button: Button = %ResetButton
@onready var _speed_1_button: Button = %Speed1Button
@onready var _speed_2_button: Button = %Speed2Button
@onready var _speed_4_button: Button = %Speed4Button

var _row_labels: Dictionary = {}
var _is_paused: bool = false


func _ready() -> void:
	_pause_button.pressed.connect(_on_pause_pressed)
	_reset_button.pressed.connect(_on_reset_pressed)
	_speed_1_button.pressed.connect(func() -> void: _on_speed_pressed(1.0))
	_speed_2_button.pressed.connect(func() -> void: _on_speed_pressed(2.0))
	_speed_4_button.pressed.connect(func() -> void: _on_speed_pressed(4.0))
	set_status_message("Ready")


func set_status_message(message: String) -> void:
	_state_label.text = message


func set_error(message: String) -> void:
	_state_label.text = "Error: %s" % message
	_pause_button.disabled = true
	_reset_button.disabled = true
	_speed_1_button.disabled = true
	_speed_2_button.disabled = true
	_speed_4_button.disabled = true


func set_empty(message: String) -> void:
	_state_label.text = message
	_pause_button.disabled = true
	_reset_button.disabled = true
	_speed_1_button.disabled = true
	_speed_2_button.disabled = true
	_speed_4_button.disabled = true


func render(snapshot: RaceTypes.RaceSnapshot, is_paused: bool, time_scale: float) -> void:
	if snapshot == null:
		return

	_is_paused = is_paused
	_pause_button.text = "Resume" if _is_paused else "Pause"
	set_status_message(
		"%s | Time Scale %.1fx | Race Time %s" % [
			"Paused" if _is_paused else "Running",
			time_scale,
			_format_time(snapshot.race_time)
		]
	)

	_sync_rows(snapshot.cars)
	for car in snapshot.cars:
		var row: Dictionary = _row_labels.get(car.id, {})
		if row.is_empty():
			continue
		row["id"].text = car.id
		row["speed"].text = _format_speed(car.effective_speed_units_per_sec)
		row["lap_count"].text = str(car.lap_count)
		row["current_lap"].text = _format_time(maxf(snapshot.race_time - car.lap_start_time, 0.0))
		row["last_lap"].text = _format_optional_time(car.last_lap_time)
		row["best_lap"].text = _format_optional_time(car.best_lap_time)


func _on_pause_pressed() -> void:
	_is_paused = not _is_paused
	emit_signal("pause_toggled", _is_paused)


func _on_reset_pressed() -> void:
	emit_signal("reset_requested")


func _on_speed_pressed(speed_scale: float) -> void:
	emit_signal("speed_selected", speed_scale)


func _sync_rows(cars: Array) -> void:
	var active_ids := {}
	for car in cars:
		active_ids[car.id] = true
		if not _row_labels.has(car.id):
			_row_labels[car.id] = _create_row()

	var ids_to_remove: Array[String] = []
	for existing_id in _row_labels.keys():
		if not active_ids.has(existing_id):
			ids_to_remove.append(existing_id)

	for obsolete_id in ids_to_remove:
		var obsolete_row: Dictionary = _row_labels[obsolete_id]
		var cells: Array = obsolete_row["cells"]
		for cell in cells:
			cell.queue_free()
		_row_labels.erase(obsolete_id)


func _create_row() -> Dictionary:
	var id_label := _create_grid_label()
	var speed_label := _create_grid_label()
	var lap_count_label := _create_grid_label()
	var current_lap_label := _create_grid_label()
	var last_lap_label := _create_grid_label()
	var best_lap_label := _create_grid_label()

	_body_grid.add_child(id_label)
	_body_grid.add_child(speed_label)
	_body_grid.add_child(lap_count_label)
	_body_grid.add_child(current_lap_label)
	_body_grid.add_child(last_lap_label)
	_body_grid.add_child(best_lap_label)

	return {
		"id": id_label,
		"speed": speed_label,
		"lap_count": lap_count_label,
		"current_lap": current_lap_label,
		"last_lap": last_lap_label,
		"best_lap": best_lap_label,
		"cells": [id_label, speed_label, lap_count_label, current_lap_label, last_lap_label, best_lap_label]
	}


func _create_grid_label() -> Label:
	var label := Label.new()
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return label


func _format_time(value_seconds: float) -> String:
	return "%.3f s" % value_seconds


func _format_optional_time(value_seconds: float) -> String:
	if value_seconds < 0.0 or is_inf(value_seconds):
		return "--"
	return "%.3f s" % value_seconds


func _format_speed(speed_units_per_sec: float) -> String:
	return "%.1f u/s" % speed_units_per_sec
