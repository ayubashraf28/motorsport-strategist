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
const LapSnapshotLogger = preload("res://scripts/lap_snapshot_logger.gd")
const AiStrategyController = preload("res://scripts/ai_strategy_controller.gd")
const RaceEngineer = preload("res://scripts/race_engineer.gd")

const FIXED_DT: float = 1.0 / 120.0
const MAX_STEPS_PER_FRAME: int = 16
const DOT_RADIUS: float = 7.0
const TRACK_BAKE_INTERVAL: float = 8.0
const ENABLE_LAP_SNAPSHOT_LOGGING: bool = true
const LAP_SNAPSHOT_OUTPUT_DIR: String = "res://../data/telemetry"

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

@onready var _track_view: Node2D = %TrackView
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
var _lap_snapshot_logger: LapSnapshotLogger = LapSnapshotLogger.new()
var _ai_strategy: AiStrategyController = null
var _car_color_map: Dictionary = {}
var _race_finished_handled: bool = false
var _race_engineer: RaceEngineer = null


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

	var snapshot: RaceTypes.RaceSnapshot = _simulator.get_snapshot()

	# AI strategy evaluation after stepping
	if _ai_strategy != null and not _is_paused:
		_ai_strategy.evaluate(snapshot, _simulator)

	# Race engineer radio messages
	if _race_engineer != null and not _is_paused:
		var drs_threshold: float = 0.0
		if _simulator.is_drs_enabled():
			var drs_zones: Array = _simulator.get_drs_zones()
			if not drs_zones.is_empty():
				drs_threshold = 50.0  # default detection threshold
		var radio_messages: Array = _race_engineer.evaluate(snapshot, drs_threshold)
		if not radio_messages.is_empty():
			_hud.show_radio_messages(radio_messages, snapshot.race_time)

	_apply_snapshot(snapshot)


func _exit_tree() -> void:
	if _lap_snapshot_logger != null:
		_lap_snapshot_logger.close()


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
	# Try GameState first (normal game flow via menu)
	if _try_load_from_game_state():
		return true
	# Fallback to disk (editor debugging, backward compat)
	return _load_config_from_disk()


func _try_load_from_game_state() -> bool:
	var game_state: Node = get_node_or_null("/root/GameState")
	if game_state == null:
		return false
	if game_state.active_config == null:
		return false
	_active_config = game_state.active_config
	_config_source_path = game_state.track_geometry_asset_path
	_car_color_map = game_state.car_colors
	return true


func _load_config_from_disk() -> bool:
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
		_hud.set_empty("No cars configured. Add cars in config/race_v3.json, config/race_v2.json, config/race_v1.1.json, or config/race_v1.json.")
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

	_track_line.points = _track_sampler.get_polyline()
	_track_line.closed = false
	_update_start_finish_marker()
	_fit_track_to_viewport()
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

	_track_line.points = _track_sampler.get_polyline()
	_track_line.closed = false
	_update_start_finish_marker()
	_fit_track_to_viewport()
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
	_race_finished_handled = false
	_step_runner.reset()
	_build_car_nodes(_simulator.get_snapshot().cars)
	_configure_debug_overlays(runtime.track_length)
	_hud.configure_strategy_ui(
		_simulator.is_pit_enabled(),
		_simulator.is_fuel_enabled(),
		_simulator.get_available_compounds(),
		_simulator.get_fuel_capacity_kg()
	)
	_hud.set_car_colors(_car_color_map)
	_initialize_ai_strategy()
	_race_engineer = RaceEngineer.new()
	_start_lap_snapshot_logging()
	return true


