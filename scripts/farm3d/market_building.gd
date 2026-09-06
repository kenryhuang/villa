extends Node3D

## A permanent wooden trading hall, facing south toward its public counter.
var sign: Label3D
var _session: Node

func configure(session: Node) -> void:
	_session = session
	name = "VillageMarket"
	var wood := _material("79502f")
	var trim := _material("d7b778")
	var stone := _material("9c9479")
	var green := _material("456453")
	var cream := _material("e6d7aa")
	_box("StoneFoundation", Vector3(7.7, .16, 5.7), Vector3(0, .04, 0), stone)
	_box("BackWall", Vector3(6.8, 2.7, .18), Vector3(0, 1.4, -2.15), wood, true)
	for x in [-3.25, 0.0, 3.25]:
		for z in [-2.15, 1.95]:
			_box("TimberPost", Vector3(.22, 3.05, .22), Vector3(x, 1.6, z), wood, true)
	for side in [-1.0, 1.0]:
		var roof := _box("GabledRoof", Vector3(7.5, .16, 2.85), Vector3(0, 3.45, side * 1.22), green)
		roof.rotation.x = side * deg_to_rad(20)
	_box("RoofRidge", Vector3(7.6, .18, .2), Vector3(0, 3.95, 0), trim)
	for x in [-2.0, 1.6]:
		_box("TradingCounter", Vector3(2.7, 1, .9), Vector3(x, .64, 1.4), wood, true)
		_box("CounterTop", Vector3(2.85, .13, 1.04), Vector3(x, 1.18, 1.4), trim)
	for i in 12:
		var stripe := _box("StripedAwning", Vector3(.6, .07, 1.35), Vector3(-3.3 + i * .6, 2.85, 2.0), green if i % 2 == 0 else cream)
		stripe.rotation.x = deg_to_rad(12)
		_box("AwningValance", Vector3(.6, .27, .07), Vector3(-3.3 + i * .6, 2.58, 2.65), green if i % 2 == 0 else cream)
	_box("Signboard", Vector3(2.65, .63, .12), Vector3(0, 3.35, 2.38), wood)
	sign = _label("农 庄 市 集", Vector3(0, 3.35, 2.46), 64, .006)
	_label("点击摊位 · 买入 / 卖出", Vector3(0, 2.35, 2.8), 36, .005)
	for i in 3:
		var crate_pos := Vector3(-2.7 + i * .78, 1.34, 1.4)
		_crate(crate_pos, trim)
		for j in 6:
			var fruit := SphereMesh.new()
			fruit.radius = .105
			fruit.height = .20
			_mesh(fruit, crate_pos + Vector3((j % 3 - 1) * .17, .12, (j / 3 - .5) * .17), _material("bd5939" if i == 0 else "c9ab46" if i == 1 else "6a8942"))
	for i in 3:
		var fish_mesh := SphereMesh.new()
		fish_mesh.radius = .13
		fish_mesh.height = .65
		var fish := _mesh(fish_mesh, Vector3(1.05 + i * .55, 1.34, 1.4), _material("83a9a6"))
		fish.rotation.z = PI * .5
		var tail := PrismMesh.new()
		tail.size = Vector3(.23, .11, .27)
		_mesh(tail, fish.position + Vector3(.36, 0, 0), _material("537c79"))
	for x in [-2.7, 2.7]:
		_box("StorageCrate", Vector3(1, .85, .85), Vector3(x, .58, -.8), trim, true)
		for y in [.3, .6, .9]:
			_box("CrateSlat", Vector3(1.02, .035, .88), Vector3(x, y, -.8), wood)
	# Broad pick volume includes the roof/sign as well as the counter; it is not solid.
	var pick := StaticBody3D.new()
	pick.name = "MarketPickTarget"
	pick.collision_layer = 64
	pick.collision_mask = 0
	pick.set_meta("farm_market", true)
	add_child(pick)
	_shape(pick, Vector3(7.7, 4.1, 5.7), Vector3(0, 2, 0))
	sync_position()
	session.state_loaded.connect(sync_position)

func sync_position() -> void:
	var site: Vector2 = _session.market_site
	position = Vector3(site.x, Farm3DTerrainProfile.surface_height(site.x, site.y), site.y)

func can_trade(player: Node3D) -> bool:
	var local := to_local(player.global_position)
	# Reach the front counter; walls and the rear cannot be traded through.
	return absf(local.x) <= 4.4 and local.z >= 2.0 and local.z <= 6.0 and absf(local.y) < 1.8

func _material(hex: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(hex)
	material.roughness = .85
	return material

func _mesh(mesh: Mesh, point: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = point
	add_child(instance)
	return instance

func _box(label: String, size: Vector3, point: Vector3, material: Material, solid := false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := _mesh(mesh, point, material)
	instance.name = label
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.set_meta("farm_market", true)
		instance.add_child(body)
		_shape(body, size, Vector3.ZERO)
	return instance

func _shape(body: CollisionObject3D, size: Vector3, point: Vector3) -> void:
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	collider.position = point
	body.add_child(collider)

func _label(text: String, point: Vector3, font_size: int, pixel_size: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = point
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = Color("f9e6b7")
	label.outline_modulate = Color("3c3426")
	label.no_depth_test = false
	add_child(label)
	return label

func _crate(point: Vector3, material: Material) -> void:
	_box("ProduceTray", Vector3(.7, .08, .65), point, material)
	for z in [-.3, .3]:
		_box("TrayRim", Vector3(.7, .18, .04), point + Vector3(0, .06, z), material)
	for x in [-.33, .33]:
		_box("TrayRim", Vector3(.04, .18, .65), point + Vector3(x, .06, 0), material)
