extends RefCounted
class_name StintTracker

const RaceTypes = preload("res://sim/src/race_types.gd")
const TyreCompound = preload("res://sim/src/tyre_compound.gd")

var _car_stints: Dictionary = {}
var _initial_compounds: Dictionary = {}
var _compounds: Array[RaceTypes.TyreCompoundConfig] = []


func configure(
	cars: Array[RaceTypes.CarState],
	compounds: Array[RaceTypes.TyreCompoundConfig],
	starting_compounds: Dictionary
) -> void:
	_compounds.clear()
	for compound in compounds:
		if compound != null:
			_compounds.append(compound.clone())

	_initial_compounds.clear()
	_car_stints.clear()
	var default_compound: String = TyreCompound.get_default_compound_name(_compounds)
	for car in cars:
		if car == null or car.id.is_empty():
			continue
		var requested: String = String(starting_compounds.get(car.id, ""))
		var resolved: String = _resolve_compound_name(requested, default_compound)
		_initial_compounds[car.id] = resolved
		_car_stints[car.id] = _create_stint_state(resolved)


func reset() -> void:
	_car_stints.clear()
	for car_id in _initial_compounds.keys():
		_car_stints[car_id] = _create_stint_state(String(_initial_compounds[car_id]))


func get_compound_name(car_id: String) -> String:
	var stint: Dictionary = _car_stints.get(car_id, {})
	if stint.is_empty():
		return TyreCompound.get_default_compound_name(_compounds)
	return String(stint.get("compound_name", TyreCompound.get_default_compound_name(_compounds)))


func get_stint_lap_count(car_id: String) -> int:
	var stint: Dictionary = _car_stints.get(car_id, {})
	if stint.is_empty():
		return 0
	return int(stint.get("stint_lap_count", 0))


func get_stint_number(car_id: String) -> int:
	var stint: Dictionary = _car_stints.get(car_id, {})
	if stint.is_empty():
		return 1
	return int(stint.get("stint_number", 1))


func get_degradation_config(car_id: String) -> RaceTypes.DegradationConfig:
	var compound_name: String = get_compound_name(car_id)
	var compound: RaceTypes.TyreCompoundConfig = TyreCompound.find_compound(_compounds, compound_name)
	if compound != null and compound.degradation != null:
		return compound.degradation.clone()
	return RaceTypes.DegradationConfig.new()


func get_history(car_id: String) -> Array[RaceTypes.CompletedStint]:
	var history_copy: Array[RaceTypes.CompletedStint] = []
	var stint: Dictionary = _car_stints.get(car_id, {})
	if stint.is_empty():
		return history_copy
	var history: Array = stint.get("history", [])
	for raw_entry in history:
		var entry: RaceTypes.CompletedStint = raw_entry as RaceTypes.CompletedStint
		if entry != null:
			history_copy.append(entry.clone())
	return history_copy


func on_lap_completed(car_id: String) -> void:
	if not _car_stints.has(car_id):
		return
	var stint: Dictionary = _car_stints[car_id]
	stint["stint_lap_count"] = int(stint.get("stint_lap_count", 0)) + 1
	_car_stints[car_id] = stint


func on_pit_stop_complete(car_id: String, new_compound_name: String) -> void:
	if not _car_stints.has(car_id):
		return

	var stint: Dictionary = _car_stints[car_id]
	var completed: RaceTypes.CompletedStint = RaceTypes.CompletedStint.new()
	completed.compound_name = String(stint.get("compound_name", ""))
	completed.laps = int(stint.get("stint_lap_count", 0))
	completed.stint_number = int(stint.get("stint_number", 1))

	var history: Array = stint.get("history", [])
	history.append(completed)

	var default_compound: String = TyreCompound.get_default_compound_name(_compounds)
	stint["compound_name"] = _resolve_compound_name(new_compound_name, default_compound)
	stint["stint_lap_count"] = 0
	stint["stint_number"] = int(stint.get("stint_number", 1)) + 1
	stint["history"] = history
	_car_stints[car_id] = stint


func _create_stint_state(compound_name: String) -> Dictionary:
	return {
		"compound_name": compound_name,
		"stint_lap_count": 0,
		"stint_number": 1,
		"history": []
	}


func _resolve_compound_name(requested_name: String, fallback_name: String) -> String:
	var requested_compound: RaceTypes.TyreCompoundConfig = TyreCompound.find_compound(_compounds, requested_name)
	if requested_compound != null:
		return requested_compound.name
	var fallback_compound: RaceTypes.TyreCompoundConfig = TyreCompound.find_compound(_compounds, fallback_name)
	if fallback_compound != null:
		return fallback_compound.name
	return TyreCompound.get_default_compound_name(_compounds)
