extends RefCounted

const NpcScript = preload("res://scripts/actors/npc.gd")

class SignalSpy:
	extends RefCounted
	var defeated_count := 0

	func on_defeated(_npc) -> void:
		defeated_count += 1

func run(assertions) -> void:
	var npc = NpcScript.new()
	var spy := SignalSpy.new()
	npc.defeated.connect(spy.on_defeated)
	npc.take_hit(2, Vector3.RIGHT)
	assertions.equal(npc.health, 1, "npc loses health")
	assertions.truthy(npc.knockback_velocity.x > 0.0, "npc receives knockback")
	npc.take_hit(1, Vector3.ZERO)
	npc.take_hit(1, Vector3.ZERO)
	assertions.equal(npc.health, 0, "npc health clamps at zero")
	assertions.equal(spy.defeated_count, 1, "npc emits defeated once")
	npc.free()
