extends "res://scripts/preview/tree_3d_preview.gd"

const GOLDEN = preload("res://scenes/vegetation/golden_broadleaf.tscn")
const GREEN = preload("res://scenes/vegetation/green_columnar.tscn")
const OPEN = preload("res://scenes/vegetation/open_green.tscn")
var samples: Array[Node3D] = []
var shrubs: Array[Node3D] = []
var selected_lod := -1
var wind := true

func _ready() -> void:
	$PaintedOak.free()
	$FarmerReference.position = Vector3(0, 0, 3.5)
	$Camera3D.fov = 52.0
	for index in range(3):
		var tree := ([GOLDEN,GREEN,OPEN][index] as PackedScene).instantiate() as Node3D
		tree.position.x = (index-1)*4.8
		add_child(tree)
		samples.append(tree)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--lod="):
			selected_lod = clampi(argument.trim_prefix("--lod=").to_int(), -1, 2)
	_apply_sample_settings()
	super._ready()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_L:
			selected_lod = -1 if selected_lod == 2 else selected_lod + 1
			_apply_sample_settings()
		elif event.keycode == KEY_W:
			wind = not wind
			_apply_sample_settings()
	super._unhandled_input(event)

func _apply_sample_settings() -> void:
	for tree in samples:
		tree.forced_lod = selected_lod
		tree.update_lod(0.0)
		tree.set_wind_enabled(wind)
	for shrub in shrubs: shrub.free()
	shrubs.clear()
	for index in 2:
		var species: String = ["meadow_shrub","sage_shrub"][index]
		var shrub := load("res://assets/models/vegetation/tree_pack/%s_lod%d.glb" % [species,maxi(0,selected_lod)]).instantiate() as Node3D
		shrub.position = Vector3(-2.2 if index == 0 else 2.2,0,3.5)
		for mesh in shrub.find_children("*","MeshInstance3D",true,false):
			var mat := ShaderMaterial.new()
			mat.shader = preload("res://assets/models/vegetation/tree_pack/tree_wind.gdshader")
			mat.set_shader_parameter("foliage",str(mesh.name).begins_with("Leaves"))
			mat.set_shader_parameter("tree_height",1.25 if index == 0 else 1.05)
			mat.set_shader_parameter("wind_strength",.02 if wind else 0.0)
			mesh.material_override = mat
		add_child(shrub);shrubs.append(shrub)
	$CanvasLayer/Title.text = "三种阔冠树：金叶舒展 · 绿叶圆冠 · 灰绿层冠    前排：草甸灌木 · 灰绿灌木\n细节：%s    微风：%s" % ["自动" if selected_lod < 0 else "LOD%d" % selected_lod, "开" if wind else "关"]
	$CanvasLayer/Controls.text = "右键环绕 · 滚轮缩放 · 空格转台 · 1/2/3 视角 · L 切换细节 · W 微风 · R 复位 · F12 截图"
