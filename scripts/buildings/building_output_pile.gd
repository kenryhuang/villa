class_name BuildingOutputPile
extends Area3D

signal collection_requested(item_id: String)

const GameDataScript := preload("res://scripts/core/game_data.gd")
const INTERACTION_LAYER := 128
const ATLAS_FRAME_SIZE := Vector2(192.0, 192.0)
const WORLD_WIDTH := 0.62
const RASTER_FAMILIES := ["brick", "charcoal"]

const FAMILY_BY_ITEM := {
	"wood": "wood",
	"plank": "wood",
	"furniture": "crate",
	"wooden_crate": "crate",
	"stone": "stone",
	"stone_brick": "brick",
	"brick": "brick",
	"coal": "ore",
	"charcoal": "charcoal",
	"copper_ore": "ore",
	"iron_ore": "ore",
	"silver_ore": "ore",
	"gold_ore": "ore",
	"crystal": "ore",
	"copper_ingot": "metal",
	"iron_ingot": "metal",
	"steel": "metal",
	"machine_parts": "metal",
	"farm_tools": "metal",
	"lamp": "metal",
	"flour": "sack",
	"animal_feed": "sack",
	"glass": "bottle",
	"glass_jar": "bottle",
	"glass_bottle": "bottle",
	"sunflower_oil": "bottle",
	"fruit_jam": "bottle",
	"pickles": "bottle",
	"tomato_sauce": "bottle",
	"fruit_juice": "bottle",
	"perfume": "bottle",
	"cloth": "textile",
	"rope": "textile",
	"sachet": "textile",
	"bread": "food",
	"honey_cake": "food",
	"bouquet": "food",
	"honey": "small",
	"beeswax": "small",
	"egg": "small",
	"feather": "small",
	"candle": "small",
	"jewelry": "small",
}

const TINT_BY_ITEM := {}

var item_id := ""
var quantity := 0
var quantity_capacity := 0
var _interaction_enabled := true
var _feedback_reason := ""
var _configured := false


static func visual_family(id: String) -> String:
	return str(FAMILY_BY_ITEM.get(id, "crate"))


func _ready() -> void:
	_ensure_nodes()
	add_to_group("building_output_pile")
	set_process_input(_interaction_enabled and quantity > 0)


func configure(id: String, next_quantity: int, next_capacity: int) -> bool:
	_ensure_nodes()
	var definition: Variant = GameDataScript.get_item(id)
	if id.is_empty() or not definition is Dictionary or next_quantity <= 0:
		return false
	item_id = id
	_configured = true
	update_quantity(next_quantity, next_capacity)
	return true


func update_quantity(next_quantity: int, next_capacity: int) -> void:
	quantity = maxi(next_quantity, 0)
	quantity_capacity = maxi(next_capacity, 0)
	_apply_density_texture()
	_update_tooltip()
	set_interaction_enabled(_interaction_enabled and quantity > 0)


func density_frame() -> int:
	if quantity_capacity > 0:
		var ratio := float(quantity) / float(quantity_capacity)
		if ratio <= 1.0 / 3.0:
			return 0
		if ratio <= 2.0 / 3.0:
			return 1
		return 2
	if quantity <= 1:
		return 0
	return 1 if quantity <= 3 else 2


func set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled
	collision_layer = INTERACTION_LAYER if enabled and quantity > 0 else 0
	collision_mask = 0
	monitoring = false
	monitorable = enabled and quantity > 0
	input_ray_pickable = enabled and quantity > 0
	set_process_input(enabled and quantity > 0)
	if not enabled:
		set_pointer_hovered(false)


func interact(_player: Node) -> void:
	if _interaction_enabled and quantity > 0:
		collection_requested.emit(item_id)


func handle_direct_pointer_event(
	event: InputEvent,
	pointer_inside: bool,
	pointer_over_ui: bool
) -> bool:
	var active := (
		_interaction_enabled
		and quantity > 0
		and pointer_inside
		and not pointer_over_ui
	)
	set_pointer_hovered(active)
	if (
		active
		and event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
	):
		interact(null)
		return true
	return false


func _input(event: InputEvent) -> void:
	if not event is InputEventMouse:
		return
	var handled := handle_direct_pointer_event(
		event,
		_pointer_inside_asset(event.position),
		_pointer_over_ui()
	)
	if handled:
		get_viewport().set_input_as_handled()


func set_pointer_hovered(hovered: bool) -> void:
	_ensure_nodes()
	var outline := get_node("Outline") as Sprite3D
	var tooltip := get_node("Tooltip") as Label3D
	outline.visible = hovered and _interaction_enabled and quantity > 0
	tooltip.visible = outline.visible
	if hovered:
		_feedback_reason = ""


func tooltip_visible() -> bool:
	return bool((get_node("Tooltip") as Label3D).visible)


func tooltip_text() -> String:
	return str((get_node("Tooltip") as Label3D).text)


func show_interaction_rejected(reason: String) -> void:
	_feedback_reason = reason
	_show_failure_outline()


func play_failure(reason: String) -> void:
	_feedback_reason = reason
	_show_failure_outline()


func feedback_reason() -> String:
	return _feedback_reason


