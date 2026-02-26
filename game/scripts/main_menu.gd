extends Control


@onready var _start_button: Button = %StartButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/race_setup.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
