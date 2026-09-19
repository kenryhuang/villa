class_name Farm3DGolfSwing
extends RefCounted

## Pull distance sets power; the forward stroke commits it without a speed lottery.
const FULL_PULL := 190.0
const MIN_PULL := 12.0
const MAX_DEVIATION := .06
var dragging := false
var offset := Vector2.ZERO
var peak := 0.0
var started := 0.0
var peak_time := 0.0

## Visual timing is deterministic and never changes the shot's physical power.
static func animation_profile(strength: float, short_stroke: bool) -> Dictionary:
	var amount := clampf(strength, 0, 1)
	return {
		"backswing_angle": lerpf(.12, .75 if short_stroke else 2.6, amount),
		"followthrough": lerpf(.12, .65 if short_stroke else 2.1, amount),
		"follow_seconds": lerpf(.18, .32 if short_stroke else .48, amount),
		"hold_seconds": lerpf(.06, .14 if short_stroke else .3, amount),
		"recover_seconds": lerpf(.18, .28 if short_stroke else .4, amount),
	}

func power(short_stroke := false) -> float:
	var amount := clampf(peak/FULL_PULL,0,1)
	return pow(amount,1.35) if short_stroke else amount

func corridor() -> float:
	return 9.0+peak*.04

func deviation(lateral: float, short_stroke := false) -> float:
	var excess := maxf(0,absf(lateral)-corridor())
	return signf(lateral)*minf(MAX_DEVIATION,excess/maxf(peak,40)*.12)*(.35 if short_stroke else 1.0)

func begin(now: float) -> void:
	dragging = true
	offset = Vector2.ZERO
	peak = 0
	started = now
	peak_time = now

func cancel() -> void:
	dragging = false

func motion(delta: Vector2, now: float, short_stroke := false) -> Dictionary:
	if not dragging or not delta.is_finite() or not is_finite(now) or now < started:
		return {}
	var previous := offset
	offset += delta
	# Excess backswing cannot create invisible return travel beyond the full bar.
	offset.y = clampf(offset.y,0,FULL_PULL)
	if offset.y >= peak:
		peak = offset.y
		peak_time = now
	var contact := peak*.12
	if peak < MIN_PULL or delta.y >= 0 or previous.y <= contact or offset.y > contact:
		return {}
	# Interpolate at contact, ignoring sideways travel after the ball was hit.
	var crossing := clampf((previous.y-contact)/-delta.y,0,1)
	var lateral := previous.x+delta.x*crossing
	var speed := peak*.88 / maxf(.001,now-peak_time)
	dragging = false
	return {"power": maxf(.01,power(short_stroke)), "deviation": deviation(lateral,short_stroke), "speed": speed, "backswing": peak}