func _initialize_ai_strategy() -> void:
	if not _simulator.is_pit_enabled():
		_ai_strategy = null
		return

	_ai_strategy = AiStrategyController.new()
	var compounds: PackedStringArray = _simulator.get_available_compounds()

	# Get thresholds from GameState if available, otherwise use defaults
	var thresholds: Dictionary = {}
	var game_state: Node = get_node_or_null("/root/GameState")
	if game_state != null and not game_state.ai_thresholds.is_empty():
		thresholds = game_state.ai_thresholds
	else:
		# Default thresholds for backward-compat disk loading
		for raw_car in _simulator.get_snapshot().cars:
			var car: RaceTypes.CarState = raw_car as RaceTypes.CarState
			if car != null:
				thresholds[car.id] = 0.35

	_ai_strategy.configure(thresholds, compounds)


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
		var color: Color = _car_color_map.get(car.id, CAR_COLORS[car_index % CAR_COLORS.size()])
		dot.configure(car.id, color, DOT_RADIUS)
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

	if snapshot.race_state == RaceTypes.RaceState.FINISHED and not _is_paused:
		_set_paused(true)
		if not _race_finished_handled:
			_race_finished_handled = true
			_on_race_finished(snapshot)

	var pending_requests: Dictionary = _simulator.get_pending_pit_requests() if _simulator != null else {}
	_hud.render(snapshot, _is_paused, _time_scale, pending_requests)
	if ENABLE_LAP_SNAPSHOT_LOGGING and _lap_snapshot_logger != null:
		_lap_snapshot_logger.capture(snapshot, pending_requests)


func _on_race_finished(snapshot: RaceTypes.RaceSnapshot) -> void:
	var game_state: Node = get_node_or_null("/root/GameState")
	if game_state != null:
		game_state.store_race_results(snapshot)
		_hud.show_continue_button()


func _connect_ui_signals() -> void:
	_hud.pause_toggled.connect(_on_pause_toggled)
	_hud.reset_requested.connect(_on_reset_requested)
	_hud.speed_selected.connect(_on_speed_selected)
	_hud.pit_requested.connect(_on_pit_requested)
	_hud.pit_cancelled.connect(_on_pit_cancelled)
	_hud.driver_mode_requested.connect(_on_driver_mode_requested)
	_hud.continue_requested.connect(_on_continue_requested)
	_hud.main_menu_requested.connect(_on_main_menu_requested)


func _on_pause_toggled(pause_requested: bool) -> void:
	_set_paused(pause_requested)


func _on_reset_requested() -> void:
	_reset_race()


func _on_speed_selected(speed_scale: float) -> void:
	_set_time_scale(speed_scale)


func _on_pit_requested(car_id: String, compound: String, fuel_kg: float) -> void:
	if _simulator != null:
		_simulator.request_pit_stop(car_id, compound, fuel_kg)


func _on_pit_cancelled(car_id: String) -> void:
	if _simulator != null:
		_simulator.cancel_pit_stop(car_id)


func _on_driver_mode_requested(car_id: String, mode: int) -> void:
	if _simulator != null:
		_simulator.set_driver_mode(car_id, mode)


func _on_continue_requested() -> void:
	get_tree().change_scene_to_file("res://scenes/results.tscn")


func _on_main_menu_requested() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _set_paused(value: bool) -> void:
	_is_paused = value


func _reset_race() -> void:
	if _simulator == null:
		return
	_is_paused = false
	_race_finished_handled = false
	_step_runner.reset()
	_simulator.reset()
	if _ai_strategy != null:
		_ai_strategy.reset()
	if _race_engineer != null:
		_race_engineer.reset()
	_hud.hide_continue_button()
	_start_lap_snapshot_logging()
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
	var distance_at_line: float = 0.0
	var line_center: Vector2 = _track_sampler.sample_position(distance_at_line)
	var tangent: Vector2 = _track_sampler.sample_tangent(distance_at_line)
	var normal: Vector2 = Vector2(-tangent.y, tangent.x).normalized()
	var half_width: float = 22.0
	_start_finish_marker.points = PackedVector2Array([
		line_center - normal * half_width,
		line_center + normal * half_width
	])


