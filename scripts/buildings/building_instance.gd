class_name BuildingInstance
extends Node3D

signal interacted(building: BuildingInstance, player: Node)
signal construction_stage_changed(
	building: BuildingInstance,
	stage: ConstructionStage
)
signal construction_completed(building: BuildingInstance)

enum ConstructionStage {
	FOUNDATION,
	FRAME,
	HALF_BUILT,
	COMPLETE,
}

const GameDataScript = preload("res://scripts/core/game_data.gd")
const RecipeDatabaseScript = preload("res://scripts/core/recipe_database.gd")
const ProducerStateScript = preload("res://scripts/data/producer_state.gd")
const ConstructionFeedbackScript = preload(
	"res://scripts/buildings/construction_feedback.gd"
)
const COLLISION_LAYERS := 16 | 64
const INTERACTION_LAYERS := 64 | 256
const CAMERA_OCCLUDER_LAYER := 32
const OCCLUDED_OPACITY := 0.3
const CLEAR_OPACITY := 1.0
const FADE_RATE := 10.0
const STAGE_FADE_OUT_DURATION := 0.12
const STAGE_FADE_IN_DURATION := 0.18
const CONSTRUCTION_SECONDS_PER_STAGE := 10.0
const MAX_SAFE_INTEGER := 9007199254740991
const MAX_GRID_COORDINATE := 2147483647
const CONSTRUCTION_TRANSITION_COUNT := (
	int(ConstructionStage.COMPLETE) - int(ConstructionStage.FOUNDATION)
)

@export var authored_building_id := ""

var data: BuildingData
var grid_x := 0
var grid_z := 0
var occupied_cells: Array[Dictionary] = []
var construction_stage := ConstructionStage.COMPLETE
var construction_elapsed := 0.0
var construction_duration := 0.0
var producer_state: ProducerState
var _preview_mode := false
var _preview_valid := true
var _opacity_target := CLEAR_OPACITY
var _completion_emitted := false
var _missing_construction_art_warnings := {}

var building_id: String:
	get:
		return data.building_id if data else authored_building_id

var building_data: BuildingData:
	get:
		return data
	set(value):
		data = value

var gx: int:
	get:
		return grid_x

var gz: int:
	get:
		return grid_z


static func opacity_step(current: float, target: float, delta: float) -> float:
	return lerpf(current, target, 1.0 - exp(-FADE_RATE * delta))


static func vertical_scale_for(texture_size: Vector2, target_size: Vector2) -> float:
	if texture_size.x <= 0.0 or texture_size.y <= 0.0 or target_size.x <= 0.0:
		return 1.0
	var pixel_size := target_size.x / texture_size.x
	return target_size.y / (texture_size.y * pixel_size)


static func construction_duration_for(_footprint: Vector2i) -> float:
	return CONSTRUCTION_SECONDS_PER_STAGE * float(CONSTRUCTION_TRANSITION_COUNT)


func start_construction() -> void:
	if data == null:
		return
	construction_duration = construction_duration_for(data.footprint)
	construction_elapsed = 0.0
	construction_stage = ConstructionStage.FOUNDATION
	_completion_emitted = false
	_apply_construction_stage(true)


func advance_construction(delta: float) -> void:
	if delta <= 0.0 or is_construction_complete():
		return
	if construction_duration <= 0.0:
		complete_construction()
		return
	construction_elapsed = clampf(
		construction_elapsed + delta,
		0.0,
		construction_duration
	)
	var first_threshold := CONSTRUCTION_SECONDS_PER_STAGE
	var second_threshold := CONSTRUCTION_SECONDS_PER_STAGE * 2.0
	if construction_stage == ConstructionStage.FOUNDATION and construction_elapsed >= first_threshold:
		_transition_construction_stage(ConstructionStage.FRAME)
	if construction_stage == ConstructionStage.FRAME and construction_elapsed >= second_threshold:
		_transition_construction_stage(ConstructionStage.HALF_BUILT)
	if construction_stage == ConstructionStage.HALF_BUILT and construction_elapsed >= construction_duration:
		_transition_construction_stage(ConstructionStage.COMPLETE)


