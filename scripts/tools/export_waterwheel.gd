extends SceneTree

## Archive actual mesh/material data as well as the editable procedural source.
const OUT := "res://assets/models/buildings/waterwheel/"

func _initialize() -> void:
	run.call_deferred()

func own_nodes(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		own_nodes(child,owner_node)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT+"source")
	var model := preload("res://scripts/farm3d/waterwheel_model.gd").new()
	model.name = "Waterwheel"
	root.add_child(model)
	var triangle_count := 0
	var meshes := model.find_children("*","MeshInstance3D",true,false)
	for node in meshes: triangle_count += node.mesh.get_faces().size()/3
	var manifest := {"asset":"waterwheel","version":2,"method":"native_procedural_geometry","engine":Engine.get_version_info().string,
		"generator":"scripts/farm3d/waterwheel_model.gd","generator_sha256":FileAccess.get_file_as_string("res://scripts/farm3d/waterwheel_model.gd").sha256_text(),
		"raw_mesh":"source/waterwheel_native.tscn","exchange_mesh":"waterwheel.glb","input_images":[],"textures":[],
		"materials":"Embedded PBR colors, roughness; no external texture or generated image dependency.",
		"parameters":{"units":"metres","up":"Y","core_footprint":[2,2],"wheel_radius":1.14,"well_pump_radius":0.65,"well_mode":"WellPump group replaces river geometry on inland installations","axle":"X","water_facing":"+Z","irrigation_coverage_cells":[15,15],"irrigation_shape":"square","irrigation_anchor":"foundation origin +/-7 cells","construction_groups":["Foundation","Frame","Walls","Roof","Details","Rotor","WellPump"]},
		"mesh_instances":meshes.size(),"triangles":triangle_count}
	var state := GLTFState.new()
	var document := GLTFDocument.new()
	if document.append_from_scene(model,state)!=OK or document.write_to_filesystem(state,OUT+"waterwheel.glb")!=OK:
		push_error("Waterwheel GLB export failed");quit(1);return
	own_nodes(model,model)
	model.set_script(null)
	var packed := PackedScene.new()
	if packed.pack(model)!=OK or ResourceSaver.save(packed,OUT+"source/waterwheel_native.tscn")!=OK:
		push_error("Waterwheel raw mesh archive failed");quit(1);return
	var file := FileAccess.open(OUT+"generation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest,"  "))
	file.close()
	print("WATERWHEEL ARCHIVE: ",meshes.size()," meshes, ",triangle_count," triangles")
	quit(0)
