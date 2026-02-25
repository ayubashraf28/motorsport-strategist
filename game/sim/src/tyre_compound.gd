extends RefCounted
class_name TyreCompound

const RaceTypes = preload("res://sim/src/race_types.gd")
const DegradationModel = preload("res://sim/src/degradation_model.gd")


static func find_compound(
	compounds: Array[RaceTypes.TyreCompoundConfig],
	compound_name: String
) -> RaceTypes.TyreCompoundConfig:
	var normalized_name: String = compound_name.strip_edges().to_lower()
	if normalized_name.is_empty():
		return null
	for compound in compounds:
		if compound == null:
			continue
		if compound.name.strip_edges().to_lower() == normalized_name:
			return compound
	return null


static func get_default_compound_name(compounds: Array[RaceTypes.TyreCompoundConfig]) -> String:
	for compound in compounds:
		if compound == null:
			continue
		var name: String = compound.name.strip_edges()
		if not name.is_empty():
			return name
	return "medium"


static func validate_compounds(compounds: Array[RaceTypes.TyreCompoundConfig]) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	if compounds.is_empty():
		errors.append("compounds must define at least one entry.")
		return errors

	var seen_names: Dictionary = {}
	for index in range(compounds.size()):
		var compound: RaceTypes.TyreCompoundConfig = compounds[index]
		if compound == null:
			errors.append("compounds[%d] cannot be null." % index)
			continue
		var clean_name: String = compound.name.strip_edges()
		if clean_name.is_empty():
			errors.append("compounds[%d].name must be non-empty." % index)
			continue
		var key: String = clean_name.to_lower()
		if seen_names.has(key):
			errors.append("compounds[%d].name '%s' is duplicated." % [index, clean_name])
		else:
			seen_names[key] = true

		var degradation_errors: PackedStringArray = DegradationModel.validate_config(compound.degradation)
		for degradation_error in degradation_errors:
			errors.append("compounds[%d].degradation: %s" % [index, degradation_error])
	return errors