func advance_construction_stage() -> void:
	if is_construction_complete():
		return
	match construction_stage:
		ConstructionStage.FOUNDATION:
			construction_elapsed = maxf(construction_elapsed, CONSTRUCTION_SECONDS_PER_STAGE)
			_transition_construction_stage(ConstructionStage.FRAME)
		ConstructionStage.FRAME:
			construction_elapsed = maxf(
				construction_elapsed,
				CONSTRUCTION_SECONDS_PER_STAGE * 2.0
			)
			_transition_construction_stage(ConstructionStage.HALF_BUILT)
		ConstructionStage.HALF_BUILT:
			complete_construction()


func complete_construction() -> void:
	if is_construction_complete() and _completion_emitted:
		return
	construction_elapsed = maxf(construction_duration, 0.0)
	_transition_construction_stage(ConstructionStage.COMPLETE)


func restore_construction(stage: int, elapsed: float) -> void:
	if data == null:
		return
	construction_duration = construction_duration_for(data.footprint)
	if stage < ConstructionStage.FOUNDATION or stage > ConstructionStage.COMPLETE:
		stage = ConstructionStage.COMPLETE
	construction_stage = stage as ConstructionStage
	if construction_stage == ConstructionStage.COMPLETE:
		construction_elapsed = construction_duration
	else:
		construction_elapsed = clampf(elapsed, 0.0, construction_duration)
		if construction_stage == ConstructionStage.FRAME:
			construction_elapsed = maxf(construction_elapsed, CONSTRUCTION_SECONDS_PER_STAGE)
		elif construction_stage == ConstructionStage.HALF_BUILT:
			construction_elapsed = maxf(
				construction_elapsed,
				CONSTRUCTION_SECONDS_PER_STAGE * 2.0
			)
	_completion_emitted = construction_stage == ConstructionStage.COMPLETE
	_apply_construction_stage(false)


func is_construction_complete() -> bool:
	return construction_stage == ConstructionStage.COMPLETE


func get_construction_progress() -> float:
	if is_construction_complete():
		return 1.0
	if construction_duration <= 0.0:
		return 0.0
	return clampf(construction_elapsed / construction_duration, 0.0, 1.0)


func _transition_construction_stage(next_stage: ConstructionStage) -> void:
	if construction_stage == next_stage:
		return
	construction_stage = next_stage
	_apply_construction_stage(true)
	construction_stage_changed.emit(self, construction_stage)
	if construction_stage == ConstructionStage.COMPLETE and not _completion_emitted:
		_completion_emitted = true
		construction_completed.emit(self)


func _ready() -> void:
	_ensure_nodes()
	if data == null and not authored_building_id.is_empty():
		var game_data = GameDataScript.new()
		configure(BuildingData.from_dictionary(game_data.get_building(authored_building_id)), 0, 0, [])
		game_data.free()


func configure(
	building_data: BuildingData,
	gx: int,
	gz: int,
	cells: Array
) -> void:
	data = building_data
	grid_x = gx
	grid_z = gz
	occupied_cells.clear()
	for cell in cells:
		if cell is Dictionary:
			occupied_cells.append((cell as Dictionary).duplicate(true))
	if producer_state == null and data != null and RecipeDatabaseScript.has_station(data.building_id):
		producer_state = ProducerStateScript.new(data.building_id)
	_ensure_nodes()
	if data == null or not data.is_valid():
		return
	name = data.display_name
	_configure_visuals()
	_configure_physics()
	_apply_construction_stage(false)
	if not _preview_mode and not is_in_group("building_instance"):
		add_to_group("building_instance")


