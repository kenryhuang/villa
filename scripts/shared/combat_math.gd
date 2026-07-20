class_name CombatMath
extends RefCounted

static func apply_damage(current: int, amount: int) -> int:
	return maxi(0, current - maxi(0, amount))
