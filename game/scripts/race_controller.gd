extends Node2D

const RaceTypes = preload("res://sim/src/race_types.gd")
const RaceSimulator = preload("res://sim/src/race_simulator.gd")
const FixedStepRunner = preload("res://sim/src/fixed_step_runner.gd")
const RaceConfigLoader = preload("res://scripts/race_config_loader.gd")
const TrackSampler = preload("res://scripts/track_sampler.gd")
const CarDot = preload("res://scripts/car_dot.gd")

const FIXED_DT: float = 1.0 / 120.0
const MAX_STEPS_PER_FRAME: int = 16
const DOT_RADIUS: float = 7.0
const TRACK_BAKE_INTERVAL: float = 8.0

const CAR_COLORS := [
	Color(0.92, 0.29, 0.16),
	Color(0.17, 0.63, 0.92),
	Color(0.20, 0.76, 0.34),
	Color(0.95, 0.77, 0.15),
	Color(0.70, 0.40, 0.90),
	Color(0.98, 0.52, 0.18),
	Color(0.20, 0.84, 0.80),
	Color(0.90, 0.30, 0.50)
]

@onready var _track_path: Path2D = %TrackPath
@onready var _track_line: Line2D = %TrackLine
@onready var _cars_layer: Node2D = %CarsLayer
@onready var _hud: RaceHud = %RaceHud

var _simulator: RaceSimulator
var _track_sampler: TrackSampler = TrackSampler.new()
var _step_runner: FixedStepRunner = FixedStepRunner.new(FIXED_DT, MAX_STEPS_PER_FRAME)
var _car_nodes: Dictionary = {}
var _time_scale: float = 1.0
var _is_paused: bool = false
var _runtime_ready: bool = false
var _last_spiral_warning_ms: int = 0


func _ready() -> void:
	_connect_ui_signals()

	if not _initialize_track():
		return
	if not _initialize_simulator():
		return

	_runtime_ready = true
	_apply_snapshot(_simulator.get_snapshot())


func _process(delta: float) -> void:
	if not _runtime_ready:
		return

	if not _is_paused:
		var result: Dictionary = _step_runner.advance(delta, _time_scale, Callable(_simulator, "step"))
		if result.get("capped", false):
			_maybe_warn_spiral_of_death()

	_apply_snapshot(_simulator.get_snapshot())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_set_paused(not _is_paused)
				get_viewport().set_input_as_handled()
			KEY_R:
				_reset_race()
				get_viewport().set_input_as_handled()
			KEY_1:
				_set_time_scale(1.0)
				get_viewport().set_input_as_handled()
			KEY_2:
				_set_time_scale(2.0)
				get_viewport().set_input_as_handled()
			KEY_4:
				_set_time_scale(4.0)
				get_viewport().set_input_as_handled()


func _initialize_track() -> bool:
	var curve: Curve2D = _track_path.curve
	if curve == null or curve.point_count < 3:
		curve = _build_default_curve()
		_track_path.curve = curve

	_track_sampler.configure(curve, TRACK_BAKE_INTERVAL)
	if not _track_sampler.is_valid():
		_hud.set_error("Track curve is invalid. Add at least 3 points to TrackPath.")
		return false

	_track_line.position = _track_path.position
	_track_line.points = _track_sampler.get_polyline()
	_track_line.closed = false
	_cars_layer.position = _track_path.position
	return true


