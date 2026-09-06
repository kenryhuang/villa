class_name Farm3DGolfCourse
extends RefCounted

const BOUNDS := Rect2(-164, 56, 80, 80)
const ENTRANCE := Vector2(-124, 62)
const CUP_RADIUS := .19
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
	var height := 1.1 + .18*sin(point.x*.095)*cos(point.y*.12)
	height += .8*exp(-point.distance_squared_to(Vector2(-125,121))/90.0)
	height += .45*exp(-point.distance_squared_to(Vector2(-96,96))/120.0)
	for hole in HOLES:
		var d := point.distance_to(hole.cup)
		var flat: float = 1.12 + .009*(point.x-hole.cup.x) + .006*(point.y-hole.cup.y)
		height = lerpf(flat,height,smoothstep(3.5,7,d))
	return height - paint(point).a * .32

static func cup_for_cell(x: int, z: int) -> int:
	for i in HOLES.size():
		if Vector2(x+.5,z+.5).is_equal_approx(HOLES[i].cup):
			return i
	return -1
