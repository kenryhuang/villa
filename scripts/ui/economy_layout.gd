class_name EconomyLayout
extends RefCounted

const DRAWER_BREAKPOINT := 1500.0
const MINIMUM_SCALE := 0.8
const MAXIMUM_SCALE := 1.4


static func mode_for_size(logical_size: Vector2) -> String:
	return "drawer" if logical_size.x < DRAWER_BREAKPOINT else "three_column"


static func clamp_scale(requested_scale: float) -> float:
	return clampf(requested_scale, MINIMUM_SCALE, MAXIMUM_SCALE)
