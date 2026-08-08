class_name BuildingOutputDisplay
extends Node3D

signal collection_requested(item_id: String)

const PileScript := preload("res://scripts/buildings/building_output_pile.gd")
const INNER_MARGIN := 0.58
const OUTER_MARGIN := 0.98

var _footprint := Vector2i.ONE
var _building_id := ""
var _piles: Dictionary = {}


func configure(footprint: Vector2i) -> void:
	_footprint = Vector2i(maxi(footprint.x, 1), maxi(footprint.y, 1))


func configure_for_building(footprint: Vector2i, building_id: String) -> void:
	configure(footprint)
	_building_id = building_id


func sync_outputs(
	outputs: Dictionary,
	quantity_capacity: int,
	enabled: bool
) -> void:
	var item_ids := _positive_item_ids(outputs)
	var total_quantity := 0
	for item_id in item_ids:
		total_quantity += int(outputs.get(item_id, 0))
	var storage_full := quantity_capacity > 0 and total_quantity >= quantity_capacity
	for existing_value in _piles.keys():
		var existing_id := str(existing_value)
		if existing_id not in item_ids:
			_remove_pile(existing_id)
	var positions := layout_positions_for_building(
		item_ids.size(),
		_footprint,
		_building_id
	)
	for index in item_ids.size():
		var item_id := item_ids[index]
		var quantity := int(outputs.get(item_id, 0))
		var pile: Variant = _pile_for(item_id, quantity, quantity_capacity)
		if pile == null:
			continue
		pile.update_quantity(quantity, quantity if storage_full else quantity_capacity)
		pile.position = positions[index]
		pile.scale = Vector3.ONE * (
			0.75 if item_ids.size() > 4 and index >= 4 else 1.0
		)
		pile.set_interaction_enabled(enabled)
	visible = enabled and not _piles.is_empty()


static func layout_positions(count: int, footprint: Vector2i) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if count <= 0:
		return result
	var half_x := maxf(float(footprint.x) * 0.5, 0.5)
	var half_z := maxf(float(footprint.y) * 0.5, 0.5)
	var inner_x := half_x + INNER_MARGIN
	var inner_z := half_z + INNER_MARGIN
	var outer_x := half_x + OUTER_MARGIN
	var outer_z := half_z + OUTER_MARGIN
	var anchors: Array[Vector3] = [
		Vector3(inner_x, 0.0, inner_z),
		Vector3(-inner_x, 0.0, inner_z),
		Vector3(inner_x, 0.0, 0.0),
		Vector3(-inner_x, 0.0, 0.0),
		Vector3(outer_x, 0.0, outer_z),
		Vector3(-outer_x, 0.0, outer_z),
		Vector3(0.0, 0.0, outer_z + 0.22),
	]
	for index in mini(count, anchors.size()):
		result.append(anchors[index])
	for index in range(anchors.size(), count):
		var row := index - anchors.size()
		result.append(Vector3(
			(-1.0 if row % 2 == 0 else 1.0) * (outer_x + 0.35),
			0.0,
			outer_z + 0.55 + float(row / 2) * 0.34
		))
	return result


static func layout_positions_for_building(
	count: int,
	footprint: Vector2i,
	building_id: String
) -> Array[Vector3]:
	if building_id != "stone_kiln":
		return layout_positions(count, footprint)
	var result: Array[Vector3] = []
	if count <= 0:
		return result
	var half_x := maxf(float(footprint.x) * 0.5, 0.5)
	var half_z := maxf(float(footprint.y) * 0.5, 0.5)
	var adjacent_x := half_x + 0.5
	var adjacent_z := half_z + 0.5
	var anchors: Array[Vector3] = [
		Vector3(-0.5, 0.0, adjacent_z),
		Vector3(-adjacent_x, 0.0, 0.5),
		Vector3(0.5, 0.0, adjacent_z),
		Vector3(-adjacent_x, 0.0, -0.5),
		Vector3(adjacent_x, 0.0, 0.5),
		Vector3(adjacent_x, 0.0, -0.5),
	]
	for index in mini(count, anchors.size()):
		result.append(anchors[index])
	return result


func get_pile_count() -> int:
	return _piles.size()


func get_item_ids() -> Array[String]:
	var result: Array[String] = []
	for value in _piles.keys():
		result.append(str(value))
	result.sort()
	return result


func get_layout_positions() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for item_id in get_item_ids():
		var pile: Variant = get_pile(item_id)
		if pile != null:
			result.append(pile.position)
	return result


func get_pile(item_id: String) -> Variant:
	var value: Variant = _piles.get(item_id)
	return value if value != null and is_instance_valid(value) else null


func has_enabled_collisions() -> bool:
	for item_id in get_item_ids():
		var pile: Variant = get_pile(item_id)
		if pile != null and pile.collision_layer != 0:
			return true
	return false


func show_collection_failure(item_id: String, reason: String) -> void:
	var pile: Variant = get_pile(item_id)
	if pile != null:
		pile.play_failure(reason)


func clear_immediately() -> void:
	for value in _piles.values():
		var pile: Variant = value
		if pile != null and is_instance_valid(pile):
			pile.queue_free()
	_piles.clear()
	visible = false


func _positive_item_ids(outputs: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for value in outputs.keys():
		if int(outputs.get(value, 0)) > 0:
			result.append(str(value))
	result.sort()
	return result


func _pile_for(
	item_id: String,
	quantity: int,
	quantity_capacity: int
) -> Variant:
	var existing: Variant = get_pile(item_id)
	if existing != null:
		return existing
	var pile: Variant = PileScript.new()
	pile.name = "Output_%s" % item_id
	if not pile.configure(item_id, quantity, quantity_capacity):
		pile.free()
		return null
	add_child(pile)
	pile.collection_requested.connect(_on_pile_collection_requested)
	_piles[item_id] = pile
	return pile


func _remove_pile(item_id: String) -> void:
	var pile: Variant = get_pile(item_id)
	_piles.erase(item_id)
	if pile != null:
		pile.play_collected()


func _on_pile_collection_requested(item_id: String) -> void:
	collection_requested.emit(item_id)
