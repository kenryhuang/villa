extends RefCounted

## Business operations around the original production queue; all state belongs to buildings.
var production: Node
var assets: RefCounted
var busy := false

func configure(system: Node, access: RefCounted) -> void:
	production = system
	assets = access

func quote(building: BuildingInstance, actor: String, recipe: String, batches: int) -> Dictionary:
	if building == null or not production._registered_buildings.has(building) or not assets.exists(actor) or not assets.exists(building.owner_id) or batches < 1 or batches > 100:
		return _error("invalid_request")
	var own := actor == building.owner_id
	var policy := building.service_policy
	if not own and (not bool(policy.open) or (not policy.allowed_recipes.is_empty() and recipe not in policy.allowed_recipes)):
		return _error("service_closed")
	var state := building.producer_state
	if state == null: return _error("invalid_building")
	if not own and state.jobs.size() >= maxi(0, state.max_queue_slots - int(policy.reserved_slots)):
		return _error("reserved_capacity")
	var fee := -1
	for row in production.get_rental_fee_table(building):
		if row.recipe_id == recipe: fee = 0 if own else int(row.fee_per_batch) * batches
	if fee < 0: return _error("unknown_recipe")
	if not assets.can_apply(actor, {}, -fee): return _error("insufficient_rental_gold")
	var inventory: InventorySystem = production.rental_inventory(assets.available_items(actor))
	var result: Dictionary = production.preflight_recipe(building, recipe, batches, inventory)
	inventory.free()
	if not result.ok: return _error(str(result.reason))
	result.fee = fee
	result.policy_version = int(policy.version)
	return result

func start(building: BuildingInstance, actor: String, recipe: String, batches: int, max_fee: int, order_id := "", request_id := "") -> Dictionary:
	if busy or building == null or building.producer_state == null: return _error("service_busy")
	var state := building.producer_state
	if not order_id.is_empty() and state.service_records.has(order_id):
		var prior: Dictionary = state.service_records[order_id].job
		if prior.tenant_id != actor or prior.recipe_id != recipe or int(prior.batches) != batches or int(prior.max_fee) != max_fee:
			return _error("idempotency_conflict")
		return {"ok": true, "mutated": false, "order_id": order_id, "stage": state.service_records[order_id].stage}
	if state.service_records.size() >= 2048: return _error("order_history_full")
	var result := quote(building, actor, recipe, batches)
	if not result.ok: return result
	if max_fee < int(result.fee): return _error("rental_price_changed")
	if order_id.is_empty(): order_id = "order-" + Crypto.new().generate_random_bytes(16).hex_encode()
	var job := {"order_id": order_id, "request_id": request_id, "recipe_id": recipe, "batches": batches,
		"remaining_minutes": int(result.duration_minutes), "status": "queued", "tenant_id": actor,
		"fee_owner": building.owner_id, "rental_fee": int(result.fee), "max_fee": max_fee,
		"policy_version": int(result.policy_version), "service_inputs": result.inputs.duplicate(true),
		"payment_state": "self" if actor == building.owner_id else "escrow"}
	var delta := {}
	for id in result.inputs: delta[id] = -int(result.inputs[id])
	busy = true
	var event_tx: bool = production._begin_event_bus_transaction()
	var mapping_tx: bool = assets.inventory.begin_mapping_transaction()
	var before: Dictionary = assets.snapshot(actor)
	if not state.enqueue_job(job) or not assets.apply(actor, delta, -int(result.fee)):
		if not state.jobs.is_empty() and str(state.jobs.back().get("order_id", "")) == order_id: state.jobs.pop_back()
		assets.restore(actor, before)
		production._end_mapping_transaction(assets.inventory, mapping_tx, false)
		production._end_inventory_event_transaction(event_tx, false, "item_removed", result.inputs)
		busy = false
		return _error("transaction_failed")
	_record(building, state.jobs.back(), "queued")
	# The first job starts immediately only when the simulation is running.
	if state.jobs.size() == 1 and not production.get_tree().paused:
		activate(building, state.jobs[0])
	production._end_mapping_transaction(assets.inventory, mapping_tx, true)
	production._end_inventory_event_transaction(event_tx, true, "item_removed", result.inputs)
	if event_tx: production._emit_event("gold_changed", [int(assets.wallet.gold)])
	busy = false
	production.refresh_indicator(building)
	return {"ok": true, "mutated": true, "order_id": order_id, "status": "in_progress",
		"changed_entities": ["building:" + building.instance_id, "actor:" + actor], "resource_delta": delta.merged({"gold": -int(result.fee)}),
		"message": "加工订单已接受，费用 %d 金币；成品归客户，完成前请查看订单状态。" % int(result.fee)}

