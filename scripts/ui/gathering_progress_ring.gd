class_name GatheringProgressRing
extends Control

@export_range(0.0, 1.0) var progress := 0.0
@export var background_color := Color(0.08, 0.07, 0.05, 0.42)
@export var sweep_color := Color(0.95, 0.78, 0.35, 0.78)


func set_progress(value: float) -> void:
	progress = clampf(value, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := maxf(1.0, minf(size.x, size.y) * 0.44)
	draw_circle(center, radius, background_color)
	if progress > 0.0:
		var segments := maxi(2, ceili(40.0 * progress))
		var points := PackedVector2Array([center])
		for index in range(segments + 1):
			var angle := -PI * 0.5 + TAU * progress * float(index) / float(segments)
			points.append(center + Vector2(cos(angle), sin(angle)) * radius)
		draw_colored_polygon(points, sweep_color)
	draw_arc(center, radius, 0.0, TAU, 48, Color(1.0, 0.94, 0.76, 0.72), 2.0, true)
