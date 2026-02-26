extends RefCounted
class_name RaceTypes

enum RaceState {
	NOT_STARTED = 0,
	RUNNING = 1,
	FINISHING = 2,
	FINISHED = 3
}

enum PitPhase {
	RACING = 0,
	ENTRY = 1,
	STOPPED = 2,
	EXIT = 3
}

enum TyrePhase {
	OPTIMAL = 0,
	GRADUAL = 1,
	CLIFF = 2
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
	var optimal_threshold: float = 1.0
	var cliff_threshold: float = 0.0
	var cliff_multiplier: float = 1.0

	func clone() -> DegradationConfig:
		var copied := DegradationConfig.new()
		copied.warmup_laps = warmup_laps
		copied.peak_multiplier = peak_multiplier
		copied.degradation_rate = degradation_rate
		copied.min_multiplier = min_multiplier
		copied.optimal_threshold = optimal_threshold
		copied.cliff_threshold = cliff_threshold
		copied.cliff_multiplier = cliff_multiplier
		return copied


class TyreCompoundConfig extends RefCounted:
	var name: String = "medium"
	var degradation: DegradationConfig = DegradationConfig.new()

	func clone() -> TyreCompoundConfig:
		var copied := TyreCompoundConfig.new()
		copied.name = name
		copied.degradation = degradation.clone() if degradation != null else DegradationConfig.new()
		return copied


class FuelConfig extends RefCounted:
	var enabled: bool = true
	var max_capacity_kg: float = 110.0
	var consumption_per_lap_kg: float = 2.5
	var weight_penalty_factor: float = 0.05
	var fuel_empty_penalty: float = 0.50
	var refuel_rate_kg_per_sec: float = 2.0

	func clone() -> FuelConfig:
		var copied := FuelConfig.new()
		copied.enabled = enabled
		copied.max_capacity_kg = max_capacity_kg
		copied.consumption_per_lap_kg = consumption_per_lap_kg
		copied.weight_penalty_factor = weight_penalty_factor
		copied.fuel_empty_penalty = fuel_empty_penalty
		copied.refuel_rate_kg_per_sec = refuel_rate_kg_per_sec
		return copied


class PitConfig extends RefCounted:
	var enabled: bool = true
	var pit_entry_distance: float = 0.0
	var pit_exit_distance: float = 0.0
	var pit_box_distance: float = -1.0
	var pit_lane_speed_limit: float = 20.0
	var base_pit_stop_duration: float = 3.0
	var pit_entry_duration: float = 8.0
	var pit_exit_duration: float = 8.0
	var min_stop_lap: int = 1
	var max_stops: int = 5

	func clone() -> PitConfig:
		var copied := PitConfig.new()
		copied.enabled = enabled
		copied.pit_entry_distance = pit_entry_distance
		copied.pit_exit_distance = pit_exit_distance
		copied.pit_box_distance = pit_box_distance
		copied.pit_lane_speed_limit = pit_lane_speed_limit
		copied.base_pit_stop_duration = base_pit_stop_duration
		copied.pit_entry_duration = pit_entry_duration
		copied.pit_exit_duration = pit_exit_duration
		copied.min_stop_lap = min_stop_lap
		copied.max_stops = max_stops
		return copied


class CompletedStint extends RefCounted:
	var compound_name: String = ""
	var laps: int = 0
	var stint_number: int = 0

	func clone() -> CompletedStint:
		var copied := CompletedStint.new()
		copied.compound_name = compound_name
		copied.laps = laps
		copied.stint_number = stint_number
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
	var starting_compound: String = ""
	var starting_fuel_kg: float = -1.0

