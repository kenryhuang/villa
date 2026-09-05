extends SceneTree

const EnvironmentScene = preload("res://assets/models/farm_preview/farm_environment.glb")
const MeadowScript = preload("res://scripts/farm3d/painted_meadow.gd")

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var environment := EnvironmentScene.instantiate()
	var meadow := MeadowScript.new()
	meadow.apply_ground_material(environment)
	# Keep override resources alive while imported mesh instances are destroyed.
	var materials: Array[Material] = []
	var painted_surfaces := 0
	for mesh_node in environment.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh_node.mesh.get_surface_count():
			var material = mesh_node.get_active_material(surface)
			materials.append(material)
			if material.resource_name == "Painted meadow ground":
				painted_surfaces += 1
				_check(material.albedo_texture == MeadowScript.GRASS_TEXTURE, "Ground retains the original painted grass texture")
	_check(painted_surfaces > 0, "Painted material is applied to the actual ground")
	_check(meadow.get_child_count() == 0, "Meadow no longer generates decorative grass or flower meshes")
	await process_frame
	await process_frame
	meadow.free()
	environment.free()
	print("3D MEADOW: %s" % ("PASS (%d checks)" % checks if failures.is_empty() else "FAIL (%d/%d checks)" % [failures.size(), checks]))
	quit(0 if failures.is_empty() else 1)
