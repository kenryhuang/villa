extends RefCounted

const ProjectileScript = preload("res://scripts/combat/projectile.gd")

func run(assertions) -> void:
	assertions.equal(ProjectileScript.is_expired(1.9, 2.0), false, "projectile remains before lifetime")
	assertions.equal(ProjectileScript.is_expired(2.0, 2.0), true, "projectile expires at lifetime")
	assertions.equal(ProjectileScript.safe_direction(Vector3.ZERO), Vector3.FORWARD, "zero direction gets fallback")
	assertions.near(ProjectileScript.safe_direction(Vector3(3.0, 0.0, 4.0)).length(), 1.0, 0.0001, "projectile direction normalizes")
