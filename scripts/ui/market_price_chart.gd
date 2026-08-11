class_name MarketPriceChart
extends Control

const LINE_COLOR := Color("#5F8755")
const POINT_COLOR := Color("#C58B35")
const AREA_COLOR := Color(0.372549, 0.529412, 0.333333, 0.12)
const GRID_COLOR := Color("#7B6758", 0.25)
const EMPTY_TEXT_COLOR := Color("#7B6758", 0.72)
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


static func empty_state_text(values: Array) -> String:
	return "历史积累中" if values.is_empty() else ""


static func smooth_points(anchors: PackedVector2Array) -> PackedVector2Array:
	if anchors.size() <= 1:
		return anchors
	var curve := Curve2D.new()
	for index in range(anchors.size()):
		var point := anchors[index]
		var previous := anchors[maxi(0, index - 1)]
		var following := anchors[mini(anchors.size() - 1, index + 1)]
		var tangent := (following - previous) * 0.18
		curve.add_point(point, -tangent, tangent)
	var baked := curve.tessellate(5, 2.0)
	if not baked.is_empty():
		baked[0] = anchors[0]
		baked[-1] = anchors[-1]
	return baked


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
	var chart_rect := Rect2(
		Vector2(8.0, size.y * VERTICAL_PADDING),
		Vector2(maxf(0.0, size.x - 16.0), size.y * (1.0 - VERTICAL_PADDING * 2.0))
	)
	var normalized := normalized_points(history)
	_hover_points = PackedVector2Array()
	if normalized.is_empty():
		var message := empty_state_text(history)
		var font := get_theme_default_font()
		var font_size := get_theme_default_font_size()
		draw_string(
			font,
			Vector2(chart_rect.position.x, chart_rect.get_center().y + float(font_size) * 0.35),
			message,
			HORIZONTAL_ALIGNMENT_CENTER,
			chart_rect.size.x,
			font_size,
			EMPTY_TEXT_COLOR
		)
		return
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
		var smooth := smooth_points(_hover_points)
		for index in range(smooth.size()):
			smooth[index].y = clampf(smooth[index].y, chart_rect.position.y, chart_rect.end.y)
		var area := smooth.duplicate()
		area.append(Vector2(smooth[-1].x, chart_rect.end.y))
		area.append(Vector2(smooth[0].x, chart_rect.end.y))
		draw_colored_polygon(area, AREA_COLOR)
		draw_polyline(smooth, LINE_COLOR, 2.0, true)
	for index in range(_hover_points.size()):
		if index != _hovered_index and index != _hover_points.size() - 1:
			continue
		var radius := 6.0 if index == _hovered_index else 4.0
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
