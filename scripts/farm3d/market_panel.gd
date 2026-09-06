extends "res://scripts/ui/market_panel.gd"

const Icons = preload("res://scripts/farm3d/target_catalog.gd")

func _item_icon_info(definition: Dictionary) -> Dictionary:
	var texture := Icons.item_icon(str(definition.get("id", "")))
	if texture != null:
		return {"texture": texture, "fallback": false}
	# A neutral goods crate replaces the original debug checkerboard texture.
	return {"texture": preload("res://assets/ui/material_icons/goods.svg"), "fallback": true}
