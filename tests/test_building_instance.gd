extends RefCounted

const BuildingDataScript = preload("res://scripts/data/building_data.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")
const ProducerStateScript = preload("res://scripts/data/producer_state.gd")
const IDS := [
	"barn",
	"greenhouse",
	"windmill",
	"chicken_coop",
	"beehive",
	"well",
	"workbench",
	"lamp",
	"fence",
]


func run(assertions: TestAssert, tree: SceneTree) -> void:
	assertions.near(
		BuildingInstance.anchored_center_y(2.0, Vector2(0.5, 0.9375)),
		0.875,
		0.0001,
		"explicit art anchor maps to world ground"
	)
	var game_data = GameDataScript.new()
	for id in IDS:
		var data = BuildingDataScript.from_dictionary(game_data.get_building(id))
		var packed = load(data.scene_path) as PackedScene
		var instance = packed.instantiate()
		tree.root.add_child(instance)

		assertions.truthy(instance.has_method("configure"), "%s root is configurable" % id)
		if not instance.has_method("configure"):
			instance.queue_free()
			continue
		instance.configure(data, 3, 4, [
			{"gx": 3, "gz": 4, "previous_state": 0},
		])
		assertions.equal(instance.building_data, data, "%s exposes typed building data" % id)
		assertions.truthy(instance.is_in_group("building_instance"), "%s joins building group" % id)
		assertions.truthy(instance.has_node("VisualRoot/BackLayer"), "%s has back layer" % id)
		assertions.truthy(instance.has_node("VisualRoot/FrontLayer"), "%s has front layer" % id)
		assertions.truthy(instance.has_node("EconomyIndicator"), "%s has a world economy indicator" % id)
		assertions.truthy(instance.has_node("BuildingMaintenanceVisual"), "%s has maintenance damage visuals" % id)
		assertions.truthy(instance.has_node("BuildingOutputDisplay"), "%s has an output display" % id)
		assertions.equal(
			instance.has_node("ProductionYard"),
			data.has_production_yard(),
			"%s has the expected production-yard component" % id
		)
		assertions.equal(instance.get_node("Collision").collision_layer, 16 | 64, "%s collision layers" % id)
		assertions.equal(instance.get_node("InteractionArea").collision_layer, 64 | 256, "%s interaction layers" % id)
		assertions.equal(instance.get_node("CameraOccluder").collision_layer, 32, "%s occluder layer" % id)
		assertions.equal(instance.get_node("Collision").collision_mask, 0, "%s collision mask" % id)
		assertions.equal(instance.get_node("InteractionArea").collision_mask, 0, "%s interaction mask" % id)
		assertions.equal(instance.get_node("CameraOccluder").collision_mask, 0, "%s occluder mask" % id)
		assertions.equal(instance.to_dict().building_id, id, "%s serializes id" % id)
		assertions.equal(instance.to_dict().gx, 3, "%s serializes grid x" % id)
		if data.has_production_yard():
			var yard: Variant = instance.get_node("ProductionYard")
			assertions.equal(instance.call("get_structure_footprint"), data.structure_footprint(), "%s exposes original structure footprint" % id)
			assertions.equal(instance.get_node("VisualRoot").position, data.production_yard_offset(), "%s shifts its structure into the rear yard" % id)
			var structure_shape := instance.get_node("Collision/CollisionShape3D").shape as BoxShape3D
			assertions.near(structure_shape.size.x, float(data.structure_footprint().x) * 0.78, 0.001, "%s collision uses structure width" % id)
			assertions.near(structure_shape.size.z, float(data.structure_footprint().y) * 0.78, 0.001, "%s collision uses structure depth" % id)
			assertions.truthy(not yard.has_enabled_collisions(), "%s production ground stays walkable" % id)
			assertions.equal(yard.get_collision_layers(), [], "%s production ground owns no physics layer" % id)
		if id == "workbench":
			assertions.truthy(instance.has_method("set_economy_indicator"), "building exposes economy indicator updates")
			assertions.truthy(instance.has_method("get_economy_indicator"), "building exposes economy indicator state")
			if instance.has_method("set_economy_indicator") and instance.has_method("get_economy_indicator"):
				instance.call("set_economy_indicator", "collect")
				assertions.equal(instance.call("get_economy_indicator"), "", "collect glyph state is rejected")
				assertions.truthy(not instance.get_node("EconomyIndicator").visible, "collect glyph never renders")
				instance.call("set_economy_indicator", "full")
				assertions.equal(instance.call("get_economy_indicator"), "full", "full indicator remains available")
				instance.call("set_economy_indicator", "maintenance")
				assertions.equal(instance.call("get_economy_indicator"), "", "maintenance never uses a text indicator")
				assertions.equal(instance.get_node("EconomyIndicator").text, "", "repair character is removed")
				assertions.equal(instance.call("get_maintenance_visual_state"), "overdue", "legacy maintenance signal maps to damage")
				instance.call("set_economy_indicator", "")
				assertions.truthy(not instance.get_node("EconomyIndicator").visible, "empty indicator hides the glyph")
			instance.producer_state.outputs = {"plank": 2}
			instance.call("sync_output_display", instance.producer_state.outputs, 9)
			assertions.equal(instance.call("get_output_pile_count"), 1, "stored output creates one pile")
			assertions.equal(instance.call("get_output_pile_item_ids"), ["plank"], "pile represents stored plank")
			var yard_slots: Array[Vector3] = instance.get_node("ProductionYard").get_output_slots()
			assertions.equal(
				instance.get_node("BuildingOutputDisplay").get_pile("plank").position,
				yard_slots[0],
				"production output appears inside the yard collection zone"
			)
			instance.set_preview_mode(true)
			assertions.truthy(not instance.get_node("BuildingOutputDisplay").visible, "preview hides output piles")
			instance.set_preview_mode(false)
			assertions.truthy(instance.get_node("BuildingOutputDisplay").visible, "leaving preview restores output piles")
			instance.start_construction()
			assertions.equal(instance.get_node("ProductionYard").get_construction_stage(), 0, "ground records the initial construction stage")
			assertions.truthy(not instance.get_node("ProductionYard").has_enabled_collisions(), "construction ground remains walkable")
			assertions.truthy(not instance.get_node("BuildingOutputDisplay").visible, "construction hides output piles")
			instance.complete_construction()
			assertions.equal(instance.get_node("ProductionYard").get_construction_stage(), 3, "completed building records its final ground stage")
			assertions.truthy(instance.get_node("BuildingOutputDisplay").visible, "completion restores output piles")
			instance.visible = false
			assertions.truthy(
				not instance.get_node("BuildingOutputDisplay").has_enabled_collisions(),
				"directly hidden building disables output pile interaction"
			)
			instance.visible = true
			assertions.truthy(
				instance.get_node("BuildingOutputDisplay").has_enabled_collisions(),
				"directly shown building restores output pile interaction"
			)

		instance.set_camera_occluded(true)
		assertions.near(instance.get_target_opacity(), 0.3, 0.001, "%s fades for camera" % id)
		instance.set_preview_mode(true)
		assertions.equal(instance.get_node("Collision").collision_layer, 0, "%s preview disables collision" % id)
		assertions.equal(instance.get_node("InteractionArea").collision_layer, 0, "%s preview disables interaction" % id)
		assertions.equal(instance.get_node("CameraOccluder").collision_layer, 0, "%s preview disables occluder" % id)
		if data.has_production_yard():
			assertions.truthy(not instance.get_node("ProductionYard").has_enabled_collisions(), "%s preview ground remains walkable" % id)
		instance.set_preview_mode(false)
		assertions.equal(instance.get_node("Collision").collision_layer, 16 | 64, "%s restores collision" % id)
		if data.has_production_yard():
			assertions.truthy(not instance.get_node("ProductionYard").has_enabled_collisions(), "%s leaving preview keeps ground walkable" % id)
			instance.set_preview_valid(false)
			instance.set_preview_mode(true)
			assertions.equal(instance.get_node("ProductionYard").get_visual_tint(), Color(1.0, 0.38, 0.38, 0.68), "%s invalid preview tints ground red" % id)
			instance.set_preview_mode(false)
		instance.deactivate()
		assertions.equal(instance.get_node("Collision").collision_layer, 0, "%s removal disables collision immediately" % id)
		assertions.equal(instance.get_node("InteractionArea").collision_layer, 0, "%s removal disables interaction immediately" % id)
		assertions.equal(instance.get_node("CameraOccluder").collision_layer, 0, "%s removal disables occlusion immediately" % id)
		assertions.equal(instance.is_in_group("building_instance"), false, "%s removal leaves building group immediately" % id)
		if id == "workbench":
			assertions.equal(instance.call("get_output_pile_count"), 0, "removal clears derived output piles")
			assertions.equal(instance.get_node("ProductionYard").get_fence_segment_count(), 0, "removal clears derived yard visuals")
		instance.queue_free()

	game_data.free()
	_test_activity_state_bridge(assertions, tree)


