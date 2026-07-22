extends RefCounted

const TreeInstanceScript = preload("res://scripts/world/tree_instance.gd")
const PlayerScene = preload("res://scenes/actors/player.tscn")
const NpcScene = preload("res://scenes/actors/npc.tscn")
const ProjectileScene = preload("res://scenes/combat/projectile.tscn")

func run(assertions) -> void:
	var image := Image.create_empty(16, 24, false, Image.FORMAT_RGBA8)
	var texture := ImageTexture.create_from_image(image)
	var tree = TreeInstanceScript.new()
	tree.configure({"x": 0.0, "z": 0.0, "width": 2.0, "height": 3.0, "clearance": 1.0}, texture, 0.0)
	assertions.equal(tree.get_node("TrunkBody").collision_layer, 16, "tree trunk uses obstacle layer")
	assertions.equal(tree.get_node("CameraOccluder").collision_layer, 32, "canopy uses camera layer")
	assertions.truthy(tree.get_node("TrunkBody/CollisionShape3D").shape is CylinderShape3D, "tree has cylinder trunk")
	tree.free()

	var player = PlayerScene.instantiate()
	var npc = NpcScene.instantiate()
	var projectile = ProjectileScene.instantiate()
	assertions.equal(player.collision_mask, 21, "player collides with terrain, NPCs, and tree trunks")
	assertions.equal(npc.collision_mask, 19, "NPC collides with terrain, player, and tree trunks")
	assertions.equal(projectile.collision_mask, 21, "projectile collides with terrain, NPCs, and tree trunks")
	player.free()
	npc.free()
	projectile.free()
