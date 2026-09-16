extends SceneTree

## Archive actual mesh/material data as well as the editable procedural source.
const OUT := "res://assets/models/buildings/greenhouse/"

func _initialize() -> void:
	run.call_deferred()

func own_nodes(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		own_nodes(child,owner_node)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT+"source")
	var model := preload("res://scripts/farm3d/greenhouse_model.gd").new()
	model.name = "Greenhouse"
	root.add_child(model)
	var triangle_count := 0
	var meshes := model.find_children("*","MeshInstance3D",true,false)
	for node in meshes: triangle_count += node.mesh.get_faces().size()/3
	var manifest := {"asset":"greenhouse","version":1,"method":"native_procedural_geometry","engine":Engine.get_version_info().string,
		"generator":"scripts/farm3d/greenhouse_model.gd","generator_sha256":FileAccess.get_file_as_string("res://scripts/farm3d/greenhouse_model.gd").sha256_text(),
		"raw_mesh":"source/greenhouse_native.tscn","exchange_mesh":"greenhouse.glb","input_images":[],"textures":[],
		"materials":"Embedded PBR colors, roughness and glass alpha; no external texture or generated image dependency.",
		"parameters":{"units":"metres","up":"Y","core_footprint":[3,3],"growing_beds":8,"ridge_height":3.15,"total_width":4.95,"construction_groups":["Foundation","Frame","Walls","Roof","Details"]},
		"mesh_instances":meshes.size(),"triangles":triangle_count}
	var state := GLTFState.new()
	var document := GLTFDocument.new()
	if document.append_from_scene(model,state)!=OK or document.write_to_filesystem(state,OUT+"greenhouse.glb")!=OK:
		push_error("Greenhouse GLB export failed");quit(1);return
	own_nodes(model,model)
	model.set_script(null)
	var packed := PackedScene.new()
	if packed.pack(model)!=OK or ResourceSaver.save(packed,OUT+"source/greenhouse_native.tscn")!=OK:
		push_error("Greenhouse raw mesh archive failed");quit(1);return
	var file := FileAccess.open(OUT+"generation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest,"  "))
	file.close()
	print("GREENHOUSE ARCHIVE: ",meshes.size()," meshes, ",triangle_count," triangles")
	quit(0)
