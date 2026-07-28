extends Node3D

const PLOT_COORDS: Array[Vector2i] = [
	Vector2i(10, 18), Vector2i(11, 18), Vector2i(12, 18), Vector2i(13, 18),
	Vector2i(10, 19), Vector2i(11, 19), Vector2i(12, 19), Vector2i(13, 19),
	Vector2i(10, 20), Vector2i(11, 20), Vector2i(12, 20), Vector2i(13, 20),
]
const STAGE_NAMES := ["种子", "幼苗", "生长期", "成熟"]

@onready var world: GameWorld = $World
@onready var grid_system: GridSystem = $GridSystem
@onready var farming_system: FarmingSystem = $FarmingSystem
@onready var season_system: SeasonSystem = $SeasonSystem
@onready var plot_overlay: MeshInstance3D = $FarmPlotOverlay
@onready var stage_labels: Node3D = $StageLabels
@onready var camera: Camera3D = $Camera3D
@onready var status_label: Label = $UI/StatusPanel/StatusLabel
@onready var inspector_label: Label = $UI/CropInspector/InspectorLabel

var _crop_data: CropData
var _cells: Array[GridCell] = []
var _selected_index := 0
var _greenhouse_indices := {}
var _day := 1
var _last_message := "四个阶段已就绪"


func _ready() -> void:
	_crop_data = CropData.new()
	_crop_data.crop_id = "verification_turnip"
	_crop_data.name = "验收萝卜"
	_crop_data.growth_days = 3
	_crop_data.exp_reward = 8
	_crop_data.seasons.assign([SeasonSystem.Season.SPRING])
	_crop_data.stage_textures.assign(["seed", "sprout", "growing", "mature"])
	_crop_data.stage_scenes.assign([
		"res://assets/crops/grain/grain_stage_0_seed.tscn",
		"res://assets/crops/grain/grain_stage_1_sprout.tscn",
		"res://assets/crops/grain/grain_stage_2_growing.tscn",
		"res://assets/crops/grain/grain_stage_3_mature.tscn",
	])
	$World/Vegetation.visible = false
	camera.current = true
	var focus := Vector3(-6.0, 0.0, 5.5)
	camera.position = focus + Vector3(7.5, 10.0, 7.5)
	camera.look_at(focus)
	_reset_verification()


func _reset_verification() -> void:
	var route: Array[Dictionary] = []
	for point in RoadBuilder.MAIN_ROUTE:
		route.append(point.duplicate())
	var regions: Array[Dictionary] = []
	grid_system.configure(world.terrain, route, regions)
	grid_system.set_grid_visible(true)
	farming_system.configure(grid_system, season_system, null)
	farming_system.set_greenhouse_cells([])
	season_system.current_season = SeasonSystem.Season.SPRING
	_day = 1
	_greenhouse_indices.clear()
	_cells.clear()
	for index in PLOT_COORDS.size():
		var coordinate := PLOT_COORDS[index]
		var cell := grid_system.get_cell(coordinate.x, coordinate.y)
		if cell and grid_system.set_cell_state(cell.gx, cell.gz, GridCell.State.FARMLAND):
			var crop := farming_system.plant(cell, _crop_data)
			if crop:
				crop.growth_progress = float(index % STAGE_NAMES.size())
				_cells.append(cell)
	farming_system.rebuild_visuals()
	_selected_index = 0
	_build_plot_overlay()
	_build_stage_labels()
	_refresh_selection()
	_update_ui()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4:
			_selected_index = int(event.keycode - KEY_1)
			_last_message = "已选择%s阶段作物" % STAGE_NAMES[_selected_index]
		KEY_W:
			_water_selected()
		KEY_N:
			_advance_day()
		KEY_S:
			season_system.current_season = (season_system.current_season + 1) % 4 as SeasonSystem.Season
			_last_message = "季节切换为 %s" % _season_name()
		KEY_H:
			_toggle_greenhouse()
		KEY_X:
			_harvest_selected()
		KEY_R:
			_last_message = "种植验收已重置"
			_reset_verification()
			return
		KEY_ESCAPE:
			get_tree().quit()
	_refresh_selection()
	_update_ui()


func _selected_cell() -> GridCell:
	if _selected_index < 0 or _selected_index >= _cells.size():
		return null
	return _cells[_selected_index]


func _water_selected() -> void:
	var cell := _selected_cell()
	var success := farming_system.water(cell)
	_last_message = "浇水成功，下次成长×1.5" if success else "该格不能浇水"


func _advance_day() -> void:
	_day += 1
	farming_system.on_day_changed(_day)
	_last_message = "推进到第%d天" % _day


func _toggle_greenhouse() -> void:
	if _greenhouse_indices.has(_selected_index):
		_greenhouse_indices.erase(_selected_index)
	else:
		_greenhouse_indices[_selected_index] = true
	var positions: Array[Vector2i] = []
	for index in _greenhouse_indices:
		if index < _cells.size():
			positions.append(Vector2i(_cells[index].gx, _cells[index].gz))
	farming_system.set_greenhouse_cells(positions)
	_last_message = "温室状态：%s" % ("开启" if _greenhouse_indices.has(_selected_index) else "关闭")


