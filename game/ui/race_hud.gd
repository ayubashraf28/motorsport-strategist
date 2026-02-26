extends Control
class_name RaceHud

signal pause_toggled(is_paused: bool)
signal reset_requested()
signal speed_selected(speed_scale: float)
signal pit_requested(car_id: String, compound: String, fuel_kg: float)
signal pit_cancelled(car_id: String)
signal driver_mode_requested(car_id: String, mode: int)
signal continue_requested()
signal main_menu_requested()

const RaceTypes = preload("res://sim/src/race_types.gd")
const StandingsCalculator = preload("res://sim/src/standings_calculator.gd")
const DriverModeModule = preload("res://sim/src/driver_mode.gd")

enum DataMode { INTERVAL, LAST_LAP, TYRE, FUEL }

const DATA_MODE_LABELS := {
	DataMode.INTERVAL: "INTERVAL",
	DataMode.LAST_LAP: "LAST LAP",
	DataMode.TYRE: "TYRE",
	DataMode.FUEL: "FUEL",
}

const COMPOUND_COLORS := {
	"S": Color(0.95, 0.25, 0.25),
	"M": Color(0.95, 0.85, 0.15),
	"H": Color(0.85, 0.85, 0.85),
}
const MODE_COLORS := {
	DriverModeModule.Mode.PUSH: Color(0.95, 0.3, 0.3),
	DriverModeModule.Mode.STANDARD: Color(0.65, 0.65, 0.7),
	DriverModeModule.Mode.CONSERVE: Color(0.3, 0.7, 0.95),
}
const DEFAULT_CAR_COLOR := Color(0.7, 0.7, 0.7)
const ROW_HEIGHT: int = 22
const FONT_SIZE_ROW: int = 11
const PANEL_BG_COLOR := Color(0.08, 0.09, 0.12, 0.88)
const PANEL_CORNER_RADIUS: int = 6
const BAR_BG_COLOR := Color(0.08, 0.09, 0.12, 0.82)

@onready var _timing_tower: PanelContainer = %TimingTower
@onready var _bottom_bar: PanelContainer = %BottomBar
@onready var _row_container: VBoxContainer = %RowContainer
@onready var _state_label: Label = %StateLabel
@onready var _pause_button: Button = %PauseButton
@onready var _reset_button: Button = %ResetButton
@onready var _speed_1_button: Button = %Speed1Button
@onready var _speed_2_button: Button = %Speed2Button
@onready var _speed_4_button: Button = %Speed4Button
@onready var _prev_mode_button: Button = %PrevModeButton
@onready var _next_mode_button: Button = %NextModeButton
@onready var _mode_label: Label = %ModeLabel

var _row_widgets: Dictionary = {}
var _is_paused: bool = false
var _pit_enabled: bool = false
var _fuel_enabled: bool = false
var _available_compounds: PackedStringArray = PackedStringArray()
var _fuel_capacity_kg: float = 0.0
var _car_colors: Dictionary = {}
var _continue_button: Button = null
var _menu_button: Button = null
var _data_mode: DataMode = DataMode.INTERVAL
var _available_modes: Array[DataMode] = []

# Radio message panel
var _radio_panel: PanelContainer = null
var _radio_vbox: VBoxContainer = null
var _radio_messages: Array = []  # Array of { label: Label, expire_time: float }
const RADIO_MAX_MESSAGES: int = 4
const RADIO_MESSAGE_DURATION: float = 6.0
const RADIO_PANEL_WIDTH: float = 260.0


func _ready() -> void:
	_style_panels()
	_pause_button.pressed.connect(_on_pause_pressed)
	_reset_button.pressed.connect(_on_reset_pressed)
	_speed_1_button.pressed.connect(func() -> void: _on_speed_pressed(1.0))
	_speed_2_button.pressed.connect(func() -> void: _on_speed_pressed(2.0))
	_speed_4_button.pressed.connect(func() -> void: _on_speed_pressed(4.0))
	_prev_mode_button.pressed.connect(_on_prev_mode)
	_next_mode_button.pressed.connect(_on_next_mode)
	_create_post_race_buttons()
	_create_radio_panel()
	_rebuild_available_modes()
	_apply_mode_label()
	set_status_message("Ready")


