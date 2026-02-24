extends Node2D

const RaceTypes = preload("res://sim/src/race_types.gd")
const RaceSimulator = preload("res://sim/src/race_simulator.gd")
const FixedStepRunner = preload("res://sim/src/fixed_step_runner.gd")
const RaceConfigLoader = preload("res://scripts/race_config_loader.gd")
const TrackSampler = preload("res://scripts/track_sampler.gd")
const TrackLoader = preload("res://scripts/track_loader.gd")
const CarDot = preload("res://scripts/car_dot.gd")
const PaceDebugOverlay = preload("res://scripts/pace_debug_overlay.gd")
const CurvatureDebugOverlay = preload("res://scripts/curvature_debug_overlay.gd")
const SpeedDebugOverlay = preload("res://scripts/speed_debug_overlay.gd")

const FIXED_DT: float = 1.0 / 120.0
const MAX_STEPS_PER_FRAME: int = 16
const DOT_RADIUS: float = 7.0
const TRACK_BAKE_INTERVAL: float = 8.0

const DEBUG_MODE_OFF: int = 0
const DEBUG_MODE_CURVATURE: int = 1
const DEBUG_MODE_SPEED: int = 2
const DEBUG_MODE_PACE: int = 3

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
@onready var _start_finish_marker: Line2D = %StartFinishMarker
@onready var _pace_debug_overlay: PaceDebugOverlay = %PaceDebugOverlay
@onready var _curvature_debug_overlay: CurvatureDebugOverlay = %CurvatureDebugOverlay
@onready var _speed_debug_overlay: SpeedDebugOverlay = %SpeedDebugOverlay
@onready var _cars_layer: Node2D = %CarsLayer
@onready var _hud: RaceHud = %RaceHud

var _simulator: RaceSimulator = null
var _track_sampler: TrackSampler = TrackSampler.new()
var _step_runner: FixedStepRunner = FixedStepRunner.new(FIXED_DT, MAX_STEPS_PER_FRAME)
var _car_nodes: Dictionary = {}
var _time_scale: float = 1.0
var _is_paused: bool = false
var _runtime_ready: bool = false
var _last_spiral_warning_ms: int = 0
var _config_source_path: String = ""
var _active_config: RaceTypes.RaceConfig = null
var _runtime_geometry: RaceTypes.TrackGeometryData = null
var _debug_mode: int = DEBUG_MODE_OFF


func _ready() -> void:
	_connect_ui_signals()

	if not _load_config():
		return
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
			KEY_D:
				_cycle_debug_overlay_mode()
				get_viewport().set_input_as_handled()


func _load_config() -> bool:
	var load_result: Dictionary = RaceConfigLoader.load_race_config()
	var load_errors: PackedStringArray = load_result.get("errors", PackedStringArray())
	if not load_errors.is_empty():
		_hud.set_error("\n".join(load_errors))
		return false

	_config_source_path = String(load_result.get("source_path", ""))
	_active_config = load_result.get("config", null) as RaceTypes.RaceConfig
	if _active_config == null:
		_hud.set_error("Race config could not be parsed.")
		return false
	if _active_config.cars.is_empty():
		_hud.set_empty("No cars configured. Add cars in config/race_v1.1.json or config/race_v1.json.")
		return false
	return true


func _initialize_track() -> bool:
	_runtime_geometry = null
	if _active_config != null and _active_config.is_physics_profile():
		return _initialize_track_from_geometry_asset()
	return _initialize_track_from_curve()


func _initialize_track_from_curve() -> bool:
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
	_update_start_finish_marker()
	return true


func _initialize_track_from_geometry_asset() -> bool:
	var speed_track: RaceTypes.SpeedProfileConfig = _active_config.track as RaceTypes.SpeedProfileConfig
	if speed_track == null:
		_hud.set_error("Schema 1.1 requires speed profile track configuration.")
		return false

	var load_result: Dictionary = TrackLoader.load_track_geometry(
		speed_track.geometry_asset_path,
		_config_source_path
	)
	var load_errors: PackedStringArray = load_result.get("errors", PackedStringArray())
	if not load_errors.is_empty():
		_hud.set_error("\n".join(load_errors))
		return false

	_runtime_geometry = load_result.get("geometry", null) as RaceTypes.TrackGeometryData
	var polyline: PackedVector2Array = load_result.get("polyline", PackedVector2Array())
	if _runtime_geometry == null or polyline.is_empty():
		_hud.set_error("Track geometry asset parsed without usable data.")
		return false

	_track_sampler.configure_from_polyline(polyline)
	if not _track_sampler.is_valid():
		_hud.set_error("Track geometry asset produced an invalid polyline.")
		return false

	_track_line.position = _track_path.position
	_track_line.points = _track_sampler.get_polyline()
	_track_line.closed = false
	_cars_layer.position = _track_path.position
	_update_start_finish_marker()
	return true


func _initialize_simulator() -> bool:
	_simulator = RaceSimulator.new()
	var runtime: RaceTypes.RaceRuntimeParams = RaceTypes.RaceRuntimeParams.new()
	runtime.track_length = _track_sampler.get_total_length()
	runtime.geometry = _runtime_geometry
	_simulator.initialize(_active_config, runtime)
	if not _simulator.is_ready():
		_hud.set_error("\n".join(_simulator.get_validation_errors()))
		return false

	_time_scale = _sanitize_time_scale(_active_config.default_time_scale)
	_is_paused = false
	_step_runner.reset()
	_build_car_nodes(_simulator.get_snapshot().cars)
	_configure_debug_overlays(runtime.track_length)
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
	for raw_car in snapshot.cars:
		var car: RaceTypes.CarState = raw_car as RaceTypes.CarState
		if car == null:
			continue
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


