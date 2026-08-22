extends RefCounted

const HudScene := preload("res://scenes/ui/hud.tscn")
const BusScript := preload("res://scripts/ui/hud_message_bus.gd")


func run(assertions: TestAssert, tree: SceneTree) -> void:
	for viewport_size in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		var viewport := SubViewport.new()
		viewport.size = viewport_size
		tree.root.add_child(viewport)
		var hud = HudScene.instantiate()
		viewport.add_child(hud)
		var bus := BusScript.new()
		viewport.add_child(bus)
		assertions.truthy(hud.configure_message_bus(bus), "%s HUD configures message bus" % viewport_size)
		bus.publish("farming", "success", "已播种薰衣草", {"timestamp_msec": 1000})
		bus.publish("building", "warning", "空间不足", {"timestamp_msec": 2100})
		await tree.process_frame
		await tree.process_frame
		var top_bar := hud.get_node("TopBar") as Control
		var bottom_bar := hud.get_node("BottomBar") as Control
		var stream := hud.get_node("MessageStream") as Control
		assertions.truthy(not top_bar.get_rect().intersects(stream.get_rect()), "%s top HUD reserves the message rail" % viewport_size)
		assertions.truthy(not bottom_bar.get_rect().intersects(stream.get_rect()), "%s bottom HUD stays below the expanded rail" % viewport_size)
		assertions.truthy(stream.size.x >= 280.0 and stream.size.x <= 360.0, "%s message rail width is clamped" % viewport_size)
		var stream_style := stream.get_theme_stylebox("panel") as StyleBoxFlat
		assertions.truthy(stream_style != null, "%s message rail owns a readable background" % viewport_size)
		if stream_style != null:
			assertions.near(stream_style.bg_color.a, 0.45, 0.001, "%s expanded rail keeps approved transparency" % viewport_size)
		stream.call("set_collapsed", true)
		await tree.process_frame
		assertions.near(stream.size.y, top_bar.size.y, 0.001, "%s collapsed rail matches top HUD height" % viewport_size)
		viewport.free()
