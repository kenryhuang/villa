extends RefCounted

var world: Node
var leases: Dictionary = {}
var builds: Dictionary = {}

func configure(owner: Node) -> void:
	world = owner
	world.session.buildings.actor_assets = world.assets
	world.session.buildings.actor_lookup = world.actor
	world.session.buildings.land_permission = allows
	world.session.buildings.building_instance_removed.connect(_removed)

func reserve(actor: String, id: String, gx: int, gz: int, ttl := 360) -> Dictionary:
	if absi(gx) > 1024 or absi(gz) > 1024: return _error("invalid_site")
	if leases.has(id):
		var prior: Dictionary = leases[id]
		return {"ok": prior.actor_id == actor and int(prior.gx) == gx and int(prior.gz) == gz and prior.status == "reserved", "lease_id": id}
	if not world.assets.exists(actor) or ttl < 1 or ttl > 1080: return _error("invalid_lease")
	if not legal(actor, gx, gz): return _error("land_unavailable")
	leases[id] = {"id": id, "actor_id": actor, "gx": gx, "gz": gz, "expires": world.minute() + ttl, "status": "reserved"}
	return {"ok": true, "lease_id": id}

func legal(actor: String, gx: int, gz: int, except_id := "") -> bool:
	for x in range(gx, gx + 3):
		for z in range(gz, gz + 3):
			if not world.session.grid.get_cell_owner(x, z).is_empty(): return false
	var data: BuildingData = world.session.buildings._resolve_data("windmill")
	data = data.duplicate()
	data.cost = {} # Land quote excludes money/materials and distance; committing never does.
	if not world.session.buildings.diagnose_placement(data, gx, gz, actor, false).allowed: return false
	var footprint := Rect2i(gx, gz, 3, 3)
	for lease in leases.values():
		if lease.id != except_id and lease.status == "reserved" and int(lease.expires) > world.minute() and footprint.intersects(Rect2i(int(lease.gx), int(lease.gz), 3, 3)): return false
	return true

func start(actor: String, id: String, lease_id: String) -> Dictionary:
	if builds.has(id): return {"ok": builds[id].actor_id == actor and builds[id].lease_id == lease_id and builds[id].status not in ["cancelled", "demolished"], "building_id": builds[id].building_id}
	var lease: Dictionary = leases.get(lease_id, {})
	if lease.is_empty() or lease.actor_id != actor or lease.status != "reserved" or int(lease.expires) <= world.minute(): return _error("lease_expired_or_foreign")
	if not legal(actor, int(lease.gx), int(lease.gz), lease_id): return _error("land_changed")
	var result: Dictionary = world.session.buildings.try_place_building("windmill", int(lease.gx), int(lease.gz), actor)
	if not result.placed: return _error(str(result.get("code", "placement_failed")))
	var building: BuildingInstance = result.instance
	building.instance_id = "npc-" + id
	building.service_policy.open = false
	lease.status = "built"
	builds[id] = {"id": id, "actor_id": actor, "lease_id": lease_id, "building_id": building.instance_id, "materials": building.data.cost.duplicate(true), "status": "building"}
	return {"ok": true, "building_id": building.instance_id}

func cancel(actor: String, id: String) -> Dictionary:
	if not builds.has(id) or builds[id].actor_id != actor: return _error("not_owner")
	var record: Dictionary = builds[id]
	if record.status == "cancelled": return {"ok": true}
	var building: BuildingInstance = world.building(record.building_id)
	if building == null or building.is_construction_complete(): return _error("already_completed")
	if not world.assets.can_apply(actor, record.materials, 0): return _error("refund_capacity")
	if not world.session.buildings.remove_building(building, actor): return _error("building_busy")
	world.assets.apply(actor, record.materials, 0)
	record.status = "cancelled"
	leases[record.lease_id].status = "cancelled"
	return {"ok": true}

func advance() -> void:
	for lease in leases.values():
		if lease.status == "reserved" and world.minute() >= int(lease.expires): lease.status = "expired"
	for record in builds.values():
		var building: BuildingInstance = world.building(record.building_id)
		if record.status == "building" and building != null and building.is_construction_complete(): record.status = "completed"

func sites(actor: String) -> Array:
	var result := []
	# Survey actual legal grid cells near the village; not pre-created free buildings.
	for gx in range(28, 55, 4):
		for gz in range(26, 44, 4):
			if legal(actor, gx, gz):
				var cell: GridCell = world.session.grid.get_cell(gx, gz)
				result.append({"gx": gx, "gz": gz, "approach": {"x": cell.world_position().x - 1.2, "z": cell.world_position().y}, "lease_fee": 0, "cost": {"plank": 12, "stone_brick": 8, "rope": 2}})
				if result.size() == 3: return result
	return result

func to_dict() -> Dictionary: return {"leases": leases.duplicate(true), "builds": builds.duplicate(true)}

func validate(v: Variant) -> bool:
	v = preload("res://scripts/ai_agent/agent_protocol.gd")._normalize_json_numbers(v)
	if not v is Dictionary or v.size() != 2 or not v.get("leases") is Dictionary or not v.get("builds") is Dictionary: return false
	var occupied: Array[Rect2i] = []
	for id in v.leases:
		var lease: Variant = v.leases[id]
		if not lease is Dictionary or lease.get("id") != id or not world.assets.exists(str(lease.get("actor_id", ""))) or lease.get("status") not in ["reserved", "built", "expired", "cancelled"]: return false
		for key in ["gx", "gz", "expires"]:
			if not world.integer(lease.get(key)): return false
		if int(lease.expires) < 0 or absi(int(lease.gx)) > 1024 or absi(int(lease.gz)) > 1024: return false
		if lease.status == "reserved":
			var rect := Rect2i(int(lease.gx), int(lease.gz), 3, 3)
			for prior in occupied:
				if prior.intersects(rect): return false
			occupied.append(rect)
	for id in v.builds:
		var b: Variant = v.builds[id]
		if not b is Dictionary or b.get("id") != id or not v.leases.has(b.get("lease_id")) or b.get("actor_id") != v.leases[b.lease_id].actor_id or b.get("status") not in ["building", "completed", "cancelled", "demolished"] or not b.get("building_id") is String or b.get("materials") != {"plank": 12, "stone_brick": 8, "rope": 2}: return false
	return true

func restore(v: Dictionary) -> void:
	leases = v.leases.duplicate(true)
	builds = v.builds.duplicate(true)

static func _error(code: String) -> Dictionary: return {"ok": false, "error": code}


func allows(actor_id: String, gx: int, gz: int) -> bool:
	for lease in leases.values():
		if lease.status == "reserved" and int(lease.expires) > world.minute() and lease.actor_id != actor_id and Rect2i(int(lease.gx), int(lease.gz), 3, 3).has_point(Vector2i(gx, gz)): return false
	return true


func _removed(building: BuildingInstance) -> void:
	for record in builds.values():
		if record.building_id == building.instance_id:
			record.status = "demolished"
			leases[record.lease_id].status = "cancelled"
