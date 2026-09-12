extends "res://scripts/preview/tree_3d_preview.gd"
## Isolated art review; no farm session, save writes, or agents.

const SPECIES := ["elder_oak", "open_canopy", "golden_leaning", "open_pine", "tall_pine"]
const TITLES := ["粗根老橡树", "舒展伞冠树", "斜干金叶树", "疏层松树", "直干高松树"]
var selected_tree := 0
var selected_lod := 0
var show_leaves := true
var model: Node3D

func _ready() -> void:
	$PaintedOak.free()
	$FarmerReference.position = Vector3(-3.0, 0, 1)
	$Camera3D.fov = 40.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tree="): selected_tree = clampi(arg.trim_prefix("--tree=").to_int(), 0, SPECIES.size() - 1)
		if arg.begins_with("--lod="): selected_lod = clampi(arg.trim_prefix("--lod=").to_int(), 0, 2)
		if arg == "--bare": show_leaves = false
	_load_tree()
	super._ready()

func _load_tree() -> void:
	if is_instance_valid(model): model.free()
	var path := "res://assets/models/vegetation/illustrated_trees/%s_lod%d.glb" % [SPECIES[selected_tree], selected_lod]
	model = (load(path) as PackedScene).instantiate() as Node3D
	add_child(model)
	$Camera3D.fov = 46.0 if selected_tree == 4 else 40.0
	if is_instance_valid(camera): _update_camera()
	_update_labels()

func _update_camera() -> void:
	var target := Vector3(0, 4.3 if selected_tree == 4 else 2.7, 0)
	var horizontal := cos(pitch) * distance
	camera.global_position = target + Vector3(sin(yaw) * horizontal, sin(pitch) * distance, cos(yaw) * horizontal)
	camera.look_at(target, Vector3.UP)

func _update_labels() -> void:
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		if str(mesh.name).begins_with("Leaves"): mesh.visible = show_leaves
	$CanvasLayer/Title.text = "原画风格树木  ·  %s\nLOD%d  ·  %s" % [TITLES[selected_tree], selected_lod, "疏叶树冠" if show_leaves else "树干与分叉"]
	$CanvasLayer/Controls.text = "1–5 切换树种 · B 显示/隐藏叶子 · L 切换细节 · 右键环绕 · 滚轮缩放 · 空格转台 · R 复位 · F12 截图"

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_5:
			selected_tree = event.keycode - KEY_1
			_load_tree()
			return
		if event.keycode == KEY_L:
			selected_lod = (selected_lod + 1) % 3
			_load_tree()
			return
		if event.keycode == KEY_B:
			show_leaves = not show_leaves
			_update_labels()
			return
	super._unhandled_input(event)
