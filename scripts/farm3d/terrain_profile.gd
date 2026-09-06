class_name Farm3DTerrainProfile
extends RefCounted

## One deterministic surface definition for rendering, collision and farm cells.
## Existing world coordinates remain unchanged so old saves keep their farmland.
const WORLD_MIN := Vector2(-80, -80)
const WORLD_MAX := Vector2(80, 144)
const WORLD_SIZE := WORLD_MAX - WORLD_MIN
const CORE_HALF_SIZE := 22.0
const WATER_HEIGHT := -1.15
const BRIDGE_Z := 18.0
const SAND_START := 50.0
const SAND_END := 86.0
const LAKE_CENTER := Vector2(-6, 108)
const LAKE_RADII := Vector2(26, 19)
const LAKE_FISHING_SPOTS := [
	{"id": "NorthShore", "shore": Vector2(-6, 84), "water": Vector2(-6, 92)},
	{"id": "WestShore", "shore": Vector2(-40, 108), "water": Vector2(-29, 108)},
	{"id": "SouthShore", "shore": Vector2(-6, 132), "water": Vector2(-6, 124)},
]
const TREES := [Vector2(-34,3), Vector2(-46,15), Vector2(-58,-8), Vector2(-38,-19), Vector2(-60,32), Vector2(-47,43), Vector2(-26,36), Vector2(-7,40), Vector2(17,36), Vector2(48,22), Vector2(62,9), Vector2(55,-13), Vector2(70,-35), Vector2(-58,-44), Vector2(59,48), Vector2(-31,60)]

static func river_x(z: float) -> float:
	return 36.0 + sin(z * 0.057) * 5.0 + sin(z * 0.123) * 1.7

static func _hill(x: float, z: float, cx: float, cz: float, radius: float, height: float) -> float:
	var distance := Vector2(x-cx,z-cz).length() / radius
	return height * exp(-distance * distance * 2.0)

static func sand_weight(x: float, z: float) -> float:
	# Keep this broad transition identical to the terrain shader and minimap.
	return smoothstep(SAND_START, SAND_END, z + sin(x * .085) * 4.0 + sin(x * .21) * 1.5)

static func lake_distance(x: float, z: float) -> float:
	var local := Vector2(x, z) - LAKE_CENTER
	return (local / LAKE_RADII).length() + .035 * sin(local.x * .17) * sin(local.y * .20)

static func is_lake(x: float, z: float) -> bool:
	return lake_distance(x, z) < 1.24 and is_water(x, z)

static func is_fishing_shore(x: float, z: float) -> bool:
	for spot in LAKE_FISHING_SPOTS:
		if Vector2(x, z).distance_to(spot.shore) < 2.4:
			return true
	return false

static func is_in_world(x: float, z: float, margin: float = 0.0) -> bool:
	return x >= WORLD_MIN.x - margin and x <= WORLD_MAX.x + margin and z >= WORLD_MIN.y - margin and z <= WORLD_MAX.y + margin

