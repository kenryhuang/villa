extends RefCounted

const MainScript = preload("res://scripts/main.gd")
const GridSystemScript = preload("res://scripts/systems/grid_system.gd")
const SeasonSystemScript = preload("res://scripts/systems/season_system.gd")
const CropDataScript = preload("res://scripts/data/crop_data.gd")
const HudMessageBusScript = preload("res://scripts/ui/hud_message_bus.gd")


class FarmingDouble:
	extends FarmingSystem

	var advance_calls := 0
	var result := {"advanced": 2, "matured": 1}

	func debug_advance_growth_stage() -> Dictionary:
		advance_calls += 1
		return result.duplicate(true)


class HudDouble:
	extends CanvasLayer

	var hints: Array[String] = []

	func show_action_hint(message: String, _duration := 2.5) -> void:
		hints.append(message)


class DebugEditorDouble:
	extends RefCounted

	var result := {"ok": true, "message": "调试数据已应用"}

	func apply(_draft: Dictionary) -> Dictionary:
		return result.duplicate(true)

	func snapshot() -> Dictionary:
		return {}


class DebugPanelDouble:
	extends Node

	var shown_results: Array[Dictionary] = []

	func show_apply_result(result: Dictionary, _snapshot: Dictionary = {}) -> void:
		shown_results.append(result.duplicate(true))


class CropEventBus:
	extends Node
	signal crop_grew(gx: int, gz: int, stage: int)
	signal crop_matured(gx: int, gz: int)

	var grew_stages: Array[int] = []
	var matured_cells: Array[Vector2i] = []

	func _init() -> void:
		crop_grew.connect(func(_gx: int, _gz: int, stage: int) -> void: grew_stages.append(stage))
		crop_matured.connect(
			func(gx: int, gz: int) -> void: matured_cells.append(Vector2i(gx, gz))
		)


func run(assertions: TestAssert, tree: SceneTree) -> void:
	_test_real_stage_advancement(assertions)
	_test_main_coordinator_feedback(assertions, tree)
	_test_debug_apply_feedback(assertions)


func _test_real_stage_advancement(assertions: TestAssert) -> void:
	var grid := GridSystemScript.new() as GridSystem
	var farming := FarmingSystem.new()
	assertions.truthy(farming.configure(grid, null, null), "debug crop fixture configures real farming")
	var crop_events := CropEventBus.new()
	farming._event_bus = crop_events
	grid.set_cell_state(4, 5, GridCell.State.FARMLAND)
	var cell := grid.get_cell(4, 5)
	var crop := CropDataScript.new() as CropData
	crop.crop_id = "debug_stage_crop"
	crop.plant_item_id = "debug_stage_seed"
	crop.crop_name = "Debug Stage Crop"
	crop.growth_days = 6
	crop.stage_textures.assign(["seed", "sprout", "growing", "mature"])
	var instance := farming.plant(cell, crop)
	assertions.truthy(instance != null, "debug crop fixture plants a crop")
	assertions.equal(instance.get_current_stage(), 0, "debug crop starts at the seed stage")
	assertions.equal(
		int(farming.get_crop_visual(cell).get_meta("crop_stage", -1)),
		0,
		"debug crop starts with the seed visual"
	)

	assertions.truthy(farming.water(cell), "debug crop can be watered before stage stepping")
	var first: Dictionary = farming.debug_advance_growth_stage()
	assertions.equal(first, {"advanced": 1, "matured": 0}, "first N reports one advanced crop")
	assertions.near(instance.growth_progress, 2.0, 0.001, "first N reaches stage-one threshold")
	assertions.equal(instance.get_current_stage(), 1, "first N changes the visible stage")
	assertions.equal(
		int(farming.get_crop_visual(cell).get_meta("crop_stage", -1)),
		1,
		"first N refreshes the real crop visual"
	)
	assertions.truthy(cell.watered and instance.is_watered_today, "debug stage stepping keeps daily water state")

	var second: Dictionary = farming.debug_advance_growth_stage()
	assertions.equal(second, {"advanced": 1, "matured": 0}, "second N reports one advanced crop")
	assertions.near(instance.growth_progress, 4.0, 0.001, "second N reaches stage-two threshold")
	assertions.equal(instance.get_current_stage(), 2, "second N changes to the growing visual")

	var third: Dictionary = farming.debug_advance_growth_stage()
	assertions.equal(third, {"advanced": 1, "matured": 1}, "third N reports newly mature crop")
	assertions.near(instance.growth_progress, 6.0, 0.001, "third N reaches authored maturity")
	assertions.equal(instance.lifecycle_state, CropInstance.LifecycleState.MATURE, "third N marks crop mature")
	assertions.equal(
		int(farming.get_crop_visual(cell).get_meta("crop_stage", -1)),
		3,
		"third N refreshes the mature visual"
	)
	assertions.equal(
		farming.debug_advance_growth_stage(),
		{"advanced": 0, "matured": 0},
		"mature crops are not advanced again"
	)
	assertions.equal(crop_events.grew_stages, [1, 2, 3], "debug stages publish one ordered crop_grew each")
	assertions.equal(crop_events.matured_cells, [Vector2i(4, 5)], "debug maturity publishes exactly once")

	grid.set_cell_state(7, 8, GridCell.State.FARMLAND)
	var paused_cell := grid.get_cell(7, 8)
	var paused_instance := farming.plant(paused_cell, crop)
	farming.set_greenhouse_cells([], [Vector2i(7, 8)])
	assertions.equal(
		farming.debug_advance_growth_stage(),
		{"advanced": 0, "matured": 0},
		"paused greenhouse crops are skipped"
	)
	assertions.near(paused_instance.growth_progress, 0.0, 0.001, "paused crop progress stays unchanged")
	assertions.equal(crop_events.grew_stages, [1, 2, 3], "skipped crops publish no growth event")
	assertions.equal(crop_events.matured_cells.size(), 1, "skipped crops publish no maturity event")
	farming.free()
	crop_events.free()
	grid.free()