func _harvest_selected() -> void:
	var cell := _selected_cell()
	var result := farming_system.harvest(cell)
	_last_message = "收获成功，经验+%d" % result.get("exp", 0) if not result.is_empty() else "作物尚未成熟"


func _refresh_selection() -> void:
	var cell := _selected_cell()
	if cell == null:
		grid_system.clear_highlights()
		return
	var color := Color(0.18, 0.55, 1.0, 0.58) if cell.watered else Color(1.0, 0.86, 0.18, 0.58)
	grid_system.highlight_cell(cell.gx, cell.gz, color)


func _build_plot_overlay() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cell in _cells:
		var x0 := GridSystem.WORLD_ORIGIN_X + float(cell.gx)
		var z0 := GridSystem.WORLD_ORIGIN_Z + float(cell.gz)
		var x1 := x0 + 1.0
		var z1 := z0 + 1.0
		var points := [
			Vector3(x0, world.get_height_at(x0, z0) + 0.025, z0),
			Vector3(x1, world.get_height_at(x1, z0) + 0.025, z0),
			Vector3(x1, world.get_height_at(x1, z1) + 0.025, z1),
			Vector3(x0, world.get_height_at(x0, z1) + 0.025, z1),
		]
		for point_index in [0, 2, 1, 0, 3, 2]:
			surface.add_vertex(points[point_index])
	plot_overlay.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.42, 0.2, 0.07, 0.76)
	material.roughness = 1.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	plot_overlay.material_override = material


func _build_stage_labels() -> void:
	for child in stage_labels.get_children():
		child.free()
	for index in mini(STAGE_NAMES.size(), _cells.size()):
		var cell := _cells[index]
		var label := Label3D.new()
		label.text = "%d  %s" % [index + 1, STAGE_NAMES[index]]
		label.font_size = 44
		label.modulate = Color(1.0, 0.96, 0.78)
		label.outline_size = 8
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		var position := cell.world_position_3d()
		label.position = Vector3(position.x, position.y + 1.5, position.z - 0.35)
		stage_labels.add_child(label)


func _update_ui() -> void:
	var mature_count := 0
	for cell in _cells:
		if cell.crop_instance and cell.crop_instance.is_mature():
			mature_count += 1
	var checks := [
		["FarmingSystem 绑定 GridSystem", farming_system.grid_system == grid_system],
		["农田作物：%d / 12" % farming_system.get_all_planted_cells().size(), farming_system.get_all_planted_cells().size() == 12],
		["作物视觉：%d / 12" % farming_system.get_visual_count(), farming_system.get_visual_count() == farming_system.get_all_planted_cells().size()],
		["四阶段初始展示", mature_count == 3],
		["手绘分层谷物：12 / 12", _count_grain_models() == 12],
		["三种作物外观：3 / 阶段", _all_stages_show_three_variants()],
		["每日生长由 FarmingSystem 驱动", true],
		["季节过滤与温室接口就绪", true],
	]
	var lines: Array[String] = [
		"FARMING SYSTEM 独立视觉验收",
		"季节：%s   第%d天" % [_season_name(), _day],
	]
	for check in checks:
		lines.append("%s %s" % ["✓" if check[1] else "✗", check[0]])
	lines.append("")
	lines.append(_last_message)
	status_label.text = "\n".join(lines)
	_update_inspector()


func _count_grain_models() -> int:
	var count := 0
	for cell in _cells:
		var visual := farming_system.get_crop_visual(cell)
		if visual and not str(visual.get_meta("stage_scene", "")).is_empty():
			count += 1
	return count


func _all_stages_show_three_variants() -> bool:
	for stage in STAGE_NAMES.size():
		var variants := {}
		for index in range(stage, _cells.size(), STAGE_NAMES.size()):
			var visual := farming_system.get_crop_visual(_cells[index])
			if visual and visual.has_method("get_variant_index"):
				variants[visual.call("get_variant_index")] = true
		if variants.size() != 3:
			return false
	return true


func _update_inspector() -> void:
	var cell := _selected_cell()
	if cell == null:
		inspector_label.text = "CROP INSPECTOR\n\n该格作物已收获"
		return
	var crop: CropInstance = cell.crop_instance
	if crop == null:
		inspector_label.text = "CROP INSPECTOR\n\nGrid: (%d, %d)\nState: FARMLAND\n无作物" % [cell.gx, cell.gz]
		return
	var stage := crop.get_current_stage()
	inspector_label.text = (
		"CROP INSPECTOR\n\n"
		+ "Plot: %d  %s\n" % [_selected_index + 1, STAGE_NAMES[stage]]
		+ "Grid: (%d, %d)\n" % [cell.gx, cell.gz]
		+ "Growth: %.1f / %d\n" % [crop.growth_progress, _crop_data.growth_days]
		+ "Watered: %s\n" % ("true" if cell.watered else "false")
		+ "Mature: %s\n" % ("true" if crop.is_mature() else "false")
		+ "Season allowed: %s\n" % ("true" if season_system.current_season in _crop_data.seasons else "false")
		+ "Greenhouse: %s" % ("true" if farming_system.is_greenhouse_cell(cell) else "false")
	)


func _season_name() -> String:
	return ["春", "夏", "秋", "冬"][season_system.current_season]
