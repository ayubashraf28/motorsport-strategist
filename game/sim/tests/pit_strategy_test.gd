extends GdUnitTestSuite

const PitStrategy = preload("res://sim/src/pit_strategy.gd")


func test_request_registers_pending() -> void:
	var strategy := PitStrategy.new()
	strategy.request_pit_stop("car_1", "soft", -1.0, 10.0)
	assert(strategy.has_pending_request("car_1"))


func test_cancel_removes_pending() -> void:
	var strategy := PitStrategy.new()
	strategy.request_pit_stop("car_1", "soft", -1.0, 10.0)
	strategy.cancel_pit_stop("car_1")
	assert(not strategy.has_pending_request("car_1"))


func test_consume_returns_and_removes() -> void:
	var strategy := PitStrategy.new()
	strategy.request_pit_stop("car_1", "hard", -1.0, 10.0)
	var request: Dictionary = strategy.consume_request("car_1")
	assert(request.get("compound", "") == "hard")
	assert(not strategy.has_pending_request("car_1"))


func test_overwrite_replaces_previous() -> void:
	var strategy := PitStrategy.new()
	strategy.request_pit_stop("car_1", "soft", -1.0, 10.0)
	strategy.request_pit_stop("car_1", "hard", 90.0, 12.0)
	var request: Dictionary = strategy.consume_request("car_1")
	assert(request.get("compound", "") == "hard")
	assert(abs(float(request.get("fuel_kg", 0.0)) - 90.0) < 0.000001)


func test_consume_empty_returns_empty_dict() -> void:
	var strategy := PitStrategy.new()
	assert(strategy.consume_request("car_1").is_empty())


func test_request_includes_fuel() -> void:
	var strategy := PitStrategy.new()
	strategy.request_pit_stop("car_1", "medium", 80.0, 5.0)
	var request: Dictionary = strategy.consume_request("car_1")
	assert(abs(float(request.get("fuel_kg", -1.0)) - 80.0) < 0.000001)


func test_reset_clears_all() -> void:
	var strategy := PitStrategy.new()
	strategy.request_pit_stop("car_1", "soft", -1.0, 2.0)
	strategy.request_pit_stop("car_2", "hard", 70.0, 2.5)
	strategy.reset()
	assert(not strategy.has_pending_request("car_1"))
	assert(not strategy.has_pending_request("car_2"))
