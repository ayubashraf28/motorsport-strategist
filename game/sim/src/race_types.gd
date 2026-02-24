extends RefCounted
class_name RaceTypes


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


class DebugConfig extends RefCounted:
	var show_pace_profile: bool = true

	func clone() -> DebugConfig:
		var copied := DebugConfig.new()
		copied.show_pace_profile = show_pace_profile
		return copied


class CarConfig extends RefCounted:
	var id: String = ""
	var display_name: String = ""
	var base_speed_units_per_sec: float = 0.0

	func clone() -> CarConfig:
		var copied := CarConfig.new()
		copied.id = id
		copied.display_name = display_name
		copied.base_speed_units_per_sec = base_speed_units_per_sec
		return copied


class RaceConfig extends RefCounted:
	var track: PaceProfileConfig = PaceProfileConfig.new()
	var debug: DebugConfig = DebugConfig.new()
	var cars: Array[CarConfig] = []
	var count_first_lap_from_start: bool = true
	var seed: int = 0
	var default_time_scale: float = 1.0

	func clone() -> RaceConfig:
		var copied := RaceConfig.new()
		copied.track = track.clone() if track != null else PaceProfileConfig.new()
		copied.debug = debug.clone() if debug != null else DebugConfig.new()
		copied.count_first_lap_from_start = count_first_lap_from_start
		copied.seed = seed
		copied.default_time_scale = default_time_scale
		for car in cars:
			copied.cars.append(car.clone())
		return copied


class RaceRuntimeParams extends RefCounted:
	var track_length: float = 0.0

	func clone() -> RaceRuntimeParams:
		var copied := RaceRuntimeParams.new()
		copied.track_length = track_length
		return copied


class CarState extends RefCounted:
	var id: String = ""
	var display_name: String = ""
	var base_speed_units_per_sec: float = 0.0
	var current_multiplier: float = 1.0
	var effective_speed_units_per_sec: float = 0.0
	var distance_along_track: float = 0.0
	var lap_count: int = 0
	var lap_start_time: float = 0.0
	var last_lap_time: float = -1.0
	var best_lap_time: float = INF

	func reset_runtime_state() -> void:
		current_multiplier = 1.0
		effective_speed_units_per_sec = base_speed_units_per_sec
		distance_along_track = 0.0
		lap_count = 0
		lap_start_time = 0.0
		last_lap_time = -1.0
		best_lap_time = INF

	func clone() -> CarState:
		var copied := CarState.new()
		copied.id = id
		copied.display_name = display_name
		copied.base_speed_units_per_sec = base_speed_units_per_sec
		copied.current_multiplier = current_multiplier
		copied.effective_speed_units_per_sec = effective_speed_units_per_sec
		copied.distance_along_track = distance_along_track
		copied.lap_count = lap_count
		copied.lap_start_time = lap_start_time
		copied.last_lap_time = last_lap_time
		copied.best_lap_time = best_lap_time
		return copied


class RaceSnapshot extends RefCounted:
	var race_time: float = 0.0
	var cars: Array[CarState] = []
