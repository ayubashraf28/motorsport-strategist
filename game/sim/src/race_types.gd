extends RefCounted
class_name RaceTypes

enum RaceState {
	NOT_STARTED = 0,
	RUNNING = 1,
	FINISHING = 2,
	FINISHED = 3
}


class PaceSegmentConfig extends RefCounted:
	var start_distance: float = 0.0
	var end_distance: float = 0.0
	var multiplier: float = 1.0

	func clone() -> PaceSegmentConfig:
		var copied := PaceSegmentConfig.new()
		copied.start_distance = start_distance
		copied.end_distance = end_distance
		copied.multiplier = multiplier
		return copied


class PaceProfileConfig extends RefCounted:
	var blend_distance: float = 0.0
	var pace_segments: Array[PaceSegmentConfig] = []

	func clone() -> PaceProfileConfig:
		var copied := PaceProfileConfig.new()
		copied.blend_distance = blend_distance
		for segment in pace_segments:
			if segment != null:
				copied.pace_segments.append(segment.clone())
		return copied


class PhysicsVehicleConfig extends RefCounted:
	var a_lat_max: float = 25.0
	var a_long_accel: float = 8.0
	var a_long_brake: float = 20.0
	var v_top_speed: float = 83.0
	var curvature_epsilon: float = 0.0001

	func clone() -> PhysicsVehicleConfig:
		var copied := PhysicsVehicleConfig.new()
		copied.a_lat_max = a_lat_max
		copied.a_long_accel = a_long_accel
		copied.a_long_brake = a_long_brake
		copied.v_top_speed = v_top_speed
		copied.curvature_epsilon = curvature_epsilon
		return copied


class TrackGeometryData extends RefCounted:
	var sample_count: int = 0
	var ds: float = 0.0
	var track_length: float = 0.0
	var curvatures: PackedFloat64Array = PackedFloat64Array()
	var positions_x: PackedFloat32Array = PackedFloat32Array()
	var positions_y: PackedFloat32Array = PackedFloat32Array()

	func clone() -> TrackGeometryData:
		var copied := TrackGeometryData.new()
		copied.sample_count = sample_count
		copied.ds = ds
		copied.track_length = track_length
		copied.curvatures = curvatures.duplicate()
		copied.positions_x = positions_x.duplicate()
		copied.positions_y = positions_y.duplicate()
		return copied


class SpeedProfileConfig extends RefCounted:
	var geometry_asset_path: String = ""
	var physics: PhysicsVehicleConfig = PhysicsVehicleConfig.new()

	func clone() -> SpeedProfileConfig:
		var copied := SpeedProfileConfig.new()
		copied.geometry_asset_path = geometry_asset_path
		copied.physics = physics.clone() if physics != null else PhysicsVehicleConfig.new()
		return copied


class DebugConfig extends RefCounted:
	var show_pace_profile: bool = true
	var show_curvature_overlay: bool = false
	var show_speed_overlay: bool = true

	func clone() -> DebugConfig:
		var copied := DebugConfig.new()
		copied.show_pace_profile = show_pace_profile
		copied.show_curvature_overlay = show_curvature_overlay
		copied.show_speed_overlay = show_speed_overlay
		return copied


class DegradationConfig extends RefCounted:
	var warmup_laps: float = 0.5
	var peak_multiplier: float = 1.0
	var degradation_rate: float = 0.0
	var min_multiplier: float = 0.7

	func clone() -> DegradationConfig:
		var copied := DegradationConfig.new()
		copied.warmup_laps = warmup_laps
		copied.peak_multiplier = peak_multiplier
		copied.degradation_rate = degradation_rate
		copied.min_multiplier = min_multiplier
		return copied


class OvertakingConfig extends RefCounted:
	var enabled: bool = true
	var proximity_distance: float = 50.0
	var overtake_speed_threshold: float = 2.0
	var held_up_speed_buffer: float = 0.1
	var cooldown_seconds: float = 3.0

	func clone() -> OvertakingConfig:
		var copied := OvertakingConfig.new()
		copied.enabled = enabled
		copied.proximity_distance = proximity_distance
		copied.overtake_speed_threshold = overtake_speed_threshold
		copied.held_up_speed_buffer = held_up_speed_buffer
		copied.cooldown_seconds = cooldown_seconds
		return copied


