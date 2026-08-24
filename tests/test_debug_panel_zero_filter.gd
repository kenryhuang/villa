extends RefCounted

## Test that the debug panel zero-quantity filter reduces row count
## and that build_draft still includes all items when some are hidden.

const DebugPanelScene := preload("res://scenes/ui/debug_panel.tscn")


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var panel := DebugPanelScene.instantiate()
	tree.root.add_child(panel)

	# Snapshot with 2 non-zero and 3 zero-quantity items
	var snapshot := {
		"level": 1,
		"elapsed_days": 0,
		"season": 0,
		"gold": 100,
		"stamina": 50,
		"max_stamina": 100,
		"max_slots": 20,
		"items": {
			"wood": {"id": "wood", "name": "木材", "category": "material", "max_stack": 99, "quantity": 10},
			"stone": {"id": "stone", "name": "石材", "category": "material", "max_stack": 99, "quantity": 0},
			"grain_seed": {"id": "grain_seed", "name": "谷物种子", "category": "seed", "max_stack": 99, "quantity": 5},
			"tomato_seed": {"id": "tomato_seed", "name": "番茄种子", "category": "seed", "max_stack": 99, "quantity": 0},
			"iron_ingot": {"id": "iron_ingot", "name": "铁锭", "category": "processed_material", "max_stack": 99, "quantity": 0},
		},
	}

	assertions.truthy(panel.configure(snapshot), "panel accepts snapshot with mixed quantities")

	# Default: show_empty is unchecked → only non-zero items visible
	var show_empty := panel.get_node(
		"Overlay/Center/Panel/Layout/Tabs/Inventory/Toolbar/ShowEmpty"
	) as CheckBox
	assertions.truthy(show_empty != null, "show empty checkbox exists")
	if show_empty == null:
		panel.queue_free()
		await tree.process_frame
		return

	assertions.truthy(not show_empty.button_pressed, "show empty is unchecked by default")
	var visible_ids: Array[String] = panel.get_visible_item_ids()
	assertions.equal(visible_ids.size(), 2, "default hides zero-quantity items (got %d)" % visible_ids.size())

	# build_draft should still include all items, even hidden ones
	var draft: Dictionary = panel.build_draft()
	assertions.truthy(draft.items.has("wood"), "draft includes non-zero item wood")
	assertions.truthy(draft.items.has("stone"), "draft includes zero-quantity item stone")
	assertions.truthy(draft.items.has("iron_ingot"), "draft includes zero-quantity item iron_ingot")

	# Toggle show_empty on → all items visible
	show_empty.button_pressed = true
	await tree.process_frame
	visible_ids = panel.get_visible_item_ids()
	assertions.equal(visible_ids.size(), 5, "show empty reveals all items (got %d)" % visible_ids.size())

	# Toggle show_empty off → back to filtered view
	show_empty.button_pressed = false
	await tree.process_frame
	visible_ids = panel.get_visible_item_ids()
	assertions.equal(visible_ids.size(), 2, "unchecking show empty hides zero-quantity items again")

	panel.queue_free()
	await tree.process_frame
