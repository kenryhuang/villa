extends RefCounted

const BuildingOutputPileScript := preload(
	"res://scripts/buildings/building_output_pile.gd"
)


class UnhandledMouseProbe:
	extends Node

	var left_clicks := 0

	func _unhandled_input(event: InputEvent) -> void:
		if (
			event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed
		):
			left_clicks += 1


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var pile := BuildingOutputPileScript.new()
	tree.root.add_child(pile)
	assertions.truthy(
		pile.configure("stone_brick", 1, 9),
		"known production output configures"
	)
	assertions.equal(pile.item_id, "stone_brick", "pile exposes represented item")
	assertions.equal(pile.density_frame(), 0, "one ninth uses sparse frame")
	pile.update_quantity(4, 9)
	assertions.equal(pile.density_frame(), 1, "four ninths uses medium frame")
	pile.update_quantity(9, 9)
	assertions.equal(pile.density_frame(), 2, "full storage uses dense frame")
	var tooltip := pile.get_node("Tooltip") as Label3D
	assertions.equal(tooltip.font_size, 10, "output quantity uses a small unobtrusive font")
	assertions.equal(tooltip.outline_size, 3, "output quantity uses a small readable outline")
	assertions.truthy(
		pile.has_method("handle_direct_pointer_event"),
		"pile owns an independent screen-space pointer handler"
	)
	var pointer_motion := InputEventMouseMotion.new()
	if pile.has_method("handle_direct_pointer_event"):
		pile.call("handle_direct_pointer_event", pointer_motion, true, false)
	assertions.truthy(pile.tooltip_visible(), "direct hover exposes exact tooltip")
	assertions.equal(pile.tooltip_text(), "石砖 ×9", "tooltip uses localized item name")
	if pile.has_method("handle_direct_pointer_event"):
		pile.call("handle_direct_pointer_event", pointer_motion, false, false)
	assertions.truthy(not pile.tooltip_visible(), "direct pointer exit hides quantity")
	var camera := Camera3D.new()
	tree.root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.5
	camera.position = Vector3(-7.0, 6.2, 7.0)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.current = true
	var sprite := pile.get_node("Sprite") as Sprite3D
	assertions.truthy(
		pile.call(
			"_pointer_inside_asset",
			camera.unproject_position(sprite.global_position)
		),
		"screen-space trigger contains the visible pile center"
	)
	assertions.equal(pile.collision_layer, 128, "pile uses the existing interaction mask")

	var requests: Array[String] = []
	pile.collection_requested.connect(
		func(requested_item_id: String) -> void:
			requests.append(requested_item_id)
	)
	var pointer_click := InputEventMouseButton.new()
	pointer_click.button_index = MOUSE_BUTTON_LEFT
	pointer_click.pressed = true
	if pile.has_method("handle_direct_pointer_event"):
		pile.call("handle_direct_pointer_event", pointer_click, true, false)
	assertions.equal(requests, ["stone_brick"], "independent click requests represented item")
	pile.set_interaction_enabled(false)
	if pile.has_method("handle_direct_pointer_event"):
		pile.call("handle_direct_pointer_event", pointer_click, true, false)
	assertions.equal(requests.size(), 1, "disabled pile emits no request")
	pile.set_interaction_enabled(true)
	camera.queue_free()
	_test_viewport_input_route(assertions, tree)
	pile.show_interaction_rejected("too_far")
	assertions.equal(pile.feedback_reason(), "too_far", "range rejection is retained locally")
	pile.play_failure("inventory_capacity")
	assertions.equal(
		pile.feedback_reason(),
		"inventory_capacity",
		"collection failure replaces range feedback"
	)

	assertions.equal(
		BuildingOutputPileScript.visual_family("charcoal"),
		"charcoal",
		"charcoal uses its painted kiln-output family"
	)
	assertions.equal(
		BuildingOutputPileScript.visual_family("stone_brick"),
		"brick",
		"stone brick uses the kiln brick family"
	)
	assertions.equal(
		BuildingOutputPileScript.visual_family("glass_jar"),
		"bottle",
		"glass jar uses the bottle pile family"
	)
	assertions.equal(
		BuildingOutputPileScript.visual_family("unknown_item"),
		"crate",
		"future unknown output uses the crate fallback"
	)
	var charcoal_pile := BuildingOutputPileScript.new()
	tree.root.add_child(charcoal_pile)
	assertions.truthy(charcoal_pile.configure("charcoal", 2, 9), "charcoal label fixture configures")
	assertions.equal(
		(charcoal_pile.get_node("Tooltip") as Label3D).font_size,
		8,
		"charcoal quantity label is visually as compact as the brick label"
	)
	assertions.equal(
		(charcoal_pile.get_node("PickupFeedback") as Label3D).font_size,
		9,
		"charcoal pickup label stays compact"
	)
	charcoal_pile.queue_free()
	pile.queue_free()
	await _test_collection_animation(assertions, tree)


