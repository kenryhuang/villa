class_name MarketPriceChart
extends Control

const LINE_COLOR := Color("#5F8755")
const POINT_COLOR := Color("#C58B35")
const GRID_COLOR := Color("#7B6758", 0.25)
const VERTICAL_PADDING := 0.10
const HOVER_RADIUS := 10.0

var history: Array[int] = []
var dates: Array[String] = []
var change_reasons: Array[String] = []
var _hover_points := PackedVector2Array()
var _hovered_index := -1


static func normalized_points(prices: Array) -> PackedVector2Array:
	var count := mini(prices.size(), 7)
	if count <= 0:
		return PackedVector2Array()
	if count == 1:
		return PackedVector2Array([Vector2(0.5, 0.5)])
	var observed: Array[int] = []
	for index in range(prices.size() - count, prices.size()):
		observed.append(int(prices[index]))
	var low: int = observed.min()
	var high: int = observed.max()
	var result := PackedVector2Array()
	for index in range(count):
		var normalized_y := 0.5
		if high != low:
			normalized_y = 1.0 - float(observed[index] - low) / float(high - low)
		result.append(Vector2(float(index) / float(count - 1), normalized_y))
	return result


func set_history(prices: Array) -> void:
	var default_dates: Array[String] = []
	var default_reasons: Array[String] = []
	for index in range(prices.size()):
		default_dates.append("第 %d 日" % (index + 1))
		default_reasons.append(_fallback_reason(prices, index))
	set_series(prices, default_dates, default_reasons)


func set_series(prices: Array, observed_dates: Array, reasons: Array) -> void:
	history.clear()
	dates.clear()
	change_reasons.clear()
	var start := maxi(0, prices.size() - 7)
	for index in range(start, prices.size()):
		history.append(int(prices[index]))
		dates.append(
			str(observed_dates[index])
			if index < observed_dates.size()
			else "第 %d 日" % (index + 1)
		)
		change_reasons.append(
			str(reasons[index])
			if index < reasons.size() and not str(reasons[index]).is_empty()
			else _fallback_reason(prices, index)
		)
	_hovered_index = -1
	tooltip_text = ""
	queue_redraw()


func _draw() -> void:
	var normalized := normalized_points(history)
	_hover_points = PackedVector2Array()
	if normalized.is_empty():
		return
	var chart_rect := Rect2(
		Vector2(8.0, size.y * VERTICAL_PADDING),
		Vector2(maxf(0.0, size.x - 16.0), size.y * (1.0 - VERTICAL_PADDING * 2.0))
	)
	draw_line(
		Vector2(chart_rect.position.x, chart_rect.end.y),
		chart_rect.end,
		GRID_COLOR,
		1.0
	)
	for point in normalized:
		_hover_points.append(chart_rect.position + point * chart_rect.size)
	if _hover_points.size() == 1:
		draw_circle(_hover_points[0], 4.0, POINT_COLOR)
	else:
		for index in range(1, _hover_points.size()):
			var width := 4.0 if index == _hover_points.size() - 1 else 2.0
			draw_line(_hover_points[index - 1], _hover_points[index], LINE_COLOR, width, true)
	for index in range(_hover_points.size()):
		var radius := 6.0 if index == _hovered_index else 3.5
		draw_circle(_hover_points[index], radius, POINT_COLOR)


func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseMotion:
		return
	var nearest := -1
	var nearest_distance := HOVER_RADIUS
	for index in range(_hover_points.size()):
		var distance: float = event.position.distance_to(_hover_points[index])
		if distance <= nearest_distance:
			nearest = index
			nearest_distance = distance
	if nearest == _hovered_index:
		return
	_hovered_index = nearest
	tooltip_text = (
		"%s　价格 %d　主要变化：%s" % [
			dates[nearest],
			history[nearest],
			change_reasons[nearest],
		]
		if nearest >= 0 and nearest < history.size()
		else ""
	)
	queue_redraw()


static func _fallback_reason(prices: Array, index: int) -> String:
	if index <= 0 or index >= prices.size():
		return "历史起点"
	var previous := int(prices[index - 1])
	var current := int(prices[index])
	if current > previous:
		return "价格上涨"
	if current < previous:
		return "价格下跌"
	return "供需稳定"
