class_name ResourceNode
extends Node3D

signal gathering_active_changed(resource_id: String, active: bool)

const ResourceCatalogScript = preload("res://scripts/world/resource_catalog.gd")
const INTERACTION_LAYER := 64
const OBSTACLE_LAYER := 16
const STATE_VERSION := 2
const MINING_ATLAS_PATH := "res://assets/resources/mining/ore-mining-sheet.png"
const MINING_ACTION_DURATION := 3.0
const MINING_FRAME_FADE_DURATION := 0.16
const FIRST_MINING_FRAME_CENTER := 1.0 / 3.0
const SECOND_MINING_FRAME_CENTER := 2.0 / 3.0
const ORE_PAINTED_WIDTH := 1.04
const ORE_PAINTED_HEIGHT := 0.82

@export var resource_id := ""
@export var resource_type := "stone"
@export var item_id := "stone"
@export var required_tool := "pickaxe"
@export var max_units := 4
@export var remaining_units := 4
@export var respawn_days := 3
@export var visual_stage := 0
@export var gathering_enabled := true
@export var interaction_radius := 0.52

# Compatibility surfaces for old scenes and callers. Runtime rewards use the
# target-owned batch returned by preview_reward().
var hits_remaining: int:
	get:
		return remaining_units
	set(value):
		remaining_units = value
		_update_visual_stage()
var yield_per_hit: Dictionary:
	get:
		return {item_id: 1} if not item_id.is_empty() else {}
	set(value):
		if value is Dictionary and not value.is_empty():
			item_id = str(value.keys()[0])
var bonus_table: Array[Dictionary] = []
var visual_kind := "stone"

var _respawn_day := 0
var _last_advanced_day := 0
var _legacy_max_hits := 3
var _gather_active := false
var _default_position := Vector3.ZERO
var _gather_transaction_depth := 0
var _gather_transaction_initial_active := false
var _mining_active := false
var _mining_frame := -1
var _mining_atlas: Texture2D
var _mining_blend_visual: Sprite3D
var _mining_frame_positions: Array[Vector3] = []


func _ready() -> void:
	if gathering_enabled:
		add_to_group("gatherable_resource")
	else:
		remove_from_group("gatherable_resource")
	_set_gather_active(gathering_enabled and remaining_units > 0)
	_apply_visual_stage()


func configure_resource(definition: Dictionary) -> bool:
	var next_id := str(definition.get("resource_id", ""))
	var next_position: Variant = definition.get("position", Vector3.ZERO)
	if next_id.is_empty() or not next_position is Vector3 or not _finite_vector3(next_position):
		return false

	var next_type := str(definition.get("resource_type", ""))
	if next_type.is_empty():
		next_type = _infer_resource_type(definition)
	var catalog := ResourceCatalogScript.definition(next_type)
	var next_item := str(definition.get("item_id", catalog.get("item_id", "")))
	if next_item.is_empty():
		var legacy_reward: Variant = definition.get("yield_per_hit", {})
		if legacy_reward is Dictionary and not legacy_reward.is_empty():
			next_item = str(legacy_reward.keys()[0])
	var next_tool := str(definition.get("required_tool", catalog.get("required_tool", "")))
	var next_max_value: Variant = definition.get(
		"max_units",
		definition.get("hits", catalog.get("max_units", 0))
	)
	var next_respawn_value: Variant = definition.get(
		"respawn_days",
		catalog.get("respawn_days", 0)
	)
	if (
		next_type.is_empty()
		or next_item.is_empty()
		or next_tool not in ["axe", "pickaxe"]
		or not _is_positive_integer(next_max_value)
		or not _is_non_negative_integer(next_respawn_value)
	):
		return false

	resource_id = next_id
	resource_type = next_type
	item_id = next_item
	required_tool = next_tool
	max_units = int(next_max_value)
	remaining_units = max_units
	_legacy_max_hits = int(definition.get("hits", 3))
	respawn_days = int(next_respawn_value)
	position = next_position
	_default_position = next_position
	visual_kind = str(definition.get("visual_kind", catalog.get("visual_kind", next_type)))
	gathering_enabled = bool(definition.get("gatherable", true))
	bonus_table.clear()
	_respawn_day = 0
	_last_advanced_day = 0
	_update_visual_stage()
	if is_inside_tree():
		if gathering_enabled:
			add_to_group("gatherable_resource")
		else:
			remove_from_group("gatherable_resource")
	_set_gather_active(gathering_enabled and remaining_units > 0)
	return true


