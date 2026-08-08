extends RefCounted

const BuildingOutputPileScript := preload(
	"res://scripts/buildings/building_output_pile.gd"
)


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
	pile.set_pointer_hovered(true)
	assertions.truthy(pile.tooltip_visible(), "hover exposes exact tooltip")
	assertions.equal(pile.tooltip_text(), "石砖 ×9", "tooltip uses localized item name")
	assertions.equal(pile.collision_layer, 128, "pile uses the existing interaction mask")

	var requests: Array[String] = []
	pile.collection_requested.connect(
		func(requested_item_id: String) -> void:
			requests.append(requested_item_id)
	)
	pile.interact(null)
	assertions.equal(requests, ["stone_brick"], "click requests represented item")
	pile.set_interaction_enabled(false)
	pile.interact(null)
	assertions.equal(requests.size(), 1, "disabled pile emits no request")
	pile.set_interaction_enabled(true)
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
	pile.queue_free()
