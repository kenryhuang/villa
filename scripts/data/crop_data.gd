class_name CropData
extends Resource

@export var crop_id := ""
@export var name := ""
@export var crop_name := ""
@export var category := ""
@export var growth_days := 3
@export var seasons: Array[int] = []
@export var seed_price := 0
@export var sell_price := 0
@export var exp_reward := 0
@export var seed_drop_chance := 0.2
@export var stage_textures: Array[String] = []
@export var stage_scenes: Array[String] = []
@export var water_required := 1