func set_preview_mode(value: bool) -> void:
	_preview_mode = value
	_ensure_nodes()
	_apply_physics_state()
	if value:
		remove_from_group("building_instance")
	else:
		add_to_group("building_instance")
	_apply_visual_color()
	_sync_construction_feedback()


func deactivate() -> void:
	_ensure_nodes()
	var collision := get_node("Collision") as StaticBody3D
	var interaction_area := get_node("InteractionArea") as Area3D
	var camera_occluder := get_node("CameraOccluder") as Area3D
	collision.collision_layer = 0
	collision.collision_mask = 0
	interaction_area.collision_layer = 0
	interaction_area.collision_mask = 0
	interaction_area.monitoring = false
	camera_occluder.collision_layer = 0
	camera_occluder.collision_mask = 0
	camera_occluder.monitoring = false
	remove_from_group("building_instance")
	_sync_construction_feedback(false)
	visible = false
	set_process(false)


func set_preview_valid(value: bool) -> void:
	_preview_valid = value
	_apply_visual_color()


func set_camera_occluded(value: bool) -> void:
	_opacity_target = OCCLUDED_OPACITY if value else CLEAR_OPACITY


func get_target_opacity() -> float:
	return _opacity_target


func get_interaction_area() -> Area3D:
	_ensure_nodes()
	return get_node("InteractionArea") as Area3D


func interact(player: Node) -> void:
	if not is_construction_complete():
		return
	interacted.emit(self, player)


func to_dict() -> Dictionary:
	var result := {
		"building_id": data.building_id if data else authored_building_id,
		"gx": grid_x,
		"gz": grid_z,
		"occupied_cells": occupied_cells.duplicate(true),
		"construction_stage": int(construction_stage),
		"construction_elapsed": construction_elapsed,
		"construction_duration": construction_duration,
	}
	if producer_state != null:
		result["producer_state"] = producer_state.to_dict()
	return result


func from_dict(source: Dictionary) -> bool:
	if typeof(source.get("building_id")) != TYPE_STRING:
		return false
	var parsed_gx: Variant = _integer_number(source.get("gx"))
	var parsed_gz: Variant = _integer_number(source.get("gz"))
	if not _is_grid_coordinate(parsed_gx) or not _is_grid_coordinate(parsed_gz):
		return false
	var saved_cells: Variant = source.get("occupied_cells", [])
	if not saved_cells is Array:
		return false
	var normalized_saved_cells: Array[Dictionary] = []
	var saved_cell_states := {}
	for value in saved_cells:
		if not value is Dictionary:
			return false
		var cell := value as Dictionary
		var cell_gx: Variant = _integer_number(cell.get("gx"))
		var cell_gz: Variant = _integer_number(cell.get("gz"))
		var previous_state: Variant = _integer_number(cell.get("previous_state"))
		if not _is_grid_coordinate(cell_gx) or not _is_grid_coordinate(cell_gz):
			return false
		if previous_state == null or int(previous_state) not in [
			GridCell.State.WASTELAND,
			GridCell.State.FARMLAND,
		]:
			return false
		var location := Vector2i(int(cell_gx), int(cell_gz))
		if saved_cell_states.has(location):
			return false
		saved_cell_states[location] = int(previous_state)
		normalized_saved_cells.append({
			"gx": location.x,
			"gz": location.y,
			"previous_state": int(previous_state),
		})
	var next_cells: Array[Dictionary] = []
	if occupied_cells.is_empty():
		next_cells.assign(normalized_saved_cells)
	else:
		if occupied_cells.size() != saved_cell_states.size():
			return false
		var authoritative_locations := {}
		for authoritative_cell in occupied_cells:
			var location := Vector2i(
				int(authoritative_cell.get("gx", -1)),
				int(authoritative_cell.get("gz", -1))
			)
			if authoritative_locations.has(location) or not saved_cell_states.has(location):
				return false
			authoritative_locations[location] = true
			next_cells.append({
				"gx": location.x,
				"gz": location.y,
				"previous_state": int(saved_cell_states[location]),
			})
	var saved_stage: Variant = source.get("construction_stage", int(ConstructionStage.COMPLETE))
	var saved_elapsed: Variant = source.get("construction_elapsed", 0.0)
	var saved_duration: Variant = source.get("construction_duration", 0.0)
	var parsed_stage: Variant = _integer_number(saved_stage)
	if parsed_stage == null:
		return false
	if int(parsed_stage) < int(ConstructionStage.FOUNDATION) or int(parsed_stage) > int(ConstructionStage.COMPLETE):
		return false
	if not saved_elapsed is float and not saved_elapsed is int:
		return false
	if not saved_duration is float and not saved_duration is int:
		return false
	if not is_finite(float(saved_elapsed)) or float(saved_elapsed) < 0.0:
		return false
	if not is_finite(float(saved_duration)) or float(saved_duration) < 0.0:
		return false
	var next_producer: ProducerState
	if source.has("producer_state"):
		if not source.producer_state is Dictionary:
			return false
		next_producer = ProducerStateScript.new()
		if not next_producer.from_dict(source.producer_state):
			return false
	elif RecipeDatabaseScript.has_station(str(source.building_id)):
		next_producer = ProducerStateScript.new(str(source.building_id))
	if next_producer != null and next_producer.station_id != str(source.building_id):
		return false

	if data != null and str(source.building_id) != data.building_id:
		return false
	if data == null:
		authored_building_id = str(source.building_id)
	grid_x = int(parsed_gx)
	grid_z = int(parsed_gz)
	occupied_cells.assign(next_cells)
	construction_stage = int(parsed_stage) as ConstructionStage
	construction_elapsed = float(saved_elapsed)
	construction_duration = float(saved_duration)
	_completion_emitted = construction_stage == ConstructionStage.COMPLETE
	producer_state = next_producer
	return true


