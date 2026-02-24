extends GdUnitTestSuite

const RaceTypes = preload("res://sim/src/race_types.gd")
const PaceProfile = preload("res://sim/src/pace_profile.gd")


func test_rejects_gap_between_segments() -> void:
	var profile := PaceProfile.new()
	profile.configure(
		100.0,
		0.0,
		[
			_segment(0.0, 40.0, 1.0),
			_segment(45.0, 100.0, 0.8)
		]
	)
	assert(not profile.is_valid())


func test_rejects_overlap_between_segments() -> void:
	var profile := PaceProfile.new()
	profile.configure(
		100.0,
		0.0,
		[
			_segment(0.0, 70.0, 1.0),
			_segment(65.0, 100.0, 0.8)
		]
	)
	assert(not profile.is_valid())


func test_rejects_invalid_multiplier() -> void:
	var profile := PaceProfile.new()
	profile.configure(
		100.0,
		0.0,
		[
			_segment(0.0, 60.0, 1.0),
			_segment(60.0, 100.0, 0.0)
		]
	)
	assert(not profile.is_valid())


func test_rejects_blend_distance_longer_than_segment() -> void:
	var profile := PaceProfile.new()
	profile.configure(
		100.0,
		50.0,
		[
			_segment(0.0, 30.0, 1.0),
			_segment(30.0, 100.0, 0.8)
		]
	)
	assert(not profile.is_valid())


func test_smoothstep_transition_is_continuous_at_boundary() -> void:
	var profile := _standard_profile()
	assert(profile.is_valid())

	var before_boundary: float = profile.sample_multiplier(499.99)
	var after_boundary: float = profile.sample_multiplier(500.01)
	assert(abs(before_boundary - after_boundary) < 0.01)


func test_blend_is_bounded_between_adjacent_segments() -> void:
	var profile := _standard_profile()
	assert(profile.is_valid())

	for d in [480.0, 490.0, 500.0, 510.0, 520.0]:
		var sampled: float = profile.sample_multiplier(d)
		assert(sampled >= 0.8 and sampled <= 1.0)


func test_outside_blend_window_returns_base_segment_multiplier() -> void:
	var profile := _standard_profile()
	assert(profile.is_valid())

	assert(abs(profile.sample_multiplier(300.0) - 1.0) < 0.0001)
	assert(abs(profile.sample_multiplier(700.0) - 0.8) < 0.0001)


func test_constant_profile_samples_one_everywhere() -> void:
	var profile := PaceProfile.new()
	profile.configure(
		1000.0,
		60.0,
		[
			_segment(0.0, 1000.0, 1.0)
		]
	)
	assert(profile.is_valid())

	for d in [0.0, 100.0, 350.0, 999.0]:
		assert(abs(profile.sample_multiplier(d) - 1.0) < 0.0001)


func _standard_profile() -> PaceProfile:
	var profile := PaceProfile.new()
	profile.configure(
		1000.0,
		60.0,
		[
			_segment(0.0, 500.0, 1.0),
			_segment(500.0, 1000.0, 0.8)
		]
	)
	return profile


func _segment(start_distance: float, end_distance: float, multiplier: float) -> RaceTypes.PaceSegmentConfig:
	var segment := RaceTypes.PaceSegmentConfig.new()
	segment.start_distance = start_distance
	segment.end_distance = end_distance
	segment.multiplier = multiplier
	return segment
