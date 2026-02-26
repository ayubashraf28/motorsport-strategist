extends GdUnitTestSuite

const DrsSystem = preload("res://sim/src/drs_system.gd")
const RaceTypes = preload("res://sim/src/race_types.gd")


var _track_length: float = 2000.0

var _default_config: Dictionary = {
	"enabled": true,
	"detection_threshold": 50.0,
	"speed_boost": 1.06,
	"min_activation_lap": 3,
	"zones": [
		{
			"detection_distance": 800.0,
			"zone_start": 850.0,
			"zone_end": 1100.0,
		}
	],
}


func _make_car(id: String, distance: float, total_dist: float, lap: int) -> RaceTypes.CarState:
	var car := RaceTypes.CarState.new()
	car.id = id
	car.distance_along_track = distance
	car.total_distance = total_dist
	car.lap_count = lap
	car.is_finished = false
	car.is_in_pit = false
	car.drs_active = false
	car.drs_eligible = false
	return car


# --- Configuration tests ---

func test_configure_with_valid_config() -> void:
	var drs := DrsSystem.new()
	drs.configure(_default_config, _track_length)
	assert(drs.is_configured(), "DRS should be configured with valid config")
	assert(drs.is_enabled(), "DRS should be enabled after configure")


func test_configure_with_empty_config() -> void:
	var drs := DrsSystem.new()
	drs.configure({}, _track_length)
	assert(not drs.is_configured(), "DRS should not be configured with empty config")


func test_configure_with_disabled_config() -> void:
	var drs := DrsSystem.new()
	var config := _default_config.duplicate(true)
	config["enabled"] = false
	drs.configure(config, _track_length)
	assert(not drs.is_configured(), "DRS should not be configured when disabled")


func test_configure_with_no_zones() -> void:
	var drs := DrsSystem.new()
	var config := _default_config.duplicate(true)
	config["zones"] = []
	drs.configure(config, _track_length)
	assert(not drs.is_configured(), "DRS should not be configured with no zones")


func test_reset_restores_enabled() -> void:
	var drs := DrsSystem.new()
	drs.configure(_default_config, _track_length)
	drs.set_enabled(false)
	assert(not drs.is_enabled())
	drs.reset()
	assert(drs.is_enabled(), "DRS should be re-enabled after reset")


# --- Detection & activation tests ---

func test_car_within_threshold_gets_drs_in_zone() -> void:
	var drs := DrsSystem.new()
	drs.configure(_default_config, _track_length)

	# Place car ahead at detection point, car behind within threshold
	# Both on lap 3 (>= min_activation_lap)
	var ahead := _make_car("VER", 800.0, 6800.0, 3)
	var behind := _make_car("HAM", 770.0, 6770.0, 3)
	var cars: Array[RaceTypes.CarState] = [ahead, behind]

	# First: trigger detection point
	drs.evaluate_detections(cars, _track_length)
	# behind should be eligible (gap = 30m < 50m threshold)
	assert(behind.drs_eligible, "Behind car should be DRS eligible when within threshold")

	# Move behind car into the DRS zone
	behind.distance_along_track = 950.0
	behind.total_distance = 6950.0
	drs.evaluate_detections(cars, _track_length)
	assert(behind.drs_active, "Behind car should have DRS active in zone")


func test_car_outside_threshold_no_drs() -> void:
	var drs := DrsSystem.new()
	drs.configure(_default_config, _track_length)

	# Gap of 100m > 50m threshold
	var ahead := _make_car("VER", 800.0, 6800.0, 3)
	var behind := _make_car("HAM", 700.0, 6700.0, 3)
	var cars: Array[RaceTypes.CarState] = [ahead, behind]

	drs.evaluate_detections(cars, _track_length)
	assert(not behind.drs_eligible, "Behind car should NOT be eligible when outside threshold")
	assert(not behind.drs_active, "Behind car should NOT have DRS when outside threshold")


func test_leader_never_gets_drs() -> void:
	var drs := DrsSystem.new()
	drs.configure(_default_config, _track_length)

	var leader := _make_car("VER", 800.0, 6800.0, 3)
	var second := _make_car("HAM", 770.0, 6770.0, 3)
	var cars: Array[RaceTypes.CarState] = [leader, second]

	drs.evaluate_detections(cars, _track_length)
	assert(not leader.drs_active, "Leader should never have DRS active")
	assert(not leader.drs_eligible, "Leader should never be DRS eligible")


func test_drs_disabled_on_early_laps() -> void:
	var drs := DrsSystem.new()
	drs.configure(_default_config, _track_length)
	# min_activation_lap = 3, so lap_count 0 and 1 (laps 1 and 2) should be blocked

	var ahead := _make_car("VER", 800.0, 800.0, 0)
	var behind := _make_car("HAM", 770.0, 770.0, 0)
	var cars: Array[RaceTypes.CarState] = [ahead, behind]

	drs.evaluate_detections(cars, _track_length)
	assert(not behind.drs_eligible, "DRS should be disabled on lap 1")

	# Lap 2 (lap_count = 1)
	ahead.lap_count = 1
	behind.lap_count = 1
	drs.evaluate_detections(cars, _track_length)
	assert(not behind.drs_eligible, "DRS should be disabled on lap 2")


