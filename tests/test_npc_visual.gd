extends RefCounted

const SCRIPT_PATH := "res://scripts/visual/npc_visual.gd"


func run(assertions: TestAssert) -> void:
	var script_exists := ResourceLoader.exists(SCRIPT_PATH)
	assertions.truthy(script_exists, "NpcVisual script exists")
	if not script_exists:
		return
	var visual_script := load(SCRIPT_PATH) as Script
	assertions.truthy(visual_script != null, "NpcVisual script loads")
	if visual_script == null:
		return
	var visual = visual_script.new()
	assertions.truthy(
		visual.has_method("configure"),
		"NpcVisual exposes atlas configuration"
	)
	assertions.truthy(
		visual.has_method("sync_motion"),
		"NpcVisual exposes static direction synchronization"
	)
	assertions.truthy(
		visual.has_method("get_last_direction"),
		"NpcVisual exposes its last direction"
	)
	assertions.truthy(not visual.configure(null), "NpcVisual rejects a missing atlas")
	assertions.truthy(
		not visual.configure(_texture(401, 400)),
		"NpcVisual rejects a non-divisible atlas"
	)
	assertions.truthy(
		visual.configure(_texture(400, 400)),
		"NpcVisual accepts a two-by-two atlas"
	)
	assertions.equal(visual.get_last_direction(), "s", "NpcVisual begins facing front")
	assertions.equal(
		visual.region_rect,
		Rect2(0, 200, 200, 200),
		"front uses the bottom-left cell"
	)
	visual.sync_motion(Vector2(1.0, 0.0))
	assertions.equal(visual.get_last_direction(), "e", "rightward motion faces east")
	assertions.equal(
		visual.region_rect,
		Rect2(200, 0, 200, 200),
		"east uses the top-right cell"
	)
	visual.sync_motion(Vector2(-1.0, 0.0))
	assertions.equal(visual.get_last_direction(), "w", "leftward motion faces west")
	assertions.equal(
		visual.region_rect,
		Rect2(200, 200, 200, 200),
		"west uses the bottom-right cell"
	)
	visual.sync_motion(Vector2(0.0, -1.0))
	assertions.equal(visual.get_last_direction(), "n", "upward motion faces north")
	assertions.equal(
		visual.region_rect,
		Rect2(0, 0, 200, 200),
		"north uses the top-left cell"
	)
	visual.sync_motion(Vector2.ZERO)
	assertions.equal(
		visual.get_last_direction(),
		"n",
		"stopping preserves the last direction"
	)
	assertions.truthy(visual.visible, "valid configuration shows the sprite")
	visual.free()


func _texture(width: int, height: int) -> ImageTexture:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)
