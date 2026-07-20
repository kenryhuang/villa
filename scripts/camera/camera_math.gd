class_name CameraMath
extends RefCounted

const MIN_SIZE := 5.0
const MAX_SIZE := 12.0

static func clamp_size(value: float) -> float:
	return clampf(value, MIN_SIZE, MAX_SIZE)
