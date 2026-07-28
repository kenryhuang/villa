extends Node3D

const BUILDING_IDS: Array[String] = [
	"barn",
	"greenhouse",
	"windmill",
	"chicken_coop",
	"beehive",
	"well",
	"workbench",
	"lamp",
	"fence",
]
const GALLERY_ORIGINS: Array[Vector2i] = [
	Vector2i(5, 6),
	Vector2i(11, 5),
	Vector2i(18, 6),
	Vector2i(5, 12),
	Vector2i(12, 13),
	Vector2i(18, 13),
	Vector2i(5, 18),
	Vector2i(12, 18),
	Vector2i(18, 18),
]
const PREVIEW_START := Vector2i(23, 14)


class VerificationEconomy:
	extends RefCounted
	var materials_available := true
	var spend_calls := 0

	func has_resources(_cost: Dictionary) -> bool:
		return materials_available

	func spend_resources(_cost: Dictionary) -> bool:
		if not materials_available:
			return false
		spend_calls += 1
		return true


@onready var world: GameWorld = $World
@onready var grid_system: GridSystem = $GridSystem
@onready var building_system: BuildingSystem = $BuildingSystem
@onready var gallery_labels: Node3D = $GalleryLabels
@onready var camera: Camera3D = $Camera3D
@onready var status_label: Label = $UI/StatusPanel/StatusLabel
@onready var inspector_label: Label = $UI/BuildingInspector/InspectorLabel

var _economy := VerificationEconomy.new()
var _selected_index := 0
var _preview_grid := PREVIEW_START
var _last_message := "九类建筑已就绪；绿色预览区可交互"
var _resource_rejection_verified := false
var _resource_spend_verified := false
var _removal_restore_verified := false
var _preview_colors_verified := false
var _manual_blocked_states := {}


func _ready() -> void:
	$World/Vegetation.visible = false
	camera.current = true
	var focus := Vector3(-4.0, 0.0, -1.5)
	camera.position = focus + Vector3(12.5, 14.5, 12.5)
	camera.look_at(focus)
	_reset_verification()


func _reset_verification() -> void:
	building_system.clear_buildings()
	grid_system.configure(world.terrain, [], [])
	grid_system.set_grid_visible(true)
	_economy.materials_available = true
	_economy.spend_calls = 0
	_manual_blocked_states.clear()
	building_system.configure(grid_system, _economy)
	for index in BUILDING_IDS.size():
		var placed := building_system.place_building(BUILDING_IDS[index], GALLERY_ORIGINS[index].x, GALLERY_ORIGINS[index].y)
		if placed == null:
			_last_message = "画廊放置失败：%s" % BUILDING_IDS[index]
	_build_gallery_labels()
	_verify_failure_paths()
	_selected_index = 0
	_preview_grid = PREVIEW_START
	_enter_selected_preview()
	_verify_preview_states()
	_update_ui()


func _verify_failure_paths() -> void:
	var rejection_cell := grid_system.get_cell(30, 23)
	var rejection_state := rejection_cell.state
	var spend_count_before_rejection := _economy.spend_calls
	_economy.materials_available = false
	var rejected := building_system.place_building("well", 30, 23)
	_resource_rejection_verified = (
		rejected == null
		and rejection_cell.state == rejection_state
		and _economy.spend_calls == spend_count_before_rejection
	)
	_economy.materials_available = true

	var restore_cell := grid_system.get_cell(31, 23)
	grid_system.set_cell_state(restore_cell.gx, restore_cell.gz, GridCell.State.FARMLAND)
	var removable := building_system.place_building("fence", restore_cell.gx, restore_cell.gz)
	_resource_spend_verified = removable != null and _economy.spend_calls == spend_count_before_rejection + 1
	_removal_restore_verified = (
		removable != null
		and building_system.remove_building(removable)
		and restore_cell.state == GridCell.State.FARMLAND
	)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			_selected_index = int(event.keycode - KEY_1)
			_last_message = "选择：%s" % _selected_data().display_name
			_enter_selected_preview()
		KEY_LEFT:
			_move_preview(Vector2i.LEFT)
		KEY_RIGHT:
			_move_preview(Vector2i.RIGHT)
		KEY_UP:
			_move_preview(Vector2i.UP)
		KEY_DOWN:
			_move_preview(Vector2i.DOWN)
		KEY_P, KEY_ENTER, KEY_KP_ENTER:
			_place_selected()
		KEY_X:
			_remove_at_preview()
		KEY_B:
			_toggle_preview_blocked()
		KEY_M:
			_economy.materials_available = not _economy.materials_available
			_last_message = "材料：%s" % ("充足" if _economy.materials_available else "不足")
			if building_system.is_in_build_mode():
				building_system.update_preview_grid(_preview_grid.x, _preview_grid.y)
		KEY_R:
			_last_message = "建筑系统验收已重置"
			_reset_verification()
			return
		KEY_ESCAPE:
			get_tree().quit()
	_update_ui()


