extends RefCounted

const CombatMath = preload("res://scripts/shared/combat_math.gd")

func run(assertions) -> void:
	assertions.equal(CombatMath.apply_damage(5, 2), 3, "damage subtracts health")
	assertions.equal(CombatMath.apply_damage(1, 5), 0, "health never drops below zero")
	assertions.equal(CombatMath.apply_damage(4, -2), 4, "negative damage is ignored")