static func _integer_number(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		if int(value) < -MAX_SAFE_INTEGER or int(value) > MAX_SAFE_INTEGER:
			return null
		return value
	if typeof(value) != TYPE_FLOAT:
		return null
	var number := float(value)
	if not is_finite(number) or absf(number) > float(MAX_SAFE_INTEGER):
		return null
	if number != floorf(number):
		return null
	return int(number)


static func _is_grid_coordinate(value: Variant) -> bool:
	return value != null and int(value) >= 0 and int(value) <= MAX_GRID_COORDINATE


func _process(delta: float) -> void:
	if not _preview_mode and not is_construction_complete():
		advance_construction(delta)
	_sync_construction_feedback()
	var feedback := get_node_or_null("ConstructionFeedback") as ConstructionFeedback
	if feedback != null:
		feedback.advance_animation(delta)
	if _preview_mode:
		return
	for geometry in _visual_geometry():
		if geometry is Sprite3D:
			var sprite := geometry as Sprite3D
			var color: Color = sprite.modulate
			color.a = opacity_step(color.a, _opacity_target, delta)
			sprite.modulate = color
		elif geometry is MeshInstance3D:
			var mesh := geometry as MeshInstance3D
			var current_alpha := 1.0 - mesh.transparency
			mesh.transparency = 1.0 - opacity_step(current_alpha, _opacity_target, delta)


func _ensure_nodes() -> void:
	var visual_root := get_node_or_null("VisualRoot") as Node3D
	if visual_root == null:
		visual_root = Node3D.new()
		visual_root.name = "VisualRoot"
		add_child(visual_root)
	if visual_root.get_node_or_null("BackLayer") == null:
		var back := Sprite3D.new()
		back.name = "BackLayer"
		visual_root.add_child(back)
	if visual_root.get_node_or_null("FrontLayer") == null:
		var front := Sprite3D.new()
		front.name = "FrontLayer"
		visual_root.add_child(front)
	if visual_root.get_node_or_null("FallbackBody") == null:
		var fallback_body := MeshInstance3D.new()
		fallback_body.name = "FallbackBody"
		visual_root.add_child(fallback_body)
	if visual_root.get_node_or_null("FallbackRoof") == null:
		var fallback_roof := MeshInstance3D.new()
		fallback_roof.name = "FallbackRoof"
		visual_root.add_child(fallback_roof)
	if visual_root.get_node_or_null("ConstructionLayer") == null:
		var construction_layer := Sprite3D.new()
		construction_layer.name = "ConstructionLayer"
		visual_root.add_child(construction_layer)
	if visual_root.get_node_or_null("ConstructionFallback") == null:
		var construction_fallback := Node3D.new()
		construction_fallback.name = "ConstructionFallback"
		visual_root.add_child(construction_fallback)
	if visual_root.get_node_or_null("ConstructionTransitions") == null:
		var construction_transitions := Node3D.new()
		construction_transitions.name = "ConstructionTransitions"
		visual_root.add_child(construction_transitions)
	if visual_root.get_node_or_null("ConstructionEffects") == null:
		var construction_effects := Node3D.new()
		construction_effects.name = "ConstructionEffects"
		visual_root.add_child(construction_effects)
	if get_node_or_null("ConstructionFeedback") == null:
		var feedback := ConstructionFeedbackScript.new() as ConstructionFeedback
		feedback.name = "ConstructionFeedback"
		add_child(feedback)
	_ensure_physics_node("Collision", StaticBody3D)
	_ensure_physics_node("InteractionArea", Area3D)
	_ensure_physics_node("CameraOccluder", Area3D)


func _ensure_physics_node(node_name: String, node_type: Variant) -> void:
	var physics_node := get_node_or_null(node_name) as CollisionObject3D
	if physics_node == null:
		physics_node = node_type.new()
		physics_node.name = node_name
		add_child(physics_node)
	if physics_node.get_node_or_null("CollisionShape3D") == null:
		var collision_shape := CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		physics_node.add_child(collision_shape)


func _configure_visuals() -> void:
	var visual_root := get_node("VisualRoot") as Node3D
	var back := visual_root.get_node("BackLayer") as Sprite3D
	var front := visual_root.get_node("FrontLayer") as Sprite3D
	var base_path := "res://assets/buildings/painted/%s/%s" % [data.building_id, data.building_id]
	var back_texture := _load_texture(base_path + "_back.png")
	var front_texture := _load_texture(base_path + "_front.png")
	var has_painted_layers := back_texture != null and front_texture != null
	back.visible = has_painted_layers
	front.visible = has_painted_layers
	if has_painted_layers:
		_configure_sprite(back, back_texture, Vector3.ZERO, -0.1)
		_configure_sprite(front, front_texture, Vector3(0.025, 0.0, 0.025), 0.1)
	_configure_fallback(not has_painted_layers)
	_configure_construction_fallback()
	var feedback := get_node("ConstructionFeedback") as ConstructionFeedback
	feedback.configure(data.visual_size)
	_apply_visual_color()


func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _sync_construction_feedback(active: bool = true) -> void:
	var feedback := get_node_or_null("ConstructionFeedback") as ConstructionFeedback
	if feedback == null:
		return
	feedback.update_state(
		get_construction_progress(),
		_preview_mode,
		is_construction_complete(),
		active
	)


func get_construction_texture_path(stage: ConstructionStage) -> String:
	if data == null or stage == ConstructionStage.COMPLETE:
		return ""
	var suffix: String = str({
		ConstructionStage.FOUNDATION: "foundation",
		ConstructionStage.FRAME: "frame",
		ConstructionStage.HALF_BUILT: "half_built",
	}.get(stage, ""))
	if suffix.is_empty():
		return ""
	return "res://assets/buildings/construction/%s/%s_%s.png" % [
		data.building_id,
		data.building_id,
		suffix,
	]


func get_missing_construction_art_warning_count() -> int:
	return _missing_construction_art_warnings.size()


func _configure_sprite(
	sprite: Sprite3D,
	texture: Texture2D,
	offset: Vector3,
	sort_offset: float
) -> void:
	sprite.texture = texture
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.pixel_size = data.visual_size.x / float(texture.get_width())
	sprite.scale = Vector3(
		1.0,
		vertical_scale_for(texture.get_size(), data.visual_size),
		1.0
	)
	sprite.position = Vector3(
		offset.x,
		data.visual_size.y * 0.5 + offset.y,
		offset.z
	)
	sprite.sorting_offset = sort_offset


func _configure_fallback(visible: bool) -> void:
	var body := get_node("VisualRoot/FallbackBody") as MeshInstance3D
	var roof := get_node("VisualRoot/FallbackRoof") as MeshInstance3D
	body.visible = visible
	roof.visible = visible
	if not visible:
		return
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(
		maxf(float(data.footprint.x) * 0.72, 0.45),
		data.visual_size.y * 0.55,
		maxf(float(data.footprint.y) * 0.72, 0.45)
	)
	body.mesh = body_mesh
	body.position.y = body_mesh.size.y * 0.5
	body.material_override = _fallback_material(Color("b97b4c"))
	var roof_mesh := PrismMesh.new()
	roof_mesh.size = Vector3(
		body_mesh.size.x * 1.12,
		data.visual_size.y * 0.28,
		body_mesh.size.z * 1.12
	)
	roof.mesh = roof_mesh
	roof.position.y = body_mesh.size.y + roof_mesh.size.y * 0.35
	roof.material_override = _fallback_material(Color("5f4336"))


func _fallback_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material


func _configure_construction_fallback() -> void:
	var fallback := get_node("VisualRoot/ConstructionFallback") as Node3D
	for child in fallback.get_children():
		child.free()

	var slab := MeshInstance3D.new()
	slab.name = "Foundation"
	var slab_mesh := BoxMesh.new()
	slab_mesh.size = Vector3(
		maxf(float(data.footprint.x) * 0.82, 0.45),
		0.12,
		maxf(float(data.footprint.y) * 0.82, 0.45)
	)
	slab.mesh = slab_mesh
	slab.position.y = 0.06
	slab.material_override = _fallback_material(Color("8f806c"))
	fallback.add_child(slab)

	var frame_root := Node3D.new()
	frame_root.name = "Frame"
	fallback.add_child(frame_root)
	var width := maxf(float(data.footprint.x) * 0.72, 0.38)
	var depth := maxf(float(data.footprint.y) * 0.72, 0.38)
	var height := maxf(data.visual_size.y * 0.72, 0.5)
	for corner in [
		Vector3(-width * 0.5, height * 0.5, -depth * 0.5),
		Vector3(width * 0.5, height * 0.5, -depth * 0.5),
		Vector3(-width * 0.5, height * 0.5, depth * 0.5),
		Vector3(width * 0.5, height * 0.5, depth * 0.5),
	]:
		var post := MeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.07, height, 0.07)
		post.mesh = post_mesh
		post.position = corner
		post.material_override = _fallback_material(Color("a56e3f"))
		frame_root.add_child(post)

	var half_body := MeshInstance3D.new()
	half_body.name = "HalfBuilt"
	var half_mesh := BoxMesh.new()
	half_mesh.size = Vector3(width * 0.92, height * 0.58, depth * 0.92)
	half_body.mesh = half_mesh
	half_body.position.y = half_mesh.size.y * 0.5
	half_body.material_override = _fallback_material(Color("b88a5a"))
	fallback.add_child(half_body)