func _selected_data() -> BuildingData:
	return BuildingData.from_dictionary(GameData.get_building(BUILDING_IDS[_selected_index]))


func _enter_selected_preview() -> void:
	building_system.enter_preview_mode(_selected_data())
	building_system.update_preview_grid(_preview_grid.x, _preview_grid.y)


func _verify_preview_states() -> void:
	var cell := grid_system.get_cell(_preview_grid.x, _preview_grid.y)
	if cell == null or cell.state not in [GridCell.State.WASTELAND, GridCell.State.FARMLAND]:
		_preview_colors_verified = false
		return
	var previous_state := cell.state
	var valid_before := building_system.update_preview(_preview_grid.x, _preview_grid.y)
	var green_before := _preview_marker_matches(true)
	var blocked := grid_system.set_cell_state(_preview_grid.x, _preview_grid.y, GridCell.State.BUILDING)
	var invalid_while_blocked := not building_system.update_preview(_preview_grid.x, _preview_grid.y)
	var red_while_blocked := _preview_marker_matches(false)
	var restored := grid_system.set_cell_state(_preview_grid.x, _preview_grid.y, previous_state)
	var valid_after := building_system.update_preview(_preview_grid.x, _preview_grid.y)
	_preview_colors_verified = (
		valid_before
		and green_before
		and blocked
		and invalid_while_blocked
		and red_while_blocked
		and restored
		and valid_after
		and _preview_marker_matches(true)
	)


func _preview_marker_matches(expect_valid: bool) -> bool:
	var markers := building_system.get_node_or_null("BuildingPreview/FootprintMarkers")
	if markers == null or markers.get_child_count() == 0:
		return false
	var marker := markers.get_child(0) as MeshInstance3D
	var material := marker.material_override as StandardMaterial3D
	if material == null:
		return false
	return material.albedo_color.g > material.albedo_color.r if expect_valid else material.albedo_color.r > material.albedo_color.g


func _toggle_preview_blocked() -> void:
	if not building_system.is_in_build_mode():
		_enter_selected_preview()
	var location := _preview_grid
	var cell := grid_system.get_cell(location.x, location.y)
	if cell == null:
		return
	if _manual_blocked_states.has(location):
		grid_system.set_cell_state(location.x, location.y, int(_manual_blocked_states[location]))
		_manual_blocked_states.erase(location)
		_last_message = "目标格阻塞已解除"
	elif building_system.get_building_at(location.x, location.y) != null:
		_last_message = "目标格已有真实建筑，请用 X 拆除"
	elif cell.state in [GridCell.State.WASTELAND, GridCell.State.FARMLAND]:
		_manual_blocked_states[location] = cell.state
		grid_system.set_cell_state(location.x, location.y, GridCell.State.BUILDING)
		_last_message = "目标格已设为阻塞（红色预览）"
	else:
		_last_message = "当前地块状态不能切换阻塞"
	building_system.update_preview_grid(location.x, location.y)


func _move_preview(direction: Vector2i) -> void:
	var data := _selected_data()
	_preview_grid += direction
	_preview_grid.x = clampi(_preview_grid.x, 0, GridSystem.GRID_WIDTH - data.footprint.x)
	_preview_grid.y = clampi(_preview_grid.y, 0, GridSystem.GRID_DEPTH - data.footprint.y)
	if not building_system.is_in_build_mode():
		building_system.enter_preview_mode(data)
	building_system.update_preview_grid(_preview_grid.x, _preview_grid.y)
	_last_message = "预览移动到 (%d, %d)" % [_preview_grid.x, _preview_grid.y]


func _place_selected() -> void:
	if not building_system.is_in_build_mode():
		_enter_selected_preview()
		return
	var placed := building_system.place_selected_building(_preview_grid.x, _preview_grid.y)
	if placed:
		_last_message = "放置成功：%s" % placed.data.display_name
		_preview_grid.x = mini(_preview_grid.x + placed.data.footprint.x + 1, GridSystem.GRID_WIDTH - 1)
		_enter_selected_preview()
	else:
		_last_message = "放置被拒绝：检查占用格或材料"


func _remove_at_preview() -> void:
	var building := building_system.get_building_at(_preview_grid.x, _preview_grid.y)
	if building == null:
		_last_message = "当前预览格没有建筑"
		return
	var display_name := building.data.display_name
	building_system.remove_building(building)
	_last_message = "已拆除：%s；原网格状态已恢复" % display_name
	if not building_system.is_in_build_mode():
		_enter_selected_preview()
	else:
		building_system.update_preview_grid(_preview_grid.x, _preview_grid.y)


