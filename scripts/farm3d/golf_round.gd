class_name Farm3DGolfRound
extends RefCounted

const Course = preload("res://scripts/farm3d/golf_course_data.gd")
var active := false
var hole := 0
var strokes := 0
var scores: Array[int] = []
var ball := Course.HOLES[0].tee as Vector2
var best := 0

func start() -> void:
	active = true
	hole = 0
	strokes = 0
	scores.clear()
	ball = Course.HOLES[0].tee

func complete_hole() -> void:
	if not active or scores.size() != hole:
		return
	scores.append(clampi(strokes,1,12))
	ball = Course.HOLES[hole].cup
	if hole == 2:
		active = false
		var total := scores[0]+scores[1]+scores[2]
		best = total if best == 0 else mini(best,total)

func to_dict() -> Dictionary:
	return {"active":active,"hole":hole,"strokes":strokes,"scores":scores.duplicate(),"ball":{"x":ball.x,"z":ball.y},"best":best}

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 6:
		return false
	if not value.get("active") is bool or not value.get("scores") is Array or not value.get("ball") is Dictionary:
		return false
	for key in ["hole","strokes","best"]:
		if not _integer(value.get(key)):
			return false
	if value.hole < 0 or value.hole > 2 or value.strokes < 0 or value.strokes > 12 or value.best < 0 or value.best > 36 or (value.best > 0 and value.best < 3):
		return false
	for score in value.scores:
		if not _integer(score) or score < 1 or score > 12:
			return false
	if value.ball.size() != 2:
		return false
	for key in ["x","z"]:
		if typeof(value.ball.get(key)) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value.ball[key])):
			return false
	if not Course.BOUNDS.grow(3).has_point(Vector2(value.ball.x,value.ball.z)):
		return false
	if value.active:
		return value.scores.size() in [int(value.hole),int(value.hole)+1] and value.scores.size() < 3
	return (value.scores.is_empty() and value.hole == 0 and value.strokes == 0) or (value.scores.size() == 3 and value.hole == 2)

func restore(value: Dictionary) -> bool:
	if not valid(value):
		return false
	active = value.active
	hole = int(value.hole)
	strokes = int(value.strokes)
	scores.assign(value.scores)
	ball = Vector2(value.ball.x,value.ball.z)
	best = int(value.best)
	return true

static func _integer(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and floorf(value) == float(value)