func _style_panels() -> void:
	var tower_style := StyleBoxFlat.new()
	tower_style.bg_color = PANEL_BG_COLOR
	tower_style.corner_radius_top_left = PANEL_CORNER_RADIUS
	tower_style.corner_radius_top_right = PANEL_CORNER_RADIUS
	tower_style.corner_radius_bottom_left = PANEL_CORNER_RADIUS
	tower_style.corner_radius_bottom_right = PANEL_CORNER_RADIUS
	tower_style.content_margin_left = 6
	tower_style.content_margin_right = 6
	tower_style.content_margin_top = 6
	tower_style.content_margin_bottom = 6
	_timing_tower.add_theme_stylebox_override("panel", tower_style)

	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = BAR_BG_COLOR
	bar_style.content_margin_left = 12
	bar_style.content_margin_right = 12
	bar_style.content_margin_top = 6
	bar_style.content_margin_bottom = 6
	_bottom_bar.add_theme_stylebox_override("panel", bar_style)


func _create_post_race_buttons() -> void:
	var controls_row: HBoxContainer = _pause_button.get_parent() as HBoxContainer
	if controls_row == null:
		return
	_continue_button = Button.new()
	_continue_button.text = "Results"
	_continue_button.focus_mode = Control.FOCUS_NONE
	_continue_button.visible = false
	_continue_button.pressed.connect(func() -> void: emit_signal("continue_requested"))
	controls_row.add_child(_continue_button)

	_menu_button = Button.new()
	_menu_button.text = "Main Menu"
	_menu_button.focus_mode = Control.FOCUS_NONE
	_menu_button.visible = false
	_menu_button.pressed.connect(func() -> void: emit_signal("main_menu_requested"))
	controls_row.add_child(_menu_button)


func show_continue_button() -> void:
	if _continue_button != null:
		_continue_button.visible = true
	if _menu_button != null:
		_menu_button.visible = true


func hide_continue_button() -> void:
	if _continue_button != null:
		_continue_button.visible = false
	if _menu_button != null:
		_menu_button.visible = false


func set_car_colors(colors: Dictionary) -> void:
	_car_colors = colors


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
	_rebuild_available_modes()
	_apply_mode_label()


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
		var row: Dictionary = _row_widgets.get(car.id, {})
		if row.is_empty():
			continue
		var has_pending_pit: bool = pending_pit_requests.has(car.id)
		var pit_request: Dictionary = pending_pit_requests.get(car.id, {})

		# Position
		row["position"].text = _format_position(car)

		# Driver name with team color
		var driver_label: Label = row["driver"]
		driver_label.text = _format_driver_id(car.id, has_pending_pit)
		var team_color: Color = _car_colors.get(car.id, DEFAULT_CAR_COLOR)
		driver_label.add_theme_color_override("font_color", team_color)

		# Team color bar
		row["color_bar"].color = team_color

		# Data value — changes based on current mode
		var data_label: Label = row["data"]
		_render_data_cell(data_label, car, interval_map, winner_finish_time)

		# DRS indicator
		var drs_label: Label = row["drs_label"]
		if car.drs_active:
			drs_label.text = "DRS"
			drs_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.2))
		elif car.drs_eligible:
			drs_label.text = "DRS"
			drs_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		else:
			drs_label.text = ""

		# Driver mode indicator
		var mode_indicator: Label = row["mode_label"]
		mode_indicator.text = DriverModeModule.get_mode_short(car.driver_mode)
		mode_indicator.add_theme_color_override("font_color",
			MODE_COLORS.get(car.driver_mode, Color(0.65, 0.65, 0.7)))

		# Driver mode button
		var mode_btn: Button = row["mode_button"]
		mode_btn.visible = not car.is_finished
		mode_btn.set_meta("car_id", car.id)
		mode_btn.set_meta("current_mode", car.driver_mode)

		# Pit button
		var pit_button: Button = row["pit_button"]
		pit_button.visible = _pit_enabled and not car.is_finished
		pit_button.text = "X" if has_pending_pit else "P"
		pit_button.set_meta("car_id", car.id)
		pit_button.set_meta("pending", has_pending_pit)
		pit_button.set_meta("current_compound", _resolve_compound_for_request(car, pit_request))

		# Row container order matches board position
		var row_hbox: HBoxContainer = row["container"]
		_row_container.move_child(row_hbox, cars_sorted.find(car))


