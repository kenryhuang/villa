class_name ProducerState
extends RefCounted

const RecipeDatabaseScript = preload("res://scripts/core/recipe_database.gd")
const VALID_JOB_STATUSES := ["queued", "running", "output_full"]

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
	if not _is_positive_int(data.get("max_queue_slots")):
		return false
	if not _is_positive_int(data.get("output_capacity")):
		return false
	var saved_jobs: Variant = data.get("jobs")
	var saved_outputs: Variant = data.get("outputs")
	var saved_inputs: Variant = data.get("inputs", {})
	if not saved_jobs is Array or not saved_outputs is Dictionary or not saved_inputs is Dictionary:
		return false
	var next_station := data.get("station_id") as String
	var next_max_slots := data.get("max_queue_slots") as int
	var next_output_capacity := data.get("output_capacity") as int
	if (saved_jobs as Array).size() > next_max_slots:
		return false
	var next_jobs: Array[Dictionary] = []
	for value in saved_jobs:
		if not value is Dictionary:
			return false
		var job := (value as Dictionary).duplicate(true)
		if not _is_valid_job(job, next_station):
			return false
		next_jobs.append(job)
	if not _is_valid_count_map(saved_outputs as Dictionary):
		return false
	if not _is_valid_count_map(saved_inputs as Dictionary):
		return false
	if (saved_outputs as Dictionary).size() > next_output_capacity:
		return false

	station_id = next_station
	max_queue_slots = next_max_slots
	output_capacity = next_output_capacity
	jobs.assign(next_jobs)
	outputs = (saved_outputs as Dictionary).duplicate(true)
	inputs = (saved_inputs as Dictionary).duplicate(true)
	return true


func enqueue_job(job: Dictionary) -> bool:
	if jobs.size() >= max_queue_slots or not _is_valid_job(job, station_id):
		return false
	jobs.append(job.duplicate(true))
	return true


func can_store_outputs(requested: Dictionary) -> bool:
	if not _is_valid_count_map(requested):
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
	if not _is_valid_count_map(requested):
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


static func _is_valid_job(job: Dictionary, expected_station: String) -> bool:
	if not _is_valid_string(job.get("recipe_id")):
		return false
	if not _is_positive_int(job.get("batches")):
		return false
	if typeof(job.get("remaining_minutes")) != TYPE_INT or int(job.remaining_minutes) < 0:
		return false
	if not _is_valid_string(job.get("status")) or str(job.status) not in VALID_JOB_STATUSES:
		return false
	var recipe := RecipeDatabaseScript.get_recipe(str(job.recipe_id))
	if recipe.is_empty() or str(recipe.station) != expected_station:
		return false
	var maximum := int(recipe.duration_minutes) * int(job.batches)
	return int(job.remaining_minutes) <= maximum


static func _is_valid_count_map(values: Dictionary) -> bool:
	for key in values:
		if not key is String or (key as String).is_empty():
			return false
		if not _is_positive_int(values[key]):
			return false
	return true


static func _is_valid_string(value: Variant) -> bool:
	return value is String and not (value as String).is_empty()


static func _is_positive_int(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) > 0
