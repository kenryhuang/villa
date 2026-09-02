class_name AgentWorldEvent
extends RefCounted

const EVENT_SCHEMA_VERSION := 1
const VISIBILITY_SCOPES := ["public", "region", "participants", "private", "system"]
const CANDIDATE_FIELDS := [
	"event_type",
	"aggregate_type",
	"aggregate_id",
	"actor_id",
	"game_minute",
	"command_id",
	"correlation_id",
	"causation_event_id",
	"visibility",
	"payload",
]


static func normalize_candidate(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("invalid_event")
	var event := value as Dictionary
	for field in CANDIDATE_FIELDS:
		if not event.has(field):
			return _failure("missing_" + field)
	for field in ["event_type", "aggregate_type", "aggregate_id", "actor_id", "command_id", "correlation_id"]:
		if typeof(event[field]) != TYPE_STRING or str(event[field]).strip_edges().is_empty():
			return _failure("invalid_" + field)
	if typeof(event.causation_event_id) != TYPE_STRING:
		return _failure("invalid_causation_event_id")
	if not _is_nonnegative_integer(event.game_minute):
		return _failure("invalid_game_minute")
	var visibility_result := _normalize_visibility(event.visibility)
	if not visibility_result.ok:
		return visibility_result
	if not event.payload is Dictionary:
		return _failure("invalid_payload")
	return {
		"ok": true,
		"value": {
			"event_type": str(event.event_type),
			"aggregate_type": str(event.aggregate_type),
			"aggregate_id": str(event.aggregate_id),
			"actor_id": str(event.actor_id),
			"game_minute": int(event.game_minute),
			"command_id": str(event.command_id),
			"correlation_id": str(event.correlation_id),
			"causation_event_id": str(event.causation_event_id),
			"visibility": visibility_result.value,
			"payload": (event.payload as Dictionary).duplicate(true),
		},
	}


static func _normalize_visibility(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("invalid_visibility")
	var visibility := value as Dictionary
	if visibility.size() != 2 or not visibility.has("scope") or not visibility.has("actor_ids"):
		return _failure("invalid_visibility")
	if typeof(visibility.scope) != TYPE_STRING or not str(visibility.scope) in VISIBILITY_SCOPES:
		return _failure("invalid_visibility_scope")
	if not visibility.actor_ids is Array:
		return _failure("invalid_visibility_actor_ids")
	var actor_ids: Array[String] = []
	for actor_id_value in visibility.actor_ids:
		if typeof(actor_id_value) != TYPE_STRING or str(actor_id_value).strip_edges().is_empty():
			return _failure("invalid_visibility_actor_id")
		var actor_id := str(actor_id_value)
		if actor_id in actor_ids:
			return _failure("duplicate_visibility_actor_id")
		actor_ids.append(actor_id)
	actor_ids.sort()
	var scope := str(visibility.scope)
	if scope in ["participants", "private"] and actor_ids.is_empty():
		return _failure("missing_visibility_actor_ids")
	if scope in ["public", "system"] and not actor_ids.is_empty():
		return _failure("unexpected_visibility_actor_ids")
	return {"ok": true, "value": {"scope": scope, "actor_ids": actor_ids}}


static func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error}


static func _is_nonnegative_integer(value: Variant) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and is_finite(float(value))
		and floorf(float(value)) == float(value)
		and int(value) >= 0
	)
