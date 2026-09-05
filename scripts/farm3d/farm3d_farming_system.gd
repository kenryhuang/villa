class_name Farm3DFarmingSystem
extends FarmingSystem

## The original FarmingSystem remains authoritative for rules.  This adapter
## suppresses its 2D/fallback scene path and forwards every visual change to
## the imported 3D crop visual owner.
var visual_adapter: Node


func _create_visual(cell: GridCell, _instance: CropInstance) -> Node3D:
	_sync_3d(cell)
	return null


func _update_visual(cell: GridCell, _instance: CropInstance) -> void:
	_sync_3d(cell)


func _remove_visual(cell: GridCell) -> void:
	_sync_3d(cell)


func _sync_3d(cell: GridCell) -> void:
	if visual_adapter != null and visual_adapter.has_method("sync_cell"):
		visual_adapter.call("sync_cell", cell)
