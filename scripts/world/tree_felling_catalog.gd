class_name TreeFellingCatalog
extends RefCounted

const GATHER_DURATION := 2.0

const CHOPPABLE_VARIANTS := {
	"pine-small": true,
	"pine-tall": true,
	"canopy-small": true,
	"canopy-medium": true,
	"round-small": true,
}

const FELLING_ATLAS_PATHS := {
	"pine-small": "res://assets/vegetation/felling/pine-small-felling-sheet.png",
	"pine-tall": "res://assets/vegetation/felling/pine-tall-felling-sheet.png",
	"canopy-small": "res://assets/vegetation/felling/canopy-small-felling-sheet.png",
	"canopy-medium": "res://assets/vegetation/felling/canopy-medium-felling-sheet.png",
	"round-small": "res://assets/vegetation/felling/round-small-felling-sheet.png",
}


static func is_variant_choppable(variant: String) -> bool:
	return bool(CHOPPABLE_VARIANTS.get(variant, false))


static func atlas_path(variant: String) -> String:
	return str(FELLING_ATLAS_PATHS.get(variant, ""))