func _test_activity_state_bridge(assertions: TestAssert, tree: SceneTree) -> void:
	var game_data = GameDataScript.new()
	var kiln := _configured_building("stone_kiln", game_data, tree)
	assertions.truthy(kiln.has_node("VisualRoot/ActivityLayer"), "building creates activity layer")
	var kiln_activity := kiln.get_node("VisualRoot/ActivityLayer") as BuildingActivityVisual
	assertions.near(kiln_activity.sorting_offset, 0.0, 0.001, "activity sorts between painted layers")
	assertions.near(
		(kiln.get_node("VisualRoot/BackLayer") as Sprite3D).sorting_offset,
		-0.1,
		0.001,
		"back layer remains behind activity"
	)
	assertions.near(
		(kiln.get_node("VisualRoot/FrontLayer") as Sprite3D).sorting_offset,
		0.1,
		0.001,
		"front layer remains in front of activity"
	)
	kiln_activity.configure(
		_activity_texture(),
		kiln.data.visual_size,
		kiln.data.ground_anchor_uv,
		kiln.data.activity_fps
	)
	kiln.producer_state.jobs = [{
		"recipe_id": "charcoal",
		"batches": 1,
		"remaining_minutes": 180,
		"status": "running",
	}]
	kiln.sync_activity_visual()
	assertions.truthy(kiln_activity.is_active(), "running crafting job activates the kiln")
	kiln.set_process(false)
	kiln._process(0.2)
	assertions.truthy(kiln_activity.visible, "runtime process fades active work art in")
	kiln.set_maintenance_visual_state("overdue")
	assertions.equal(kiln_activity.is_active(), false, "maintenance stops crafting activity")
	for _step in 6:
		kiln._process(0.05)
	assertions.near(
		kiln_activity.modulate.a,
		0.0,
		0.001,
		"runtime process does not overwrite the activity fade-out"
	)
	assertions.equal(kiln_activity.frame, 0, "runtime fade-out resets the activity frame")
	assertions.equal(kiln_activity.visible, false, "runtime fade-out hides stopped work art")
	kiln.set_economy_indicator("")
	kiln.visible = false
	kiln.sync_activity_visual()
	assertions.equal(kiln_activity.is_active(), false, "hidden building stops crafting activity")
	kiln.visible = true
	kiln.set_preview_mode(true)
	assertions.equal(kiln_activity.is_active(), false, "preview stops crafting activity")
	kiln.set_preview_mode(false)
	kiln.start_construction()
	assertions.equal(kiln_activity.is_active(), false, "construction stops crafting activity")
	kiln.queue_free()

	var lumberyard := _configured_building("lumberyard", game_data, tree)
	var resource_activity := lumberyard.get_node("VisualRoot/ActivityLayer") as BuildingActivityVisual
	resource_activity.configure(
		_activity_texture(),
		lumberyard.data.visual_size,
		lumberyard.data.ground_anchor_uv,
		lumberyard.data.activity_fps
	)
	lumberyard.producer_state = ProducerStateScript.new("lumberyard")
	lumberyard.sync_activity_visual()
	assertions.truthy(resource_activity.is_active(), "available passive output building works")
	lumberyard.set_economy_indicator("full")
	assertions.equal(resource_activity.is_active(), false, "full passive output building stops")
	lumberyard.set_economy_indicator("")
	lumberyard.sync_activity_visual()
	assertions.truthy(resource_activity.is_active(), "clearing full state resumes passive activity")
	lumberyard.deactivate()
	assertions.equal(resource_activity.is_active(), false, "deactivated building stops activity")
	lumberyard.queue_free()
	game_data.free()


func _configured_building(id: String, game_data: Node, tree: SceneTree) -> BuildingInstance:
	var data = BuildingDataScript.from_dictionary(game_data.get_building(id))
	var packed = load(data.scene_path) as PackedScene
	var instance := packed.instantiate() as BuildingInstance
	tree.root.add_child(instance)
	instance.configure(data, 0, 0, [])
	return instance


func _activity_texture() -> ImageTexture:
	var image := Image.create(2048, 512, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)
