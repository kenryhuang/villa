class_name Farm3DGolfRound
extends RefCounted

const Course = preload("res://scripts/farm3d/golf_course_data.gd")
var active := false
var hole := 0
var strokes := 0
var scores: Array[int] = []
var ball := Course.HOLES[0].tee as Vector2
var best := 0
var layout_changed := false
var gameplay_id := ""

func start() -> void:
	gameplay_id = ""
	active = true
	hole = 0
	strokes = 0
	scores.clear()
	ball = Course.HOLES[0].tee

func complete_hole() -> void:
	if not active or scores.size() != hole:
		return
	scores.append(maxi(strokes,1))
	ball = Course.HOLES[hole].cup
	if hole == Course.HOLES.size()-1:
		active = false
		var total: int = scores.reduce(func(a,b): return a+b,0)
		best = total if best == 0 else mini(best,total)

func to_dict() -> Dictionary:
	return {"gameplay_id": gameplay_id, "course_version":Course.VERSION,"active":active,"hole":hole,"strokes":strokes,"scores":scores.duplicate(),"ball":{"x":ball.x,"z":ball.y},"best":best}

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() not in [6,7,8]:
		return false
	if value.size() == 8 and not value.has("gameplay_id"): return false
	if value.has("gameplay_id") and (not value.gameplay_id is String or value.gameplay_id.length() > 80): return false
	var legacy: bool = not value.has("course_version")
	if (legacy and value.size() != 6) or (not legacy and (value.size() not in [7,8] or not _integer(value.course_version) or int(value.course_version) != Course.VERSION)): return false
	var count := 3 if legacy else Course.HOLES.size()
	if not value.get("active") is bool or not value.get("scores") is Array or not value.get("ball") is Dictionary:
		return false
	for key in ["hole","strokes","best"]:
		if not _integer(value.get(key)):
			return false
	if value.hole < 0 or value.hole >= count or value.strokes < 0 or value.best < 0 or (value.best > 0 and value.best < count):
		return false
	for score in value.scores:
		if not _integer(score) or score < 1:
			return false
	if value.ball.size() != 2:
		return false
	for key in ["x","z"]:
		if typeof(value.ball.get(key)) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value.ball[key])):
			return false
	var bounds := Rect2(-164,56,80,80) if legacy else Course.BOUNDS
	if not bounds.grow(3).has_point(Vector2(value.ball.x,value.ball.z)):
		return false
	if value.active:
		return value.scores.size() in [int(value.hole),int(value.hole)+1] and value.scores.size() < count
	return (value.scores.is_empty() and value.hole == 0 and value.strokes == 0) or (value.scores.size() == count and value.hole == count-1)

func restore(value: Dictionary) -> bool:
	if not valid(value):
		return false
	if not value.has("course_version"):
		# A changed layout cannot resume old ball positions or compare old records.
		layout_changed = bool(value.active) or int(value.best) > 0
		start()
		active = bool(value.active)
		best = 0
		return true
	gameplay_id = str(value.get("gameplay_id", ""))
	layout_changed = false
	active = value.active
	hole = int(value.hole)
	strokes = int(value.strokes)
	scores.assign(value.scores)
	ball = Vector2(value.ball.x,value.ball.z)
	best = int(value.best)
	return true

static func _integer(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and floorf(value) == float(value)