static func height_at(x: float, z: float) -> float:
	var core_distance := maxf(absf(x),absf(z))
	if core_distance <= CORE_HALF_SIZE:
		return 0.0
	var edge_weight := smoothstep(22.0,32.0,core_distance)
	var h := 0.6 + 0.45*sin(x*.09)*cos(z*.11)
	# Broad, rounded western hills, with valleys wide enough to walk between.
	h += _hill(x,z,-43,8,25,7) + _hill(x,z,-62,39,22,5.5)
	h += _hill(x,z,-38,52,22,4.5) + _hill(x,z,-59,-24,23,8)
	# Low dunes soften the new south; the approach from the farm stays walkable.
	var dunes := .65 + .28*sin(x*.09+z*.07)*cos(z*.12) + _hill(x,z,-55,111,25,2.4) + _hill(x,z,58,117,24,2.0)
	h = lerpf(h, dunes, smoothstep(55.0, 88.0, z))
	# Northern mountain massif, unequal peaks and lower connecting saddles.
	h += _hill(x,z,-31,-57,23,25) + _hill(x,z,-4,-66,19,29)
	h += _hill(x,z,18,-53,21,19) + _hill(x,z,-64,-64,24,15)
	var mountain := smoothstep(5.0,20.0,h)
	h += mountain*(1.1*sin(x*.35+z*.14)+.55*cos(z*.43-x*.18))
	# The eastern river cuts through a raised shelf to form an actual canyon.
	var canyon := smoothstep(-16.0,-43.0,z)
	h += canyon * 12.0 * exp(-pow((x-40.0)/28.0,4.0))
	h *= edge_weight
	var river_distance := absf(x-river_x(z))
	var bed := -2.0 + .12*sin(z*.13)
	# Broad banks in the plains, narrow walls in the northern canyon.
	var bank_width := lerpf(7.5,4.0,canyon)
	var bank := smoothstep(2.5,bank_width,river_distance)
	h = lerpf(bed,h,bank)
	# A shallow shelf leads to the lake bowl; the rim remains dry and accessible.
	var lake := lake_distance(x, z)
	if lake < 1.24:
		var lake_bed := -3.8 + .15*sin(x*.12)*cos(z*.16)
		h = lerpf(lake_bed, h, smoothstep(.62, 1.24, lake))
	# Move the southern edge to the new boundary, removing the old blocking ridge.
	var edge_distance := minf(minf(x-WORLD_MIN.x, WORLD_MAX.x-x), minf(z-WORLD_MIN.y, WORLD_MAX.y-z))
	var dune_ridge := 4.8 + 1.8*sin(x*.09+z*.07) + .8*cos(x*.21)
	var ridge_height := lerpf(8.0, dune_ridge, smoothstep(60.0,96.0,z))
	h += (1.0-smoothstep(0.0,9.0,edge_distance))*ridge_height*smoothstep(6.0,13.0,river_distance)
	return h

static func slope_at(x: float, z: float) -> float:
	return Vector2(height_at(x+.5,z)-height_at(x-.5,z),height_at(x,z+.5)-height_at(x,z-.5)).length()

static func surface_height(x: float, z: float) -> float:
	# Match the actual one-metre mesh triangles, including the diagonal.
	var ix := floorf(x)
	var iz := floorf(z)
	var u := x-ix
	var v := z-iz
	var a := height_at(ix,iz)
	var d := height_at(ix+1,iz+1)
	if u >= v:
		return a*(1-u)+height_at(ix+1,iz)*(u-v)+d*v
	return a*(1-v)+height_at(ix,iz+1)*(v-u)+d*u

static func bridge_height(x: float) -> float:
	var center := river_x(BRIDGE_Z)
	var t := clampf((x-center+8.0)/16.0,0,1)
	return lerpf(surface_height(center-8,BRIDGE_Z),surface_height(center+8,BRIDGE_Z),t)+.10+.65*sin(t*PI)

static func is_water(x: float, z: float) -> bool:
	return height_at(x,z) < WATER_HEIGHT + .08

static func is_bridge(x: float, z: float) -> bool:
	return absf(z-BRIDGE_Z) < 1.8 and absf(x-river_x(BRIDGE_Z)) < 9.8

static func is_original_core(x: float, z: float) -> bool:
	return absf(x) < CORE_HALF_SIZE and absf(z) < CORE_HALF_SIZE

static func region_at(x: float, z: float) -> String:
	if is_lake(x,z):
		return "南湖"
	if is_water(x,z):
		return "河流"
	if sand_weight(x,z) > .65:
		return "沙地"
	if z < -24.0 and absf(x-river_x(z)) < 17.0:
		return "峡谷"
	if z < -35.0 and height_at(x,z) > 9.0:
		return "山地"
	if height_at(x,z) > 2.0:
		return "丘陵"
	return "平原"