func _initialize_simulator() -> bool:
	var load_result: Dictionary = RaceConfigLoader.load_race_config()
	var load_errors_value: Variant = load_result.get("errors", PackedStringArray())
	var load_errors: PackedStringArray = load_errors_value if load_errors_value is PackedStringArray else PackedStringArray()
	if not load_errors.is_empty():
		_hud.set_error("\n".join(load_errors))
		return false

	var race_config_value: Variant = load_result.get("config", null)
	var race_config: RaceTypes.RaceConfig = race_config_value as RaceTypes.RaceConfig
	if race_config == null:
		_hud.set_error("Race config could not be parsed.")
		return false

	if race_config.cars.is_empty():
		_hud.set_empty("No cars configured. Add cars in config/race_v0.json.")
		return false

	_simulator = RaceSimulator.new()
	var runtime: RaceTypes.RaceRuntimeParams = RaceTypes.RaceRuntimeParams.new()
	runtime.track_length = _track_sampler.get_total_length()
	_simulator.initialize(race_config, runtime)

	if not _simulator.is_ready():
		_hud.set_error("\n".join(_simulator.get_validation_errors()))
		return false

	_time_scale = _sanitize_time_scale(race_config.default_time_scale)
	_is_paused = false
	_step_runner.reset()
	_build_car_nodes(_simulator.get_snapshot().cars)
	return true


func _build_car_nodes(cars: Array) -> void:
	for child in _cars_layer.get_children():
		child.queue_free()
	_car_nodes.clear()

	var car_index: int = 0
	for raw_car in cars:
		var car: RaceTypes.CarState = raw_car as RaceTypes.CarState
		if car == null:
			continue
		var dot: CarDot = CarDot.new()
		dot.name = "CarDot_%s" % car.id
		dot.configure(car.id, CAR_COLORS[car_index % CAR_COLORS.size()], DOT_RADIUS)
		dot.set_id_visible(true)
		_cars_layer.add_child(dot)
		_car_nodes[car.id] = dot
		car_index += 1


func _apply_snapshot(snapshot: RaceTypes.RaceSnapshot) -> void:
	for car in snapshot.cars:
		var dot: CarDot = _car_nodes.get(car.id) as CarDot
		if dot == null:
			continue
		dot.position = _track_sampler.sample_position(car.distance_along_track)

	_hud.render(snapshot, _is_paused, _time_scale)


func _connect_ui_signals() -> void:
	_hud.pause_toggled.connect(_on_pause_toggled)
	_hud.reset_requested.connect(_on_reset_requested)
	_hud.speed_selected.connect(_on_speed_selected)


func _on_pause_toggled(pause_requested: bool) -> void:
	_set_paused(pause_requested)


func _on_reset_requested() -> void:
	_reset_race()


func _on_speed_selected(speed_scale: float) -> void:
	_set_time_scale(speed_scale)


func _set_paused(value: bool) -> void:
	_is_paused = value


func _reset_race() -> void:
	if _simulator == null:
		return
	_is_paused = false
	_step_runner.reset()
	_simulator.reset()
	_apply_snapshot(_simulator.get_snapshot())


func _set_time_scale(value: float) -> void:
	_time_scale = _sanitize_time_scale(value)


func _sanitize_time_scale(value: float) -> float:
	if is_equal_approx(value, 1.0) or is_equal_approx(value, 2.0) or is_equal_approx(value, 4.0):
		return value
	return 1.0


func _maybe_warn_spiral_of_death() -> void:
	if not OS.is_debug_build():
		return

	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_spiral_warning_ms < 1000:
		return

	_last_spiral_warning_ms = now_ms
	push_warning("Fixed-step loop hit MAX_STEPS_PER_FRAME. Simulation is throttling.")


func _build_default_curve() -> Curve2D:
	var curve := Curve2D.new()
	curve.bake_interval = TRACK_BAKE_INTERVAL
	curve.add_point(Vector2(0.0, -260.0), Vector2(-180.0, 0.0), Vector2(180.0, 0.0))
	curve.add_point(Vector2(420.0, 0.0), Vector2(0.0, -160.0), Vector2(0.0, 160.0))
	curve.add_point(Vector2(0.0, 260.0), Vector2(180.0, 0.0), Vector2(-180.0, 0.0))
	curve.add_point(Vector2(-420.0, 0.0), Vector2(0.0, 160.0), Vector2(0.0, -160.0))
	return curve
