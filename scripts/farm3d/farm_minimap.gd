extends Control

## Fixed north-up map: world -Z is north and +X is east.
const Profile = preload("res://scripts/farm3d/terrain_profile.gd")
const PANEL_SIZE := Vector2(248, 302)
const MAP_SCALE := 196.0 / maxf(Profile.WORLD_SIZE.x, Profile.WORLD_SIZE.y)
const MAP_SIZE := Profile.WORLD_SIZE * MAP_SCALE
const MAP_RECT := Rect2(Vector2(124, 146) - MAP_SIZE * .5, MAP_SIZE)
const INK := Color("f8edcf")
const GOLD := Color("e6c882")
var player: Node3D
var session: Node
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
	var normalized := (Vector2(point.x, point.z) - Profile.WORLD_MIN) / Profile.WORLD_SIZE
	return MAP_RECT.position + normalized.clamp(Vector2.ZERO, Vector2.ONE) * MAP_RECT.size

func player_heading() -> Vector2:
	# The farmer model faces local +Z (player.look_at uses use_model_front).
	var forward := player.global_basis.z
	return Vector2(forward.x, forward.z).normalized()

func _process(_delta: float) -> void:
	if is_visible_in_tree() and is_instance_valid(player):
		queue_redraw()

func _draw() -> void:
	if _terrain == null:
		return
	draw_style_box(_panel, Rect2(Vector2.ZERO, size))
	_centered("农庄地图 · G", Vector2(124, 21), 16, INK)
	draw_texture_rect(_terrain, MAP_RECT, false)
	draw_rect(MAP_RECT, Color("829365"), false, 1.0)
	for offset in [-40.0, 0.0, 40.0]:
		draw_line(world_to_map(Vector3(offset, 0, Profile.WORLD_MIN.y)), world_to_map(Vector3(offset, 0, Profile.WORLD_MAX.y)), Color(1, 1, 1, 0.08))
	for offset in range(int(Profile.WORLD_MIN.y)+40, int(Profile.WORLD_MAX.y), 40):
		draw_line(world_to_map(Vector3(Profile.WORLD_MIN.x, 0, offset)), world_to_map(Vector3(Profile.WORLD_MAX.x, 0, offset)), Color(1, 1, 1, 0.08))
	_centered("北", Vector2(124, 42), 17, GOLD)
	_centered("南", Vector2(124, 263), 17, INK)
	_centered("西", Vector2(MAP_RECT.position.x-13, 152), 17, INK)
	_centered("东", Vector2(MAP_RECT.end.x+13, 152), 17, INK)
	_map_label("山地", Vector3(-15, 0, -56))
	_map_label("丘陵", Vector3(-51, 0, 13))
	_map_label("球场", Vector3(-129,0,96))
	var entrance := Profile.Golf.ENTRANCE
	draw_circle(world_to_map(Vector3(entrance.x,0,entrance.y)),3,Color("e6c882"))
	_map_label("河流", Vector3(58, 0, -9))
	var farm := world_to_map(Vector3.ZERO)
	_map_label("沙地", Vector3(-48, 0, 83))
	_map_label("南湖", Vector3(Profile.LAKE_CENTER.x, 0, Profile.LAKE_CENTER.y))
	var farm_half := Vector2.ONE * Profile.CORE_HALF_SIZE * MAP_SCALE
	draw_rect(Rect2(farm - farm_half, farm_half * 2), Color("dfcf9470"), false, 1.0)
	_map_label("农庄", Vector3(0, 0, -17))
	if is_instance_valid(session):
		if session.golf != null and session.golf_round.active:
			var target: Vector3 = session.golf.target_point()
			draw_circle(world_to_map(target),3.5,Color.WHITE)
			var cup: Vector2 = Profile.Golf.HOLES[session.golf_round.hole].cup
			var flag := world_to_map(Vector3(cup.x,0,cup.y))
			draw_line(flag,flag-Vector2(0,7),Color.WHITE,1)
			draw_colored_polygon(PackedVector2Array([flag-Vector2(0,7),flag+Vector2(5,-5),flag-Vector2(0,3)]),Color("ef9c70"))
		var market := Vector3(session.market_site.x, 0, session.market_site.y)
		draw_circle(world_to_map(market), 3.5, GOLD)
		_map_label("市集", market + Vector3(-8, 0, 16))
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
	var resolution := Vector2i(Profile.WORLD_SIZE)
	var image := Image.create(resolution.x, resolution.y, false, Image.FORMAT_RGB8)
	for row in resolution.y:
		for column in resolution.x:
			var x := float(column) + 0.5 + Profile.WORLD_MIN.x
			var z := float(row) + 0.5 + Profile.WORLD_MIN.y
			var height := Profile.height_at(x, z)
			var color := Color("83a15a").lerp(Color("b4ad83"), clampf(height / 28.0, 0, 1))
			color = color.lerp(Color("cbb078"), Profile.sand_weight(x,z))
			var golf := Profile.Golf.paint(Vector2(x,z))
			color = color.lerp(Color("5d8245").lerp(Color("a9bf73"),golf.g).lerp(Color("dfc593"),golf.a),golf.r)
			if Profile.is_water(x, z):
				color = Color("5795aa")
			else:
				var shade := clampf((Profile.height_at(x - 1, z - 1) - height) * 0.10, -0.22, 0.18)
				color = color.lightened(shade) if shade > 0 else color.darkened(-shade)
			image.set_pixel(column, row, color)
	return ImageTexture.create_from_image(image)
