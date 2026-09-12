extends Node3D
## Static world vegetation; species follows position, independent of save/RNG state.

const SPECIES := ["elder_oak", "open_canopy", "golden_leaning", "open_pine", "tall_pine"]
const ASSET_ROOT := "res://assets/models/vegetation/illustrated_trees/"
# Approximate foliage volumes, separate from the player/navigation trunk footprint.
const CROWNS := [
	[Vector4(0, 3.8, 0, 2.1), Vector4(0, 5.1, 0, 1.5)],
	[Vector4(0, 3.9, 0, 2.15)],
	[Vector4(.35, 3.5, 0, 1.55), Vector4(.65, 4.9, 0, 1.25)],
	[Vector4(0, 2.8, 0, 1.85), Vector4(0, 4.2, 0, 1.4), Vector4(0, 5.6, 0, .85)],
	[Vector4(0, 2.9, 0, 2.05), Vector4(0, 4.5, 0, 1.7), Vector4(0, 6.0, 0, 1.25), Vector4(0, 7.3, 0, .85), Vector4(0, 8.6, 0, .4)],
]
static var _models: Dictionary = {}

@export_range(-1, 4) var species_index := -1
@export_range(-1, 2) var forced_lod := -1
var species := ""
var current_lod := -1
var lod_nodes: Array[Node3D] = []
var _elapsed := 0.0

static func species_for_position(point: Vector3) -> int:
	return ("illustrated-trees-v1:%d:%d" % [roundi(point.x * 100), roundi(point.z * 100)]).hash() % SPECIES.size()

func _ready() -> void:
	if species_index < 0: species_index = species_for_position(global_position)
	species_index = clampi(species_index, 0, SPECIES.size() - 1)
	species = SPECIES[species_index]
	add_to_group("farm_illustrated_trees")
	lod_nodes.resize(3)
	_build_collision()
	# Stagger checks; large areas should not all switch LOD on the same frame.
	_elapsed = float(species_for_position(global_position + Vector3(13, 0, 17))) * .05
	_update_from_camera()

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < .25: return
	_elapsed = 0.0
	_update_from_camera()

func _update_from_camera() -> void:
	var camera := get_viewport().get_camera_3d()
	update_lod(camera.global_position.distance_to(global_position) if camera != null else 100.0)

func update_lod(camera_distance: float) -> void:
	var d := camera_distance / maxf(.1, global_basis.get_scale().abs().x)
	var level := forced_lod
	if level < 0:
		level = current_lod if current_lod >= 0 else (0 if d < 24 else (1 if d < 55 else 2))
		if d > 58: level = 2
		elif d < 21: level = 0
		elif level == 0 and d > 27: level = 1
		elif level == 2 and d < 52: level = 1
	level = clampi(level, 0, 2)
	if level == current_lod: return
	if lod_nodes[level] == null:
		var path := ASSET_ROOT + "%s_lod%d.glb" % [species, level]
		if not _models.has(path): _models[path] = load(path) as PackedScene
		var model := (_models[path] as PackedScene).instantiate() as Node3D
		model.name = "LOD%d" % level
		add_child(model)
		lod_nodes[level] = model
	current_lod = level
	for i in 3:
		if lod_nodes[i] != null: lod_nodes[i].visible = i == level

func _build_collision() -> void:
	var trunk := StaticBody3D.new()
	trunk.name = "TrunkCollision"
	trunk.collision_layer = 1
	trunk.collision_mask = 0
	trunk.set_meta("golf_obstacle", true)
	add_child(trunk)
	var cylinder := CylinderShape3D.new()
	# Matches the existing .6 m navigation obstacle and player-clearance rules.
	cylinder.radius = .6
	cylinder.height = 2.8
	_add_shape(trunk, cylinder, Vector3(0, 1.35, 0))
	if species_index >= 3:
		var upper := CylinderShape3D.new()
		upper.radius = .19
		upper.height = 5.7 if species_index == 4 else 3.0
		_add_shape(trunk, upper, Vector3(0, 2.7 + upper.height * .5, 0))
	var crown := StaticBody3D.new()
	crown.name = "CanopyCameraCollision"
	crown.collision_layer = 4
	crown.collision_mask = 0
	crown.set_meta("golf_obstacle", true)
	add_child(crown)
	for volume: Vector4 in CROWNS[species_index]:
		var sphere := SphereShape3D.new()
		sphere.radius = volume.w
		_add_shape(crown, sphere, Vector3(volume.x, volume.y, volume.z))

func _add_shape(body: StaticBody3D, shape: Shape3D, offset: Vector3) -> void:
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = offset
	body.add_child(collider)
