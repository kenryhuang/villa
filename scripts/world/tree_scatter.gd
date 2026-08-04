class_name TreeScatter
extends RefCounted

const RoadMathScript = preload("res://scripts/world/road_math.gd")
const TreeFellingCatalogScript = preload("res://scripts/world/tree_felling_catalog.gd")

const DIMENSIONS := {
	"canopy-medium": {"width": 1.75, "height": 1.9, "clearance": 1.05},
	"canopy-small": {"width": 1.15, "height": 1.35, "clearance": 0.78},
	"fruit": {"width": 1.55, "height": 1.8, "clearance": 0.95},
	"oak-large": {"width": 2.35, "height": 2.5, "clearance": 1.1},
	"pine-large": {"width": 1.7, "height": 2.55, "clearance": 1.05},
	"pine-small": {"width": 1.05, "height": 1.45, "clearance": 0.75},
	"pine-tall": {"width": 1.5, "height": 2.75, "clearance": 0.95},
	"round-medium": {"width": 1.65, "height": 1.9, "clearance": 0.95},
	"round-small": {"width": 1.18, "height": 1.4, "clearance": 0.75},
	"yellow": {"width": 1.7, "height": 1.95, "clearance": 1.0},
}

const WEIGHTED_VARIANTS := [
	"canopy-small", "pine-small", "round-small", "canopy-medium",
	"round-medium", "pine-tall", "fruit", "oak-large", "pine-large", "yellow",
	"canopy-small", "pine-small", "round-small", "canopy-small", "pine-small", "round-small",
]

const AUTHORED := [
	{"id": "authored-oak-large", "variant": "oak-large", "x": -5.8, "z": -2.9, "width": 2.35, "height": 2.5, "yaw_offset": 0.0, "lean": 0.0, "clearance": 1.1},
	{"id": "authored-pine-small", "variant": "pine-small", "x": 5.9, "z": 3.4, "width": 1.05, "height": 1.45, "yaw_offset": 0.0, "lean": 0.0, "clearance": 0.75},
	{"id": "authored-round-small", "variant": "round-small", "x": 7.2, "z": -2.7, "width": 1.18, "height": 1.4, "yaw_offset": 0.0, "lean": 0.0, "clearance": 0.75},
]

const RESOURCE_FOREST := [
	{"id": "tree-resource-00", "variant": "pine-small", "x": 8.6, "z": -10.7},
	{"id": "tree-resource-01", "variant": "canopy-medium", "x": 10.8, "z": -10.7},
	{"id": "tree-resource-02", "variant": "round-small", "x": 13.0, "z": -10.7},
	{"id": "tree-resource-03", "variant": "pine-tall", "x": 15.2, "z": -10.7},
	{"id": "tree-resource-04", "variant": "round-medium", "x": 8.6, "z": -8.4},
	{"id": "tree-resource-05", "variant": "pine-small", "x": 10.8, "z": -8.4},
	{"id": "tree-resource-06", "variant": "canopy-small", "x": 13.0, "z": -8.4},
	{"id": "tree-resource-07", "variant": "fruit", "x": 15.2, "z": -8.4},
	{"id": "tree-resource-08", "variant": "canopy-small", "x": 8.6, "z": -6.1},
	{"id": "tree-resource-09", "variant": "pine-tall", "x": 10.8, "z": -6.1},
	{"id": "tree-resource-10", "variant": "round-small", "x": 13.0, "z": -6.1},
	{"id": "tree-resource-11", "variant": "pine-small", "x": 15.2, "z": -6.1},
]

static func generate(route: Array[Dictionary], seed: int = 0x4b4f4455) -> Array[Dictionary]:
	if route.size() < 2:
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var placements: Array[Dictionary] = []
	for resource_tree in RESOURCE_FOREST:
		var placement: Dictionary = _complete_tree_definition(resource_tree)
		placement["gatherable"] = TreeFellingCatalogScript.is_variant_choppable(str(placement.variant))
		placements.append(placement)
	for authored in AUTHORED:
		var placement: Dictionary = authored.duplicate()
		placement["gatherable"] = TreeFellingCatalogScript.is_variant_choppable(str(placement.variant))
		placements.append(placement)
	var attempts := 0
	var target_count := RESOURCE_FOREST.size() + 28
	while placements.size() < target_count and attempts < 4000:
		var generated_index := placements.size() - RESOURCE_FOREST.size() - AUTHORED.size()
		var variant: String = WEIGHTED_VARIANTS[generated_index % WEIGHTED_VARIANTS.size()]
		var dimensions: Dictionary = DIMENSIONS[variant]
		var scale := 0.88 + rng.randf() * 0.24
		var candidate := {
			"id": "scatter-%02d" % generated_index,
			"variant": variant,
			"x": -15.7 + rng.randf() * 31.4,
			"z": -11.7 + rng.randf() * 23.4,
			"width": float(dimensions.width) * scale,
			"height": float(dimensions.height) * scale,
			"yaw_offset": (rng.randf() - 0.5) * 0.14,
			"lean": (rng.randf() - 0.5) * 0.055,
			"clearance": float(dimensions.clearance) * scale,
			"gatherable": TreeFellingCatalogScript.is_variant_choppable(variant),
		}
		attempts += 1
		if Vector2(candidate.x, candidate.z).length() < 2.35:
			continue
		if RoadMathScript.distance_to_route(Vector2(candidate.x, candidate.z), candidate.clearance, route) < 0.45:
			continue
		if not _has_clearance(candidate, placements):
			continue
		placements.append(candidate)
	return placements


static func _complete_tree_definition(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	var dimensions: Dictionary = DIMENSIONS[str(result.variant)]
	result["width"] = float(dimensions.width)
	result["height"] = float(dimensions.height)
	result["clearance"] = float(dimensions.clearance)
	result["yaw_offset"] = 0.0
	result["lean"] = 0.0
	return result

static func _has_clearance(candidate: Dictionary, placements: Array[Dictionary]) -> bool:
	var candidate_position := Vector2(float(candidate.x), float(candidate.z))
	for tree in placements:
		var required := maxf(float(candidate.clearance), float(tree.clearance))
		if candidate_position.distance_to(Vector2(float(tree.x), float(tree.z))) < required:
			return false
	return true