func play_collected() -> void:
	set_interaction_enabled(false)
	if not is_inside_tree():
		queue_free()
		return
	var sprite := get_node("Sprite") as Sprite3D
	var outline := get_node("Outline") as Sprite3D
	var target_color := sprite.modulate
	target_color.a = 0.0
	outline.visible = false
	var tween := create_tween().set_parallel(true)
	tween.tween_property(sprite, "modulate", target_color, 0.2)
	tween.tween_property(sprite, "position:y", sprite.position.y + 0.14, 0.2)
	tween.tween_property(sprite, "scale", sprite.scale * 0.72, 0.2)
	tween.chain().tween_callback(queue_free)


func _ensure_nodes() -> void:
	if get_node_or_null("Outline") == null:
		var outline := Sprite3D.new()
		outline.name = "Outline"
		outline.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		outline.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		outline.modulate = Color(0.35, 1.0, 0.42, 0.55)
		outline.scale = Vector3.ONE * 1.1
		outline.position = Vector3(0.0, 0.31, -0.01)
		outline.sorting_offset = -0.01
		outline.visible = false
		add_child(outline)
	if get_node_or_null("Sprite") == null:
		var sprite := Sprite3D.new()
		sprite.name = "Sprite"
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sprite.position = Vector3(0.0, 0.31, 0.0)
		sprite.sorting_offset = 0.0
		add_child(sprite)
	if get_node_or_null("Tooltip") == null:
		var tooltip := Label3D.new()
		tooltip.name = "Tooltip"
		tooltip.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tooltip.fixed_size = true
		tooltip.font_size = 14
		tooltip.outline_size = 4
		tooltip.position = Vector3(0.0, 0.58, 0.02)
		tooltip.modulate = Color("fff1d3")
		tooltip.no_depth_test = true
		tooltip.render_priority = 3
		tooltip.visible = false
		add_child(tooltip)
	if get_node_or_null("CollisionShape3D") == null:
		var collision_shape := CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.66, 0.58, 0.48)
		collision_shape.shape = shape
		collision_shape.position.y = 0.29
		add_child(collision_shape)


func _apply_density_texture() -> void:
	if not _configured:
		return
	var family := visual_family(item_id)
	var extension := "png" if family in RASTER_FAMILIES else "svg"
	var path := "res://assets/items/output_piles/%s.%s" % [family, extension]
	var source := load(path) as Texture2D if ResourceLoader.exists(path) else null
	var texture: Texture2D
	if source != null:
		var atlas := AtlasTexture.new()
		atlas.atlas = source
		atlas.region = Rect2(
			ATLAS_FRAME_SIZE.x * float(density_frame()),
			0.0,
			ATLAS_FRAME_SIZE.x,
			ATLAS_FRAME_SIZE.y
		)
		texture = atlas
	var tint := TINT_BY_ITEM.get(item_id, Color.WHITE) as Color
	for node_name in ["Outline", "Sprite"]:
		var sprite := get_node(node_name) as Sprite3D
		sprite.texture = texture
		sprite.pixel_size = WORLD_WIDTH / ATLAS_FRAME_SIZE.x
		if node_name == "Sprite":
			sprite.modulate = tint


func _pointer_inside_asset(pointer_position: Vector2) -> bool:
	if not is_inside_tree():
		return false
	var camera := get_viewport().get_camera_3d()
	var sprite := get_node_or_null("Sprite") as Sprite3D
	if camera == null or sprite == null or camera.is_position_behind(sprite.global_position):
		return false
	var center_world := sprite.global_position
	var center_screen := camera.unproject_position(center_world)
	var half_world := WORLD_WIDTH * 0.5
	var camera_right := camera.global_transform.basis.x.normalized() * half_world
	var camera_up := camera.global_transform.basis.y.normalized() * half_world
	var half_width := maxf(
		center_screen.distance_to(camera.unproject_position(center_world + camera_right)),
		10.0
	)
	var half_height := maxf(
		center_screen.distance_to(camera.unproject_position(center_world + camera_up)),
		10.0
	)
	return Rect2(
		center_screen - Vector2(half_width, half_height),
		Vector2(half_width * 2.0, half_height * 2.0)
	).has_point(pointer_position)


func _pointer_over_ui() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered != null and hovered.mouse_filter != Control.MOUSE_FILTER_IGNORE


func _update_tooltip() -> void:
	var definition: Variant = GameDataScript.get_item(item_id)
	var display_name := item_id
	if definition is Dictionary:
		display_name = str((definition as Dictionary).get("name", item_id))
	(get_node("Tooltip") as Label3D).text = "%s ×%d" % [display_name, quantity]


func _show_failure_outline() -> void:
	_ensure_nodes()
	var outline := get_node("Outline") as Sprite3D
	outline.visible = true
	outline.modulate = Color(1.0, 0.28, 0.24, 0.78)
	if is_inside_tree():
		var tween := create_tween()
		tween.tween_interval(0.32)
		tween.tween_callback(
			func() -> void:
				if is_instance_valid(outline):
					outline.visible = false
					outline.modulate = Color(0.35, 1.0, 0.42, 0.55)
		)
