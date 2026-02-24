extends GdUnitTestSuite

const RaceTypes = preload("res://sim/src/race_types.gd")
const TrackGeometry = preload("res://sim/src/track_geometry.gd")


func test_large_radius_loop_has_near_zero_curvature_everywhere() -> void:
	var geometry: TrackGeometry = TrackGeometry.new()
	geometry.configure_from_polyline(_build_circle_polyline(10000.0, 256), 4.0)
	assert(geometry.is_valid())

	var data: RaceTypes.TrackGeometryData = geometry.get_data()
	for kappa in data.curvatures:
		assert(abs(kappa) < 0.0002)


func test_circle_curvature_matches_inverse_radius_within_tolerance() -> void:
	var radius: float = 80.0
	var geometry: TrackGeometry = TrackGeometry.new()
	geometry.configure_from_polyline(_build_circle_polyline(radius, 512), 2.0)
	assert(geometry.is_valid())

	var data: RaceTypes.TrackGeometryData = geometry.get_data()
	var sum_abs: float = 0.0
	for kappa in data.curvatures:
		sum_abs += abs(kappa)
	var avg_abs: float = sum_abs / float(data.curvatures.size())
	var expected: float = 1.0 / radius
	assert(abs(avg_abs - expected) <= expected * 0.01)


func test_degenerate_polyline_is_invalid() -> void:
	var geometry: TrackGeometry = TrackGeometry.new()
	geometry.configure_from_polyline(PackedVector2Array([Vector2.ZERO]), 2.0)
	assert(not geometry.is_valid())


func test_asset_curvature_length_mismatch_is_invalid() -> void:
	var bad_data: RaceTypes.TrackGeometryData = RaceTypes.TrackGeometryData.new()
	bad_data.sample_count = 3
	bad_data.ds = 4.0
	bad_data.track_length = 12.0
	bad_data.positions_x = PackedFloat32Array([0.0, 1.0, 2.0])
	bad_data.positions_y = PackedFloat32Array([0.0, 0.0, 0.0])
	bad_data.curvatures = PackedFloat64Array([0.0, 0.0])

	var geometry: TrackGeometry = TrackGeometry.new()
	geometry.configure_from_asset(bad_data)
	assert(not geometry.is_valid())


func test_wrap_around_samples_are_available_at_first_and_last_index() -> void:
	var geometry: TrackGeometry = TrackGeometry.new()
	geometry.configure_from_polyline(_build_circle_polyline(120.0, 128), 3.0)
	assert(geometry.is_valid())

	var data: RaceTypes.TrackGeometryData = geometry.get_data()
	assert(data.curvatures.size() == data.sample_count)
	assert(not is_nan(data.curvatures[0]))
	assert(not is_nan(data.curvatures[data.sample_count - 1]))


func _build_circle_polyline(radius: float, point_count: int) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	points.resize(point_count)
	for i in range(point_count):
		var angle: float = TAU * float(i) / float(point_count)
		points[i] = Vector2(cos(angle) * radius, sin(angle) * radius)
	return points
