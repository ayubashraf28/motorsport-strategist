extends RefCounted
class_name RaceTypes


class CarConfig extends RefCounted:
	var id: String = ""
	var display_name: String = ""
	var speed_units_per_sec: float = 0.0

	func clone() -> CarConfig:
		var copied := CarConfig.new()
		copied.id = id
		copied.display_name = display_name
		copied.speed_units_per_sec = speed_units_per_sec
		return copied


class RaceConfig extends RefCounted:
	var cars: Array[CarConfig] = []
	var count_first_lap_from_start: bool = true
	var seed: int = 0
	var default_time_scale: float = 1.0

	func clone() -> RaceConfig:
		var copied := RaceConfig.new()
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
	var speed_units_per_sec: float = 0.0
	var distance_along_track: float = 0.0
	var lap_count: int = 0
	var lap_start_time: float = 0.0
	var last_lap_time: float = -1.0
	var best_lap_time: float = INF

	func reset_runtime_state() -> void:
		distance_along_track = 0.0
		lap_count = 0
		lap_start_time = 0.0
		last_lap_time = -1.0
		best_lap_time = INF

	func clone() -> CarState:
		var copied := CarState.new()
		copied.id = id
		copied.display_name = display_name
		copied.speed_units_per_sec = speed_units_per_sec
		copied.distance_along_track = distance_along_track
		copied.lap_count = lap_count
		copied.lap_start_time = lap_start_time
		copied.last_lap_time = last_lap_time
		copied.best_lap_time = best_lap_time
		return copied


class RaceSnapshot extends RefCounted:
	var race_time: float = 0.0
	var cars: Array[CarState] = []