# --- Data Mode Cycling ---

func _rebuild_available_modes() -> void:
	_available_modes.clear()
	_available_modes.append(DataMode.INTERVAL)
	_available_modes.append(DataMode.LAST_LAP)
	if _pit_enabled:
		_available_modes.append(DataMode.TYRE)
	if _fuel_enabled:
		_available_modes.append(DataMode.FUEL)
	if _available_modes.find(_data_mode) < 0:
		_data_mode = DataMode.INTERVAL


func _apply_mode_label() -> void:
	_mode_label.text = DATA_MODE_LABELS.get(_data_mode, "INTERVAL")


func _on_prev_mode() -> void:
	var idx: int = _available_modes.find(_data_mode)
	idx = (idx - 1) if idx > 0 else (_available_modes.size() - 1)
	_data_mode = _available_modes[idx]
	_apply_mode_label()


func _on_next_mode() -> void:
	var idx: int = _available_modes.find(_data_mode)
	idx = (idx + 1) % _available_modes.size()
	_data_mode = _available_modes[idx]
	_apply_mode_label()


func _render_data_cell(
	label: Label,
	car: RaceTypes.CarState,
	interval_map: Dictionary,
	winner_finish_time: float
) -> void:
	match _data_mode:
		DataMode.INTERVAL:
			label.text = _format_gap(
				interval_map.get(car.id, 0.0),
				car.effective_speed_units_per_sec,
				car,
				winner_finish_time
			)
			label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
		DataMode.LAST_LAP:
			label.text = _format_lap_time(car.last_lap_time)
			label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
		DataMode.TYRE:
			var compound_char: String = _get_compound_char(car.current_compound)
			var life_pct: int = int(clampf(car.tyre_life_ratio, 0.0, 1.0) * 100.0)
			label.text = "%s %d%%" % [compound_char, life_pct]
			label.add_theme_color_override("font_color", COMPOUND_COLORS.get(compound_char, Color.WHITE))
		DataMode.FUEL:
			label.text = "%.1f kg" % car.fuel_kg
			var fuel_color: Color
			if _fuel_capacity_kg > 0.0 and car.fuel_kg / _fuel_capacity_kg < 0.15:
				fuel_color = Color(0.9, 0.3, 0.3)
			else:
				fuel_color = Color(0.75, 0.75, 0.8)
			label.add_theme_color_override("font_color", fuel_color)


# --- UI Signal Handlers ---

func _on_pause_pressed() -> void:
	_is_paused = not _is_paused
	emit_signal("pause_toggled", _is_paused)


func _on_reset_pressed() -> void:
	emit_signal("reset_requested")


func _on_speed_pressed(speed_scale: float) -> void:
	emit_signal("speed_selected", speed_scale)


func _on_mode_button_pressed(mode_button: Button) -> void:
	if mode_button == null:
		return
	var car_id: String = String(mode_button.get_meta("car_id", "")).strip_edges()
	if car_id.is_empty():
		return
	var current_mode: int = int(mode_button.get_meta("current_mode", DriverModeModule.Mode.STANDARD))
	var next_mode: int = _cycle_driver_mode(current_mode)
	emit_signal("driver_mode_requested", car_id, next_mode)


