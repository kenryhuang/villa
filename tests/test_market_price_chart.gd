extends RefCounted

const CHART_SCRIPT_PATH := "res://scripts/ui/market_price_chart.gd"


func run(assertions: TestAssert) -> void:
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
