class_name Farm3DGolfCourse
extends RefCounted

const VERSION := 2
const BOUNDS := Rect2(-164, -72, 80, 208)
const ENTRANCE := Vector2(-109, 62)
const CUP_RADIUS := .19
const ROLLING_RESISTANCE := {"green":.30,"fairway":.8,"rough":2.2,"sand":4.5}
const HOLES := [
	{"name":"草甸斜线", "tee":Vector2(-147.5,74.5), "cup":Vector2(-135.5,104.5), "par":3, "path":[Vector2(-144,90)], "tee_h":1.15, "green_h":1.25, "slope":Vector2(.015,.012), "hint":"平缓入门，先练习直球与力度"},
	{"name":"池畔右弯", "tee":Vector2(-128.5,119.5), "cup":Vector2(-100.5,92.5), "par":4, "path":[Vector2(-108,120),Vector2(-99,109)], "tee_h":1.35, "green_h":1.65, "slope":Vector2(.015,.05), "hint":"水塘挡住直线，沿东岸分杆或挑高右曲"},
	{"name":"橡林盲弯", "tee":Vector2(-97.5,78.5), "cup":Vector2(-142.5,46.5), "par":4, "path":[Vector2(-116,84),Vector2(-145,70)], "tee_h":1.65, "green_h":1.45, "slope":Vector2(.025,-.012), "hint":"树冠遮挡旗位，用弧线绕林或走南侧球道"},
	{"name":"山脊侧坡", "tee":Vector2(-151.5,34.5), "cup":Vector2(-117.5,10.5), "par":4, "path":[Vector2(-140,17),Vector2(-128,9)], "tee_h":2.0, "green_h":2.4, "slope":Vector2(-.03,.035), "hint":"横坡会把落地球带向低处，留出回滚余量"},
	{"name":"双湾左曲", "tee":Vector2(-102.5,4.5), "cup":Vector2(-145.5,-23.5), "par":4, "path":[Vector2(-115,-13),Vector2(-129,-26)], "tee_h":1.8, "green_h":1.3, "slope":Vector2(.025,.015), "hint":"两湾夹住落点，左曲切角或沿南岸推进"},
	{"name":"北林穿隙", "tee":Vector2(-149.5,-38.5), "cup":Vector2(-111.5,-61.5), "par":4, "path":[Vector2(-148,-58),Vector2(-130,-66)], "tee_h":1.4, "green_h":1.6, "slope":Vector2(-.02,.02), "hint":"直线穿过高树，沿林缘绕弯寻找进攻角度"},
	{"name":"归途长谷", "tee":Vector2(-96.5,-54.5), "cup":Vector2(-97.5,35.5), "par":5, "path":[Vector2(-111,-32),Vector2(-94,-8),Vector2(-104,15)], "tee_h":2.3, "green_h":1.5, "slope":Vector2(.02,-.02), "hint":"长谷需分段推进，越过山脊再攻最后果岭"},
]
const BUNKERS := [Vector3(-124,118,3.2),Vector3(-101,101,2.8),Vector3(-139,63,3.0),Vector3(-128,16,3.0),Vector3(-144,-13,2.7),Vector3(-118,-57,2.4),Vector3(-98,19,2.7)]
# Elliptical water basins: center, half-size. All share the landscape water level.
const PONDS := [
	{"center":Vector2(-118,104),"radii":Vector2(7,6)},
	{"center":Vector2(-125,-3),"radii":Vector2(7,5)},
	{"center":Vector2(-134,-39),"radii":Vector2(5,4)},
	{"center":Vector2(-94,-24),"radii":Vector2(4,6)},
]
# Explicit obstacles use the same scaled oak trunk and crown shapes as their art.
const TREES := [Vector3(-120,63,1.6),Vector3(-124,65,1.6),Vector3(-121,68,1.5),Vector3(-133,23,1.1),Vector3(-129,-49,1.6),Vector3(-133,-48,1.5),Vector3(-131,-53,1.4),Vector3(-105,-3,1.1),Vector3(-159,64,.8),Vector3(-159,111,.8),Vector3(-87,129,.7),Vector3(-157,-18,.9)]
static var _height_cache: Dictionary = {}

static func total_par() -> int:
	var total := 0
	for hole in HOLES: total += int(hole.par)
	return total

