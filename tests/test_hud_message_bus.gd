extends RefCounted

const BusScript := preload("res://scripts/ui/hud_message_bus.gd")


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var bus := BusScript.new()
	tree.root.add_child(bus)
	assertions.truthy(not bus.publish("", "info", "missing source"), "empty source is rejected")
	assertions.truthy(not bus.publish("debug", "unknown", "bad level"), "unknown severity is rejected")
	assertions.truthy(bus.publish("farming", "success", "已播种", {"timestamp_msec": 1000}), "valid message publishes")
	assertions.truthy(bus.publish("farming", "success", "已播种", {"timestamp_msec": 1500}), "same message merges")
	var recent: Array[Dictionary] = bus.get_recent()
	assertions.equal(recent.size(), 1, "one-second duplicate keeps one record")
	assertions.equal(int(recent[0]["count"]), 2, "merged record increments count")
	assertions.truthy(bus.publish("farming", "success", "已播种", {"timestamp_msec": 2501}), "late duplicate publishes")
	assertions.equal(bus.get_recent().size(), 2, "outside merge window creates a record")
	for index in range(105):
		bus.publish("debug", "debug", "trace %d" % index, {"timestamp_msec": 3000 + index})
	recent = bus.get_recent()
	assertions.equal(recent.size(), 100, "message history is capped")
	assertions.equal(str(recent[-1]["text"]), "trace 104", "newest record remains last")
	bus.free()
