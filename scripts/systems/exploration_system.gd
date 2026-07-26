class_name ExplorationSystem
extends Node

## 探索系统 - 迷雾揭示、区域解锁

signal area_revealed
signal region_unlocked(region_id: String)

var fog_image: Image
var fog_texture: ImageTexture

const FOG_RESOLUTION := 256
const REVEAL_RADIUS := 3.0
const REVEAL_THRESHOLD := 0.5  # 移动超过此距离才更新迷雾

var _player_ref
var _last_reveal_pos := Vector2(0, 0)
var _regions: Dictionary = {}  # region_id → {unlocked, unlock_conditions}
var _event_bus


func _ready() -> void:
	_event_bus = get_node_or_null("/root/EventBus")

	# 初始化迷雾图
	fog_image = Image.create(FOG_RESOLUTION, FOG_RESOLUTION, false, Image.FORMAT_L8)
	fog_image.fill(Color.BLACK)  # 全黑 = 未探索
	fog_texture = ImageTexture.create_from_image(fog_image)

	# 定义区域
	_setup_regions()


func _setup_regions() -> void:
	_regions = {
		"creek": {
			"unlocked": false,
			"name": "溪谷入口",
			"conditions": {"type": "resources", "wood": 50, "stone": 30},
		},
		"deep_forest": {
			"unlocked": false,
			"name": "深林",
			"conditions": {"type": "level", "level": 3, "item": "lantern"},
		},
		"mist_peak": {
			"unlocked": false,
			"name": "迷雾峰",
			"conditions": {"type": "story", "fragments": 10, "level": 5},
		},
		"secret_garden": {
			"unlocked": false,
			"name": "秘密花园",
			"conditions": {"type": "story", "fragments": 12, "relics": 6},
		},
	}


func configure(player: Node3D) -> void:
	_player_ref = player


func _process(_delta: float) -> void:
	if _player_ref == null:
		return

	var player_pos_2d = Vector2(_player_ref.global_position.x, _player_ref.global_position.z)
	if player_pos_2d.distance_to(_last_reveal_pos) > REVEAL_THRESHOLD:
		_last_reveal_pos = player_pos_2d
		reveal_area(player_pos_2d.x, player_pos_2d.y, REVEAL_RADIUS)


# ============================================================
# 迷雾揭示
# ============================================================

func reveal_area(world_x: float, world_z: float, radius: float) -> void:
	if fog_image == null:
		return

	# 世界坐标 → UV → 像素坐标
	# 世界范围: x[-18, 18], z[-14, 14]
	var uv_x = (world_x + 18.0) / 36.0
	var uv_z = (world_z + 14.0) / 28.0
	var px_cx = int(uv_x * FOG_RESOLUTION)
	var px_cz = int(uv_z * FOG_RESOLUTION)
	var px_radius = int(radius / 36.0 * FOG_RESOLUTION)

	for dz in range(-px_radius, px_radius + 1):
		for dx in range(-px_radius, px_radius + 1):
			if dx * dx + dz * dz <= px_radius * px_radius:
				var px = clampi(px_cx + dx, 0, FOG_RESOLUTION - 1)
				var py = clampi(px_cz + dz, 0, FOG_RESOLUTION - 1)
				fog_image.set_pixel(px, py, Color.WHITE)

	fog_texture.update(fog_image)
	area_revealed.emit()


func is_area_explored(world_x: float, world_z: float) -> bool:
	if fog_image == null:
		return false

	var uv_x = (world_x + 18.0) / 36.0
	var uv_z = (world_z + 14.0) / 28.0
	var px = clampi(int(uv_x * FOG_RESOLUTION), 0, FOG_RESOLUTION - 1)
	var py = clampi(int(uv_z * FOG_RESOLUTION), 0, FOG_RESOLUTION - 1)
	var color = fog_image.get_pixel(px, py)
	return color.r > 0.5


# ============================================================
# 区域解锁
# ============================================================

func is_unlocked(region_id: String) -> bool:
	var region = _regions.get(region_id)
	if region == null:
		return false
	return region.unlocked


func unlock_region(region_id: String) -> bool:
	var region = _regions.get(region_id)
	if region == null:
		return false
	if region.unlocked:
		return true

	if not _check_unlock_conditions(region):
		return false

	region.unlocked = true
	if _event_bus:
		_event_bus.region_unlocked.emit(region_id)

	return true


func _check_unlock_conditions(region: Dictionary) -> bool:
	var conditions = region.conditions
	match conditions.type:
		"resources":
			var inv = get_node_or_null("/root/InventorySystem")
			if inv == null:
				return false
			if conditions.has("wood") and not inv.has_item("wood", conditions.wood):
				return false
			if conditions.has("stone") and not inv.has_item("stone", conditions.stone):
				return false
			return true
		"level":
			var gs = get_node_or_null("/root/GameState")
			if gs == null:
				return false
			if gs.player_state.level < conditions.level:
				return false
			if conditions.has("item"):
				var inv = get_node_or_null("/root/InventorySystem")
				if inv == null or not inv.has_item(conditions.item, 1):
					return false
			return true
		"story":
			var story = get_node_or_null("/root/StorySystem")
			if story == null:
				return false
			if conditions.has("fragments") and story.collected_fragments.size() < conditions.fragments:
				return false
			if conditions.has("relics"):
				var collectible = get_node_or_null("/root/CollectibleSystem")
				if collectible == null:
					return false
				var relic_count = collectible.get_category_count("relic")
				if relic_count < conditions.relics:
					return false
			return true
	return false


func get_region_name(region_id: String) -> String:
	var region = _regions.get(region_id)
	if region:
		return region.name
	return region_id


func get_all_regions() -> Dictionary:
	return _regions