func _build_gallery_labels() -> void:
	for child in gallery_labels.get_children():
		child.free()
	for index in BUILDING_IDS.size():
		var data := BuildingData.from_dictionary(GameData.get_building(BUILDING_IDS[index]))
		var origin := GALLERY_ORIGINS[index]
		var first := grid_system.grid_to_world(origin.x, origin.y)
		var last := grid_system.grid_to_world(origin.x + data.footprint.x - 1, origin.y + data.footprint.y - 1)
		var label := Label3D.new()
		label.text = "%d  %s" % [index + 1, data.display_name]
		label.font_size = 42
		label.modulate = Color(1.0, 0.95, 0.76)
		label.outline_size = 8
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(
			(first.x + last.x) * 0.5,
			grid_system.get_terrain_height_at_cell(origin.x, origin.y) + data.visual_size.y + 0.42,
			(first.y + last.y) * 0.5
		)
		gallery_labels.add_child(label)


func verification_contract_passes() -> bool:
	return (
		building_system.grid_system_ref == grid_system
		and building_system.get_building_count() >= 9
		and _count_painted_buildings() >= 9
		and _count_physics_contracts() >= 9
		and _occupied_grid_count() == _expected_occupied_count()
		and _resource_rejection_verified
		and _resource_spend_verified
		and _removal_restore_verified
		and _preview_colors_verified
		and building_system.is_in_build_mode()
		and building_system.get_preview_marker_count() == _selected_data().footprint.x * _selected_data().footprint.y
	)


func _count_painted_buildings() -> int:
	var count := 0
	for building in building_system.get_all_buildings():
		var back := building.get_node_or_null("VisualRoot/BackLayer") as Sprite3D
		var front := building.get_node_or_null("VisualRoot/FrontLayer") as Sprite3D
		if back and front and back.texture != null and front.texture != null and back.visible and front.visible:
			count += 1
	return count


func _count_physics_contracts() -> int:
	var count := 0
	for building in building_system.get_all_buildings():
		if (
			building.get_node("Collision").collision_layer == 16 | 64
			and building.get_node("InteractionArea").collision_layer == 64 | 256
			and building.get_node("CameraOccluder").collision_layer == 32
		):
			count += 1
	return count


func _expected_occupied_count() -> int:
	var count := 0
	for building in building_system.get_all_buildings():
		count += building.occupied_cells.size()
	return count + _manual_blocked_states.size()


func _occupied_grid_count() -> int:
	var count := 0
	for cell in grid_system._cells.values():
		if cell.state == GridCell.State.BUILDING:
			count += 1
	return count


func _update_ui() -> void:
	var checks := [
		["BuildingSystem 绑定 GridSystem", building_system.grid_system_ref == grid_system],
		["建筑画廊：%d / 9" % building_system.get_building_count(), building_system.get_building_count() >= 9],
		["手绘双层模型：%d / 9" % _count_painted_buildings(), _count_painted_buildings() >= 9],
		["碰撞 / 交互 / 遮挡：%d / 9" % _count_physics_contracts(), _count_physics_contracts() >= 9],
		["占用格：%d / %d" % [_occupied_grid_count(), _expected_occupied_count()], _occupied_grid_count() == _expected_occupied_count()],
		["材料不足时原子拒绝", _resource_rejection_verified],
		["成功放置扣除一次资源", _resource_spend_verified],
		["拆除逐格恢复原状态", _removal_restore_verified],
		["绿色 / 红色预览状态", _preview_colors_verified],
		["预览足迹：%d 格" % building_system.get_preview_marker_count(), building_system.get_preview_marker_count() == _selected_data().footprint.x * _selected_data().footprint.y],
	]
	var lines: Array[String] = [
		"BUILDING SYSTEM 独立视觉验收",
		"固定朝向 · 2.5D 手绘双层 · 真实 3D 碰撞",
	]
	for check in checks:
		lines.append("%s %s" % ["✓" if check[1] else "✗", check[0]])
	lines.append("")
	lines.append(_last_message)
	status_label.text = "\n".join(lines)
	_update_inspector()


func _update_inspector() -> void:
	var data := _selected_data()
	var cost_parts: Array[String] = []
	for item_id in data.cost:
		cost_parts.append("%s × %d" % [item_id, data.cost[item_id]])
	inspector_label.text = (
		"BUILDING INSPECTOR\n\n"
		+ "%d  %s\n" % [_selected_index + 1, data.display_name]
		+ "ID: %s\n" % data.building_id
		+ "Footprint: %d × %d\n" % [data.footprint.x, data.footprint.y]
		+ "Cost: %s\n" % ", ".join(cost_parts)
		+ "Effect: %s\n" % data.effect
		+ "Preview Grid: (%d, %d)\n" % [_preview_grid.x, _preview_grid.y]
		+ "Can Place: %s\n" % ("true" if building_system.get_preview_can_place() else "false")
		+ "Materials: %s" % ("available" if _economy.materials_available else "missing")
	)