func can_gather(tool_id: String) -> bool:
	return (
		gathering_enabled
		and not resource_id.is_empty()
		and tool_id == required_tool
		and remaining_units > 0
		and not item_id.is_empty()
	)


func preview_reward(tool_id: String) -> Dictionary:
	return {item_id: remaining_units} if can_gather(tool_id) else {}


func commit_gather(tool_id: String, total_day: int = 0) -> Dictionary:
	if total_day < 0:
		return {}
	var reward := preview_reward(tool_id)
	if reward.is_empty():
		return {}
	remaining_units -= int(reward.get(item_id, 0))
	if remaining_units == 0:
		_respawn_day = total_day + respawn_days
	_update_visual_stage()
	_set_gather_active(gathering_enabled and remaining_units > 0)
	return reward


func get_gather_duration() -> float:
	return MINING_ACTION_DURATION


func advance_day(total_day: int) -> bool:
	if total_day < 0 or total_day <= _last_advanced_day:
		return false
	_last_advanced_day = total_day
	if remaining_units > 0 or _respawn_day <= 0 or total_day < _respawn_day:
		return false
	remaining_units = max_units
	_respawn_day = 0
	_update_visual_stage()
	_set_gather_active(gathering_enabled)
	return true


func initialize_at_day(total_day: int) -> void:
	remaining_units = max_units
	_respawn_day = 0
	_last_advanced_day = maxi(total_day, 0)
	_update_visual_stage()
	_set_gather_active(gathering_enabled)


func sync_day_cursor(total_day: int) -> bool:
	if total_day < 0:
		return false
	_last_advanced_day = total_day
	return true


func get_respawn_day() -> int:
	return _respawn_day


func get_display_name() -> String:
	return str(ResourceCatalogScript.definition(resource_type).get("display_name", resource_type))


func get_interaction_radius() -> float:
	return maxf(0.0, interaction_radius)


func to_dict() -> Dictionary:
	return {
		"state_version": STATE_VERSION,
		"resource_id": resource_id,
		"resource_type": resource_type,
		"item_id": item_id,
		"required_tool": required_tool,
		"max_units": max_units,
		"remaining_units": remaining_units,
		"respawn_days": respawn_days,
		"respawn_day": _respawn_day,
		"position": [position.x, position.y, position.z],
		"visual_stage": visual_stage,
	}


func validate_state_dict(data: Variant, loaded_day: int = -1) -> bool:
	return not _normalized_state(data, loaded_day).is_empty()


func normalize_state_dict(data: Variant, loaded_day: int = -1) -> Dictionary:
	return _normalized_state(data, loaded_day)


func default_state_dict() -> Dictionary:
	return {
		"state_version": STATE_VERSION,
		"resource_id": resource_id,
		"resource_type": resource_type,
		"item_id": item_id,
		"required_tool": required_tool,
		"max_units": max_units,
		"remaining_units": max_units,
		"respawn_days": respawn_days,
		"respawn_day": 0,
		"position": [_default_position.x, _default_position.y, _default_position.z],
		"visual_stage": 0,
	}


func from_dict(data: Dictionary) -> bool:
	var normalized := _normalized_state(data)
	if normalized.is_empty():
		return false
	var saved_position: Array = normalized.position
	position = Vector3(float(saved_position[0]), float(saved_position[1]), float(saved_position[2]))
	remaining_units = int(normalized.remaining_units)
	_respawn_day = int(normalized.respawn_day)
	_update_visual_stage()
	_set_gather_active(gathering_enabled and remaining_units > 0)
	return true


func build_fallback_visual() -> void:
	if get_node_or_null("Visual") != null or get_node_or_null("Collision") != null:
		return
	_mining_atlas = load(MINING_ATLAS_PATH) as Texture2D
	if _mining_atlas == null or _mining_atlas.get_width() % 4 != 0:
		push_error("Missing or invalid hand-painted mining atlas: %s" % MINING_ATLAS_PATH)
		return
	var visual := Sprite3D.new()
	visual.name = "Visual"
	_configure_mining_sprite(visual)
	_prepare_mining_layout(visual)
	add_child(visual)

	_mining_blend_visual = Sprite3D.new()
	_mining_blend_visual.name = "MiningBlendVisual"
	_configure_mining_sprite(_mining_blend_visual)
	_mining_blend_visual.pixel_size = visual.pixel_size
	_mining_blend_visual.scale = visual.scale
	_mining_blend_visual.position = visual.position
	_mining_blend_visual.render_priority = 1
	_mining_blend_visual.visible = false
	add_child(_mining_blend_visual)

	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = OBSTACLE_LAYER | INTERACTION_LAYER
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var sphere := SphereShape3D.new()
	sphere.radius = 0.52
	collision.shape = sphere
	collision.position.y = 0.2
	body.add_child(collision)
	add_child(body)
	_apply_visual_stage()
	_set_gather_active(gathering_enabled and remaining_units > 0)