func activate(building: BuildingInstance, job: Dictionary) -> bool:
	if not job.has("order_id"): return true # Legacy rent has already been paid.
	if production.get_tree().paused: return false
	if str(job.payment_state) == "escrow":
		if not assets.apply(str(job.fee_owner), {}, int(job.rental_fee)): return false
		job.payment_state = "paid"
	job.status = "running"
	_record(building, job, "running")
	return true

func complete(building: BuildingInstance, job: Dictionary, outputs: Dictionary) -> bool:
	var actor := str(job.tenant_id)
	var state := building.producer_state
	if actor == "player" and building.owner_id == "player":
		if not state.add_outputs(outputs): return false
	elif actor == "player":
		var storage: Dictionary = state.customer_outputs.get(actor, {}).duplicate()
		for id in outputs:
			if int(storage.get(id, 0)) > 9007199254740991 - int(outputs[id]): return false
			storage[id] = int(storage.get(id, 0)) + int(outputs[id])
		if storage.size() > state.output_capacity: return false
		state.customer_outputs[actor] = storage
	else:
		if not assets.apply(actor, outputs, 0): return false
	_record(building, job, "ready" if actor == "player" else "delivered", false)
	return true

func cancel(building: BuildingInstance, actor: String, order_id: String) -> Dictionary:
	if busy or building == null or building.producer_state == null: return _error("service_busy")
	var state := building.producer_state
	if state.service_records.has(order_id) and state.service_records[order_id].stage == "cancelled":
		return {"ok": state.service_records[order_id].job.tenant_id == actor, "mutated": false}
	for index in state.jobs.size():
		var job: Dictionary = state.jobs[index]
		if str(job.get("order_id", "")) != order_id: continue
		if str(job.tenant_id) != actor: return _error("not_order_owner")
		if str(job.status) != "queued" or str(job.payment_state) not in ["escrow", "self"]: return _error("already_started")
		if not assets.can_apply(actor, job.service_inputs, int(job.rental_fee)): return _error("refund_capacity")
		busy = true
		var tx: bool = production._begin_event_bus_transaction()
		var mapping: bool = assets.inventory.begin_mapping_transaction()
		if not assets.apply(actor, job.service_inputs, int(job.rental_fee)):
			production._end_mapping_transaction(assets.inventory, mapping, false)
			production._end_inventory_event_transaction(tx, false, "item_added", job.service_inputs)
			busy = false
			return _error("transaction_failed")
		state.jobs.remove_at(index)
		job.payment_state = "refunded"
		_record(building, job, "cancelled")
		production._end_mapping_transaction(assets.inventory, mapping, true)
		production._end_inventory_event_transaction(tx, true, "item_added", job.service_inputs)
		if tx: production._emit_event("gold_changed", [int(assets.wallet.gold)])
		busy = false
		production.refresh_indicator(building)
		return {"ok": true, "mutated": true}
	return _error("order_not_found")

