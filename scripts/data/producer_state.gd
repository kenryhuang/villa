class_name ProducerState
extends RefCounted

const RecipeDatabaseScript = preload("res://scripts/core/recipe_database.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")
const VALID_JOB_STATUSES := ["queued", "running", "output_full"]
const MAX_SAFE_INTEGER := 9007199254740991

var station_id := ""
var max_queue_slots := 2
var output_capacity := 3
var jobs: Array[Dictionary] = []
var outputs: Dictionary = {}
var inputs: Dictionary = {}
var customer_outputs: Dictionary = {}
var service_records: Dictionary = {}
var beehive_cycle: Dictionary = {"elapsed_minutes": 0, "completed_cycles": 0, "flower_signature": ""}


func _init(initial_station_id: String = "") -> void:
	station_id = initial_station_id


func to_dict() -> Dictionary:
	var result := {
		"station_id": station_id,
		"max_queue_slots": max_queue_slots,
		"output_capacity": output_capacity,
		"jobs": jobs.duplicate(true),
		"outputs": outputs.duplicate(true),
		"inputs": inputs.duplicate(true),
		"customer_outputs": customer_outputs.duplicate(true),
		"service_records": service_records.duplicate(true),
	}

	if station_id == "beehive": result["beehive_cycle"] = beehive_cycle.duplicate(true)
	return result


func from_dict(data: Dictionary) -> bool:
	var customers: Variant = data.get("customer_outputs", {})
	var records: Variant = data.get("service_records", {})
	if not customers is Dictionary or not records is Dictionary or records.size() > 2048:
		return false
	records = records.duplicate(true)
	for actor in customers:
		if not _is_valid_string(actor) or not customers[actor] is Dictionary or _normalized_count_map(customers[actor]) == null:
			return false
	for id in records:
		var record: Variant = records[id]
		if not _is_valid_string(id) or not record is Dictionary or not record.get("job") is Dictionary or str(record.get("stage", "")) not in ["queued", "running", "ready", "delivered", "cancelled"]:
			return false
		var normalized_record: Variant = _normalized_job(record.job, str(data.get("station_id", "")))
		if normalized_record == null or str(record.job.get("order_id", "")) != id:
			return false
		record.job = normalized_record
	if not _is_valid_string(data.get("station_id")):
		return false
	var parsed_max_slots: Variant = _integer_number(data.get("max_queue_slots"))
	if parsed_max_slots == null or int(parsed_max_slots) <= 0:
		return false
	var parsed_output_capacity: Variant = _integer_number(data.get("output_capacity"))
	if parsed_output_capacity == null or int(parsed_output_capacity) <= 0:
		return false
	var saved_jobs: Variant = data.get("jobs")
	var saved_outputs: Variant = data.get("outputs")
	var saved_inputs: Variant = data.get("inputs", {})
	if not saved_jobs is Array or not saved_outputs is Dictionary or not saved_inputs is Dictionary:
		return false
	var next_station := data.get("station_id") as String
	var cycle: Variant = data.get("beehive_cycle", {"elapsed_minutes": 0, "completed_cycles": 0, "flower_signature": ""})
	if data.has("beehive_cycle") and next_station != "beehive": return false
	if not cycle is Dictionary or cycle.size() != 3: return false
	var elapsed: Variant = _integer_number(cycle.get("elapsed_minutes"))
	var completed: Variant = _integer_number(cycle.get("completed_cycles"))
	var signature: Variant = cycle.get("flower_signature")
	if elapsed == null or int(elapsed) < 0 or int(elapsed) > 1000000: return false
	if completed == null or int(completed) < 0 or int(completed) > 1000000000: return false
	if not signature is String or (not signature.is_empty() and (signature.length() != 64 or not signature.is_valid_hex_number(false))): return false
	if signature.is_empty() and int(elapsed) != 0: return false
	var next_max_slots := int(parsed_max_slots)
	var next_output_capacity := int(parsed_output_capacity)
	if (saved_jobs as Array).size() > next_max_slots:
		return false
	var next_jobs: Array[Dictionary] = []
	for value in saved_jobs:
		if not value is Dictionary:
			return false
		var normalized_job: Variant = _normalized_job(value as Dictionary, next_station)
		if normalized_job == null:
			return false
		next_jobs.append(normalized_job as Dictionary)
	var next_outputs_value: Variant = _normalized_count_map(saved_outputs as Dictionary)
	if next_outputs_value == null:
		return false
	var next_inputs_value: Variant = _normalized_count_map(saved_inputs as Dictionary)
	if next_inputs_value == null:
		return false
	var next_outputs := next_outputs_value as Dictionary
	var next_inputs := next_inputs_value as Dictionary
	if next_outputs.size() > next_output_capacity:
		return false

	var seen := {}
	for job in next_jobs:
		if not job.has("order_id"): continue
		if seen.has(job.order_id) or not records.has(job.order_id) or job.payment_state == "refunded": return false
		seen[job.order_id] = true
		var record: Dictionary = records[job.order_id]
		if record.stage not in ["queued", "running"]: return false
		for field in ["tenant_id", "fee_owner", "rental_fee", "payment_state", "service_inputs", "recipe_id", "batches", "request_id"]:
			if job[field] != record.job[field]: return false
	for id in records:
		var record: Dictionary = records[id]
		if (record.stage in ["queued", "running"]) != seen.has(id): return false
		if record.stage == "cancelled" and record.job.payment_state != "refunded": return false
		if record.stage in ["ready", "delivered"] and record.job.payment_state not in ["paid", "self"]: return false
		if not record.get("events") is Array or record.events.is_empty() or record.events.size() > 6: return false
		for event in record.events:
			if not event is Dictionary or not event.get("stage") is String or _integer_number(event.get("game_minute")) == null: return false
	for actor in customers:
		if customers[actor].size() > next_output_capacity: return false

	beehive_cycle = {"elapsed_minutes": int(elapsed), "completed_cycles": int(completed), "flower_signature": str(signature)}
	station_id = next_station
	max_queue_slots = next_max_slots
	output_capacity = next_output_capacity
	jobs.assign(next_jobs)
	outputs = next_outputs
	inputs = next_inputs
	customer_outputs = {}
	for actor in customers: customer_outputs[actor] = _normalized_count_map(customers[actor])
	service_records = records.duplicate(true)
	for record in service_records.values():
		record.job = _normalized_job(record.job, station_id)
		for event in record.events: event.game_minute = int(event.game_minute)
	return true


