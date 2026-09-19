extends RefCounted

## Edits use the actual save schema and the normal cross-system validators.
var session: Node

func configure(owner: Node) -> void:
	session = owner

func actors() -> Array:
	var result: Array = [{"id":"player","name":session.living_world.actor_name("player")}]
	for row in session.living_world.society.config.residents:
		result.append({"id":row.id,"name":session.living_world.actor_name(row.id)})
	return result

func snapshot(actor: String) -> Dictionary:
	if not session.living_world.relationships.person(actor): return {}
	var data: Dictionary = session.snapshot_save_data().duplicate(true)
	var records := {}
	_collect(data,[],actor,records)
	var world: Node = session.living_world
	# Crop cells reference their farm by coordinates rather than actor IDs.
	var farm = session.agent_runtime.farm_registry.for_actor(actor)
	if farm != null:
		var coordinates: Array = farm.to_dict().plots.map(func(p): return p.coordinate)
		for i in data.grid.cells.size():
			var cell: Dictionary = data.grid.cells[i]
			if [cell.gx,cell.gz] in coordinates: _add(records,["grid","cells",i],cell,data,"农田作物 · (%s,%s)" % [cell.gx,cell.gz])
	_add(records,["living_world","society","focus"],data.living_world.society.focus,data,"重点 NPC 名单（共享）")
	_add(records,["living_world","character_overrides",actor],world.character_profile(actor),data,"属性与性格（存档覆盖）")
	# Make zero affection editable even before two people have met.
	for other in actors():
		if other.id == actor: continue
		var key: String = world.relationships.pair_key(actor,other.id)
		_add(records,["living_world","relationships","pairs",key],world.relationships._pair(actor,other.id),data,"好感与关系 · " + str(other.name))
	if actor == "player":
		for field in ["gold","inventory","stamina","experience","level","tools","golf"]:
			_add(records,[field],data[field],data,"玩家 · " + field)
	return {"actor_id":actor,"records":records,"save_path":session.save_path}

func _add(records: Dictionary, path: Array, value: Variant, data: Dictionary, label := "") -> void:
	var key := JSON.stringify(path)
	records[key] = {"path":path.duplicate(),"label":label if not label.is_empty() else " / ".join(path.map(func(p): return str(p))),"value":_copy(value),"original":_copy(_read_path(data,path)),"exists":_exists(data,path)}

func _collect(value: Variant, path: Array, actor: String, records: Dictionary) -> void:
	# The original farmer's save is also the container for all later farms.
	# Show only his own fields, never the other farmers' nested state.
	if value is Dictionary and value.has("additional_farms") and value.get("agent_id") == actor:
		for field in value:
			if field == "additional_farms": continue
			var own_path := path + [field]
			records[JSON.stringify(own_path)] = {"path":own_path,"label":"农田 · "+str(field),"value":_copy(value[field]),"original":_copy(value[field]),"exists":true}
		return
	if not path.is_empty() and path[-1] is String and actor in str(path[-1]).replace("|",":").split(":"):
		var key := JSON.stringify(path)
		records[key] = {"path":path.duplicate(),"label":" / ".join(path.map(func(p): return str(p))),"value":_copy(value),"original":_copy(value),"exists":true}
		return
	if value is Dictionary:
		if not path.is_empty() and (str(path[-1]) == actor or _belongs(value,actor)):
			var key := JSON.stringify(path)
			records[key] = {"path":path.duplicate(),"label":" / ".join(path.map(func(p): return str(p))),"value":value.duplicate(true),"original":value.duplicate(true),"exists":true}
			return
		for key in value: _collect(value[key],path+[key],actor,records)
	elif value is Array:
		for index in value.size(): _collect(value[index],path+[index],actor,records)

func _belongs(value: Dictionary, actor: String) -> bool:
	for field in ["id","agent_id","npc_id","actor_id","owner_id","owner","actor","employer","worker_id","recipient_id","proposer_id","target_actor_id","left_id","right_id","source_actor","speaker_id"]:
		if value.get(field) == actor: return true
	for field in ["participants","actor_ids","accepted_by"]:
		if value.get(field) is Array and actor in value[field]: return true
	for field in ["terms","intent","payload","visibility"]:
		if value.get(field) is Dictionary and _belongs(value[field],actor): return true
	return false

func apply(view: Dictionary, changes: Dictionary) -> Dictionary:
	if not OS.is_debug_build(): return _error("只允许在开发版本中编辑。")
	if not session.get_tree().paused: return _error("请先暂停模拟再应用。")
	if view.is_empty() or not session.living_world.relationships.person(str(view.get("actor_id",""))): return _error("角色不存在。")
	var before: Dictionary = session.snapshot_save_data().duplicate(true)
	var candidate := before.duplicate(true)
	var count := 0
	for key in changes:
		if not view.records.has(key): return _error("不能修改未读取的状态记录。")
		var record: Dictionary = view.records[key]
		var value: Variant = changes[key]
		if value == record.value: continue
		if (record.value is Dictionary and not value is Dictionary) or (record.value is Array and not value is Array):
			return _error("记录类型不正确，请保留对象/数组结构：" + str(record.label))
		if _exists(before,record.path) != record.exists or _read_path(before,record.path) != record.original:
			return _error("状态已变化，请重新读取后编辑：" + str(record.label))
		_write_path(candidate,record.path,_copy(value))
		count += 1
	if count == 0: return {"ok":true,"message":"没有需要应用的修改。"}
	# Position is stored both by society and the visible focus-actor pool.
	var actor := str(view.actor_id)
	var resident_path := ["living_world","society","residents",actor]
	if _read_path(candidate,resident_path) != _read_path(before,resident_path) and candidate.living_world.positions.has(actor):
		candidate.living_world.positions[actor] = _read_path(candidate,resident_path).get("position",{})
	elif candidate.living_world.positions.get(actor) != before.living_world.positions.get(actor):
		candidate.living_world.society.residents[actor].position = candidate.living_world.positions[actor].duplicate(true)
	if not session._valid_save(candidate): return _error("校验失败：检查属性类型、金币/物品数量、好感范围、职业、时间及合同关联；未应用任何修改。")
	session.agent_runtime.gateway.cancel_all("debug_state_changed")
	if not session.restore_save_data(candidate,false):
		session.restore_save_data(before,false)
		return _error("应用失败，已尝试恢复修改前状态。")
	if not session.save_game():
		var save_reason: String = session.save_error
		session.restore_save_data(before,false)
		return _error("存档写入失败，已撤销本次修改：" + save_reason)
	return {"ok":true,"message":"已应用 %d 项修改并保存到 %s。" % [count,session.save_path]}

func _read_path(data: Variant, path: Array) -> Variant:
	var at: Variant = data
	for key in path:
		if at is Dictionary:
			if not at.has(key): return null
		elif at is Array:
			if not key is int or key < 0 or key >= at.size(): return null
		else: return null
		at = at[key]
	return at

func _exists(data: Variant, path: Array) -> bool:
	var parent: Variant = _read_path(data,path.slice(0,-1))
	return parent.has(path[-1]) if parent is Dictionary else parent is Array and path[-1] is int and path[-1] >= 0 and path[-1] < parent.size()

func _write_path(data: Dictionary, path: Array, value: Variant) -> void:
	var parent: Variant = _read_path(data,path.slice(0,-1))
	parent[path[-1]] = value

func _copy(value: Variant) -> Variant:
	return value.duplicate(true) if value is Dictionary or value is Array else value

func _error(message: String) -> Dictionary:
	return {"ok":false,"message":message}
