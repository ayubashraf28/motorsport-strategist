extends Control
class_name RaceHud

signal pause_toggled(is_paused: bool)
signal reset_requested()
signal speed_selected(speed_scale: float)
signal pit_requested(car_id: String, compound: String, fuel_kg: float)
signal pit_cancelled(car_id: String)

const RaceTypes = preload("res://sim/src/race_types.gd")
const StandingsCalculator = preload("res://sim/src/standings_calculator.gd")

@onready var _state_label: Label = %StateLabel
@onready var _body_grid: GridContainer = %BodyGrid
@onready var _pause_button: Button = %PauseButton
@onready var _reset_button: Button = %ResetButton
@onready var _speed_1_button: Button = %Speed1Button
@onready var _speed_2_button: Button = %Speed2Button
@onready var _speed_4_button: Button = %Speed4Button
@onready var _header_compound: Label = %HeaderCompound
@onready var _header_stint: Label = %HeaderStint
@onready var _header_fuel: Label = %HeaderFuel

var _row_labels: Dictionary = {}
var _is_paused: bool = false
var _pit_enabled: bool = false
var _fuel_enabled: bool = false
var _available_compounds: PackedStringArray = PackedStringArray()
var _fuel_capacity_kg: float = 0.0


func _ready() -> void:
	_pause_button.pressed.connect(_on_pause_pressed)
	_reset_button.pressed.connect(_on_reset_pressed)
	_speed_1_button.pressed.connect(func() -> void: _on_speed_pressed(1.0))
	_speed_2_button.pressed.connect(func() -> void: _on_speed_pressed(2.0))
	_speed_4_button.pressed.connect(func() -> void: _on_speed_pressed(4.0))
	set_status_message("Ready")


func configure_strategy_ui(
	pit_enabled: bool,
	fuel_enabled: bool,
	compound_names: PackedStringArray,
	fuel_capacity_kg: float
) -> void:
	_pit_enabled = pit_enabled
	_fuel_enabled = fuel_enabled
	_available_compounds = compound_names.duplicate()
	_fuel_capacity_kg = fuel_capacity_kg

	_header_compound.visible = _pit_enabled
	_header_stint.visible = _pit_enabled
	_header_fuel.visible = _fuel_enabled

	for row in _row_labels.values():
		_apply_row_visibility(row)


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


func render(
	snapshot: RaceTypes.RaceSnapshot,
	is_paused: bool,
	time_scale: float,
	pending_pit_requests: Dictionary = {}
) -> void:
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
		var has_pending_pit: bool = pending_pit_requests.has(car.id)
		var pit_request: Dictionary = pending_pit_requests.get(car.id, {})

		row["position"].text = _format_position_cell(car)
		row["id"].text = _format_car_id(car.id, has_pending_pit)
		row["compound"].text = _format_compound(car.current_compound)
		row["speed"].text = _format_speed_cell(car)
		row["lap_count"].text = str(car.lap_count)
		row["stint"].text = str(car.stint_lap_count)
		row["gap"].text = _format_gap(
			interval_map.get(car.id, 0.0),
			car.effective_speed_units_per_sec,
			car,
			winner_finish_time
		)
		row["degradation"].text = _format_tyre(car)
		row["fuel"].text = _format_fuel(car.fuel_kg)
		row["current_lap"].text = _format_time(maxf(snapshot.race_time - car.lap_start_time, 0.0))
		row["last_lap"].text = _format_optional_time(car.last_lap_time)
		row["best_lap"].text = _format_optional_time(car.best_lap_time)

		var pit_button: Button = row["pit_button"]
		pit_button.visible = _pit_enabled and not car.is_finished
		pit_button.disabled = not _pit_enabled or car.is_finished
		pit_button.text = "CANCEL" if has_pending_pit else "PIT"
		pit_button.set_meta("car_id", car.id)
		pit_button.set_meta("pending", has_pending_pit)
		pit_button.set_meta("current_compound", _resolve_compound_for_request(car, pit_request))
		_apply_row_visibility(row)


func _on_pause_pressed() -> void:
	_is_paused = not _is_paused
	emit_signal("pause_toggled", _is_paused)


func _on_reset_pressed() -> void:
	emit_signal("reset_requested")


func _on_speed_pressed(speed_scale: float) -> void:
	emit_signal("speed_selected", speed_scale)


