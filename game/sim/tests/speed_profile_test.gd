extends GdUnitTestSuite

const RaceTypes = preload("res://sim/src/race_types.gd")
const SpeedProfile = preload("res://sim/src/speed_profile.gd")


func test_zero_curvature_track_matches_top_speed_everywhere() -> void:
	var profile: SpeedProfile = SpeedProfile.new()
	var geometry: RaceTypes.TrackGeometryData = _geometry_constant_curvature(200, 4.0, 0.0)
	var physics: RaceTypes.PhysicsVehicleConfig = _physics()
	profile.configure(geometry, physics)
	assert(profile.is_valid())

	for distance in [0.0, 128.0, 511.0]:
		assert(abs(profile.sample_speed(distance) - physics.v_top_speed) < 0.0001)


func test_tight_circle_speed_matches_lateral_limit() -> void:
	var radius: float = 30.0
	var curvature: float = 1.0 / radius
	var profile: SpeedProfile = SpeedProfile.new()
	var geometry: RaceTypes.TrackGeometryData = _geometry_constant_curvature(240, 2.0, curvature)
	var physics: RaceTypes.PhysicsVehicleConfig = _physics()
	profile.configure(geometry, physics)
	assert(profile.is_valid())

	var expected_corner_speed: float = sqrt(physics.a_lat_max / curvature)
	for speed_value in profile.get_speed_array():
		assert(abs(speed_value - expected_corner_speed) < 0.05)


func test_sampled_speed_is_continuous_for_small_ds_profile() -> void:
	var profile: SpeedProfile = SpeedProfile.new()
	var geometry: RaceTypes.TrackGeometryData = _geometry_with_corner_zone(600, 0.1, 220, 260, 0.05)
	var physics: RaceTypes.PhysicsVehicleConfig = _physics()
	profile.configure(geometry, physics)
	assert(profile.is_valid())

	var speeds: PackedFloat64Array = profile.get_speed_array()
	for i in range(speeds.size()):
		var next_index: int = (i + 1) % speeds.size()
		assert(abs(speeds[next_index] - speeds[i]) <= 0.1)


func test_forward_pass_respects_acceleration_constraint_out_of_corner() -> void:
	var profile: SpeedProfile = SpeedProfile.new()
	var geometry: RaceTypes.TrackGeometryData = _geometry_with_corner_zone(400, 1.0, 140, 170, 0.04)
	var physics: RaceTypes.PhysicsVehicleConfig = _physics()
	profile.configure(geometry, physics)
	assert(profile.is_valid())

	var speeds: PackedFloat64Array = profile.get_speed_array()
	for i in range(speeds.size()):
		var next_index: int = (i + 1) % speeds.size()
		var max_next: float = sqrt(maxf((speeds[i] * speeds[i]) + (2.0 * physics.a_long_accel * geometry.ds), 0.0))
		assert(speeds[next_index] <= max_next + 0.0001)


func test_backward_pass_creates_braking_zone_before_corner() -> void:
	var profile: SpeedProfile = SpeedProfile.new()
	var geometry: RaceTypes.TrackGeometryData = _geometry_with_corner_zone(500, 1.0, 250, 275, 0.07)
	var physics: RaceTypes.PhysicsVehicleConfig = _physics()
	profile.configure(geometry, physics)
	assert(profile.is_valid())

	var speeds: PackedFloat64Array = profile.get_speed_array()
	var far_upstream_index: int = 180
	var near_corner_index: int = 235
	assert(speeds[near_corner_index] < speeds[far_upstream_index])


func test_two_identical_instances_are_deterministic() -> void:
	var geometry: RaceTypes.TrackGeometryData = _geometry_with_corner_zone(300, 2.0, 120, 150, 0.05)
	var physics: RaceTypes.PhysicsVehicleConfig = _physics()

	var profile_a: SpeedProfile = SpeedProfile.new()
	var profile_b: SpeedProfile = SpeedProfile.new()
	profile_a.configure(geometry, physics)
	profile_b.configure(geometry, physics)
	assert(profile_a.is_valid())
	assert(profile_b.is_valid())

	var speeds_a: PackedFloat64Array = profile_a.get_speed_array()
	var speeds_b: PackedFloat64Array = profile_b.get_speed_array()
	assert(speeds_a.size() == speeds_b.size())
	for i in range(speeds_a.size()):
		assert(abs(speeds_a[i] - speeds_b[i]) < 0.0000001)


func test_null_geometry_is_invalid() -> void:
	var profile: SpeedProfile = SpeedProfile.new()
	profile.configure(null, _physics())
	assert(not profile.is_valid())


func test_curvature_epsilon_prevents_infinite_speed() -> void:
	var profile: SpeedProfile = SpeedProfile.new()
	var geometry: RaceTypes.TrackGeometryData = _geometry_constant_curvature(150, 3.0, 0.0)
	var physics: RaceTypes.PhysicsVehicleConfig = _physics()
	physics.curvature_epsilon = 0.0001
	profile.configure(geometry, physics)
	assert(profile.is_valid())

	for speed_value in profile.get_speed_array():
		assert(not is_inf(speed_value))
		assert(speed_value <= physics.v_top_speed + 0.0001)


func _physics() -> RaceTypes.PhysicsVehicleConfig:
	var physics: RaceTypes.PhysicsVehicleConfig = RaceTypes.PhysicsVehicleConfig.new()
	physics.a_lat_max = 25.0
	physics.a_long_accel = 8.0
	physics.a_long_brake = 20.0
	physics.v_top_speed = 83.0
	physics.curvature_epsilon = 0.0001
	return physics


func _geometry_constant_curvature(sample_count: int, ds: float, curvature: float) -> RaceTypes.TrackGeometryData:
	var geometry: RaceTypes.TrackGeometryData = RaceTypes.TrackGeometryData.new()
	geometry.sample_count = sample_count
	geometry.ds = ds
	geometry.track_length = float(sample_count) * ds
	geometry.curvatures = PackedFloat64Array()
	geometry.curvatures.resize(sample_count)
	for i in range(sample_count):
		geometry.curvatures[i] = curvature
	return geometry


func _geometry_with_corner_zone(
	sample_count: int,
	ds: float,
	corner_start: int,
	corner_end: int,
	corner_curvature: float
) -> RaceTypes.TrackGeometryData:
	var geometry: RaceTypes.TrackGeometryData = _geometry_constant_curvature(sample_count, ds, 0.0)
	for i in range(corner_start, corner_end):
		geometry.curvatures[i % sample_count] = corner_curvature
	return geometry
