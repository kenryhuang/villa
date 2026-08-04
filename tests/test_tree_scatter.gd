extends RefCounted

const RoadMath = preload("res://scripts/world/road_math.gd")
const TreeScatter = preload("res://scripts/world/tree_scatter.gd")
const TreeFellingCatalogScript = preload("res://scripts/world/tree_felling_catalog.gd")

func run(assertions) -> void:
	var route := _route()
	var first := TreeScatter.generate(route)
	var second := TreeScatter.generate(route)
	assertions.equal(first, second, "same seed produces identical trees")
	assertions.equal(first.size(), 40, "tree scatter includes decorative trees and resource forest")
	var gatherable_count := 0
	var gatherable_outside_resource_forest := 0
	for tree in first:
		var expected_gatherable := TreeFellingCatalogScript.is_variant_choppable(str(tree.variant))
		assertions.equal(
			bool(tree.get("gatherable", false)),
			expected_gatherable,
			"tree eligibility follows its variant for %s" % tree.id
		)
		if bool(tree.get("gatherable", false)):
			gatherable_count += 1
			if not str(tree.id).begins_with("tree-resource-"):
				gatherable_outside_resource_forest += 1
		assertions.truthy(Vector2(tree.x, tree.z).length() >= 2.35, "tree clears player spawn")
		assertions.truthy(RoadMath.distance_to_route(Vector2(tree.x, tree.z), tree.clearance, route) >= 0.45, "tree clears road")
	assertions.truthy(gatherable_count > 12, "eligible authored and scattered trees are gatherable")
	assertions.truthy(gatherable_outside_resource_forest > 0, "gatherability applies outside the resource forest")
	for index in first.size():
		for other_index in range(index + 1, first.size()):
			var a: Dictionary = first[index]
			var b: Dictionary = first[other_index]
			var required: float = maxf(a.clearance, b.clearance)
			assertions.truthy(Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)) >= required, "trees keep mutual clearance")

func _route() -> Array[Dictionary]:
	return [
		{"x": -17.2, "z": -10.5, "width": 2.3},
		{"x": -12.0, "z": -8.1, "width": 2.45},
		{"x": -8.0, "z": -6.4, "width": 2.35},
		{"x": -3.0, "z": -5.2, "width": 2.55},
		{"x": 0.0, "z": -1.2, "width": 2.7},
		{"x": 4.0, "z": -0.4, "width": 2.5},
		{"x": 8.0, "z": 0.0, "width": 2.25},
		{"x": 12.0, "z": 4.5, "width": 2.4},
		{"x": 17.2, "z": 8.8, "width": 2.3},
	]
