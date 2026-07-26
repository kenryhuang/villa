extends Node3D

const TEST_WATER_RECT := Rect2(-17.5, 9.5, 3.0, 3.0)
const TEST_DECORATION_RECT := Rect2(14.0, -13.0, 2.5, 2.5)

@onready var world: GameWorld = $World
@onready var grid_system: GridSystem = $GridSystem
@onready var state_overlay: MeshInstance3D = $VerificationStateOverlay
@onready var camera: Camera3D = $Camera3D
@onready var status_label: Label = $UI/StatusPanel/StatusLabel
@onready var inspector_label: Label = $UI/CellInspector/InspectorLabel

var _hovered_cell: GridCell
var _selected_cell: GridCell
var _test_crop: CropData
var _last_message := "移动鼠标检查格子，左键选择"


func _ready() -> void:
	_test_crop = CropData.new()
	_test_crop.crop_id = "verification_crop"
	_test_crop.name = "验收作物"
	_test_crop.growth_days = 2
	_test_crop.exp_reward = 5
	_test_crop.stage_textures.assign(["seed", "sprout", "mature"])
	camera.current = true
	_configure_grid()


func _configure_grid() -> void:
	var route: Array[Dictionary] = []
	for point in RoadBuilder.MAIN_ROUTE:
		route.append(point.duplicate())
	var regions: Array[Dictionary] = [
		{"state": GridCell.State.WATER, "rect": TEST_WATER_RECT},
		{"state": GridCell.State.DECORATION, "rect": TEST_DECORATION_RECT},
	]
	if not grid_system.configure(world.terrain, route, regions):
		status_label.text = "✗ GridSystem 配置失败"
		return
	grid_system.set_grid_visible(true)
	_selected_cell = null
	_hovered_cell = null
	_build_state_overlay()
	_update_status()
	_update_inspector()


func _process(_delta: float) -> void:
	var hit: Variant = _raycast_mouse_to_terrain()
	if hit == null:
		return
	var next_cell: GridCell = grid_system.get_cell_at_world(hit.x, hit.z)
	if next_cell == _hovered_cell:
		return
	_hovered_cell = next_cell
	if _hovered_cell:
		var color := Color(1.0, 0.86, 0.2, 0.58)
		if not grid_system.can_farm_at(_hovered_cell.gx, _hovered_cell.gz):
			color = Color(1.0, 0.34, 0.22, 0.58)
		grid_system.highlight_cell(_hovered_cell.gx, _hovered_cell.gz, color)
	_update_inspector()


func _raycast_mouse_to_terrain() -> Variant:
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var end := origin + camera.project_ray_normal(mouse) * 100.0
	var query := PhysicsRayQueryParameters3D.create(origin, end, 1)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	return result.position if result.has("position") else null


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_selected_cell = _hovered_cell
		_last_message = "已选择格子" if _selected_cell else "没有命中格子"
		_update_inspector()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_H:
			_apply_hoe()
		KEY_P:
			_plant_test_crop()
		KEY_W:
			_water_selected()
		KEY_G:
			var overlay := grid_system.get_node("GridOverlay") as MeshInstance3D
			grid_system.set_grid_visible(not overlay.visible)
			_last_message = "网格线：%s" % ("显示" if overlay.visible else "隐藏")
		KEY_S:
			state_overlay.visible = not state_overlay.visible
			_last_message = "状态覆盖：%s" % ("显示" if state_overlay.visible else "隐藏")
		KEY_R:
			_last_message = "验证状态已重置"
			_configure_grid()
		KEY_ESCAPE:
			get_tree().quit()
	_update_status()
	_update_inspector()


func _apply_hoe() -> void:
	if _selected_cell == null:
		_last_message = "请先左键选择格子"
		return
	var changed := grid_system.set_cell_state(
		_selected_cell.gx,
		_selected_cell.gz,
		GridCell.State.FARMLAND
	)
	_last_message = "开垦成功" if changed else "开垦被规则拒绝"
	_build_state_overlay()


func _plant_test_crop() -> void:
	if _selected_cell == null:
		_last_message = "请先左键选择格子"
		return
	var crop := grid_system.plant_crop(_selected_cell.gx, _selected_cell.gz, _test_crop)
	_last_message = "种植成功" if crop else "只能在农田种植"
	_build_state_overlay()


