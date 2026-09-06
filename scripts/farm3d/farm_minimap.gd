extends Control

## Fixed north-up map: world -Z is north and +X is east.
const Profile = preload("res://scripts/farm3d/terrain_profile.gd")
const PANEL_SIZE := Vector2(248, 302)
const MAP_RECT := Rect2(26, 48, 196, 196)
const INK := Color("f8edcf")
const GOLD := Color("e6c882")
var player: Node3D
var _terrain: ImageTexture
var _panel: StyleBoxFlat

func _ready() -> void:
	name = "Minimap"
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	# The map occupies UI space, so clicks must not place crops behind it.
	mouse_filter = Control.MOUSE_FILTER_STOP
	_panel = StyleBoxFlat.new()
	_panel.bg_color = Color("202e25f2")
	_panel.border_color = Color("a89058")
	_panel.set_border_width_all(1)
	_panel.set_corner_radius_all(9)
	_terrain = _make_terrain()

func world_to_map(point: Vector3) -> Vector2:
	var normalized := (Vector2(point.x, point.z) + Vector2.ONE * Profile.HALF_SIZE) / (Profile.HALF_SIZE * 2.0)
	return MAP_RECT.position + normalized.clamp(Vector2.ZERO, Vector2.ONE) * MAP_RECT.size

func player_heading() -> Vector2:
	# The farmer model faces local +Z (player.look_at uses use_model_front).
	var forward := player.global_basis.z
	return Vector2(forward.x, forward.z).normalized()

func _process(_delta: float) -> void:
	if is_instance_valid(player):
		queue_redraw()

func _draw() -> void:
	if _terrain == null:
		return
	draw_style_box(_panel, Rect2(Vector2.ZERO, size))
	_text("农庄地图", Vector2(80, 21), 16, INK)
	draw_texture_rect(_terrain, MAP_RECT, false)
	draw_rect(MAP_RECT, Color("829365"), false, 1.0)
	for offset in [-40.0, 0.0, 40.0]:
		draw_line(world_to_map(Vector3(offset, 0, -80)), world_to_map(Vector3(offset, 0, 80)), Color(1, 1, 1, 0.08))
		draw_line(world_to_map(Vector3(-80, 0, offset)), world_to_map(Vector3(80, 0, offset)), Color(1, 1, 1, 0.08))
	_centered("北", Vector2(124, 42), 17, GOLD)
	_centered("南", Vector2(124, 263), 17, INK)
	_centered("西", Vector2(13, 152), 17, INK)
	_centered("东", Vector2(235, 152), 17, INK)
	_map_label("山地", Vector3(-15, 0, -56))
	_map_label("丘陵", Vector3(-51, 0, 13))
	_map_label("河流", Vector3(58, 0, -9))
	var farm := world_to_map(Vector3.ZERO)
	var farm_half := Profile.CORE_HALF_SIZE / (Profile.HALF_SIZE * 2.0) * MAP_RECT.size
	draw_rect(Rect2(farm - farm_half, farm_half * 2), Color("dfcf9470"), false, 1.0)
	_map_label("农庄", Vector3(0, 0, -17))
	var bridge_x := Profile.river_x(Profile.BRIDGE_Z)
	draw_line(world_to_map(Vector3(bridge_x - 8, 0, Profile.BRIDGE_Z)), world_to_map(Vector3(bridge_x + 8, 0, Profile.BRIDGE_Z)), GOLD, 4.0, true)
	_map_label("木桥", Vector3(bridge_x + 8, 0, Profile.BRIDGE_Z + 14))
	if not is_instance_valid(player):
		return
	# Keep the whole arrow visible when the player reaches a world edge.
	var point := world_to_map(player.global_position).clamp(MAP_RECT.position + Vector2.ONE * 10, MAP_RECT.end - Vector2.ONE * 10)
	var forward := player_heading()
	var side := Vector2(-forward.y, forward.x)
	draw_circle(point, 10.0, Color("17271ee0"))
	var arrow := PackedVector2Array([point + forward * 9, point - forward * 6 + side * 5, point - forward * 3, point - forward * 6 - side * 5])
	draw_colored_polygon(arrow, INK)
	arrow.append(arrow[0])
	draw_polyline(arrow, GOLD, 1.0, true)
	var pos := player.global_position
	var region := "木桥" if Profile.is_bridge(pos.x, pos.z) else Profile.region_at(pos.x, pos.z)
	_centered("%s · %s %d / %s %d 米" % [region, "东" if pos.x >= 0 else "西", roundi(absf(pos.x)), "南" if pos.z >= 0 else "北", roundi(absf(pos.z))], Vector2(124, 287), 13, INK)

func _text(value: String, baseline: Vector2, font_size: int, color: Color) -> void:
	var font := get_theme_default_font()
	draw_string_outline(font, baseline, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color("202e25"))
	draw_string(font, baseline, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _centered(value: String, baseline: Vector2, font_size: int, color: Color) -> void:
	var width := get_theme_default_font().get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(value, baseline - Vector2(width * 0.5, 0), font_size, color)

func _map_label(value: String, point: Vector3) -> void:
	_centered(value, world_to_map(point), 12, INK)

func _make_terrain() -> ImageTexture:
	# Cache a lightweight topographic map from the same surface as the 3D world.
	var resolution := 160
	var image := Image.create(resolution, resolution, false, Image.FORMAT_RGB8)
	for row in resolution:
		for column in resolution:
			var x := (float(column) + 0.5) / resolution * Profile.HALF_SIZE * 2.0 - Profile.HALF_SIZE
			var z := (float(row) + 0.5) / resolution * Profile.HALF_SIZE * 2.0 - Profile.HALF_SIZE
			var height := Profile.height_at(x, z)
			var color := Color("83a15a").lerp(Color("b4ad83"), clampf(height / 28.0, 0, 1))
			if Profile.is_water(x, z):
				color = Color("5795aa")
			else:
				var shade := clampf((Profile.height_at(x - 1, z - 1) - height) * 0.10, -0.22, 0.18)
				color = color.lightened(shade) if shade > 0 else color.darkened(-shade)
			image.set_pixel(column, row, color)
	return ImageTexture.create_from_image(image)
