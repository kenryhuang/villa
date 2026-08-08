extends RefCounted

const CHART_SCRIPT_PATH := "res://scripts/ui/market_price_chart.gd"


func run(assertions: TestAssert, tree: SceneTree) -> void:
	assertions.truthy(ResourceLoader.exists(CHART_SCRIPT_PATH), "market price chart script exists")
	if not ResourceLoader.exists(CHART_SCRIPT_PATH):
		return
	var chart_script: Script = load(CHART_SCRIPT_PATH)
	assertions.equal(
		chart_script.call("normalized_points", []),
		PackedVector2Array(),
		"empty history renders no points"
	)
	assertions.equal(
		chart_script.call("normalized_points", [10]),
		PackedVector2Array([Vector2(0.5, 0.5)]),
		"one price renders at chart center"
	)
	var flat: PackedVector2Array = chart_script.call("normalized_points", [10, 10, 10])
	assertions.equal(flat.size(), 3, "flat history keeps every observed day")
	assertions.equal(flat[0].x, 0.0, "flat history starts at left edge")
	assertions.near(flat[0].y, 0.5, 0.001, "flat history uses centered y")
	assertions.equal(flat[2].x, 1.0, "flat history ends at right edge")
	var trend: PackedVector2Array = chart_script.call("normalized_points", [10, 15, 20])
	assertions.equal(trend[0], Vector2(0.0, 1.0), "lowest first price maps bottom-left")
	assertions.equal(trend[2], Vector2(1.0, 0.0), "highest latest price maps top-right")
	var seven: PackedVector2Array = chart_script.call(
		"normalized_points", [16, 15, 14, 13, 12, 11, 10]
	)
	assertions.equal(seven.size(), 7, "seven integer prices keep exactly seven points")
	assertions.near(seven[3].x, 0.5, 0.001, "seven-day history spaces observations evenly")
	assertions.equal(seven[0].y, 0.0, "descending high starts at chart top")
	assertions.equal(seven[6].y, 1.0, "descending low ends at chart bottom")
	assertions.truthy(chart_script.has_method("smooth_points"), "chart exposes deterministic smoothing")
	if not chart_script.has_method("smooth_points"):
		return
	var anchors := PackedVector2Array([
		Vector2(0.0, 1.0),
		Vector2(0.5, 0.25),
		Vector2(1.0, 0.0),
	])
	var smooth: PackedVector2Array = chart_script.call("smooth_points", anchors)
	assertions.truthy(smooth.size() > anchors.size(), "curve adds intermediate points")
	assertions.equal(smooth[0], anchors[0], "smooth curve preserves first observation")
	assertions.equal(smooth[-1], anchors[-1], "smooth curve preserves latest observation")
	assertions.equal(
		chart_script.call(
			"smooth_points",
			PackedVector2Array([Vector2(0.5, 0.5)])
		),
		PackedVector2Array([Vector2(0.5, 0.5)]),
		"single observation stays a point"
	)
	await _test_drawn_hover_context(assertions, tree, chart_script)


func _test_drawn_hover_context(
	assertions: TestAssert,
	tree: SceneTree,
	chart_script: Script
) -> void:
	var chart := chart_script.new() as Control
	chart.size = Vector2(320.0, 180.0)
	tree.root.add_child(chart)
	assertions.truthy(chart.has_method("set_series"), "chart accepts dated history and change reasons")
	if not chart.has_method("set_series"):
		chart.free()
		return
	chart.call(
		"set_series",
		[10, 12, 11],
		["春 1", "春 2", "春 3"],
		["历史起点", "库存偏紧", "供给高于需求"]
	)
	await tree.process_frame
	await tree.process_frame
	var hover_points: PackedVector2Array = chart.get("_hover_points")
	assertions.equal(hover_points.size(), 3, "real chart draw registers one hover point per observation")
	if hover_points.size() == 3:
		var motion := InputEventMouseMotion.new()
		motion.position = hover_points[1]
		chart.call("_gui_input", motion)
		assertions.truthy(chart.tooltip_text.contains("春 2"), "hover shows the observed game date")
		assertions.truthy(chart.tooltip_text.contains("价格 12"), "hover shows the observed price")
		assertions.truthy(chart.tooltip_text.contains("主要变化：库存偏紧"), "hover shows the principal change reason")
	chart.free()