func _water_selected() -> void:
	if _selected_cell == null:
		_last_message = "请先左键选择格子"
		return
	var watered := grid_system.water_cell(_selected_cell.gx, _selected_cell.gz)
	_last_message = "浇水成功" if watered else "该格不能浇水"


func _build_state_overlay() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cell in grid_system._cells.values():
		var color := _cell_color(cell)
		var gx: int = cell.gx
		var gz: int = cell.gz
		var x0 := GridSystem.WORLD_ORIGIN_X + float(gx)
		var z0 := GridSystem.WORLD_ORIGIN_Z + float(gz)
		var x1 := x0 + GridSystem.CELL_SIZE
		var z1 := z0 + GridSystem.CELL_SIZE
		var points := [
			Vector3(x0, world.get_height_at(x0, z0) + 0.022, z0),
			Vector3(x1, world.get_height_at(x1, z0) + 0.022, z0),
			Vector3(x1, world.get_height_at(x1, z1) + 0.022, z1),
			Vector3(x0, world.get_height_at(x0, z1) + 0.022, z1),
		]
		for index in [0, 2, 1, 0, 3, 2]:
			surface.set_color(color)
			surface.add_vertex(points[index])
	state_overlay.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	state_overlay.material_override = material


func _cell_color(cell: GridCell) -> Color:
	if cell.state == GridCell.State.WASTELAND and cell.slope > GridSystem.SLOPE_THRESHOLD:
		return Color(0.95, 0.1, 0.08, 0.36)
	match cell.state:
		GridCell.State.FARMLAND:
			return Color(0.45, 0.2, 0.06, 0.38)
		GridCell.State.PLANTED:
			return Color(0.12, 0.72, 0.22, 0.42)
		GridCell.State.BUILDING:
			return Color(1.0, 0.45, 0.08, 0.4)
		GridCell.State.ROAD:
			return Color(0.72, 0.48, 0.18, 0.32)
		GridCell.State.WATER:
			return Color(0.05, 0.38, 0.95, 0.5)
		GridCell.State.DECORATION:
			return Color(0.65, 0.18, 0.82, 0.42)
	return Color(0.25, 0.28, 0.2, 0.08)


func _update_status() -> void:
	var road_count := 0
	var water_count := 0
	var decoration_count := 0
	for cell in grid_system._cells.values():
		match cell.state:
			GridCell.State.ROAD:
				road_count += 1
			GridCell.State.WATER:
				water_count += 1
			GridCell.State.DECORATION:
				decoration_count += 1
	var overlay := grid_system.get_node_or_null("GridOverlay") as MeshInstance3D
	var checks := [
		["GridSystem 已绑定 Terrain", grid_system.terrain == world.terrain],
		["网格数量：%d / 1008" % grid_system._cells.size(), grid_system._cells.size() == 1008],
		["坐标边界：(0,0) → (35,27)", grid_system.get_cell(35, 27) != null],
		["单 ArrayMesh 网格线", overlay != null and overlay.mesh is ArrayMesh],
		["道路格：%d" % road_count, road_count > 0],
		["测试水域格：%d" % water_count, water_count > 0],
		["测试装饰格：%d" % decoration_count, decoration_count > 0],
	]
	var lines: Array[String] = ["GRID SYSTEM 独立视觉验收"]
	for check in checks:
		lines.append("%s %s" % ["✓" if check[1] else "✗", check[0]])
	lines.append("")
	lines.append(_last_message)
	status_label.text = "\n".join(lines)


func _update_inspector() -> void:
	var cell := _selected_cell if _selected_cell else _hovered_cell
	if cell == null:
		inspector_label.text = "CELL INSPECTOR\n\n移动鼠标到地形网格"
		return
	var point := cell.world_position_3d()
	var state_name: String = GridCell.State.keys()[cell.state]
	inspector_label.text = (
		"CELL INSPECTOR\n\n"
		+ "Grid: (%d, %d)\n" % [cell.gx, cell.gz]
		+ "World: (%.1f, %.3f, %.1f)\n" % [point.x, point.y, point.z]
		+ "State: %s\n" % state_name
		+ "Height: %.4f\n" % cell.terrain_height
		+ "Slope: %.4f\n" % cell.slope
		+ "Farmable: %s\n" % ("true" if grid_system.can_farm_at(cell.gx, cell.gz) else "false")
		+ "Watered: %s" % ("true" if cell.watered else "false")
	)