func _cycle_driver_mode(current: int) -> int:
	match current:
		DriverModeModule.Mode.STANDARD:
			return DriverModeModule.Mode.PUSH
		DriverModeModule.Mode.PUSH:
			return DriverModeModule.Mode.CONSERVE
		DriverModeModule.Mode.CONSERVE:
			return DriverModeModule.Mode.STANDARD
		_:
			return DriverModeModule.Mode.STANDARD


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


# --- Row Management ---

func _sync_rows(cars: Array) -> void:
	var active_ids := {}
	for car in cars:
		active_ids[car.id] = true
		if not _row_widgets.has(car.id):
			_row_widgets[car.id] = _create_row()

	var ids_to_remove: Array[String] = []
	for existing_id in _row_widgets.keys():
		if not active_ids.has(existing_id):
			ids_to_remove.append(existing_id)

	for obsolete_id in ids_to_remove:
		var obsolete_row: Dictionary = _row_widgets[obsolete_id]
		var container: HBoxContainer = obsolete_row["container"]
		container.queue_free()
		_row_widgets.erase(obsolete_id)

	_fit_tower_height(cars.size())


func _fit_tower_height(car_count: int) -> void:
	# Header (22) + separator (~4) + rows + padding (12 top+bottom)
	var needed: float = 22.0 + 4.0 + car_count * (ROW_HEIGHT + 2.0) + 12.0
	_timing_tower.offset_bottom = _timing_tower.offset_top + needed


func _create_row() -> Dictionary:
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	hbox.add_theme_constant_override("separation", 3)

	# Position label (narrow, centered)
	var pos_label := Label.new()
	pos_label.custom_minimum_size = Vector2(24, 0)
	pos_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pos_label.add_theme_font_size_override("font_size", FONT_SIZE_ROW)
	pos_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
	hbox.add_child(pos_label)

	# Team color bar (thin vertical stripe)
	var color_bar := ColorRect.new()
	color_bar.custom_minimum_size = Vector2(3, 0)
	color_bar.size_flags_vertical = SIZE_EXPAND_FILL
	color_bar.color = DEFAULT_CAR_COLOR
	hbox.add_child(color_bar)

	# Driver code label (expand to fill)
	var driver_label := Label.new()
	driver_label.size_flags_horizontal = SIZE_EXPAND_FILL
	driver_label.add_theme_font_size_override("font_size", FONT_SIZE_ROW)
	driver_label.clip_text = true
	hbox.add_child(driver_label)

	# Single data value (right-aligned, fixed width)
	var data_label := Label.new()
	data_label.custom_minimum_size = Vector2(68, 0)
	data_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	data_label.add_theme_font_size_override("font_size", FONT_SIZE_ROW)
	data_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	hbox.add_child(data_label)

	# DRS indicator (small label)
	var drs_label := Label.new()
	drs_label.custom_minimum_size = Vector2(28, 0)
	drs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drs_label.add_theme_font_size_override("font_size", 9)
	drs_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hbox.add_child(drs_label)

	# Driver mode indicator (small label)
	var mode_label := Label.new()
	mode_label.custom_minimum_size = Vector2(14, 0)
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_label.add_theme_font_size_override("font_size", 9)
	mode_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
	mode_label.text = "S"
	hbox.add_child(mode_label)

	# Driver mode cycle button
	var mode_button := Button.new()
	mode_button.text = "M"
	mode_button.focus_mode = Control.FOCUS_NONE
	mode_button.custom_minimum_size = Vector2(22, 18)
	mode_button.add_theme_font_size_override("font_size", 9)
	mode_button.pressed.connect(func() -> void: _on_mode_button_pressed(mode_button))
	hbox.add_child(mode_button)

	# Pit button (small)
	var pit_button := Button.new()
	pit_button.text = "P"
	pit_button.focus_mode = Control.FOCUS_NONE
	pit_button.custom_minimum_size = Vector2(22, 18)
	pit_button.add_theme_font_size_override("font_size", 9)
	pit_button.visible = false
	pit_button.pressed.connect(func() -> void: _on_pit_button_pressed(pit_button))
	hbox.add_child(pit_button)

	_row_container.add_child(hbox)

	return {
		"container": hbox,
		"position": pos_label,
		"color_bar": color_bar,
		"driver": driver_label,
		"data": data_label,
		"drs_label": drs_label,
		"mode_label": mode_label,
		"mode_button": mode_button,
		"pit_button": pit_button,
	}


