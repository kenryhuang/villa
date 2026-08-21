extends RefCounted

const MainScript = preload("res://scripts/main.gd")
const SeasonSystemScript = preload("res://scripts/systems/season_system.gd")


class FarmingDouble:
	extends FarmingSystem

	var days: Array[int] = []

	func on_day_changed(day: int) -> void:
		days.append(day)


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var main := MainScript.new()
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
	tree.root.add_child(clock)
	tree.root.add_child(farming)
	clock.hour = 14
	clock.minute = 35
	main.season_system = clock
	main.farming_system = farming
	assertions.truthy(main._advance_debug_crop_day(), "debug crop day succeeds with required systems")
	assertions.equal(clock.current_day, 2, "debug crop day advances the calendar once")
	assertions.equal(farming.days, [2], "debug crop day advances farming once")
	assertions.equal(formal_days.size(), 0, "debug crop day does not emit formal day_changed")
	main.farming_system = null
	assertions.truthy(
		not main._advance_debug_crop_day(),
		"debug crop day refuses partial advancement without farming"
	)
	event_bus.day_changed.disconnect(callback)
	main.free()
	clock.free()
	farming.free()
