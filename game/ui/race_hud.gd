extends Control
class_name RaceHud

signal pause_toggled(is_paused: bool)
signal reset_requested()
signal speed_selected(speed_scale: float)

const RaceTypes = preload("res://sim/src/race_types.gd")
const StandingsCalculator = preload("res://sim/src/standings_calculator.gd")

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
	set_status_message(_build_state_message(snapshot, time_scale))

	var cars_sorted: Array[RaceTypes.CarState] = _sort_cars_for_board(snapshot.cars)
	var interval_map: Dictionary = StandingsCalculator.compute_interval_to_car_ahead(snapshot.cars)
	var winner_finish_time: float = _get_winner_finish_time(snapshot)

	_sync_rows(cars_sorted)
	for car in cars_sorted:
		var row: Dictionary = _row_labels.get(car.id, {})
		if row.is_empty():
			continue
		row["position"].text = _format_position_cell(car)
		row["id"].text = car.id
		row["speed"].text = _format_speed(car.effective_speed_units_per_sec, car.is_held_up)
		row["lap_count"].text = str(car.lap_count)
		row["gap"].text = _format_gap(
			interval_map.get(car.id, 0.0),
			car.effective_speed_units_per_sec,
			car,
			winner_finish_time
		)
		row["degradation"].text = _format_degradation(car.degradation_multiplier)
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
	var position_label := _create_grid_label()
	var id_label := _create_grid_label()
	var speed_label := _create_grid_label()
	var lap_count_label := _create_grid_label()
	var gap_label := _create_grid_label()
	var degradation_label := _create_grid_label()
	var current_lap_label := _create_grid_label()
	var last_lap_label := _create_grid_label()
	var best_lap_label := _create_grid_label()

	_body_grid.add_child(position_label)
	_body_grid.add_child(id_label)
	_body_grid.add_child(speed_label)
	_body_grid.add_child(lap_count_label)
	_body_grid.add_child(gap_label)
	_body_grid.add_child(degradation_label)
	_body_grid.add_child(current_lap_label)
	_body_grid.add_child(last_lap_label)
	_body_grid.add_child(best_lap_label)

	return {
		"position": position_label,
		"id": id_label,
		"speed": speed_label,
		"lap_count": lap_count_label,
		"gap": gap_label,
		"degradation": degradation_label,
		"current_lap": current_lap_label,
		"last_lap": last_lap_label,
		"best_lap": best_lap_label,
		"cells": [position_label, id_label, speed_label, lap_count_label, gap_label, degradation_label, current_lap_label, last_lap_label, best_lap_label]
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


func _format_speed(speed_units_per_sec: float, is_held_up: bool) -> String:
	var suffix: String = " [H]" if is_held_up else ""
	return "%.1f u/s%s" % [speed_units_per_sec, suffix]


func _format_degradation(multiplier: float) -> String:
	return "%d%%" % int(round(multiplier * 100.0))


func _format_gap(
	interval_distance: float,
	speed_units_per_sec: float,
	car: RaceTypes.CarState,
	winner_finish_time: float
) -> String:
	if car != null and car.is_finished:
		var finish_prefix: String = "F%d" % car.finish_position if car.finish_position > 0 else "--"
		if car.finish_position <= 1:
			return finish_prefix
		if winner_finish_time < 0.0 or car.finish_time < 0.0:
			return finish_prefix
		var delta: float = maxf(car.finish_time - winner_finish_time, 0.0)
		return "%s +%.3fs" % [finish_prefix, delta]

	if car == null or car.position <= 1:
		return "Leader"
	if speed_units_per_sec <= 0.0:
		return "--"
	return "%.3f s" % (interval_distance / speed_units_per_sec)


func _sort_cars_for_board(cars: Array) -> Array[RaceTypes.CarState]:
	var typed_cars: Array[RaceTypes.CarState] = []
	for raw_car in cars:
		var car: RaceTypes.CarState = raw_car as RaceTypes.CarState
		if car != null:
			typed_cars.append(car)

	typed_cars.sort_custom(func(a: RaceTypes.CarState, b: RaceTypes.CarState) -> bool:
		var a_board_position: int = a.finish_position if a.is_finished and a.finish_position > 0 else a.position
		var b_board_position: int = b.finish_position if b.is_finished and b.finish_position > 0 else b.position
		if a_board_position != b_board_position:
			return a_board_position < b_board_position
		return a.id < b.id
	)
	return typed_cars


func _build_state_message(snapshot: RaceTypes.RaceSnapshot, time_scale: float) -> String:
	var race_status: String = "Running"
	match snapshot.race_state:
		RaceTypes.RaceState.NOT_STARTED:
			race_status = "Not Started"
		RaceTypes.RaceState.RUNNING:
			if snapshot.total_laps > 0:
				var leader_lap: int = _get_leader_lap(snapshot.cars)
				race_status = "Running Lap %d/%d" % [min(leader_lap + 1, snapshot.total_laps), snapshot.total_laps]
			else:
				race_status = "Running"
		RaceTypes.RaceState.FINISHING:
			race_status = "Finishing..."
		RaceTypes.RaceState.FINISHED:
			race_status = "Race Over"

	return "%s%s | Time Scale %.1fx | Race Time %s" % [
		"Paused | " if _is_paused else "",
		race_status,
		time_scale,
		_format_time(snapshot.race_time)
	]


func _get_leader_lap(cars: Array) -> int:
	var leader_lap: int = 0
	for raw_car in cars:
		var car: RaceTypes.CarState = raw_car as RaceTypes.CarState
		if car == null:
			continue
		if car.position == 1:
			return car.lap_count
		leader_lap = max(leader_lap, car.lap_count)
	return leader_lap


func _format_position_cell(car: RaceTypes.CarState) -> String:
	if car == null:
		return "--"
	if car.is_finished and car.finish_position > 0:
		return "F%d" % car.finish_position
	return str(car.position)


func _get_winner_finish_time(snapshot: RaceTypes.RaceSnapshot) -> float:
	if snapshot.finish_order.is_empty():
		return -1.0

	var winner_id: String = snapshot.finish_order[0]
	for raw_car in snapshot.cars:
		var car: RaceTypes.CarState = raw_car as RaceTypes.CarState
		if car != null and car.id == winner_id:
			return car.finish_time
	return -1.0