class CarConfig extends RefCounted:
	var id: String = ""
	var display_name: String = ""
	var base_speed_units_per_sec: float = 0.0
	var v_ref: float = 0.0
	var degradation: DegradationConfig = null

	func clone() -> CarConfig:
		var copied := CarConfig.new()
		copied.id = id
		copied.display_name = display_name
		copied.base_speed_units_per_sec = base_speed_units_per_sec
		copied.v_ref = v_ref
		copied.degradation = degradation.clone() if degradation != null else null
		return copied


class RaceConfig extends RefCounted:
	var schema_version: String = "1.0"
	var track: RefCounted = PaceProfileConfig.new()
	var debug: DebugConfig = DebugConfig.new()
	var cars: Array[CarConfig] = []
	var count_first_lap_from_start: bool = true
	var total_laps: int = 0
	var seed: int = 0
	var default_time_scale: float = 1.0
	var degradation: DegradationConfig = null
	var overtaking: OvertakingConfig = null

	func is_physics_profile() -> bool:
		return track is SpeedProfileConfig

	func is_pace_profile() -> bool:
		return track is PaceProfileConfig

	func clone() -> RaceConfig:
		var copied := RaceConfig.new()
		copied.schema_version = schema_version
		copied.track = _clone_track(track)
		copied.debug = debug.clone() if debug != null else DebugConfig.new()
		copied.count_first_lap_from_start = count_first_lap_from_start
		copied.total_laps = total_laps
		copied.seed = seed
		copied.default_time_scale = default_time_scale
		copied.degradation = degradation.clone() if degradation != null else null
		copied.overtaking = overtaking.clone() if overtaking != null else null
		for car in cars:
			copied.cars.append(car.clone())
		return copied

	func _clone_track(value: RefCounted) -> RefCounted:
		if value is PaceProfileConfig:
			return (value as PaceProfileConfig).clone()
		if value is SpeedProfileConfig:
			return (value as SpeedProfileConfig).clone()
		return PaceProfileConfig.new()


class RaceRuntimeParams extends RefCounted:
	var track_length: float = 0.0
	var geometry: TrackGeometryData = null

	func clone() -> RaceRuntimeParams:
		var copied := RaceRuntimeParams.new()
		copied.track_length = track_length
		copied.geometry = geometry.clone() if geometry != null else null
		return copied


class CarState extends RefCounted:
	var id: String = ""
	var display_name: String = ""
	var base_speed_units_per_sec: float = 0.0
	var v_ref: float = 0.0
	var current_multiplier: float = 1.0
	var effective_speed_units_per_sec: float = 0.0
	var distance_along_track: float = 0.0
	var total_distance: float = 0.0
	var position: int = 0
	var lap_count: int = 0
	var lap_start_time: float = 0.0
	var last_lap_time: float = -1.0
	var best_lap_time: float = INF
	var is_finished: bool = false
	var finish_position: int = 0
	var finish_time: float = -1.0
	var degradation_multiplier: float = 1.0
	var is_held_up: bool = false
	var held_up_by: String = ""

	func reset_runtime_state() -> void:
		current_multiplier = 1.0
		effective_speed_units_per_sec = base_speed_units_per_sec if base_speed_units_per_sec > 0.0 else v_ref
		distance_along_track = 0.0
		total_distance = 0.0
		position = 0
		lap_count = 0
		lap_start_time = 0.0
		last_lap_time = -1.0
		best_lap_time = INF
		is_finished = false
		finish_position = 0
		finish_time = -1.0
		degradation_multiplier = 1.0
		is_held_up = false
		held_up_by = ""

	func clone() -> CarState:
		var copied := CarState.new()
		copied.id = id
		copied.display_name = display_name
		copied.base_speed_units_per_sec = base_speed_units_per_sec
		copied.v_ref = v_ref
		copied.current_multiplier = current_multiplier
		copied.effective_speed_units_per_sec = effective_speed_units_per_sec
		copied.distance_along_track = distance_along_track
		copied.total_distance = total_distance
		copied.position = position
		copied.lap_count = lap_count
		copied.lap_start_time = lap_start_time
		copied.last_lap_time = last_lap_time
		copied.best_lap_time = best_lap_time
		copied.is_finished = is_finished
		copied.finish_position = finish_position
		copied.finish_time = finish_time
		copied.degradation_multiplier = degradation_multiplier
		copied.is_held_up = is_held_up
		copied.held_up_by = held_up_by
		return copied


class RaceSnapshot extends RefCounted:
	var race_time: float = 0.0
	var race_state: int = RaceState.NOT_STARTED
	var total_laps: int = 0
	var finish_order: Array[String] = []
	var cars: Array[CarState] = []
