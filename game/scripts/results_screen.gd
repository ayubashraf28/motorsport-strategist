extends Control


@onready var _title_label: Label = %TitleLabel
@onready var _results_grid: GridContainer = %ResultsGrid
@onready var _next_race_button: Button = %NextRaceButton
@onready var _menu_button: Button = %MenuButton


func _ready() -> void:
	_next_race_button.pressed.connect(_on_next_race)
	_menu_button.pressed.connect(_on_main_menu)
	_populate_results()


func _populate_results() -> void:
	var game_state: Node = get_node_or_null("/root/GameState")
	if game_state == null or game_state.race_results.is_empty():
		_title_label.text = "RACE RESULTS - No Data"
		return

	var results: Dictionary = game_state.race_results
	var track_name: String = results.get("track_name", "Unknown")
	var total_laps: int = results.get("total_laps", 0)
	var race_time: float = results.get("race_time", 0.0)
	_title_label.text = "RACE RESULTS - %s (%d laps)" % [track_name, total_laps]

	# Clear existing rows
	for child in _results_grid.get_children():
		child.queue_free()

	# Add header row
	_add_header("P")
	_add_header("Driver")
	_add_header("Team")
	_add_header("Time")
	_add_header("Best Lap")
	_add_header("Pits")
	_add_header("Compound")

	# Sort cars by finish position
	var cars: Array = results.get("cars", [])
	cars.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_pos: int = a.get("finish_position", 99)
		var b_pos: int = b.get("finish_position", 99)
		return a_pos < b_pos
	)

	# Winner time for computing gaps
	var winner_time: float = -1.0
	if not cars.is_empty():
		winner_time = cars[0].get("finish_time", -1.0)

	for car in cars:
		var pos: int = car.get("finish_position", 0)
		var driver_name: String = car.get("display_name", car.get("id", ""))
		var team_name: String = car.get("team_name", "")
		var team_color: String = car.get("team_color", "#FFFFFF")
		var finish_time: float = car.get("finish_time", -1.0)
		var best_lap: float = car.get("best_lap_time", -1.0)
		var pit_stops: int = car.get("pit_stops_completed", 0)
		var compound: String = car.get("current_compound", "").to_upper().substr(0, 1)

		_add_cell(str(pos))

		# Driver name with team color
		var driver_label: Label = Label.new()
		driver_label.text = driver_name
		driver_label.add_theme_color_override("font_color", Color.html(team_color))
		driver_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_results_grid.add_child(driver_label)

		_add_cell(team_name)

		# Time: winner gets absolute, others get gap
		if pos == 1 or winner_time < 0.0:
			_add_cell(_format_time(finish_time))
		else:
			var gap: float = finish_time - winner_time
			_add_cell("+%.3f s" % gap if finish_time > 0.0 else "DNF")

		_add_cell(_format_time(best_lap))
		_add_cell(str(pit_stops))
		_add_cell(compound)


func _add_header(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8, 1.0))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_results_grid.add_child(label)


func _add_cell(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_results_grid.add_child(label)


func _format_time(value: float) -> String:
	if value < 0.0 or is_inf(value):
		return "--"
	return "%.3f s" % value


func _on_next_race() -> void:
	get_tree().change_scene_to_file("res://scenes/race_setup.tscn")


func _on_main_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
