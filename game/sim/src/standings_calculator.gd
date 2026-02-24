extends RefCounted
class_name StandingsCalculator

const RaceTypes = preload("res://sim/src/race_types.gd")


static func update_positions(cars: Array[RaceTypes.CarState]) -> void:
	if cars.is_empty():
		return

	var sorted_indices: Array[int] = []
	for index in range(cars.size()):
		sorted_indices.append(index)

	sorted_indices.sort_custom(func(a: int, b: int) -> bool:
		var car_a: RaceTypes.CarState = cars[a]
		var car_b: RaceTypes.CarState = cars[b]
		if car_a.total_distance > car_b.total_distance:
			return true
		if car_a.total_distance < car_b.total_distance:
			return false
		return a < b
	)

	for rank in range(sorted_indices.size()):
		cars[sorted_indices[rank]].position = rank + 1


static func compute_interval_to_car_ahead(cars: Array[RaceTypes.CarState]) -> Dictionary:
	var intervals: Dictionary = {}
	if cars.is_empty():
		return intervals

	var cars_by_position: Dictionary = {}
	for car in cars:
		if car == null or car.id.is_empty():
			continue
		cars_by_position[car.position] = car

	for car in cars:
		if car == null or car.id.is_empty():
			continue
		if car.position <= 1:
			intervals[car.id] = 0.0
			continue

		var ahead_car: RaceTypes.CarState = cars_by_position.get(car.position - 1, null)
		if ahead_car == null:
			intervals[car.id] = 0.0
			continue
		intervals[car.id] = maxf(ahead_car.total_distance - car.total_distance, 0.0)

	return intervals