func _update_start_finish_marker() -> void:
	_start_finish_marker.position = _track_path.position
	var distance_at_line: float = 0.0
	var line_center: Vector2 = _track_sampler.sample_position(distance_at_line)
	var tangent: Vector2 = _track_sampler.sample_tangent(distance_at_line)
	var normal: Vector2 = Vector2(-tangent.y, tangent.x).normalized()
	var half_width: float = 22.0
	_start_finish_marker.points = PackedVector2Array([
		line_center - normal * half_width,
		line_center + normal * half_width
	])


func _configure_debug_overlays(track_length: float) -> void:
	_pace_debug_overlay.visible = false
	_curvature_debug_overlay.visible = false
	_speed_debug_overlay.visible = false

	var debug: RaceTypes.DebugConfig = _active_config.debug if _active_config.debug != null else RaceTypes.DebugConfig.new()
	if _active_config.is_physics_profile():
		_configure_curvature_overlay(track_length)
		_configure_speed_overlay(track_length)
		if debug.show_curvature_overlay:
			_debug_mode = DEBUG_MODE_CURVATURE
		elif debug.show_speed_overlay:
			_debug_mode = DEBUG_MODE_SPEED
		else:
			_debug_mode = DEBUG_MODE_OFF
	else:
		_configure_pace_overlay(track_length)
		_debug_mode = DEBUG_MODE_PACE if debug.show_pace_profile else DEBUG_MODE_OFF

	_apply_debug_mode_visibility()


func _configure_pace_overlay(track_length: float) -> void:
	var blend_distance: float = 0.0
	var segments: Array[RaceTypes.PaceSegmentConfig] = []
	if _active_config.track is RaceTypes.PaceProfileConfig:
		var pace_track: RaceTypes.PaceProfileConfig = _active_config.track as RaceTypes.PaceProfileConfig
		blend_distance = pace_track.blend_distance
		segments = pace_track.pace_segments

	_pace_debug_overlay.position = _track_path.position
	_pace_debug_overlay.configure(
		_track_sampler,
		track_length,
		blend_distance,
		segments
	)


func _configure_curvature_overlay(track_length: float) -> void:
	if _runtime_geometry == null:
		return
	_curvature_debug_overlay.position = _track_path.position
	_curvature_debug_overlay.configure(_track_sampler, track_length, _runtime_geometry.curvatures)


func _configure_speed_overlay(track_length: float) -> void:
	var profile_speeds: PackedFloat64Array = _simulator.get_speed_profile_array()
	if profile_speeds.is_empty():
		return
	var physics_config: RaceTypes.PhysicsVehicleConfig = _simulator.get_physics_config()
	if physics_config == null:
		return
	_speed_debug_overlay.position = _track_path.position
	_speed_debug_overlay.configure(_track_sampler, track_length, profile_speeds, physics_config.v_top_speed)


func _cycle_debug_overlay_mode() -> void:
	if _active_config == null:
		return

	if _active_config.is_physics_profile():
		match _debug_mode:
			DEBUG_MODE_SPEED:
				_debug_mode = DEBUG_MODE_CURVATURE
			DEBUG_MODE_CURVATURE:
				_debug_mode = DEBUG_MODE_OFF
			_:
				_debug_mode = DEBUG_MODE_SPEED
	else:
		_debug_mode = DEBUG_MODE_OFF if _debug_mode == DEBUG_MODE_PACE else DEBUG_MODE_PACE

	_apply_debug_mode_visibility()


func _apply_debug_mode_visibility() -> void:
	_pace_debug_overlay.visible = _debug_mode == DEBUG_MODE_PACE
	_curvature_debug_overlay.visible = _debug_mode == DEBUG_MODE_CURVATURE
	_speed_debug_overlay.visible = _debug_mode == DEBUG_MODE_SPEED


func _build_default_curve() -> Curve2D:
	var curve: Curve2D = Curve2D.new()
	curve.bake_interval = TRACK_BAKE_INTERVAL
	# Monza-inspired fallback for schema 1.0 when no editor curve exists.
	curve.add_point(Vector2(-312.48, -17.36), Vector2(-104.16, 52.08), Vector2(156.24, 0.0))
	curve.add_point(Vector2(312.48, -21.7), Vector2(-190.96, 0.0), Vector2(60.76, 34.72))
	curve.add_point(Vector2(355.88, 60.76), Vector2(-34.72, -26.04), Vector2(8.68, 52.08))
	curve.add_point(Vector2(282.1, 125.86), Vector2(60.76, -17.36), Vector2(43.4, 52.08))
	curve.add_point(Vector2(312.48, 217.0), Vector2(-26.04, -43.4), Vector2(-78.12, 34.72))
	curve.add_point(Vector2(217.0, 260.4), Vector2(60.76, -17.36), Vector2(-60.76, 34.72))
	curve.add_point(Vector2(121.52, 234.36), Vector2(43.4, 17.36), Vector2(-121.52, 13.02))
	curve.add_point(Vector2(-156.24, 251.72), Vector2(104.16, -8.68), Vector2(-69.44, 60.76))
	curve.add_point(Vector2(-260.4, 164.92), Vector2(34.72, 34.72), Vector2(-17.36, -69.44))
	curve.add_point(Vector2(-312.48, 60.76), Vector2(13.02, 56.42), Vector2(-26.04, -104.16))
	curve.add_point(Vector2(-381.92, -112.84), Vector2(0.0, 69.44), Vector2(104.16, -69.44))
	return curve
