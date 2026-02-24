extends RefCounted
class_name RaceStateMachine

const RaceTypes = preload("res://sim/src/race_types.gd")

var _state: int = RaceTypes.RaceState.NOT_STARTED
var _total_laps: int = 0
var _finish_order: Array[String] = []
var _next_finish_position: int = 1
var _total_car_count: int = 0


func configure(total_laps: int, car_count: int) -> void:
	_total_laps = max(total_laps, 0)
	_total_car_count = max(car_count, 0)
	reset()


func reset() -> void:
	_state = RaceTypes.RaceState.NOT_STARTED
	_finish_order.clear()
	_next_finish_position = 1


func get_state() -> int:
	return _state


func get_finish_order() -> Array[String]:
	return _finish_order.duplicate()


func is_unlimited() -> bool:
	return _total_laps <= 0


func on_race_start() -> void:
	if _state == RaceTypes.RaceState.NOT_STARTED:
		_state = RaceTypes.RaceState.RUNNING


func on_lap_completed(car: RaceTypes.CarState, crossing_time: float) -> void:
	if car == null or car.is_finished:
		return

	if _state == RaceTypes.RaceState.RUNNING:
		if is_unlimited():
			return
		if car.lap_count >= _total_laps:
			_state = RaceTypes.RaceState.FINISHING
			_mark_finished(car, crossing_time)
	elif _state == RaceTypes.RaceState.FINISHING:
		_mark_finished(car, crossing_time)


func is_car_racing(car: RaceTypes.CarState) -> bool:
	if car == null:
		return false
	return not car.is_finished


func _mark_finished(car: RaceTypes.CarState, crossing_time: float) -> void:
	if car == null or car.is_finished:
		return

	car.is_finished = true
	car.finish_position = _next_finish_position
	car.finish_time = crossing_time
	_next_finish_position += 1
	_finish_order.append(car.id)

	if _finish_order.size() >= _total_car_count:
		_state = RaceTypes.RaceState.FINISHED
