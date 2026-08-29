class_name NpcFarmActionVisual
extends Node3D

signal finished

const DURATION := 1.0
const HOE_TEXTURE := preload("res://assets/ui/action_icons/hoe.png")
const BASKET_TEXTURE := preload("res://assets/ui/action_icons/harvest_basket.svg")
const ICON_WORLD_HEIGHTS := {
	"till": 0.38,
	"plant": 0.42,
	"harvest": 0.32,
}
const ICON_MOTION := {
	"till": {"start": Vector3(0.18, 1.08, 0.0), "finish": Vector3(0.28, 0.62, 0.0)},
	"plant": {"start": Vector3(0.16, 0.78, 0.0), "finish": Vector3(0.18, 0.30, 0.0)},
	"harvest": {"start": Vector3(0.18, 0.52, 0.0), "finish": Vector3(0.20, 0.96, 0.0)},
}

var _icon: Sprite3D
var _particles: CPUParticles3D
var _tween: Tween
var _playing := false


func _ready() -> void:
	_icon = Sprite3D.new()
	_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_icon.no_depth_test = true
	_icon.shaded = false
	_icon.pixel_size = 0.001
	_icon.position = Vector3(0.0, 1.75, 0.0)
	_icon.visible = false
	add_child(_icon)
	_particles = CPUParticles3D.new()
	_particles.amount = 8
	_particles.lifetime = 0.6
	_particles.one_shot = true
	_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_particles.emission_sphere_radius = 0.18
	_particles.initial_velocity_min = 0.35
	_particles.initial_velocity_max = 0.75
	_particles.gravity = Vector3(0.0, -1.2, 0.0)
	_particles.scale_amount_min = 0.035
	_particles.scale_amount_max = 0.07
	add_child(_particles)


func play(action_name: String, item_texture: Texture2D = null) -> bool:
	if _playing or action_name not in ["till", "plant", "harvest"]:
		return false
	_playing = true
	_icon.texture = (
		item_texture
		if item_texture != null
		else BASKET_TEXTURE if action_name == "harvest" else HOE_TEXTURE
	)
	if _icon.texture == null or _icon.texture.get_height() <= 0:
		_playing = false
		return false
	var motion: Dictionary = ICON_MOTION[action_name]
	_icon.pixel_size = float(ICON_WORLD_HEIGHTS[action_name]) / float(_icon.texture.get_height())
	_icon.position = motion.start
	_icon.scale = Vector3.ONE * 0.82
	_icon.modulate.a = 0.0
	_icon.visible = true
	_particles.emitting = true
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_icon, "position", motion.finish, DURATION * 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_icon, "scale", Vector3.ONE, DURATION * 0.35)
	_tween.tween_property(_icon, "modulate:a", 1.0, DURATION * 0.2)
	_tween.chain().tween_property(_icon, "modulate:a", 0.0, DURATION * 0.35)
	_tween.finished.connect(_finish, CONNECT_ONE_SHOT)
	return true


func cancel() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_finish()


func is_playing() -> bool:
	return _playing


func _finish() -> void:
	var was_playing := _playing
	_playing = false
	if _icon != null:
		_icon.visible = false
	if was_playing:
		finished.emit()
