extends Node3D

const ProjectileScene = preload("res://scenes/combat/projectile.tscn")

@onready var world = $World
@onready var player = $Actors/Player
@onready var npcs: Node3D = $Actors/Npcs
@onready var projectiles: Node3D = $Projectiles
@onready var camera_rig = $CameraRig
@onready var hud = $HUD

var active_npc_count := 0

func _ready() -> void:
	_place_on_terrain(player, Vector2(0.0, 0.0))
	player.configure(camera_rig, world)
	player.fire_requested.connect(_on_fire_requested)
	player.health_changed.connect(_on_player_health_changed)
	camera_rig.set_target(player)
	var spawn_points := [Vector2(-3.2, -2.0), Vector2(3.0, -3.2), Vector2(4.0, 2.4)]
	active_npc_count = npcs.get_child_count()
	for index in npcs.get_child_count():
		var npc = npcs.get_child(index)
		_place_on_terrain(npc, spawn_points[index])
		npc.configure(player)
		npc.defeated.connect(_on_npc_defeated)
	hud.set_health(player.health)
	hud.set_npc_count(active_npc_count)
	hud.set_projectile_count(0)
	hud.set_state("探索中")

func _process(_delta: float) -> void:
	hud.set_projectile_count(projectiles.get_child_count())

func _place_on_terrain(actor: Node3D, point: Vector2) -> void:
	actor.global_position = Vector3(point.x, world.get_height_at(point.x, point.y) + 1.0, point.y)

func _on_fire_requested(origin: Vector3, direction: Vector3) -> void:
	var projectile = ProjectileScene.instantiate()
	projectiles.add_child(projectile)
	projectile.configure(origin, direction)

func _on_player_health_changed(value: int) -> void:
	hud.set_health(value)
	if value == 0:
		hud.set_state("倒下了")

func _on_npc_defeated(_npc: Node) -> void:
	active_npc_count = maxi(0, active_npc_count - 1)
	hud.set_npc_count(active_npc_count)
	if active_npc_count == 0:
		hud.set_state("山谷安全")