func enqueue_job(job: Dictionary) -> bool:
	if jobs.size() >= max_queue_slots:
		return false
	var normalized_job: Variant = _normalized_job(job, station_id)
	if normalized_job == null:
		return false
	jobs.append(normalized_job as Dictionary)
	return true


func can_store_outputs(requested: Dictionary) -> bool:
	if _normalized_count_map(requested) == null:
		return false
	var occupied := outputs.size()
	for item_id in requested:
		if not outputs.has(item_id):
			occupied += 1
	return occupied <= output_capacity


func add_outputs(requested: Dictionary) -> bool:
	if not can_store_outputs(requested):
		return false
	for item_id in requested:
		outputs[item_id] = int(outputs.get(item_id, 0)) + int(requested[item_id])
	return true


func remove_outputs(requested: Dictionary) -> bool:
	if _normalized_count_map(requested) == null:
		return false
	for item_id in requested:
		if get_output_count(str(item_id)) < int(requested[item_id]):
			return false
	for item_id in requested:
		var remaining := get_output_count(str(item_id)) - int(requested[item_id])
		if remaining > 0:
			outputs[item_id] = remaining
		else:
			outputs.erase(item_id)
	return true


func get_output_count(item_id: String) -> int:
	return int(outputs.get(item_id, 0))


func add_input(item_id: String, quantity: int) -> bool:
	if item_id.is_empty() or quantity <= 0:
		return false
	inputs[item_id] = get_input_count(item_id) + quantity
	return true


func remove_input(item_id: String, quantity: int) -> bool:
	if item_id.is_empty() or quantity <= 0 or get_input_count(item_id) < quantity:
		return false
	var remaining := get_input_count(item_id) - quantity
	if remaining > 0:
		inputs[item_id] = remaining
	else:
		inputs.erase(item_id)
	return true


func get_input_count(item_id: String) -> int:
	return int(inputs.get(item_id, 0))