	func clone() -> CarConfig:
		var copied := CarConfig.new()
		copied.id = id
		copied.display_name = display_name
		copied.base_speed_units_per_sec = base_speed_units_per_sec
		copied.v_ref = v_ref
		copied.degradation = degradation.clone() if degradation != null else null
		copied.starting_compound = starting_compound
		copied.starting_fuel_kg = starting_fuel_kg
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
	var compounds: Array[TyreCompoundConfig] = []
	var fuel: FuelConfig = null
	var pit: PitConfig = null
	var overtaking: OvertakingConfig = null
	var drs: Dictionary = {}  # Raw DRS config dictionary, passed to DrsSystem

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
		for compound in compounds:
			if compound != null:
				copied.compounds.append(compound.clone())
		copied.fuel = fuel.clone() if fuel != null else null
		copied.pit = pit.clone() if pit != null else null
		copied.overtaking = overtaking.clone() if overtaking != null else null
		copied.drs = drs.duplicate(true)
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
	var reference_speed_units_per_sec: float = 0.0
	var current_multiplier: float = 1.0
	var strategy_multiplier: float = 1.0
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
	var tyre_life_ratio: float = 1.0
	var tyre_phase: int = TyrePhase.OPTIMAL
	var current_compound: String = "medium"
	var stint_lap_count: int = 0
	var stint_number: int = 1
	var is_in_pit: bool = false
	var pit_phase: int = PitPhase.RACING
	var pit_time_remaining: float = 0.0
	var pit_stops_completed: int = 0
	var pit_target_compound: String = ""
	var pit_target_fuel_kg: float = -1.0
	var fuel_kg: float = 0.0
	var fuel_multiplier: float = 1.0
	var is_held_up: bool = false
	var held_up_by: String = ""
	var driver_mode: int = 1  # DriverMode.STANDARD
	var drs_active: bool = false
	var drs_eligible: bool = false

	func reset_runtime_state() -> void:
		current_multiplier = 1.0
		reference_speed_units_per_sec = base_speed_units_per_sec if base_speed_units_per_sec > 0.0 else v_ref
		strategy_multiplier = 1.0
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
		tyre_life_ratio = 1.0
		tyre_phase = TyrePhase.OPTIMAL
		current_compound = "medium"
		stint_lap_count = 0
		stint_number = 1
		is_in_pit = false
		pit_phase = PitPhase.RACING
		pit_time_remaining = 0.0
		pit_stops_completed = 0
		pit_target_compound = ""
		pit_target_fuel_kg = -1.0
		fuel_kg = 0.0
		fuel_multiplier = 1.0
		is_held_up = false
		held_up_by = ""
		driver_mode = 1
		drs_active = false
		drs_eligible = false

	func clone() -> CarState:
		var copied := CarState.new()
		copied.id = id
		copied.display_name = display_name
		copied.base_speed_units_per_sec = base_speed_units_per_sec
		copied.v_ref = v_ref
		copied.reference_speed_units_per_sec = reference_speed_units_per_sec
		copied.current_multiplier = current_multiplier
		copied.strategy_multiplier = strategy_multiplier
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
		copied.tyre_life_ratio = tyre_life_ratio
		copied.tyre_phase = tyre_phase
		copied.current_compound = current_compound
		copied.stint_lap_count = stint_lap_count
		copied.stint_number = stint_number
		copied.is_in_pit = is_in_pit
		copied.pit_phase = pit_phase
		copied.pit_time_remaining = pit_time_remaining
		copied.pit_stops_completed = pit_stops_completed
		copied.pit_target_compound = pit_target_compound
		copied.pit_target_fuel_kg = pit_target_fuel_kg
		copied.fuel_kg = fuel_kg
		copied.fuel_multiplier = fuel_multiplier
		copied.is_held_up = is_held_up
		copied.held_up_by = held_up_by
		copied.driver_mode = driver_mode
		copied.drs_active = drs_active
		copied.drs_eligible = drs_eligible
		return copied


class RaceSnapshot extends RefCounted:
	var race_time: float = 0.0
	var race_state: int = RaceState.NOT_STARTED
	var total_laps: int = 0
	var finish_order: Array[String] = []
	var cars: Array[CarState] = []
