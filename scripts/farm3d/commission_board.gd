extends Node3D

var session: Node

func configure(farm: Node) -> void:
	session = farm
	name = "CommissionBoard"
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("715335")
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color("eee0b6")
	for x in [-.65, .65]: _box(Vector3(.12, 2.2, .12), Vector3(x, 1.1, 0), wood)
	_box(Vector3(1.6, 1.1, .12), Vector3(0, 1.55, 0), wood)
	for x in [-.45, 0, .45]: _box(Vector3(.34, .52, .02), Vector3(x, 1.5, .08), paper)
	var roof := _box(Vector3(1.85, .12, .65), Vector3(0, 2.2, 0), wood)
	roof.rotation.x = -.12
	var label := Label3D.new()
	label.text = "村 庄 委 托\n点击查看 / 接单 / 发布"
	label.font_size = 34
	label.pixel_size = .005
	label.position = Vector3(0, 2.55, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	var body := StaticBody3D.new()
	body.collision_layer = 256
	body.collision_mask = 0
	body.set_meta("commission_board", true)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.85, 2.8, .65)
	collision.shape = box
	collision.position.y = 1.4
	body.add_child(collision)
	add_child(body)
	sync_position()
	session.state_loaded.connect(sync_position)

func sync_position() -> void:
	var site: Vector2 = session.market_site + Vector2(3.1, 2.8)
	position = Vector3(site.x, Farm3DTerrainProfile.surface_height(site.x, site.y), site.y)

func _box(size: Vector3, point: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = point
	add_child(mesh)
	return mesh
