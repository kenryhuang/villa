class_name EconomyLimits
extends RefCounted

const MAX_SAFE_INTEGER := 9007199254740991
const MAINTENANCE_HORIZON_DAYS := 7
const MAX_SAFE_DATE := MAX_SAFE_INTEGER - MAINTENANCE_HORIZON_DAYS


static func is_safe_date(value: Variant, allow_zero: bool = true) -> bool:
	var minimum := 0 if allow_zero else 1
	if typeof(value) == TYPE_INT:
		return int(value) >= minimum and int(value) <= MAX_SAFE_DATE
	if typeof(value) != TYPE_FLOAT or not is_finite(value) or floorf(value) != value:
		return false
	return value >= float(minimum) and value <= float(MAX_SAFE_DATE)


static func is_safe_due_date(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return int(value) >= 0 and int(value) <= MAX_SAFE_INTEGER
	if typeof(value) != TYPE_FLOAT or not is_finite(value) or floorf(value) != value:
		return false
	return value >= 0.0 and value <= float(MAX_SAFE_INTEGER)
