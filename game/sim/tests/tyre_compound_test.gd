extends GdUnitTestSuite

const RaceTypes = preload("res://sim/src/race_types.gd")
const TyreCompound = preload("res://sim/src/tyre_compound.gd")


func test_find_compound_by_name() -> void:
	var compounds: Array[RaceTypes.TyreCompoundConfig] = _build_standard_compounds()
	assert(TyreCompound.find_compound(compounds, "soft") != null)
	assert(TyreCompound.find_compound(compounds, "medium") != null)
	assert(TyreCompound.find_compound(compounds, "hard") != null)


func test_find_compound_returns_null_for_unknown() -> void:
	var compounds: Array[RaceTypes.TyreCompoundConfig] = _build_standard_compounds()
	assert(TyreCompound.find_compound(compounds, "ultra") == null)


func test_default_compound_is_first_in_array() -> void:
	var compounds: Array[RaceTypes.TyreCompoundConfig] = _build_standard_compounds()
	assert(TyreCompound.get_default_compound_name(compounds) == "soft")


func test_empty_compounds_default_is_medium() -> void:
	assert(TyreCompound.get_default_compound_name([]) == "medium")


func test_validate_rejects_duplicate_names() -> void:
	var compounds: Array[RaceTypes.TyreCompoundConfig] = _build_standard_compounds()
	var duplicate := RaceTypes.TyreCompoundConfig.new()
	duplicate.name = "soft"
	duplicate.degradation = compounds[1].degradation.clone()
	compounds.append(duplicate)

	var errors: PackedStringArray = TyreCompound.validate_compounds(compounds)
	assert(errors.size() > 0)


func test_validate_rejects_empty_array() -> void:
	var errors: PackedStringArray = TyreCompound.validate_compounds([])
	assert(errors.size() > 0)


func test_validate_delegates_to_degradation_model() -> void:
	var compounds: Array[RaceTypes.TyreCompoundConfig] = _build_standard_compounds()
	compounds[0].degradation.peak_multiplier = -1.0
	var errors: PackedStringArray = TyreCompound.validate_compounds(compounds)
	assert(errors.size() > 0)


func test_compound_clone_is_deep() -> void:
	var source := RaceTypes.TyreCompoundConfig.new()
	source.name = "soft"
	source.degradation = RaceTypes.DegradationConfig.new()
	source.degradation.degradation_rate = 0.04

	var clone := source.clone()
	clone.name = "hard"
	clone.degradation.degradation_rate = 0.01

	assert(source.name == "soft")
	assert(abs(source.degradation.degradation_rate - 0.04) < 0.000001)


func _build_standard_compounds() -> Array[RaceTypes.TyreCompoundConfig]:
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
