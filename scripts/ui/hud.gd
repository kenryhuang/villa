class_name VillaHud
extends CanvasLayer

@onready var health_label: Label = $TopLeft/Panel/Margin/Rows/Health
@onready var state_label: Label = $TopLeft/Panel/Margin/Rows/State
@onready var npc_label: Label = $TopLeft/Panel/Margin/Rows/Npcs
@onready var projectile_label: Label = $TopLeft/Panel/Margin/Rows/Projectiles

func set_health(value: int) -> void:
	health_label.text = "生命  %d / 5" % value

func set_state(value: String) -> void:
	state_label.text = "状态  %s" % value

func set_npc_count(value: int) -> void:
	npc_label.text = "入侵者  %d" % value

func set_projectile_count(value: int) -> void:
	projectile_label.text = "场上弹丸  %d" % value