func _apply_construction_stage(play_effect: bool) -> void:
	if data == null:
		return
	_ensure_nodes()
	var visual_root := get_node("VisualRoot") as Node3D
	var back := visual_root.get_node("BackLayer") as Sprite3D
	var front := visual_root.get_node("FrontLayer") as Sprite3D
	var body := visual_root.get_node("FallbackBody") as MeshInstance3D
	var roof := visual_root.get_node("FallbackRoof") as MeshInstance3D
	var construction_layer := visual_root.get_node("ConstructionLayer") as Sprite3D
	var construction_fallback := visual_root.get_node("ConstructionFallback") as Node3D
	var completed := is_construction_complete()

	if play_effect:
		_retain_outgoing_construction_visual(construction_layer)
	back.visible = completed and back.texture != null
	front.visible = completed and front.texture != null
	body.visible = completed and back.texture == null
	roof.visible = completed and front.texture == null
	construction_layer.visible = not completed
	construction_fallback.visible = not completed

	if not completed:
		var texture_path := get_construction_texture_path(construction_stage)
		var texture := _load_texture(texture_path)
		construction_layer.texture = texture
		construction_layer.visible = texture != null
		construction_fallback.visible = texture == null
		if texture:
			_configure_sprite(construction_layer, texture, Vector3.ZERO, 0.0)
			_fade_in_geometry(construction_layer)
		else:
			_warn_missing_construction_art(texture_path)
		var foundation := construction_fallback.get_node("Foundation") as MeshInstance3D
		var frame := construction_fallback.get_node("Frame") as Node3D
		var half_body := construction_fallback.get_node("HalfBuilt") as MeshInstance3D
		foundation.visible = true
		frame.visible = construction_stage >= ConstructionStage.FRAME
		half_body.visible = construction_stage >= ConstructionStage.HALF_BUILT
	else:
		construction_layer.texture = null
		if back.visible:
			_fade_in_geometry(back)
		if front.visible:
			_fade_in_geometry(front)

	var feedback := get_node("ConstructionFeedback") as ConstructionFeedback
	feedback.configure(data.visual_size, construction_layer.texture)
	_sync_construction_feedback()
	_apply_physics_state()
	if play_effect:
		_play_construction_effect(construction_stage)


