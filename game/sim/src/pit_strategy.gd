extends RefCounted
class_name PitStrategy

var _pending_requests: Dictionary = {}


func reset() -> void:
	_pending_requests.clear()


func get_pending_requests() -> Dictionary:
	return _pending_requests.duplicate(true)


func request_pit_stop(
	car_id: String,
	target_compound: String,
	target_fuel_kg: float,
	race_time: float
) -> void:
	var clean_id: String = car_id.strip_edges()
	if clean_id.is_empty():
		return
	_pending_requests[clean_id] = {
		"compound": target_compound.strip_edges(),
		"fuel_kg": target_fuel_kg,
		"requested_at": race_time
	}


func cancel_pit_stop(car_id: String) -> void:
	_pending_requests.erase(car_id)


func has_pending_request(car_id: String) -> bool:
	return _pending_requests.has(car_id)


func consume_request(car_id: String) -> Dictionary:
	if not _pending_requests.has(car_id):
		return {}
	var request: Dictionary = _pending_requests[car_id]
	_pending_requests.erase(car_id)
	return {
		"compound": String(request.get("compound", "")),
		"fuel_kg": float(request.get("fuel_kg", -1.0))
	}