func _set_gather_active(active: bool) -> void:
	visible = true
	var body := get_node_or_null("Collision") as CollisionObject3D
	if body != null:
		# Inactive ore must stop blocking navigation, but its visible rubble/full
		# model remains pointer-addressable so the pickaxe hover can explain the
		# unavailable state with a red eligibility ring.
		body.collision_layer = (
			(OBSTACLE_LAYER | INTERACTION_LAYER) if active else INTERACTION_LAYER
		)
	if active != _gather_active:
		_gather_active = active
		if _gather_transaction_depth == 0:
			gathering_active_changed.emit(resource_id, active)


func begin_gather_transaction() -> bool:
	if _gather_transaction_depth != 0:
		return false
	_gather_transaction_initial_active = _gather_active
	_gather_transaction_depth = 1
	return true


func end_gather_transaction(commit: bool) -> bool:
	if _gather_transaction_depth != 1:
		return false
	var active_changed := _gather_active != _gather_transaction_initial_active
	_gather_transaction_depth = 0
	if commit and active_changed:
		gathering_active_changed.emit(resource_id, _gather_active)
	return true


func _update_visual_stage() -> void:
	if remaining_units <= 0:
		visual_stage = 3
	elif remaining_units >= max_units:
		visual_stage = 0
	elif remaining_units * 3 > max_units:
		visual_stage = 1
	else:
		visual_stage = 2
	_apply_visual_stage()


func _apply_visual_stage() -> void:
	var visual := get_node_or_null("Visual") as Node3D
	if visual == null:
		return
	if visual is Sprite3D and _mining_atlas != null:
		_mining_active = false
		_mining_frame = -1
		_show_persistent_mining_stage()
		return
	match visual_stage:
		0:
			visual.scale = Vector3.ONE
		1:
			visual.scale = Vector3(0.82, 0.82, 0.82)
		2:
			visual.scale = Vector3(0.62, 0.62, 0.62)
		_:
			visual.scale = Vector3(0.42, 0.18, 0.42)


func begin_mining() -> bool:
	if required_tool != "pickaxe" or remaining_units <= 0 or _mining_atlas == null:
		return false
	_mining_active = true
	set_mining_progress(0.0)
	return true


func set_mining_progress(progress: float) -> void:
	if not _mining_active:
		return
	var value := clampf(progress, 0.0, 1.0)
	var fade_half_progress := MINING_FRAME_FADE_DURATION / MINING_ACTION_DURATION * 0.5
	if absf(value - FIRST_MINING_FRAME_CENTER) <= fade_half_progress:
		_show_mining_blend(
			0,
			1,
			inverse_lerp(
				FIRST_MINING_FRAME_CENTER - fade_half_progress,
				FIRST_MINING_FRAME_CENTER + fade_half_progress,
				value
			)
		)
	elif absf(value - SECOND_MINING_FRAME_CENTER) <= fade_half_progress:
		_show_mining_blend(
			1,
			2,
			inverse_lerp(
				SECOND_MINING_FRAME_CENTER - fade_half_progress,
				SECOND_MINING_FRAME_CENTER + fade_half_progress,
				value
			)
		)
	else:
		_show_mining_frame(
			0 if value < FIRST_MINING_FRAME_CENTER else (1 if value < SECOND_MINING_FRAME_CENTER else 2)
		)


func cancel_mining() -> void:
	_mining_active = false
	_mining_frame = -1
	_show_persistent_mining_stage()


func get_mining_frame() -> int:
	return _mining_frame


func _configure_mining_sprite(target: Sprite3D) -> void:
	target.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	target.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	target.no_depth_test = false
	target.shaded = false
	target.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	target.modulate = Color.WHITE.lerp(_fallback_color(), 0.55)


