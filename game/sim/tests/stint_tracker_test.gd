extends GdUnitTestSuite

const RaceTypes = preload("res://sim/src/race_types.gd")
const StintTracker = preload("res://sim/src/stint_tracker.gd")


func test_initial_compound_matches_config() -> void:
	var tracker := _configured_tracker({"car_1": "hard"})
	assert(tracker.get_compound_name("car_1") == "hard")


func test_default_compound_when_not_specified() -> void:
	var tracker := _configured_tracker({})
	assert(tracker.get_compound_name("car_1") == "soft")


func test_stint_lap_increments_on_lap_complete() -> void:
	var tracker := _configured_tracker({})
	tracker.on_lap_completed("car_1")
	tracker.on_lap_completed("car_1")
	assert(tracker.get_stint_lap_count("car_1") == 2)


func test_pit_stop_resets_stint_laps() -> void:
	var tracker := _configured_tracker({})
	tracker.on_lap_completed("car_1")
	tracker.on_pit_stop_complete("car_1", "medium")
	assert(tracker.get_stint_lap_count("car_1") == 0)


func test_pit_stop_changes_compound() -> void:
	var tracker := _configured_tracker({"car_1": "soft"})
	tracker.on_pit_stop_complete("car_1", "hard")
	assert(tracker.get_compound_name("car_1") == "hard")


func test_pit_stop_increments_stint_number() -> void:
	var tracker := _configured_tracker({})
	tracker.on_pit_stop_complete("car_1", "medium")
	assert(tracker.get_stint_number("car_1") == 2)


func test_degradation_config_matches_compound() -> void:
	var tracker := _configured_tracker({"car_1": "hard"})
	var config: RaceTypes.DegradationConfig = tracker.get_degradation_config("car_1")
	assert(abs(config.peak_multiplier - 0.95) < 0.000001)


func test_pit_stop_records_history() -> void:
	var tracker := _configured_tracker({"car_1": "soft"})
	tracker.on_lap_completed("car_1")
	tracker.on_lap_completed("car_1")
	tracker.on_pit_stop_complete("car_1", "medium")

	var history: Array[RaceTypes.CompletedStint] = tracker.get_history("car_1")
	assert(history.size() == 1)
	assert(history[0].compound_name == "soft")
	assert(history[0].laps == 2)
	assert(history[0].stint_number == 1)


func test_multiple_pit_stops() -> void:
	var tracker := _configured_tracker({"car_1": "soft"})
	tracker.on_lap_completed("car_1")
	tracker.on_pit_stop_complete("car_1", "medium")
	tracker.on_lap_completed("car_1")
	tracker.on_lap_completed("car_1")
	tracker.on_pit_stop_complete("car_1", "hard")
	assert(tracker.get_stint_number("car_1") == 3)
	assert(tracker.get_compound_name("car_1") == "hard")
	assert(tracker.get_history("car_1").size() == 2)


func test_unknown_compound_on_pit_falls_back() -> void:
	var tracker := _configured_tracker({"car_1": "soft"})
	tracker.on_pit_stop_complete("car_1", "unknown")
	assert(tracker.get_compound_name("car_1") == "soft")


func test_reset_clears_all_state() -> void:
	var tracker := _configured_tracker({"car_1": "hard"})
	tracker.on_lap_completed("car_1")
	tracker.on_pit_stop_complete("car_1", "soft")
	tracker.reset()
	assert(tracker.get_compound_name("car_1") == "hard")
	assert(tracker.get_stint_lap_count("car_1") == 0)
	assert(tracker.get_stint_number("car_1") == 1)
	assert(tracker.get_history("car_1").is_empty())


func _configured_tracker(starting_compounds: Dictionary) -> StintTracker:
	var cars: Array[RaceTypes.CarState] = []
	var car := RaceTypes.CarState.new()
	car.id = "car_1"
	cars.append(car)

	var tracker := StintTracker.new()
	tracker.configure(cars, _build_compounds(), starting_compounds)
	return tracker


func _build_compounds() -> Array[RaceTypes.TyreCompoundConfig]:
	var soft := RaceTypes.TyreCompoundConfig.new()
	soft.name = "soft"
	soft.degradation = _degradation(0.3, 1.05, 0.04, 0.70)

	var medium := RaceTypes.TyreCompoundConfig.new()
	medium.name = "medium"
	medium.degradation = _degradation(0.5, 1.0, 0.02, 0.75)

	var hard := RaceTypes.TyreCompoundConfig.new()
	hard.name = "hard"
	hard.degradation = _degradation(0.8, 0.95, 0.01, 0.80)
	return [soft, medium, hard]


func _degradation(warmup: float, peak: float, rate: float, minimum: float) -> RaceTypes.DegradationConfig:
	var config := RaceTypes.DegradationConfig.new()
	config.warmup_laps = warmup
	config.peak_multiplier = peak
	config.degradation_rate = rate
	config.min_multiplier = minimum
	return config