func _retain_outgoing_construction_visual(source: Sprite3D) -> void:
	if not is_inside_tree() or not source.visible or source.texture == null:
		return
	var transitions := get_node("VisualRoot/ConstructionTransitions") as Node3D
	var outgoing := source.duplicate() as Sprite3D
	if outgoing == null:
		return
	outgoing.name = "ConstructionOutgoing"
	outgoing.sorting_offset = source.sorting_offset + 0.01
	transitions.add_child(outgoing)
	var target := outgoing.modulate
	target.a = 0.0
	var tween := create_tween()
	tween.tween_property(outgoing, "modulate", target, STAGE_FADE_OUT_DURATION)
	tween.finished.connect(outgoing.queue_free)


func _warn_missing_construction_art(path: String) -> void:
	if path.is_empty() or _missing_construction_art_warnings.has(path):
		return
	_missing_construction_art_warnings[path] = true
	push_warning(
		"Missing construction stage art '%s'; using procedural fallback for %s."
		% [path, building_id]
	)


func _fade_in_geometry(geometry: GeometryInstance3D) -> void:
	if not is_inside_tree():
		return
	if geometry is Sprite3D:
		var sprite := geometry as Sprite3D
		var target := sprite.modulate
		target.a = 1.0
		sprite.modulate.a = 0.0
		create_tween().tween_property(sprite, "modulate", target, STAGE_FADE_IN_DURATION)