func set_policy(building: BuildingInstance, actor: String, policy: Dictionary, version: int) -> Dictionary:
	if busy or building == null or building.owner_id != actor: return _error("not_building_owner")
	if version != int(building.service_policy.version): return _error("policy_changed")
	var next := policy.duplicate(true)
	next.version = version + 1
	if not BuildingInstance.valid_service_policy(next, building.building_id): return _error("invalid_policy")
	if building.producer_state == null or int(next.reserved_slots) > building.producer_state.max_queue_slots: return _error("invalid_policy")
	building.service_policy = next
	return {"ok": true}

func collect(building: BuildingInstance, actor: String, item_id := "") -> Dictionary:
	if busy or building == null or not assets.exists(actor): return _error("invalid_request")
	var state := building.producer_state
	if state == null: return _error("invalid_building")
	var goods: Dictionary = state.customer_outputs.get(actor, {})
	var requested: Dictionary = goods.duplicate() if item_id.is_empty() else {item_id: int(goods.get(item_id, 0))}
	if requested.is_empty() or requested.values().has(0): return _error("nothing_to_collect")
	if not assets.can_apply(actor, requested, 0): return _error("inventory_capacity")
	busy = true
	var tx: bool = production._begin_event_bus_transaction()
	var mapping: bool = assets.inventory.begin_mapping_transaction()
	if not assets.apply(actor, requested, 0):
		production._end_mapping_transaction(assets.inventory, mapping, false)
		production._end_inventory_event_transaction(tx, false, "item_added", requested)
		busy = false
		return _error("transaction_failed")
	for id in requested: goods.erase(id)
	if goods.is_empty():
		state.customer_outputs.erase(actor)
		for record in state.service_records.values():
			if record.stage == "ready" and record.job.tenant_id == actor: _record(building, record.job, "delivered")
	production._end_mapping_transaction(assets.inventory, mapping, true)
	production._end_inventory_event_transaction(tx, true, "item_added", requested)
	if tx: production._emit_event("gold_changed", [int(assets.wallet.gold)])
	busy = false
	production.refresh_indicator(building)
	return {"ok": true, "requested": requested}

func _record(building: BuildingInstance, job: Dictionary, stage: String, publish := true) -> void:
	if not job.has("order_id"): return
	var record: Dictionary = building.producer_state.service_records.get(job.order_id, {"events": []})
	var changed := str(record.get("stage", "")) != stage
	if changed:
		record.events.append({"stage": stage, "game_minute": production._last_clock_minutes})
	record.stage = stage
	record.job = job.duplicate(true)
	building.producer_state.service_records[job.order_id] = record
	if changed and publish: production.service_order_changed.emit(building, record.duplicate(true))

func _error(reason: String) -> Dictionary:
	return {"ok": false, "error": reason, "reason": reason}

func maintain(building: BuildingInstance, actor: String) -> Dictionary:
	if busy or building == null or actor != building.owner_id: return _error("not_building_owner")
	if production.get_maintenance_state(building) not in ["warning", "overdue"]: return _error("maintenance_not_due")
	var quote: Dictionary = production.get_maintenance_quote(building)
	if quote.is_empty(): return _error("invalid_building")
	var delta := {}
	for id in quote.materials: delta[id] = -int(quote.materials[id])
	if not assets.can_apply(actor, delta, -int(quote.gold_cost)): return _error("insufficient_maintenance_assets")
	busy = true
	var tx: bool = production._begin_event_bus_transaction()
	var mapping: bool = assets.inventory.begin_mapping_transaction()
	var ok: bool = assets.apply(actor, delta, -int(quote.gold_cost))
	if ok:
		production.repair_remaining_seconds[production.building_key(building)] = production.REPAIR_DURATION_SECONDS
		production._refresh_greenhouse_cells()
		production.refresh_indicator(building)
		production.set_process(true)
	production._end_mapping_transaction(assets.inventory, mapping, ok)
	production._end_inventory_event_transaction(tx, ok, "item_removed", quote.materials)
	busy = false
	return {"ok": ok}
