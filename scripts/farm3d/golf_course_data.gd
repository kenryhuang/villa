class_name Farm3DGolfCourse
extends RefCounted

const BOUNDS := Rect2(-164, 56, 80, 80)
const ENTRANCE := Vector2(-124, 62)
const CUP_RADIUS := .19
const CUP_CAPTURE_SPEED := 4.5
const ROLLING_RESISTANCE := {"green":.30,"fairway":.8,"rough":2.2,"sand":4.5}
const HOLES := [
	{"name": "草甸直道", "tee": Vector2(-147.5, 74.5), "cup": Vector2(-148.5, 106.5), "par": 3},
	{"name": "沙丘弯道", "tee": Vector2(-143.5, 123.5), "cup": Vector2(-103.5, 122.5), "par": 3},
	{"name": "湖风长道", "tee": Vector2(-93.5, 118.5), "cup": Vector2(-94.5, 72.5), "par": 3},
]
const BUNKERS := [Vector3(-124, 118, 3.2), Vector3(-100, 90, 2.8)]

static func contains(point: Vector2) -> bool:
	return BOUNDS.has_point(point)

static func line_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(a + (b-a) * clampf((p-a).dot(b-a) / (b-a).length_squared(), 0, 1))

static func paint(point: Vector2) -> Color:
	if not BOUNDS.grow(5).has_point(point):
		return Color(0, 0, 0, 0)
	var edge := minf(minf(point.x-BOUNDS.position.x, BOUNDS.end.x-point.x), minf(point.y-BOUNDS.position.y, BOUNDS.end.y-point.y))
	var course := smoothstep(-4, 3, edge)
	var fairway := 0.0
	var green := 0.0
	var sand := 0.0
	for hole in HOLES:
		var d := line_distance(point, hole.tee, hole.cup)
		fairway = maxf(fairway, 1-smoothstep(4.0, 6.2, d))
		green = maxf(green, 1-smoothstep(3.7, 4.5, point.distance_to(hole.cup)))
	for bunker in BUNKERS:
		var d := ((point-Vector2(bunker.x,bunker.y)) / Vector2(1.3,.8)).length()
		sand = maxf(sand, 1-smoothstep(bunker.z-.5,bunker.z+.4,d))
	return Color(course, fairway, green, sand)

static func surface(point: Vector2) -> String:
	var mask := paint(point)
	if mask.a > .45:
		return "sand"
	if mask.b > .5:
		return "green"
	return "fairway" if mask.g > .45 else "rough"

static func terrain_height(point: Vector2) -> float:
	var height := _hill_terrain_height(point)
	# Keep the third fairway and its green intact while easing the first two.
	var third_clearance := smoothstep(6.3,9,line_distance(point,HOLES[2].tee,HOLES[2].cup))
	for i in 2:
		var hole: Dictionary = HOLES[i]
		var weight := (1-smoothstep(5,9,line_distance(point,hole.tee,hole.cup)))*third_clearance
		if weight <= 0:
			continue
		var gentle := _gentle_height(point,i)
		# A tiny level collar supports the cup, without raising a green platform.
		for anchor in [hole.tee,hole.cup]:
			gentle = lerpf(_gentle_height(anchor,i),gentle,smoothstep(.8,1.8,point.distance_to(anchor)))
		height = lerpf(height,gentle,weight)
	return height

static func _gentle_height(point: Vector2, hole: int) -> float:
	if hole == 0:
		return 1.15+.10*sin((point.y-74.5)*.13)+.03*sin((point.x+148)*.2)
	return 1.25+.05*(point.y-123)+.10*sin((point.x+130)*.10)

static func _hill_terrain_height(point: Vector2) -> float:
	var height := 1.1 + .18*sin(point.x*.095)*cos(point.y*.12)
	# Broad slopes are playable both on foot and with a rolling ball.
	height += _mound(point,Vector2(-149,88),Vector2(7,6),2.0)
	height += _mound(point,Vector2(-147,98),Vector2(6,4),-.4)
	height += _mound(point,Vector2(-126,121),Vector2(8,6),3.1)
	height += _mound(point,Vector2(-116,127),Vector2(6,5),1.1)
	height += _mound(point,Vector2(-95,96),Vector2(5,9),3.4)
	height += _mound(point,Vector2(-89,84),Vector2(5,6),1.2)
	for i in HOLES.size():
		var hole: Dictionary = HOLES[i]
		var d := point.distance_to(hole.cup)
		var slope: Vector2 = [Vector2(.022,.012),Vector2(-.014,.024),Vector2(.025,-.012)][i]
		var green: float = [1.25,1.65,1.45][i]+slope.dot(point-hole.cup)*smoothstep(.8,2.8,d)
		height = lerpf(green,height,smoothstep(3.5,7,d))
		height = lerpf(float([1.15,1.35,1.65][i]),height,smoothstep(1.8,4,point.distance_to(hole.tee)))
	for bunker in BUNKERS:
		var distance := ((point-Vector2(bunker.x,bunker.y))/Vector2(1.3,.8)).length()
		height -= (1-smoothstep(bunker.z-.7,bunker.z+1.2,distance))*.45
	return lerpf(1.2,height,smoothstep(2,5,point.distance_to(ENTRANCE)))

static func _mound(point: Vector2, center: Vector2, spread: Vector2, height: float) -> float:
	return height*exp(-((point-center)/spread).length_squared())

static func cup_for_cell(x: int, z: int) -> int:
	for i in HOLES.size():
		if Vector2(x+.5,z+.5).is_equal_approx(HOLES[i].cup):
			return i
	return -1
