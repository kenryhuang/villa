extends RefCounted

const BuildingDataScript = preload("res://scripts/data/building_data.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")
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
		assertions.equal(instance.get_node("Collision").collision_layer, 16 | 64, "%s collision layers" % id)
		assertions.equal(instance.get_node("InteractionArea").collision_layer, 64 | 256, "%s interaction layers" % id)
		assertions.equal(instance.get_node("CameraOccluder").collision_layer, 32, "%s occluder layer" % id)
		assertions.equal(instance.get_node("Collision").collision_mask, 0, "%s collision mask" % id)
		assertions.equal(instance.get_node("InteractionArea").collision_mask, 0, "%s interaction mask" % id)
		assertions.equal(instance.get_node("CameraOccluder").collision_mask, 0, "%s occluder mask" % id)
		assertions.equal(instance.to_dict().building_id, id, "%s serializes id" % id)
		assertions.equal(instance.to_dict().gx, 3, "%s serializes grid x" % id)
		if id == "workbench":
			assertions.truthy(instance.has_method("set_economy_indicator"), "building exposes economy indicator updates")
			assertions.truthy(instance.has_method("get_economy_indicator"), "building exposes economy indicator state")
			if instance.has_method("set_economy_indicator") and instance.has_method("get_economy_indicator"):
				instance.call("set_economy_indicator", "collect")
				assertions.equal(instance.call("get_economy_indicator"), "collect", "collect indicator is visible")
				assertions.equal(instance.get_node("EconomyIndicator").text, "收", "collect indicator uses a compact glyph")
				instance.call("set_economy_indicator", "full")
				assertions.equal(instance.call("get_economy_indicator"), "full", "full replaces collect")
				instance.call("set_economy_indicator", "maintenance")
				assertions.equal(instance.call("get_economy_indicator"), "maintenance", "maintenance has priority")
				instance.call("set_economy_indicator", "")
				assertions.truthy(not instance.get_node("EconomyIndicator").visible, "empty indicator hides the glyph")

		instance.set_camera_occluded(true)
		assertions.near(instance.get_target_opacity(), 0.3, 0.001, "%s fades for camera" % id)
		instance.set_preview_mode(true)
		assertions.equal(instance.get_node("Collision").collision_layer, 0, "%s preview disables collision" % id)
		assertions.equal(instance.get_node("InteractionArea").collision_layer, 0, "%s preview disables interaction" % id)
		assertions.equal(instance.get_node("CameraOccluder").collision_layer, 0, "%s preview disables occluder" % id)
		instance.set_preview_mode(false)
		assertions.equal(instance.get_node("Collision").collision_layer, 16 | 64, "%s restores collision" % id)
		instance.deactivate()
		assertions.equal(instance.get_node("Collision").collision_layer, 0, "%s removal disables collision immediately" % id)
		assertions.equal(instance.get_node("InteractionArea").collision_layer, 0, "%s removal disables interaction immediately" % id)
		assertions.equal(instance.get_node("CameraOccluder").collision_layer, 0, "%s removal disables occlusion immediately" % id)
		assertions.equal(instance.is_in_group("building_instance"), false, "%s removal leaves building group immediately" % id)
		instance.queue_free()

	game_data.free()