func _prepare_mining_layout(target: Sprite3D) -> void:
	var cell_size := Vector2(float(_mining_atlas.get_width()) / 4.0, float(_mining_atlas.get_height()))
	var standing_bounds := mining_frame_used_rect(_mining_atlas, 0)
	var painted_width := maxf(float(standing_bounds.size.x), 1.0)
	var painted_height := maxf(float(standing_bounds.size.y), 1.0)
	target.pixel_size = ORE_PAINTED_WIDTH / painted_width
	target.scale = Vector3(
		1.0,
		ORE_PAINTED_HEIGHT / (painted_height * target.pixel_size),
		1.0
	)
	_mining_frame_positions.clear()
	for frame in range(4):
		var frame_anchor := mining_ground_anchor(_mining_atlas, frame)
		_mining_frame_positions.append(Vector3(
			-(frame_anchor.x - cell_size.x * 0.5) * target.pixel_size * target.scale.x,
			-(cell_size.y * 0.5 - frame_anchor.y) * target.pixel_size * target.scale.y,
			0.0
		))
	target.position = _mining_frame_positions[0]


func _show_mining_frame(frame: int) -> void:
	var visual := get_node_or_null("Visual") as Sprite3D
	if visual == null or frame < 0 or frame > 2:
		return
	_set_mining_texture(visual, frame)
	_set_mining_sprite_alpha(visual, 1.0)
	visual.visible = true
	if _mining_blend_visual != null:
		_mining_blend_visual.visible = false
		_set_mining_sprite_alpha(_mining_blend_visual, 0.0)
	_mining_frame = frame


func _show_mining_blend(from_frame: int, to_frame: int, weight: float) -> void:
	var visual := get_node_or_null("Visual") as Sprite3D
	if visual == null or _mining_blend_visual == null:
		return
	var blend := clampf(weight, 0.0, 1.0)
	_set_mining_texture(visual, from_frame)
	_set_mining_texture(_mining_blend_visual, to_frame)
	_set_mining_sprite_alpha(visual, 1.0 - blend)
	_set_mining_sprite_alpha(_mining_blend_visual, blend)
	visual.visible = true
	_mining_blend_visual.visible = true
	_mining_frame = to_frame if blend >= 0.5 else from_frame


func _show_persistent_mining_stage() -> void:
	var visual := get_node_or_null("Visual") as Sprite3D
	if visual == null or _mining_atlas == null:
		return
	_set_mining_texture(visual, clampi(visual_stage, 0, 3))
	_set_mining_sprite_alpha(visual, 1.0)
	visual.visible = true
	visual.scale = Vector3(1.0, visual.scale.y, 1.0)
	if _mining_blend_visual != null:
		_mining_blend_visual.visible = false
		_set_mining_sprite_alpha(_mining_blend_visual, 0.0)


func _set_mining_texture(target: Sprite3D, frame: int) -> void:
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = _mining_atlas
	var cell_width := float(_mining_atlas.get_width()) / 4.0
	atlas_texture.region = Rect2(cell_width * float(frame), 0.0, cell_width, _mining_atlas.get_height())
	target.texture = atlas_texture
	if frame < _mining_frame_positions.size():
		target.position = _mining_frame_positions[frame]


func _set_mining_sprite_alpha(target: Sprite3D, alpha: float) -> void:
	var color := target.modulate
	color.a = clampf(alpha, 0.0, 1.0)
	target.modulate = color


static func mining_frame_used_rect(texture: Texture2D, frame: int) -> Rect2i:
	if texture == null or texture.get_width() % 4 != 0 or frame < 0 or frame > 3:
		return Rect2i()
	var image := texture.get_image()
	if image == null or image.is_empty():
		return Rect2i()
	var cell_width := image.get_width() / 4
	return image.get_region(Rect2i(cell_width * frame, 0, cell_width, image.get_height())).get_used_rect()


static func mining_ground_anchor(texture: Texture2D, frame: int) -> Vector2:
	var used_rect := mining_frame_used_rect(texture, frame)
	if not used_rect.has_area():
		return Vector2.ZERO
	var image := texture.get_image()
	var cell_width := image.get_width() / 4
	var region := image.get_region(Rect2i(cell_width * frame, 0, cell_width, image.get_height()))
	var band_start := used_rect.position.y + floori(float(used_rect.size.y) * 0.90)
	var weighted_x := 0.0
	var total_alpha := 0.0
	for y in range(band_start, used_rect.end.y):
		for x in range(used_rect.position.x, used_rect.end.x):
			var alpha := region.get_pixel(x, y).a
			if alpha <= 0.10:
				continue
			weighted_x += float(x) * alpha
			total_alpha += alpha
	return Vector2(
		weighted_x / total_alpha if total_alpha > 0.0 else float(used_rect.get_center().x),
		float(used_rect.end.y)
	)