# --- Formatting Helpers ---

func _format_position(car: RaceTypes.CarState) -> String:
	if car == null:
		return "--"
	if car.is_finished and car.finish_position > 0:
		return str(car.finish_position)
	return str(car.position)


func _format_driver_id(car_id: String, has_pending_pit: bool) -> String:
	if has_pending_pit:
		return "%s PIT" % car_id
	return car_id


func _get_compound_char(compound_name: String) -> String:
	var clean: String = compound_name.strip_edges().to_upper()
	if clean.is_empty():
		return "-"
	return clean.substr(0, 1)


func _format_gap(
	interval_distance: float,
	speed_units_per_sec: float,
	car: RaceTypes.CarState,
	winner_finish_time: float
) -> String:
	if car != null and car.is_finished:
		if car.finish_position <= 1:
			return "FIN"
		if winner_finish_time < 0.0 or car.finish_time < 0.0:
			return "FIN"
		var delta: float = maxf(car.finish_time - winner_finish_time, 0.0)
		return "+%.1fs" % delta

	if car == null or car.position <= 1:
		return "Leader"
	if car.is_in_pit:
		return "PIT"
	if speed_units_per_sec <= 0.0:
		return "--"
	var gap_seconds: float = interval_distance / speed_units_per_sec
	if gap_seconds < 1.0:
		return "+%.2f" % gap_seconds
	return "+%.1f" % gap_seconds


func _format_lap_time(lap_time: float) -> String:
	if lap_time < 0.0:
		return "--"
	var minutes: int = int(lap_time) / 60
	var seconds: float = fmod(lap_time, 60.0)
	if minutes > 0:
		return "%d:%05.2f" % [minutes, seconds]
	return "%.2f" % seconds


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


# --- State Message ---