func _play_construction_effect(stage: ConstructionStage) -> void:
	if not is_inside_tree():
		return
	var effects := get_node("VisualRoot/ConstructionEffects") as Node3D
	var particles := CPUParticles3D.new()
	particles.name = "Dust" if stage in [ConstructionStage.FOUNDATION, ConstructionStage.COMPLETE] else "WoodChips"
	particles.one_shot = true
	particles.amount = 12 if particles.name == "Dust" else 8
	particles.lifetime = 0.55
	particles.explosiveness = 0.85
	particles.direction = Vector3.UP
	particles.spread = 55.0
	particles.initial_velocity_min = 0.45
	particles.initial_velocity_max = 0.9
	particles.gravity = Vector3(0.0, -1.4, 0.0)
	var particle_mesh := QuadMesh.new()
	particle_mesh.size = Vector2(0.08, 0.08)
	var particle_material := StandardMaterial3D.new()
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particle_material.albedo_color = (
		Color(0.72, 0.56, 0.34, 0.72)
		if particles.name == "WoodChips"
		else Color(0.77, 0.69, 0.54, 0.52)
	)
	particle_mesh.material = particle_material
	particles.mesh = particle_mesh
	particles.position.y = 0.12
	effects.add_child(particles)
	particles.finished.connect(particles.queue_free)
	particles.emitting = true