func _fit_track_to_viewport() -> void:
	var polyline: PackedVector2Array = _track_sampler.get_polyline()
	if polyline.is_empty():
		return

	# Compute bounding box of raw track data
	var bb_min := Vector2(INF, INF)
	var bb_max := Vector2(-INF, -INF)
	for point in polyline:
		bb_min.x = minf(bb_min.x, point.x)
		bb_min.y = minf(bb_min.y, point.y)
		bb_max.x = maxf(bb_max.x, point.x)
		bb_max.y = maxf(bb_max.y, point.y)

	var track_center := (bb_min + bb_max) * 0.5
	var track_size := bb_max - bb_min

	# Available viewport area: leave room for timing tower (left) and bottom bar
	var vp_width: float = 1600.0
	var vp_height: float = 900.0
	var margin: float = 30.0
	var tower_width: float = 280.0
	var bar_height: float = 38.0
	var avail_left: float = tower_width + margin
	var avail_top: float = margin
	var avail_right: float = vp_width - margin
	var avail_bottom: float = vp_height - bar_height - margin
	var avail_size := Vector2(avail_right - avail_left, avail_bottom - avail_top)
	var avail_center := Vector2(
		(avail_left + avail_right) * 0.5,
		(avail_top + avail_bottom) * 0.5
	)

	# Try 0 and 90 degree rotation, pick whichever fills the available area better
	var score_0 := _fit_score(track_size, avail_size)
	var score_90 := _fit_score(Vector2(track_size.y, track_size.x), avail_size)
	var angle: float = -PI * 0.5 if score_90 > score_0 else 0.0

	# Effective size after rotation
	var eff_size: Vector2
	if absf(angle) > 0.01:
		eff_size = Vector2(track_size.y, track_size.x)
	else:
		eff_size = track_size

	# Uniform scale to fit with 90% fill for padding
	var scale_factor: float = minf(
		avail_size.x / maxf(eff_size.x, 0.001),
		avail_size.y / maxf(eff_size.y, 0.001)
	) * 0.9

	# Position TrackView so that the rotated+scaled track center maps to avail_center
	var cos_a: float = cos(angle)
	var sin_a: float = sin(angle)
	var rotated_center := Vector2(
		track_center.x * cos_a - track_center.y * sin_a,
		track_center.x * sin_a + track_center.y * cos_a
	)
	_track_view.rotation = angle
	_track_view.scale = Vector2(scale_factor, scale_factor)
	_track_view.position = avail_center - scale_factor * rotated_center


static func _fit_score(content: Vector2, container: Vector2) -> float:
	var sx: float = container.x / maxf(content.x, 0.001)
	var sy: float = container.y / maxf(content.y, 0.001)
	var s: float = minf(sx, sy)
	return (content.x * s * content.y * s) / maxf(container.x * container.y, 0.001)


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

	_pace_debug_overlay.configure(
		_track_sampler,
		track_length,
		blend_distance,
		segments
	)


func _configure_curvature_overlay(track_length: float) -> void:
	if _runtime_geometry == null:
		return
	_curvature_debug_overlay.configure(_track_sampler, track_length, _runtime_geometry.curvatures)


func _configure_speed_overlay(track_length: float) -> void:
	var profile_speeds: PackedFloat64Array = _simulator.get_speed_profile_array()
	if profile_speeds.is_empty():
		return
	var physics_config: RaceTypes.PhysicsVehicleConfig = _simulator.get_physics_config()
	if physics_config == null:
		return
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


func _start_lap_snapshot_logging() -> void:
	if not ENABLE_LAP_SNAPSHOT_LOGGING or _lap_snapshot_logger == null or _simulator == null:
		return
	_lap_snapshot_logger.start_session(_simulator.get_snapshot(), LAP_SNAPSHOT_OUTPUT_DIR)

	var logger_error: String = _lap_snapshot_logger.get_last_error()
	if not logger_error.is_empty():
		push_warning(logger_error)
		return

	var logger_path: String = _lap_snapshot_logger.get_output_path()
	if logger_path.is_empty():
		return
	print("Lap snapshots writing to %s" % logger_path)


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
