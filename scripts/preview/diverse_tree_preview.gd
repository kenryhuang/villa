extends "res://scripts/preview/tree_3d_preview.gd"
## Isolated review of the same runtime models used in the farm.

const TreeModel = preload("res://scripts/vegetation/diverse_tree.gd")
const TITLES := ["暖褐橡树", "分叉桦树", "铜红枫树", "金叶高杨", "蓝绿层松", "垂枝柳树"]
var selected_tree := 0
var selected_lod := 0
var show_leaves := true
var model: Node3D

func _ready() -> void:
	$PaintedOak.free()
	$FarmerReference.position = Vector3(-3.2, 0, 1)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tree="): selected_tree = clampi(arg.trim_prefix("--tree=").to_int(), 0, 5)
		if arg.begins_with("--lod="): selected_lod = clampi(arg.trim_prefix("--lod=").to_int(), 0, 2)
		if arg == "--bare": show_leaves = false
	_load_tree()
	super._ready()

func _load_tree() -> void:
	if is_instance_valid(model): model.free()
	model = TreeModel.new()
	model.species = TreeModel.TREE_SPECIES[selected_tree]
	model.forced_lod = selected_lod
	add_child(model)
	$Camera3D.fov = 48
	if is_instance_valid(camera): _update_camera()
	_update_labels()

func _update_camera() -> void:
	var target := Vector3(0, TreeModel.TREE_HEIGHTS[selected_tree]*.48, 0)
	var horizontal := cos(pitch) * distance
	camera.global_position = target + Vector3(sin(yaw)*horizontal, sin(pitch)*distance, cos(yaw)*horizontal)
	camera.look_at(target)

func _update_labels() -> void:
	for mesh in model.find_children("Leaves*", "MeshInstance3D", true, false): mesh.visible = show_leaves
	$CanvasLayer/Title.text = "地图树木 · %s\nLOD%d · %.1f 米" % [TITLES[selected_tree],selected_lod,TreeModel.TREE_HEIGHTS[selected_tree]]
	$CanvasLayer/Controls.text = "1–6 切换树种 · B 隐藏叶子 · L 切换细节 · W 风动 · 右键环绕 · 滚轮缩放 · 空格转台 · F12 截图"

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_6:
			selected_tree = event.keycode - KEY_1
			_load_tree()
			return
		if event.keycode == KEY_B:
			show_leaves = not show_leaves
			_update_labels()
			return
		if event.keycode == KEY_L:
			selected_lod = (selected_lod + 1) % 3
			model.forced_lod = selected_lod
			model.update_lod(0)
			_update_labels()
			return
		if event.keycode == KEY_W:
			model.set_wind_enabled(not model.wind_enabled)
			return
	super._unhandled_input(event)
