extends RefCounted


func run(assertions: TestAssert) -> void:
	var visual := BuildingActivityVisual.new()
	var valid_texture := _texture(Vector2i(2048, 512))
	assertions.truthy(
		visual.configure(
			valid_texture,
			Vector2(2.0, 2.0),
			Vector2(0.5, 0.9375),
			4.0
		),
		"valid activity atlas configures"
	)
	assertions.equal(visual.hframes, 4, "activity atlas exposes four frames")
	assertions.equal(visual.frame, 0, "activity starts at frame zero")
	assertions.equal(visual.visible, false, "configured activity starts hidden")
	assertions.truthy(visual.is_configured(), "valid atlas reports configured")

	visual.set_active(true)
	visual.advance_animation(0.26)
	assertions.equal(visual.frame, 1, "activity advances at configured fps")
	assertions.truthy(visual.is_active(), "activity reports active target state")
	assertions.near(visual.modulate.a, 1.0, 0.001, "activity fades fully in")

	visual.set_active(false)
	visual.advance_animation(0.16)
	assertions.equal(visual.frame, 0, "inactive activity resets")
	assertions.equal(visual.visible, false, "inactive activity hides after fade")
	assertions.equal(visual.is_active(), false, "activity reports inactive target state")

	var fallback_fps := BuildingActivityVisual.new()
	assertions.truthy(
		fallback_fps.configure(
			valid_texture,
			Vector2(2.0, 2.0),
			Vector2(0.5, 0.9375),
			0.0
		),
		"invalid fps does not discard a valid atlas"
	)
	assertions.near(
		fallback_fps.get_effective_fps(),
		4.0,
		0.001,
		"invalid fps uses the safe fallback"
	)

	var malformed := BuildingActivityVisual.new()
	assertions.equal(
		malformed.configure(
			_texture(Vector2i(1024, 512)),
			Vector2(2.0, 2.0),
			Vector2(0.5, 0.9375),
			4.0
		),
		false,
		"malformed atlas is rejected"
	)
	assertions.equal(malformed.visible, false, "malformed atlas remains hidden")
	assertions.equal(malformed.is_configured(), false, "malformed atlas is not configured")

	var missing := BuildingActivityVisual.new()
	assertions.equal(
		missing.configure(
			null,
			Vector2(2.0, 2.0),
			Vector2(0.5, 0.9375),
			4.0
		),
		false,
		"missing atlas is rejected"
	)

	visual.free()
	fallback_fps.free()
	malformed.free()
	missing.free()


func _texture(size: Vector2i) -> ImageTexture:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)
