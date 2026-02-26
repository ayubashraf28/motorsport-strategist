extends RefCounted
class_name TeamOrders

const RaceTypes = preload("res://sim/src/race_types.gd")

enum Order {
	NONE = 0,
	LET_THROUGH = 1,
	HOLD_POSITION = 2,
	DEFEND = 3,
}

const LET_THROUGH_MAX_GAP: float = 120.0
const HOLD_POSITION_GAP: float = 70.0
const DEFEND_MAX_GAP: float = 90.0
const DEFEND_BUFFER: float = 0.05
const DEFEND_PACE_SCALE: float = 0.97
const LET_THROUGH_PACE_SCALE: float = 0.90
const LET_THROUGH_TIMEOUT_SECONDS: float = 25.0


static func is_valid_order(order: int) -> bool:
	return (
		order == Order.NONE
		or order == Order.LET_THROUGH
		or order == Order.HOLD_POSITION
		or order == Order.DEFEND
	)


static func get_order_short(order: int) -> String:
	match order:
		Order.LET_THROUGH:
			return "L"
		Order.HOLD_POSITION:
			return "H"
		Order.DEFEND:
			return "D"
		_:
			return "-"


static func order_priority(order: int) -> int:
	match order:
		Order.LET_THROUGH:
			return 3
		Order.DEFEND:
			return 2
		Order.HOLD_POSITION:
			return 1
		_:
			return 0


static func should_yield(car: RaceTypes.CarState, to_car: RaceTypes.CarState) -> bool:
	if car == null or to_car == null:
		return false
	if car.team_id.is_empty() or car.team_id != to_car.team_id:
		return false
	if car.team_order != Order.LET_THROUGH:
		return false
	return car.team_order_target == to_car.id


static func should_hold_position(car: RaceTypes.CarState, teammate_ahead: RaceTypes.CarState) -> bool:
	if car == null or teammate_ahead == null:
		return false
	if car.team_id.is_empty() or car.team_id != teammate_ahead.team_id:
		return false
	if car.team_order != Order.HOLD_POSITION:
		return false
	return car.team_order_target == teammate_ahead.id


static func should_defend(car: RaceTypes.CarState, rival: RaceTypes.CarState) -> bool:
	if car == null or rival == null:
		return false
	if car.team_id.is_empty() or car.team_id == rival.team_id:
		return false
	if car.team_order != Order.DEFEND:
		return false
	return car.team_order_target == rival.id
