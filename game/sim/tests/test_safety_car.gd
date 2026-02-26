extends GdUnitTestSuite

const RaceTypes = preload("res://sim/src/race_types.gd")
const RaceSimulator = preload("res://sim/src/race_simulator.gd")
const SafetyCarController = preload("res://sim/src/safety_car_controller.gd")


func test_controller_phase_transitions_and_restart_drs_lock() -> void:
	var config := _safety_car_config(0.0)
	config.enabled = true
	config.trigger_probability_per_lap = 1.0
	config.vsc_probability = 0.0
	config.sc_laps_min = 2
	config.sc_laps_max = 2
	config.restart_drs_lock_laps = 2

	var controller := SafetyCarController.new()
	controller.configure(config, 7)
	assert(controller.get_phase() == RaceTypes.SafetyCarPhase.GREEN)

	controller.on_leader_lap_started(1, 15)
	assert(controller.get_phase() == RaceTypes.SafetyCarPhase.GREEN)

	controller.on_leader_lap_started(2, 15)
	assert(controller.get_phase() == RaceTypes.SafetyCarPhase.SC_DEPLOYED)

	controller.on_leader_lap_started(3, 15)
	assert(controller.get_phase() == RaceTypes.SafetyCarPhase.SC_DEPLOYED)

	controller.on_leader_lap_started(4, 15)
	assert(controller.get_phase() == RaceTypes.SafetyCarPhase.SC_ENDING)

	controller.on_leader_lap_started(5, 15)
	assert(controller.get_phase() == RaceTypes.SafetyCarPhase.GREEN)
	assert(not controller.is_drs_allowed())

	controller.on_leader_lap_started(6, 15)
	assert(not controller.is_drs_allowed())
	controller.on_leader_lap_started(7, 15)
	assert(not controller.is_drs_allowed())
	controller.on_leader_lap_started(8, 15)
	assert(controller.is_drs_allowed())


func test_simulator_sc_caps_speed_and_disables_drs() -> void:
	var config := _base_config([
		_car("lead", 70.0),
		_car("chase", 68.0)
	], 100.0)
	config.drs = _always_on_drs()
	var sc := _safety_car_config(0.0)
	sc.trigger_probability_per_lap = 1.0
	sc.vsc_probability = 0.0
	sc.sc_speed_cap = 20.0
	sc.sc_leader_pace_ratio = 0.9
	sc.sc_laps_min = 3
	sc.sc_laps_max = 3
	config.safety_car = sc

	var simulator := _build_simulator(config, 100.0)
	assert(simulator.is_ready())

	var snapshot: RaceTypes.RaceSnapshot = simulator.get_snapshot()
	for _i in range(300):
		simulator.step(0.05)
		snapshot = simulator.get_snapshot()
		if snapshot.safety_car_phase == RaceTypes.SafetyCarPhase.SC_DEPLOYED:
			break

	assert(snapshot.safety_car_phase == RaceTypes.SafetyCarPhase.SC_DEPLOYED)
	assert(not simulator.is_drs_runtime_enabled())
	for raw_car in snapshot.cars:
		var car: RaceTypes.CarState = raw_car as RaceTypes.CarState
		assert(not car.drs_active)
		assert(not car.drs_eligible)
		if car.position == 1:
			assert(car.effective_speed_units_per_sec <= 18.01)
		else:
			assert(car.effective_speed_units_per_sec <= 20.01)


func test_simulator_vsc_applies_speed_multiplier() -> void:
	var config := _base_config([
		_car("lead", 60.0),
		_car("chase", 59.0)
	], 100.0)
	config.drs = _always_on_drs()
	var sc := _safety_car_config(1.0)
	sc.trigger_probability_per_lap = 1.0
	sc.vsc_probability = 1.0
	sc.vsc_speed_multiplier = 0.5
	sc.vsc_laps_min = 2
	sc.vsc_laps_max = 2
	config.safety_car = sc

	var simulator := _build_simulator(config, 100.0)
	assert(simulator.is_ready())
	simulator.step(0.1)
	var baseline: RaceTypes.RaceSnapshot = simulator.get_snapshot()

	var snapshot: RaceTypes.RaceSnapshot = baseline
	for _i in range(400):
		simulator.step(0.05)
		snapshot = simulator.get_snapshot()
		if snapshot.safety_car_phase == RaceTypes.SafetyCarPhase.VSC:
			break

	assert(snapshot.safety_car_phase == RaceTypes.SafetyCarPhase.VSC)
	assert(not simulator.is_drs_runtime_enabled())

	var baseline_map: Dictionary = {}
	for raw_car in baseline.cars:
		var base_car: RaceTypes.CarState = raw_car as RaceTypes.CarState
		baseline_map[base_car.id] = base_car.effective_speed_units_per_sec

	for raw_car in snapshot.cars:
		var car: RaceTypes.CarState = raw_car as RaceTypes.CarState
		var base_speed: float = float(baseline_map.get(car.id, 0.0))
		assert(car.effective_speed_units_per_sec <= (base_speed * 0.52))


func _base_config(cars: Array, track_length: float) -> RaceTypes.RaceConfig:
	var config := RaceTypes.RaceConfig.new()
	config.schema_version = "4.0"
	config.track = _constant_track_profile(track_length)
	config.count_first_lap_from_start = true
	config.total_laps = 15
	config.seed = 42
	for car in cars:
		config.cars.append(car)
	var overtaking := RaceTypes.OvertakingConfig.new()
	overtaking.enabled = true
	config.overtaking = overtaking
	return config


func _build_simulator(config: RaceTypes.RaceConfig, track_length: float) -> RaceSimulator:
	var runtime := RaceTypes.RaceRuntimeParams.new()
	runtime.track_length = track_length
	var simulator := RaceSimulator.new()
	simulator.initialize(config, runtime)
	return simulator


func _car(car_id: String, speed: float) -> RaceTypes.CarConfig:
	var car := RaceTypes.CarConfig.new()
	car.id = car_id
	car.display_name = car_id
	car.base_speed_units_per_sec = speed
	car.v_ref = speed
	return car


func _always_on_drs() -> Dictionary:
	return {
		"enabled": true,
		"detection_threshold": 999.0,
		"speed_boost": 1.06,
		"min_activation_lap": 1,
		"zones": [
			{
				"detection_distance": 0.0,
				"zone_start": 0.0,
				"zone_end": 100.0
			}
		]
	}


func _constant_track_profile(track_length: float) -> RaceTypes.PaceProfileConfig:
	var profile := RaceTypes.PaceProfileConfig.new()
	var segment := RaceTypes.PaceSegmentConfig.new()
	segment.start_distance = 0.0
	segment.end_distance = track_length
	segment.multiplier = 1.0
	profile.pace_segments.append(segment)
	return profile


func _safety_car_config(vsc_probability: float) -> RaceTypes.SafetyCarConfig:
	var config := RaceTypes.SafetyCarConfig.new()
	config.enabled = true
	config.trigger_probability_per_lap = 1.0
	config.max_events = 1
	config.min_lap = 2
	config.cooldown_laps = 0
	config.sc_laps_min = 3
	config.sc_laps_max = 3
	config.vsc_laps_min = 2
	config.vsc_laps_max = 2
	config.vsc_probability = vsc_probability
	config.sc_speed_cap = 25.0
	config.sc_leader_pace_ratio = 0.9
	config.vsc_speed_multiplier = 0.6
	config.restart_drs_lock_laps = 2
	return config