func _fallback_color() -> Color:
	return Color(ResourceCatalogScript.definition(resource_type).get("color", Color("62666a")))


func _normalized_state(data: Variant, loaded_day: int = -1) -> Dictionary:
	if not data is Dictionary:
		return {}
	if int(data.get("state_version", 1)) == STATE_VERSION:
		return _normalized_v2_state(data, loaded_day)
	return _normalized_legacy_state(data, loaded_day)


func _normalized_v2_state(data: Dictionary, loaded_day: int) -> Dictionary:
	for field in [
		"resource_id", "resource_type", "item_id", "required_tool", "max_units",
		"remaining_units", "respawn_days", "respawn_day", "position", "visual_stage",
	]:
		if not data.has(field):
			return {}
	if (
		str(data.resource_id) != resource_id
		or str(data.resource_type) != resource_type
		or str(data.item_id) != item_id
		or str(data.required_tool) != required_tool
		or not _is_integer_number(data.max_units)
		or int(data.max_units) != max_units
		or not _is_integer_number(data.remaining_units)
		or not _is_integer_number(data.respawn_days)
		or int(data.respawn_days) != respawn_days
		or not _is_integer_number(data.respawn_day)
		or not _is_integer_number(data.visual_stage)
	):
		return {}
	return _validated_normalized_state(data, loaded_day)


func _normalized_legacy_state(data: Dictionary, loaded_day: int) -> Dictionary:
	for field in ["resource_id", "position", "hits_remaining", "respawn_day"]:
		if not data.has(field):
			return {}
	if str(data.resource_id) != resource_id or not _is_integer_number(data.hits_remaining):
		return {}
	var old_hits := int(data.hits_remaining)
	if old_hits < 0 or old_hits > _legacy_max_hits:
		return {}
	var migrated_units := 0
	if old_hits > 0:
		migrated_units = ceili(float(old_hits) / float(_legacy_max_hits) * float(max_units))
	return _validated_normalized_state({
		"state_version": STATE_VERSION,
		"resource_id": resource_id,
		"resource_type": resource_type,
		"item_id": item_id,
		"required_tool": required_tool,
		"max_units": max_units,
		"remaining_units": migrated_units,
		"respawn_days": respawn_days,
		"respawn_day": data.respawn_day,
		"position": data.position,
		"visual_stage": _stage_for_units(migrated_units),
	}, loaded_day)


func _validated_normalized_state(data: Dictionary, loaded_day: int) -> Dictionary:
	var saved_position: Variant = data.position
	if not saved_position is Array or saved_position.size() != 3:
		return {}
	for coordinate in saved_position:
		if not _is_finite_number(coordinate):
			return {}
	var saved_units := int(data.remaining_units)
	var saved_respawn := int(data.respawn_day)
	if saved_units < 0 or saved_units > max_units or saved_respawn < 0:
		return {}
	if saved_units == 0 and saved_respawn <= 0:
		return {}
	if saved_units > 0 and saved_respawn != 0:
		return {}
	if loaded_day >= 0 and saved_units == 0 and (
		saved_respawn <= loaded_day or saved_respawn > loaded_day + respawn_days
	):
		return {}
	var expected_stage := _stage_for_units(saved_units)
	if int(data.visual_stage) != expected_stage:
		return {}
	return data.duplicate(true)


func _stage_for_units(units: int) -> int:
	if units <= 0:
		return 3
	if units >= max_units:
		return 0
	return 1 if units * 3 > max_units else 2


func _infer_resource_type(definition: Dictionary) -> String:
	var reward: Variant = definition.get("yield_per_hit", {})
	if not reward is Dictionary or reward.is_empty():
		return ""
	var inferred_item := str(reward.keys()[0])
	if inferred_item == "wood":
		return "tree"
	return inferred_item


func _is_positive_integer(value: Variant) -> bool:
	return _is_integer_number(value) and int(value) > 0


func _is_non_negative_integer(value: Variant) -> bool:
	return _is_integer_number(value) and int(value) >= 0


func _is_integer_number(value: Variant) -> bool:
	return _is_finite_number(value) and floorf(float(value)) == float(value)


func _is_finite_number(value: Variant) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and is_finite(float(value))
	)


func _finite_vector3(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
