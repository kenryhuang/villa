extends RefCounted

const BuildingOutputDisplayScript := preload(
	"res://scripts/buildings/building_output_display.gd"
)


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var display := BuildingOutputDisplayScript.new()
	tree.root.add_child(display)
	display.configure(Vector2i(3, 3))
	display.sync_outputs({
		"wood": 1,
		"stone": 2,
		"coal": 3,
		"iron_ore": 4,
		"copper_ore": 5,
		"gold_ore": 6,
		"crystal": 7,
	}, 9, true)
	assertions.equal(
		display.get_pile_count(),
		7,
		"all upgraded mine outputs remain clickable"
	)
	assertions.equal(
		display.get_item_ids(),
		["coal", "copper_ore", "crystal", "gold_ore", "iron_ore", "stone", "wood"],
		"pile assignment is stable by item id"
	)
	var positions: Array[Vector3] = display.get_layout_positions()
	assertions.equal(positions.size(), 7, "layout covers storage-upgrade maximum")
	var unique_positions := {}
	for position in positions:
		unique_positions[position] = true
	assertions.equal(unique_positions.size(), 7, "every pile owns a unique anchor")
	assertions.truthy(display.has_enabled_collisions(), "active display enables pile collisions")

	var requested: Array[String] = []
	display.collection_requested.connect(
		func(item_id: String) -> void:
			requested.append(item_id)
	)
	display.get_pile("coal").interact(null)
	assertions.equal(requested, ["coal"], "display proxies represented item request")

	display.sync_outputs({"stone": 2}, 9, true)
	assertions.equal(display.get_item_ids(), ["stone"], "stale output piles are removed")
	display.sync_outputs({"stone": 2}, 9, true)
	assertions.equal(display.get_pile_count(), 1, "repeated synchronization is idempotent")
	display.show_collection_failure("stone", "inventory_capacity")
	assertions.equal(
		display.get_pile("stone").feedback_reason(),
		"inventory_capacity",
		"failure routes to represented pile"
	)
	display.sync_outputs({"stone": 2}, 9, false)
	assertions.truthy(not display.visible, "inactive output projection is hidden")
	assertions.truthy(
		not display.has_enabled_collisions(),
		"inactive output projection disables interaction"
	)
	display.sync_outputs({"missing_output": 1}, 9, true)
	assertions.equal(
		display.get_pile_count(),
		0,
		"invalid output ids do not create invisible interactive piles"
	)

	display.sync_outputs({"wood": 3, "stone": 3, "coal": 3}, 9, true)
	for item_id in ["wood", "stone", "coal"]:
		assertions.equal(
			display.get_pile(item_id).density_frame(),
			2,
			"full shared storage renders %s as dense" % item_id
		)
	display.queue_free()