static func _normalized_job(job: Dictionary, expected_station: String) -> Variant:
	if not _is_valid_string(job.get("recipe_id")):
		return null
	var parsed_batches: Variant = _integer_number(job.get("batches"))
	if parsed_batches == null or int(parsed_batches) <= 0:
		return null
	var parsed_remaining: Variant = _integer_number(job.get("remaining_minutes"))
	if parsed_remaining == null or int(parsed_remaining) < 0:
		return null
	if not _is_valid_string(job.get("status")) or str(job.status) not in VALID_JOB_STATUSES:
		return null
	var recipe := RecipeDatabaseScript.get_recipe(str(job.recipe_id))
	if recipe.is_empty() or str(recipe.station) != expected_station:
		return null
	var batches := int(parsed_batches)
	var remaining := int(parsed_remaining)
	var duration := int(recipe.duration_minutes)
	if batches > MAX_SAFE_INTEGER / duration:
		return null
	var maximum := duration * batches
	if remaining > maximum:
		return null
	var result := job.duplicate(true)
	if job.has("tenant_id") or job.has("rental_fee"):
		if not _is_valid_string(job.get("tenant_id")) or str(job.tenant_id).length() > 80:
			return null
		var fee: Variant = _integer_number(job.get("rental_fee"))
		if fee == null or int(fee) < (0 if job.has("order_id") else 1):
			return null
		result.rental_fee = int(fee)
	if job.has("order_id"):
		if not _is_valid_string(job.order_id) or not _is_valid_string(job.get("tenant_id")) or not _is_valid_string(job.get("fee_owner")) or str(job.get("payment_state", "")) not in ["escrow", "paid", "self", "refunded"]:
			return null
		if not job.get("service_inputs") is Dictionary or _normalized_count_map(job.service_inputs) == null:
			return null
		var maximum_fee: Variant = _integer_number(job.get("max_fee"))
		if maximum_fee == null or int(maximum_fee) < int(result.rental_fee): return null
		result.max_fee = int(maximum_fee)
		result.service_inputs = _normalized_count_map(job.service_inputs)
		if _integer_number(job.get("policy_version")) == null or int(job.policy_version) < 1 or not job.get("request_id") is String: return null
		result.policy_version = int(job.policy_version)
		if job.payment_state == "self" and (job.tenant_id != job.fee_owner or int(job.rental_fee) != 0): return null
		if job.payment_state in ["escrow", "paid"] and job.tenant_id == job.fee_owner: return null
		if job.payment_state == "escrow" and (job.status != "queued" or remaining != maximum): return null
		var required := {}
		for id in recipe.inputs: required[id] = int(recipe.inputs[id]) * batches
		var actual: Dictionary = job.service_inputs.duplicate()
		for id in required:
			if int(actual.get(id, 0)) < int(required[id]): return null
			actual[id] = int(actual[id]) - int(required[id])
			if actual[id] == 0: actual.erase(id)
		for selector in recipe.get("input_selectors", []):
			var needed := int(selector.quantity) * batches
			for id in actual.keys():
				var item: Variant = GameDataScript.get_item(id)
				if str(selector.tag) in item.get("tags", []):
					var used := mini(needed, int(actual[id]))
					needed -= used
					actual[id] = int(actual[id]) - used
					if actual[id] == 0: actual.erase(id)
			if needed != 0: return null
		if not actual.is_empty(): return null
	result.batches = batches
	result.remaining_minutes = remaining
	return result


static func _normalized_count_map(values: Dictionary) -> Variant:
	var result := {}
	for key in values:
		if not key is String or (key as String).is_empty():
			return null
		if GameDataScript.get_item(key as String) == null:
			return null
		var parsed_quantity: Variant = _integer_number(values[key])
		if parsed_quantity == null or int(parsed_quantity) <= 0:
			return null
		result[key] = int(parsed_quantity)
	return result


static func _is_valid_string(value: Variant) -> bool:
	return value is String and not (value as String).is_empty()


static func _integer_number(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		if int(value) < -MAX_SAFE_INTEGER or int(value) > MAX_SAFE_INTEGER:
			return null
		return value
	if typeof(value) != TYPE_FLOAT:
		return null
	var number := float(value)
	if not is_finite(number) or absf(number) > float(MAX_SAFE_INTEGER):
		return null
	if number != floorf(number):
		return null
	return int(number)
