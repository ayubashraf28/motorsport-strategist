extends Control

const TeamRegistry = preload("res://scripts/team_registry.gd")

@onready var _track_list: ItemList = %TrackList
@onready var _laps_spinbox: SpinBox = %LapsSpinBox
@onready var _fuel_toggle: CheckButton = %FuelToggle
@onready var _player_team_option: OptionButton = %PlayerTeamOption
@onready var _teams_grid: GridContainer = %TeamsGrid
@onready var _start_button: Button = %StartButton
@onready var _back_button: Button = %BackButton
@onready var _status_label: Label = %StatusLabel

var _track_ids: Array = []


func _ready() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_track_list.item_selected.connect(_on_track_selected)

	_populate_tracks()
	_populate_player_team_option()
	_populate_teams()
	_fuel_toggle.button_pressed = true


func _populate_tracks() -> void:
	_track_list.clear()
	_track_ids.clear()

	var game_state: Node = get_node_or_null("/root/GameState")
	if game_state == null:
		_status_label.text = "Error: GameState not found."
		return

	for entry in game_state.track_list:
		var track_id: String = entry.get("id", "")
		var display_name: String = entry.get("display_name", track_id)
		var country: String = entry.get("country", "")
		var label: String = "%s  -  %s" % [display_name, country] if not country.is_empty() else display_name
		_track_list.add_item(label)
		_track_ids.append(track_id)

	# Select the current track
	var selected_id: String = game_state.selected_track_id
	for i in range(_track_ids.size()):
		if _track_ids[i] == selected_id:
			_track_list.select(i)
			break

	if _track_list.get_selected_items().is_empty() and _track_list.item_count > 0:
		_track_list.select(0)

	_update_laps_from_selection()


func _populate_teams() -> void:
	for child in _teams_grid.get_children():
		child.queue_free()

	var game_state: Node = get_node_or_null("/root/GameState")
	if game_state == null:
		return

	for team in game_state.teams_data:
		var color: Color = Color.html(team.get("color", "#FFFFFF"))
		var team_name: String = team.get("name", "Unknown")
		var drivers: Array = team.get("drivers", [])

		# Color swatch
		var swatch: ColorRect = ColorRect.new()
		swatch.custom_minimum_size = Vector2(16, 16)
		swatch.color = color
		_teams_grid.add_child(swatch)

		# Team name
		var name_label: Label = Label.new()
		name_label.text = team_name
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_teams_grid.add_child(name_label)

		# Driver names
		var driver_names: PackedStringArray = PackedStringArray()
		for driver in drivers:
			driver_names.append("%s (%s)" % [driver.get("display_name", ""), driver.get("id", "")])
		var drivers_label: Label = Label.new()
		drivers_label.text = ", ".join(driver_names)
		drivers_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_teams_grid.add_child(drivers_label)


func _populate_player_team_option() -> void:
	_player_team_option.clear()
	var game_state: Node = get_node_or_null("/root/GameState")
	if game_state == null:
		return

	var selected_index: int = 0
	for idx in range(game_state.teams_data.size()):
		var team: Dictionary = game_state.teams_data[idx]
		var team_name: String = String(team.get("name", "Unknown"))
		var team_id: String = String(team.get("id", "")).strip_edges()
		_player_team_option.add_item(team_name)
		_player_team_option.set_item_metadata(idx, team_id)
		if team_id == String(game_state.player_team_id):
			selected_index = idx

	if _player_team_option.item_count > 0:
		_player_team_option.select(selected_index)


func _on_track_selected(index: int) -> void:
	_update_laps_from_selection()


func _update_laps_from_selection() -> void:
	# Load track config to get default laps
	var selected: Array = _track_list.get_selected_items()
	if selected.is_empty():
		return
	var track_id: String = _track_ids[selected[0]]
	var track_result: Dictionary = preload("res://scripts/track_registry.gd").load_track_config(track_id)
	if track_result.get("errors", PackedStringArray()).is_empty():
		var config: Dictionary = track_result["config"]
		_laps_spinbox.value = config.get("default_laps", 15)


func _on_start_pressed() -> void:
	var game_state: Node = get_node_or_null("/root/GameState")
	if game_state == null:
		_status_label.text = "Error: GameState not found."
		return

	var selected: Array = _track_list.get_selected_items()
	if selected.is_empty():
		_status_label.text = "Please select a track."
		return

	game_state.selected_track_id = _track_ids[selected[0]]
	game_state.selected_laps = int(_laps_spinbox.value)
	game_state.fuel_enabled = _fuel_toggle.button_pressed
	if _player_team_option.item_count > 0 and _player_team_option.selected >= 0:
		game_state.player_team_id = String(_player_team_option.get_item_metadata(_player_team_option.selected))

	_status_label.text = "Loading..."
	_start_button.disabled = true

	var errors: PackedStringArray = game_state.compose_race_config()
	if not errors.is_empty():
		_status_label.text = "Config error: %s" % "\n".join(errors)
		_start_button.disabled = false
		return

	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