func test_drs_enabled_from_min_activation_lap() -> void:
	var drs := DrsSystem.new()
	drs.configure(_default_config, _track_length)
	# min_activation_lap = 3, lap_count 2 = lap 3

	var ahead := _make_car("VER", 800.0, 4800.0, 2)
	var behind := _make_car("HAM", 770.0, 4770.0, 2)
	var cars: Array[RaceTypes.CarState] = [ahead, behind]

	drs.evaluate_detections(cars, _track_length)
	assert(behind.drs_eligible, "DRS should be enabled from lap 3 onward")


func test_drs_disabled_via_set_enabled() -> void:
	var drs := DrsSystem.new()
	drs.configure(_default_config, _track_length)

	var ahead := _make_car("VER", 800.0, 6800.0, 3)
	var behind := _make_car("HAM", 770.0, 6770.0, 3)
	var cars: Array[RaceTypes.CarState] = [ahead, behind]

	drs.set_enabled(false)
	drs.evaluate_detections(cars, _track_length)
	assert(not behind.drs_eligible, "DRS should not activate when disabled")
	assert(not behind.drs_active, "DRS should not be active when disabled")


# --- Multiplier tests ---

func test_drs_multiplier_when_active() -> void:
	var drs := DrsSystem.new()
	drs.configure(_default_config, _track_length)

	var car := _make_car("VER", 950.0, 6950.0, 3)
	car.drs_active = true
	var mult: float = drs.get_drs_multiplier(car)
	assert(abs(mult - 1.06) < 0.001, "DRS multiplier should be speed_boost when active")


func test_drs_multiplier_when_inactive() -> void:
	var drs := DrsSystem.new()
	drs.configure(_default_config, _track_length)

	var car := _make_car("VER", 950.0, 6950.0, 3)
	car.drs_active = false
	var mult: float = drs.get_drs_multiplier(car)
	assert(abs(mult - 1.0) < 0.001, "DRS multiplier should be 1.0 when not active")


func test_drs_multiplier_null_car() -> void:
	var drs := DrsSystem.new()
	drs.configure(_default_config, _track_length)

	var mult: float = drs.get_drs_multiplier(null)
	assert(abs(mult - 1.0) < 0.001, "DRS multiplier should be 1.0 for null car")


# --- Zone wrapping tests ---

func test_wrapping_zone_across_start_finish() -> void:
	var drs := DrsSystem.new()
	var config := {
		"enabled": true,
		"detection_threshold": 50.0,
		"speed_boost": 1.06,
		"min_activation_lap": 3,
		"zones": [
			{
				"detection_distance": 1900.0,
				"zone_start": 1950.0,
				"zone_end": 150.0,
			}
		],
	}
	drs.configure(config, _track_length)

	# Cars near detection point at 1900m
	var ahead := _make_car("VER", 1900.0, 7900.0, 3)
	var behind := _make_car("HAM", 1870.0, 7870.0, 3)
	var cars: Array[RaceTypes.CarState] = [ahead, behind]

	# Trigger detection
	drs.evaluate_detections(cars, _track_length)
	assert(behind.drs_eligible, "Should be eligible at wrapping zone detection")

	# Move into the zone (past start/finish, wrapping to low distance)
	behind.distance_along_track = 50.0
	behind.total_distance = 8050.0
	ahead.distance_along_track = 100.0
	ahead.total_distance = 8100.0
	drs.evaluate_detections(cars, _track_length)
	assert(behind.drs_active, "DRS should be active in wrapping zone past start/finish")


# --- Car state edge cases ---

func test_car_in_pit_no_drs() -> void:
	var drs := DrsSystem.new()
	drs.configure(_default_config, _track_length)

	var ahead := _make_car("VER", 800.0, 6800.0, 3)
	var behind := _make_car("HAM", 770.0, 6770.0, 3)
	behind.is_in_pit = true
	var cars: Array[RaceTypes.CarState] = [ahead, behind]

	drs.evaluate_detections(cars, _track_length)
	assert(not behind.drs_eligible, "Car in pit should not get DRS")
	assert(not behind.drs_active, "Car in pit should not have DRS active")


func test_finished_car_no_drs() -> void:
	var drs := DrsSystem.new()
	drs.configure(_default_config, _track_length)

	var ahead := _make_car("VER", 800.0, 6800.0, 3)
	var behind := _make_car("HAM", 770.0, 6770.0, 3)
	behind.is_finished = true
	var cars: Array[RaceTypes.CarState] = [ahead, behind]

	drs.evaluate_detections(cars, _track_length)
	assert(not behind.drs_eligible, "Finished car should not get DRS")
	assert(not behind.drs_active, "Finished car should not have DRS active")


func test_get_zones_returns_copy() -> void:
	var drs := DrsSystem.new()
	drs.configure(_default_config, _track_length)
	var zones: Array = drs.get_zones()
	assert(zones.size() == 1, "Should return configured zones")
	zones.clear()
	assert(drs.get_zones().size() == 1, "Original zones should be unchanged")