func _test_collection_animation(assertions: TestAssert, tree: SceneTree) -> void:
	var pile := BuildingOutputPileScript.new()
	tree.root.add_child(pile)
	assertions.truthy(
		pile.configure("charcoal", 2, 9),
		"collection animation fixture configures"
	)
	pile.play_collected()
	var feedback := pile.get_node_or_null("PickupFeedback") as Label3D
	assertions.truthy(feedback != null, "collection displays pickup feedback")
	if feedback != null:
		assertions.truthy(feedback.visible, "pickup feedback is immediately visible")
		assertions.equal(feedback.text, "木炭 +2", "pickup feedback names the collected output")
		assertions.equal(feedback.font_size, 9, "charcoal pickup feedback stays visually compact")
		assertions.equal(feedback.outline_size, 3, "pickup feedback uses a compact outline")
	assertions.equal(pile.collision_layer, 0, "collected pile immediately disables collision")
	assertions.truthy(
		not pile.is_processing_input(),
		"collected pile immediately disables direct input"
	)
	await tree.create_timer(0.55).timeout
	assertions.truthy(
		not is_instance_valid(pile),
		"collected pile is freed after the pickup animation"
	)


func _test_viewport_input_route(assertions: TestAssert, tree: SceneTree) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 600)
	viewport.handle_input_locally = true
	tree.root.add_child(viewport)
	var pile := BuildingOutputPileScript.new()
	viewport.add_child(pile)
	pile.configure("stone_brick", 3, 9)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.5
	camera.position = Vector3(-7.0, 6.2, 7.0)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.current = true
	var probe := UnhandledMouseProbe.new()
	viewport.add_child(probe)
	var requests: Array[String] = []
	pile.collection_requested.connect(
		func(requested_item_id: String) -> void:
			requests.append(requested_item_id)
	)
	var sprite := pile.get_node("Sprite") as Sprite3D
	var pointer_position := camera.unproject_position(sprite.global_position)
	assertions.truthy(
		pile.call("_pointer_inside_asset", pointer_position),
		"viewport route targets the visible pile"
	)
	var pointer_click := InputEventMouseButton.new()
	pointer_click.button_index = MOUSE_BUTTON_LEFT
	pointer_click.pressed = true
	pointer_click.position = pointer_position
	viewport.push_input(pointer_click, true)
	assertions.equal(
		requests,
		["stone_brick"],
		"viewport click reaches the pile exactly once"
	)
	assertions.equal(
		probe.left_clicks,
		0,
		"handled pile click does not reach later world interaction"
	)
	var ui_blocker := Control.new()
	ui_blocker.position = pointer_position - Vector2(24.0, 24.0)
	ui_blocker.size = Vector2(48.0, 48.0)
	ui_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	viewport.add_child(ui_blocker)
	var pointer_over_ui := InputEventMouseMotion.new()
	pointer_over_ui.position = pointer_position
	viewport.push_input(pointer_over_ui, true)
	viewport.push_input(pointer_click, true)
	assertions.equal(
		requests.size(),
		1,
		"UI under the pointer blocks direct pile collection"
	)
	viewport.queue_free()