func _build_state_message(snapshot: RaceTypes.RaceSnapshot, time_scale: float) -> String:
	var race_status: String = "Running"
	match snapshot.race_state:
		RaceTypes.RaceState.NOT_STARTED:
			race_status = "Not Started"
		RaceTypes.RaceState.RUNNING:
			if snapshot.total_laps > 0:
				var leader_lap: int = _get_leader_lap(snapshot.cars)
				race_status = "Lap %d/%d" % [min(leader_lap + 1, snapshot.total_laps), snapshot.total_laps]
			else:
				race_status = "Running"
		RaceTypes.RaceState.FINISHING:
			race_status = "Finishing..."
		RaceTypes.RaceState.FINISHED:
			race_status = "Race Over"

	return "%s%s | %.0fx | %s" % [
		"PAUSED | " if _is_paused else "",
		race_status,
		time_scale,
		_format_race_time(snapshot.race_time)
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


func _format_race_time(value_seconds: float) -> String:
	var minutes: int = int(value_seconds) / 60
	var seconds: float = fmod(value_seconds, 60.0)
	return "%d:%05.2f" % [minutes, seconds]


func _sort_cars_for_board(cars: Array) -> Array[RaceTypes.CarState]:
	var typed_cars: Array[RaceTypes.CarState] = []
	for raw_car in cars:
		var car: RaceTypes.CarState = raw_car as RaceTypes.CarState
		if car != null:
			typed_cars.append(car)

	typed_cars.sort_custom(func(a: RaceTypes.CarState, b: RaceTypes.CarState) -> bool:
		var a_pos: int = a.finish_position if a.is_finished and a.finish_position > 0 else a.position
		var b_pos: int = b.finish_position if b.is_finished and b.finish_position > 0 else b.position
		if a_pos != b_pos:
			return a_pos < b_pos
		return a.id < b.id
	)
	return typed_cars


func _get_winner_finish_time(snapshot: RaceTypes.RaceSnapshot) -> float:
	if snapshot.finish_order.is_empty():
		return -1.0

	var winner_id: String = snapshot.finish_order[0]
	for raw_car in snapshot.cars:
		var car: RaceTypes.CarState = raw_car as RaceTypes.CarState
		if car != null and car.id == winner_id:
			return car.finish_time
	return -1.0


# --- Radio Message Panel ---

func _create_radio_panel() -> void:
	_radio_panel = PanelContainer.new()
	_radio_panel.layout_mode = 1
	_radio_panel.anchors_preset = 0
	_radio_panel.offset_left = 1600.0 - RADIO_PANEL_WIDTH - 10.0
	_radio_panel.offset_top = 10.0
	_radio_panel.offset_right = 1600.0 - 10.0
	_radio_panel.offset_bottom = 200.0
	_radio_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.14, 0.85)
	style.corner_radius_top_left = PANEL_CORNER_RADIUS
	style.corner_radius_top_right = PANEL_CORNER_RADIUS
	style.corner_radius_bottom_left = PANEL_CORNER_RADIUS
	style.corner_radius_bottom_right = PANEL_CORNER_RADIUS
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	_radio_panel.add_theme_stylebox_override("panel", style)

	_radio_vbox = VBoxContainer.new()
	_radio_vbox.add_theme_constant_override("separation", 4)
	_radio_panel.add_child(_radio_vbox)

	# Header
	var header := Label.new()
	header.text = "RADIO"
	header.add_theme_font_size_override("font_size", 10)
	header.add_theme_color_override("font_color", Color(0.5, 0.6, 0.8))
	_radio_vbox.add_child(header)

	add_child(_radio_panel)
	_radio_panel.visible = false


func show_radio_messages(messages: Array, race_time: float) -> void:
	if _radio_vbox == null:
		return

	# Remove expired messages
	var i: int = _radio_messages.size() - 1
	while i >= 0:
		var entry: Dictionary = _radio_messages[i]
		if race_time > float(entry["expire_time"]):
			var lbl: Label = entry["label"] as Label
			if lbl != null:
				lbl.queue_free()
			_radio_messages.remove_at(i)
		i -= 1

	# Add new messages (limit to avoid overflow)
	for msg in messages:
		if _radio_messages.size() >= RADIO_MAX_MESSAGES:
			# Remove oldest
			var oldest: Dictionary = _radio_messages[0]
			var old_lbl: Label = oldest["label"] as Label
			if old_lbl != null:
				old_lbl.queue_free()
			_radio_messages.remove_at(0)

		var label := Label.new()
		label.text = String(msg["text"])
		label.add_theme_font_size_override("font_size", 10)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(RADIO_PANEL_WIDTH - 20, 0)

		# Color by priority
		var priority: int = int(msg.get("priority", 0))
		match priority:
			2:  # HIGH
				label.add_theme_color_override("font_color", Color(0.95, 0.3, 0.3))
			1:  # MEDIUM
				label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.2))
			_:  # LOW
				label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))

		_radio_vbox.add_child(label)
		_radio_messages.append({
			"label": label,
			"expire_time": race_time + RADIO_MESSAGE_DURATION,
		})

	# Show/hide panel based on whether there are messages
	_radio_panel.visible = not _radio_messages.is_empty()

	# Resize panel height to fit content
	if _radio_panel.visible:
		var needed: float = 28.0 + _radio_messages.size() * 22.0
		_radio_panel.offset_bottom = _radio_panel.offset_top + needed
