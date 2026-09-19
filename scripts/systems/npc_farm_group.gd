extends VisibleNpcFarmSystem

## Keep the original farm save/port compatible while routing each owner to
## independent physical plots and an independent work queue.
const FARMERS := {"xiao_hua": Vector3(-3,0,-12), "afu_shui": Vector3(-12,0,0), "resident_shan": Vector3(0,0,0)}
var farms: Dictionary = {}

func ensure_farms() -> bool:
	if not preload("res://scripts/systems/resident_society_system.gd").expanded(): return true
	for actor in FARMERS:
		if farms.has(actor): continue
		var farm := VisibleNpcFarmSystem.new()
		add_child(farm)
		if not farm.configure(_grid,_farming,_economy,_game_data,actor,FARMERS[actor]):
			push_error("Cannot allocate farmland for " + actor)
			farm.queue_free()
			return false
		farms[actor] = farm
		farm.work_finished.connect(func(intent, result): work_finished.emit(intent,result))
	return true

func for_actor(actor: String) -> VisibleNpcFarmSystem:
	return self if actor == _agent_id else farms.get(actor)

func get_plot_count(actor: String) -> int:
	return farms[actor].get_plot_count(actor) if farms.has(actor) else super.get_plot_count(actor)

func get_plot(actor: String, index: int) -> Dictionary:
	return farms[actor].get_plot(actor,index) if farms.has(actor) else super.get_plot(actor,index)

func get_snapshot(actor: String, minute := 0) -> Array[Dictionary]:
	return farms[actor].get_snapshot(actor,minute) if farms.has(actor) else super.get_snapshot(actor,minute)

func get_crop_options(actor: String) -> Array[Dictionary]:
	return farms[actor].get_crop_options(actor) if farms.has(actor) else super.get_crop_options(actor)

func has_pending_work(actor: String) -> bool:
	return farms[actor].has_pending_work(actor) if farms.has(actor) else super.has_pending_work(actor)

func queue_batch(intent: Dictionary, minute: int) -> Array[Dictionary]:
	return farms[intent.agent_id].queue_batch(intent,minute) if farms.has(intent.agent_id) else super.queue_batch(intent,minute)

func clear_pending_work() -> void:
	super.clear_pending_work()
	for farm in farms.values(): farm.clear_pending_work()

func to_dict() -> Dictionary:
	var result := super.to_dict()
	if not farms.is_empty():
		result.additional_farms = {}
		for actor in farms: result.additional_farms[actor] = farms[actor].to_dict()
	return result

func validate_dict(value: Dictionary) -> bool:
	if not super.validate_dict(value) or not value.get("additional_farms",{}) is Dictionary: return false
	var seen := {}
	for plot in value.plots: seen[str(plot.coordinate)] = true
	for actor in value.get("additional_farms",{}):
		var data: Variant = value.additional_farms[actor]
		if actor not in FARMERS or not data is Dictionary or data.get("agent_id") != actor or data.has("additional_farms") or not super.validate_dict(data): return false
		for plot in data.plots:
			if seen.has(str(plot.coordinate)): return false
			seen[str(plot.coordinate)] = true
	return true

func restore_queue(value: Dictionary) -> bool:
	if not validate_dict(value): return false
	for actor in farms: _grid.release_cells(actor)
	if not super.restore_queue(value): return false
	if not ensure_farms(): return false
	for actor in farms:
		var farm: VisibleNpcFarmSystem = farms[actor]
		if value.get("additional_farms",{}).has(actor):
			if not farm.from_dict(value.additional_farms[actor]): return false
		else:
			farm.clear_pending_work()
			if not farm.configure(_grid,_farming,_economy,_game_data,actor,FARMERS[actor]): return false
	return true
