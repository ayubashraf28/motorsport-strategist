extends GdUnitTestSuite

const DriverMode = preload("res://sim/src/driver_mode.gd")


func test_standard_pace_is_1() -> void:
	assert(abs(DriverMode.get_pace_multiplier(DriverMode.Mode.STANDARD) - 1.0) < 0.0001)


func test_push_pace_is_greater_than_standard() -> void:
	assert(DriverMode.get_pace_multiplier(DriverMode.Mode.PUSH) > 1.0)


func test_conserve_pace_is_less_than_standard() -> void:
	assert(DriverMode.get_pace_multiplier(DriverMode.Mode.CONSERVE) < 1.0)


func test_standard_deg_scale_is_1() -> void:
	assert(abs(DriverMode.get_deg_rate_scale(DriverMode.Mode.STANDARD) - 1.0) < 0.0001)


func test_push_deg_scale_greater_than_1() -> void:
	assert(DriverMode.get_deg_rate_scale(DriverMode.Mode.PUSH) > 1.0)


func test_conserve_deg_scale_less_than_1() -> void:
	assert(DriverMode.get_deg_rate_scale(DriverMode.Mode.CONSERVE) < 1.0)


func test_standard_fuel_scale_is_1() -> void:
	assert(abs(DriverMode.get_fuel_consumption_scale(DriverMode.Mode.STANDARD) - 1.0) < 0.0001)


func test_push_fuel_scale_greater_than_1() -> void:
	assert(DriverMode.get_fuel_consumption_scale(DriverMode.Mode.PUSH) > 1.0)


func test_conserve_fuel_scale_less_than_1() -> void:
	assert(DriverMode.get_fuel_consumption_scale(DriverMode.Mode.CONSERVE) < 1.0)


func test_is_valid_mode_accepts_all_three() -> void:
	assert(DriverMode.is_valid_mode(DriverMode.Mode.PUSH))
	assert(DriverMode.is_valid_mode(DriverMode.Mode.STANDARD))
	assert(DriverMode.is_valid_mode(DriverMode.Mode.CONSERVE))


func test_is_valid_mode_rejects_invalid() -> void:
	assert(not DriverMode.is_valid_mode(-1))
	assert(not DriverMode.is_valid_mode(99))


func test_invalid_mode_returns_standard_effects() -> void:
	var effects: Dictionary = DriverMode.get_mode_effects(999)
	var standard: Dictionary = DriverMode.get_mode_effects(DriverMode.Mode.STANDARD)
	assert(abs(float(effects["pace_multiplier"]) - float(standard["pace_multiplier"])) < 0.0001)


func test_get_mode_name_returns_string() -> void:
	assert(DriverMode.get_mode_name(DriverMode.Mode.PUSH) == "PUSH")
	assert(DriverMode.get_mode_name(DriverMode.Mode.STANDARD) == "STD")
	assert(DriverMode.get_mode_name(DriverMode.Mode.CONSERVE) == "CONSERVE")


func test_get_mode_short_returns_single_char() -> void:
	assert(DriverMode.get_mode_short(DriverMode.Mode.PUSH) == "P")
	assert(DriverMode.get_mode_short(DriverMode.Mode.STANDARD) == "S")
	assert(DriverMode.get_mode_short(DriverMode.Mode.CONSERVE) == "C")


func test_push_tradeoff_deg_increase_exceeds_pace_gain() -> void:
	# Push should cost more in degradation than it gains in pace
	var push_effects: Dictionary = DriverMode.get_mode_effects(DriverMode.Mode.PUSH)
	var pace_gain: float = float(push_effects["pace_multiplier"]) - 1.0
	var deg_increase: float = float(push_effects["deg_rate_scale"]) - 1.0
	assert(deg_increase > pace_gain, "Push deg penalty should exceed pace gain for strategic balance")


func test_conserve_tradeoff_deg_saving_exceeds_pace_loss() -> void:
	# Conserve should save more in degradation than it loses in pace
	var conserve_effects: Dictionary = DriverMode.get_mode_effects(DriverMode.Mode.CONSERVE)
	var pace_loss: float = 1.0 - float(conserve_effects["pace_multiplier"])
	var deg_saving: float = 1.0 - float(conserve_effects["deg_rate_scale"])
	assert(deg_saving > pace_loss, "Conserve deg saving should exceed pace loss for strategic balance")
