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


func _init(initial_station_id: String = "") -> void:
	station_id = initial_station_id


func to_dict() -> Dictionary:
	return {
		"station_id": station_id,
		"max_queue_slots": max_queue_slots,
		"output_capacity": output_capacity,
		"jobs": jobs.duplicate(true),
		"outputs": outputs.duplicate(true),
		"inputs": inputs.duplicate(true),
	}


func from_dict(data: Dictionary) -> bool:
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

	station_id = next_station
	max_queue_slots = next_max_slots
	output_capacity = next_output_capacity
	jobs.assign(next_jobs)
	outputs = next_outputs
	inputs = next_inputs
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
