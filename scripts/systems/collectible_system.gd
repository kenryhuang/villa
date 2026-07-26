class_name CollectibleSystem
extends Node

## 收集品系统 - 图鉴管理、收集状态

signal collectible_collected(collectible_id: String)
signal category_completed(category: String)

var discovered: Dictionary = {}  # collectible_id → true
var _category_stats: Dictionary = {}  # category → {total: int, found: int}
var _event_bus


func _ready() -> void:
	_event_bus = get_node_or_null("/root/EventBus")

	# 初始化分类统计
	_init_category_stats()


func _init_category_stats() -> void:
	var categories = ["diary", "fossil", "relic", "specimen"]
	for cat in categories:
		_category_stats[cat] = {
			"total": GameData.get_collectible_count_by_category(cat),
			"found": 0,
		}


func collect(collectible_id: String) -> void:
	if discovered.has(collectible_id):
		return

	var data = GameData.get_collectible(collectible_id)
	if data.is_empty():
		push_error("Unknown collectible: %s" % collectible_id)
		return

	discovered[collectible_id] = true

	# 更新分类统计
	var category = data.get("category", "")
	if _category_stats.has(category):
		_category_stats[category].found += 1
		if _category_stats[category].found >= _category_stats[category].total:
			category_completed.emit(category)

	if _event_bus:
		_event_bus.collectible_found.emit(data)

	collectible_collected.emit(collectible_id)


func is_discovered(collectible_id: String) -> bool:
	return discovered.has(collectible_id)


func get_discovered_count() -> int:
	return discovered.size()


func get_category_count(category: String) -> int:
	var count := 0
	for id in discovered:
		var data = GameData.get_collectible(id)
		if not data.is_empty() and data.get("category") == category:
			count += 1
	return count


func get_category_progress(category: String) -> Dictionary:
	return _category_stats.get(category, {"total": 0, "found": 0})


func get_total_progress() -> Dictionary:
	var total_found := discovered.size()
	var total_all := 0
	for cat in _category_stats.values():
		total_all += cat.total
	return {"found": total_found, "total": total_all}