func _test_main_coordinator_feedback(assertions: TestAssert, tree: SceneTree) -> void:
	var main := MainScript.new()
	var has_bus_property := false
	for property in main.get_property_list():
		if str(property.get("name", "")) == "hud_message_bus":
			has_bus_property = true
			break
	assertions.truthy(has_bus_property, "Main exposes the session HUD message bus")
	assertions.truthy(
		main.has_method("_advance_debug_crop_day"),
		"Main exposes a crop-only debug day coordinator"
	)
	if not main.has_method("_advance_debug_crop_day"):
		main.free()
		return

	var event_bus := tree.root.get_node_or_null("EventBus")
	var formal_days: Array[int] = []
	var callback := func(day: int) -> void: formal_days.append(day)
	event_bus.day_changed.connect(callback)
	var clock := SeasonSystemScript.new()
	var farming := FarmingDouble.new()
	var hud := HudDouble.new()
	tree.root.add_child(clock)
	tree.root.add_child(farming)
	tree.root.add_child(hud)
	clock.hour = 14
	clock.minute = 35
	main.season_system = clock
	main.farming_system = farming
	main.hud = hud
	var message_bus := HudMessageBusScript.new()
	main.add_child(message_bus)
	if has_bus_property:
		main.hud_message_bus = message_bus
	assertions.truthy(main._advance_debug_crop_day(), "debug crop day succeeds with required systems")
	assertions.equal(clock.current_day, 1, "debug crop day leaves the season calendar unchanged")
	assertions.equal(clock.total_days, 1, "debug crop day leaves the authoritative day cursor unchanged")
	assertions.equal(farming.advance_calls, 1, "debug crop day advances farming exactly once")
	assertions.equal(formal_days.size(), 0, "debug crop day does not emit formal day_changed")
	if has_bus_property:
		assertions.equal(str(message_bus.get_recent()[-1].text), "推进了 2 株作物，其中 1 株成熟", "debug crop day reports visible progress")
		assertions.equal(str(message_bus.get_recent()[-1].severity), "debug", "debug crop day uses debug severity")
	assertions.equal(hud.hints, [], "debug crop day no longer uses a transient HUD hint")
	farming.result = {"advanced": 0, "matured": 0}
	assertions.truthy(main._advance_debug_crop_day(), "debug crop day handles an empty crop set")
	if has_bus_property:
		assertions.equal(str(message_bus.get_recent()[-1].text), "没有可推进的作物", "debug crop day reports an empty crop set")
	main.farming_system = null
	assertions.truthy(
		not main._advance_debug_crop_day(),
		"debug crop day refuses partial advancement without farming"
	)
	event_bus.day_changed.disconnect(callback)
	main.free()
	clock.free()
	farming.free()
	hud.free()


func _test_debug_apply_feedback(assertions: TestAssert) -> void:
	var main := MainScript.new()
	var message_bus := HudMessageBusScript.new()
	message_bus.name = "HudMessageBus"
	main.add_child(message_bus)
	main.hud_message_bus = message_bus
	var editor := DebugEditorDouble.new()
	var panel := DebugPanelDouble.new()
	main.add_child(panel)
	main.debug_state_editor = editor
	main.debug_panel = panel
	main._on_debug_panel_apply_requested({})
	assertions.equal(str(message_bus.get_recent()[-1].severity), "success", "successful debug apply enters the stream")
	assertions.equal(str(message_bus.get_recent()[-1].text), "调试数据已应用", "successful debug apply keeps its result text")
	editor.result = {"ok": false, "reason": "invalid_gold"}
	main._on_debug_panel_apply_requested({})
	assertions.equal(str(message_bus.get_recent()[-1].severity), "error", "failed debug apply enters the stream")
	assertions.truthy(str(message_bus.get_recent()[-1].text).contains("invalid_gold"), "failed debug apply includes its reason")
	assertions.equal(panel.shown_results.size(), 2, "debug panel still receives both apply results")
	main.free()