func _on_pit_button_pressed(pit_button: Button) -> void:
	if pit_button == null:
		return
	var car_id: String = String(pit_button.get_meta("car_id", "")).strip_edges()
	if car_id.is_empty():
		return
	if bool(pit_button.get_meta("pending", false)):
		emit_signal("pit_cancelled", car_id)
		return

	var current_compound: String = String(pit_button.get_meta("current_compound", ""))
	var target_compound: String = _get_next_compound(current_compound)
	emit_signal("pit_requested", car_id, target_compound, -1.0)


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
	var id_container := HBoxContainer.new()
	id_container.size_flags_horizontal = SIZE_EXPAND_FILL
	id_container.add_theme_constant_override("separation", 6)
	var id_label := _create_grid_label()
	id_label.size_flags_horizontal = SIZE_EXPAND_FILL
	var pit_button := Button.new()
	pit_button.text = "PIT"
	pit_button.focus_mode = Control.FOCUS_NONE
	pit_button.custom_minimum_size = Vector2(56, 0)
	pit_button.pressed.connect(func() -> void: _on_pit_button_pressed(pit_button))
	id_container.add_child(id_label)
	id_container.add_child(pit_button)

	var compound_label := _create_grid_label()
	var speed_label := _create_grid_label()
	var lap_count_label := _create_grid_label()
	var stint_label := _create_grid_label()
	var gap_label := _create_grid_label()
	var degradation_label := _create_grid_label()
	var fuel_label := _create_grid_label()
	var current_lap_label := _create_grid_label()
	var last_lap_label := _create_grid_label()
	var best_lap_label := _create_grid_label()

	_body_grid.add_child(position_label)
	_body_grid.add_child(id_container)
	_body_grid.add_child(compound_label)
	_body_grid.add_child(speed_label)
	_body_grid.add_child(lap_count_label)
	_body_grid.add_child(stint_label)
	_body_grid.add_child(gap_label)
	_body_grid.add_child(degradation_label)
	_body_grid.add_child(fuel_label)
	_body_grid.add_child(current_lap_label)
	_body_grid.add_child(last_lap_label)
	_body_grid.add_child(best_lap_label)

	var row := {
		"position": position_label,
		"id_container": id_container,
		"id": id_label,
		"pit_button": pit_button,
		"compound": compound_label,
		"speed": speed_label,
		"lap_count": lap_count_label,
		"stint": stint_label,
		"gap": gap_label,
		"degradation": degradation_label,
		"fuel": fuel_label,
		"current_lap": current_lap_label,
		"last_lap": last_lap_label,
		"best_lap": best_lap_label,
		"cells": [
			position_label,
			id_container,
			compound_label,
			speed_label,
			lap_count_label,
			stint_label,
			gap_label,
			degradation_label,
			fuel_label,
			current_lap_label,
			last_lap_label,
			best_lap_label
		]
	}
	_apply_row_visibility(row)
	return row


func _create_grid_label() -> Label:
	var label := Label.new()
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return label


func _apply_row_visibility(row: Dictionary) -> void:
	if row.is_empty():
		return
	row["compound"].visible = _pit_enabled
	row["stint"].visible = _pit_enabled
	row["fuel"].visible = _fuel_enabled
	var pit_button: Button = row["pit_button"]
	pit_button.visible = _pit_enabled and not pit_button.disabled


func _format_time(value_seconds: float) -> String:
	return "%.3f s" % value_seconds


func _format_optional_time(value_seconds: float) -> String:
	if value_seconds < 0.0 or is_inf(value_seconds):
		return "--"
	return "%.3f s" % value_seconds


func _format_speed(speed_units_per_sec: float, is_held_up: bool) -> String:
	var suffix: String = " [H]" if is_held_up else ""
	return "%.1f u/s%s" % [speed_units_per_sec, suffix]


func _format_speed_cell(car: RaceTypes.CarState) -> String:
	if car == null:
		return "--"
	if car.is_in_pit:
		if car.pit_phase == RaceTypes.PitPhase.STOPPED:
			return "BOX [%.1fs]" % maxf(car.pit_time_remaining, 0.0)
		return "IN PIT"
	var normalized_ratio: float = 1.0
	if car.reference_speed_units_per_sec > 0.0:
		normalized_ratio = car.effective_speed_units_per_sec / car.reference_speed_units_per_sec
	var normalized_pct: int = int(round(clampf(normalized_ratio, 0.0, 2.0) * 100.0))
	var held_up_suffix: String = " [H]" if car.is_held_up else ""
	return "%.1f u/s | N%d%%%s" % [car.effective_speed_units_per_sec, normalized_pct, held_up_suffix]


func _format_tyre(car: RaceTypes.CarState) -> String:
	if car == null:
		return "--"
	var life_pct: int = int(round(clampf(car.tyre_life_ratio, 0.0, 1.0) * 100.0))
	return "%d%% %s" % [life_pct, _format_tyre_phase(car.tyre_phase)]


func _format_tyre_phase(phase: int) -> String:
	match phase:
		RaceTypes.TyrePhase.OPTIMAL:
			return "OPTIMAL"
		RaceTypes.TyrePhase.GRADUAL:
			return "GRADUAL"
		RaceTypes.TyrePhase.CLIFF:
			return "CLIFF"
	return "OPTIMAL"


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


func _format_car_id(car_id: String, has_pending_pit: bool) -> String:
	return "%s [PIT]" % car_id if has_pending_pit else car_id


func _format_compound(compound_name: String) -> String:
	if not _pit_enabled:
		return "--"
	var clean_name: String = compound_name.strip_edges().to_upper()
	if clean_name.is_empty():
		return "--"
	if clean_name == "SOFT" or clean_name == "MEDIUM" or clean_name == "HARD":
		return clean_name.substr(0, 1)
	if clean_name.length() > 3:
		return clean_name.substr(0, 3)
	return clean_name.substr(0, 1)


func _format_fuel(fuel_kg: float) -> String:
	if not _fuel_enabled or _fuel_capacity_kg <= 0.0:
		return "--"
	if fuel_kg <= 0.0:
		return "EMPTY"
	var pct: int = int(round(clampf(fuel_kg / _fuel_capacity_kg, 0.0, 1.0) * 100.0))
	return "%d%%" % pct


func _resolve_compound_for_request(car: RaceTypes.CarState, pit_request: Dictionary) -> String:
	if pit_request.is_empty():
		return car.current_compound if car != null else ""
	var requested: String = String(pit_request.get("compound", "")).strip_edges()
	if requested.is_empty():
		return car.current_compound if car != null else ""
	return requested


func _get_next_compound(current_compound: String) -> String:
	if _available_compounds.is_empty():
		return ""
	var current: String = current_compound.strip_edges().to_lower()
	for index in range(_available_compounds.size()):
		if _available_compounds[index].to_lower() == current:
			return _available_compounds[(index + 1) % _available_compounds.size()]
	return _available_compounds[0]
