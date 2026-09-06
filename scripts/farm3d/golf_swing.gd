class_name Farm3DGolfSwing
extends RefCounted

## Input measured in logical pixels and seconds, independent of event frequency.
var dragging := false
var offset := Vector2.ZERO
var peak := 0.0
var started := 0.0
var peak_time := 0.0

func begin(now: float) -> void:
	dragging = true
	offset = Vector2.ZERO
	peak = 0
	started = now
	peak_time = now

func cancel() -> void:
	dragging = false

func motion(delta: Vector2, now: float) -> Dictionary:
	if not dragging or not delta.is_finite() or not is_finite(now) or now < started:
		return {}
	offset += delta.limit_length(500)
	if offset.y >= peak:
		peak = minf(offset.y, 280)
		peak_time = now
	if peak < 28 or now-peak_time < .045 or offset.y > peak*.12:
		return {}
	var speed := (peak-offset.y) / maxf(.045,now-peak_time)
	var power := clampf(peak/190, .08, 1.0) * clampf(speed/850, .25, 1.1)
	var deviation := clampf(offset.x/maxf(peak,28), -.85, .85) * .30
	dragging = false
	return {"power": clampf(power,.035,1), "deviation": deviation, "speed": speed, "backswing": peak}
