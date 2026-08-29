class_name FishingSpot
extends Area3D

signal interaction_requested(spot: Node, player: Variant)

var _spot_data: Resource


func _ready() -> void:
	add_to_group("fishing_spot")


func configure(data: Resource) -> bool:
	if data == null or not data.has_method("is_valid") or not bool(data.call("is_valid")):
		return false
	_spot_data = data.call("duplicate_data") as Resource
	name = str(_spot_data.get("spot_id"))
	set_meta("spot_id", str(_spot_data.get("spot_id")))
	return true


func get_spot_data() -> Resource:
	return _spot_data.call("duplicate_data") as Resource if _spot_data != null else null


func interact(player: Variant = null) -> bool:
	if _spot_data == null:
		return false
	interaction_requested.emit(self, player)
	return true


func get_interaction_radius() -> float:
	return 0.65