static func contains(point: Vector2) -> bool:
	return BOUNDS.has_point(point)

static func line_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(a+(b-a)*clampf((p-a).dot(b-a)/maxf(.001,(b-a).length_squared()),0,1))

static func route(hole: Dictionary) -> Array:
	return [hole.tee]+hole.path+[hole.cup]

static func route_distance(point: Vector2, hole: Dictionary) -> float:
	var points := route(hole)
	var distance := INF
	for i in points.size()-1: distance = minf(distance,line_distance(point,points[i],points[i+1]))
	return distance

static func paint(point: Vector2) -> Color:
	if not BOUNDS.grow(5).has_point(point): return Color(0,0,0,0)
	var fairway := 0.0
	var green := 0.0
	var sand := 0.0
	for hole in HOLES:
		fairway = maxf(fairway,1-smoothstep(3.7,5.8,route_distance(point,hole)))
		green = maxf(green,1-smoothstep(3.7,4.5,point.distance_to(hole.cup)))
	for bunker in BUNKERS:
		var d := ((point-Vector2(bunker.x,bunker.y))/Vector2(1.3,.8)).length()
		sand = maxf(sand,1-smoothstep(bunker.z-.5,bunker.z+.4,d))
	return Color(coverage(point),fairway,green,sand)

static func coverage(point: Vector2) -> float:
	var edge := minf(minf(point.x-BOUNDS.position.x,BOUNDS.end.x-point.x),minf(point.y-BOUNDS.position.y,BOUNDS.end.y-point.y))
	return smoothstep(-4,3,edge)

static func surface(point: Vector2) -> String:
	var mask := paint(point)
	if mask.a > .45: return "sand"
	if mask.b > .5: return "green"
	return "fairway" if mask.g > .45 else "rough"

static func terrain_height(point: Vector2) -> float:
	# The course is immutable. Reuse the mesh lattice heights for ball physics
	# and preview updates instead of resampling every hill at every substep.
	var lattice := point.x == floorf(point.x) and point.y == floorf(point.y)
	if lattice and _height_cache.has(point): return float(_height_cache[point])
	var height := _terrain_height(point)
	if lattice and _height_cache.size() < 30000: _height_cache[point] = height
	return height

static func _terrain_height(point: Vector2) -> float:
	var height := 1.1+.18*sin(point.x*.095)*cos(point.y*.12)
	for mound in [Vector4(-119,62,9,3.0),Vector4(-139,20,12,3.0),Vector4(-104,-35,9,2.2),Vector4(-97,-1,9,2.5),Vector4(-126,-48,10,2.0)]:
		height += mound.w*exp(-((point-Vector2(mound.x,mound.y))/mound.z).length_squared())
	# The first diagonal fairway is an accessible, continuous introduction.
	var first_weight := 1-smoothstep(5,9,route_distance(point,HOLES[0]))
	height = lerpf(height,1.15+.06*sin((point.y-74)*.13),first_weight)
	for bunker in BUNKERS:
		var d := ((point-Vector2(bunker.x,bunker.y))/Vector2(1.3,.8)).length()
		height -= (1-smoothstep(bunker.z-.7,bunker.z+1.2,d))*.55
	for tree in TREES:
		var d := point.distance_to(Vector2(tree.x,tree.y))
		height -= (1-smoothstep(.6,2.2,d))*.16
	for pond in PONDS:
		var d: float = ((point-pond.center)/pond.radii).length()
		height = lerpf(-2.0,height,smoothstep(.25,1.85,d))
	# Blend each green and tee into its surroundings, with a flat cup collar.
	for hole in HOLES:
		var d := point.distance_to(hole.cup)
		var green: float = hole.green_h+hole.slope.dot(point-hole.cup)*smoothstep(.8,2.8,d)
		height = lerpf(green,height,smoothstep(3.5,7,d))
		height = lerpf(float(hole.tee_h),height,smoothstep(1.8,4,point.distance_to(hole.tee)))
	return lerpf(1.2,height,smoothstep(2,8,point.distance_to(ENTRANCE)))

static func cup_for_cell(x: int, z: int) -> int:
	for i in HOLES.size():
		if Vector2(x+.5,z+.5).is_equal_approx(HOLES[i].cup): return i
	return -1