func _configure_physics() -> void:
	var footprint_size := Vector3(
		maxf(float(data.footprint.x) * 0.78, 0.4),
		maxf(data.visual_size.y * 0.58, 0.5),
		maxf(float(data.footprint.y) * 0.78, 0.4)
	)
	_set_box_shape("Collision", footprint_size, footprint_size.y * 0.5)
	_set_box_shape(
		"InteractionArea",
		footprint_size + Vector3(0.55, 0.35, 0.55),
		(footprint_size.y + 0.35) * 0.5
	)
	_set_box_shape(
		"CameraOccluder",
		Vector3(
			maxf(data.visual_size.x * 0.82, 0.5),
			maxf(data.visual_size.y * 0.9, 0.6),
			maxf(float(data.footprint.y) * 0.65, 0.4)
		),
		data.visual_size.y * 0.45
	)
	set_preview_mode(_preview_mode)


func _apply_physics_state() -> void:
	var collision := get_node("Collision") as StaticBody3D
	var interaction_area := get_node("InteractionArea") as Area3D
	var camera_occluder := get_node("CameraOccluder") as Area3D
	var active := not _preview_mode
	var completed := is_construction_complete()
	collision.collision_layer = COLLISION_LAYERS if active else 0
	collision.collision_mask = 0
	interaction_area.collision_layer = INTERACTION_LAYERS if active and completed else 0
	interaction_area.collision_mask = 0
	interaction_area.monitoring = active and completed
	camera_occluder.collision_layer = (
		CAMERA_OCCLUDER_LAYER
		if active and construction_stage != ConstructionStage.FOUNDATION
		else 0
	)
	camera_occluder.collision_mask = 0
	camera_occluder.monitoring = false


func _set_box_shape(node_path: NodePath, size: Vector3, center_y: float) -> void:
	var collision_shape := get_node(NodePath("%s/CollisionShape3D" % node_path)) as CollisionShape3D
	var shape := BoxShape3D.new()
	shape.size = size
	collision_shape.shape = shape
	collision_shape.position.y = center_y


func _apply_visual_color() -> void:
	var tint := Color.WHITE
	if _preview_mode:
		tint = Color(0.48, 1.0, 0.52, 0.68) if _preview_valid else Color(1.0, 0.38, 0.38, 0.68)
	for geometry in _visual_geometry():
		if geometry is Sprite3D:
			(geometry as Sprite3D).modulate = tint
		elif geometry is MeshInstance3D:
			var mesh := geometry as MeshInstance3D
			var material := mesh.material_override as StandardMaterial3D
			if material:
				material.albedo_color = Color(tint.r, tint.g, tint.b, 1.0)
			mesh.transparency = 1.0 - tint.a


func _visual_geometry() -> Array[GeometryInstance3D]:
	var result: Array[GeometryInstance3D] = []
	var visual_root := get_node_or_null("VisualRoot")
	if visual_root == null:
		return result
	_collect_visual_geometry(visual_root, result)
	return result


func _collect_visual_geometry(
	parent: Node,
	result: Array[GeometryInstance3D]
) -> void:
	for child in parent.get_children():
		if child is GeometryInstance3D:
			result.append(child)
		if child.get_child_count() > 0:
			_collect_visual_geometry(child, result)
