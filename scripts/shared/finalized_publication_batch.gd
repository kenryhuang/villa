class_name FinalizedPublicationBatch
extends RefCounted

var _source_id := 0
var _actions: Array[Dictionary] = []
var _children: Array = []
var _enter_guard := Callable()
var _exit_guard := Callable()
var _pending := true


func _init(
	source: Object = null,
	actions: Array[Dictionary] = [],
	children: Array = [],
	enter_guard: Callable = Callable(),
	exit_guard: Callable = Callable()
) -> void:
	_source_id = source.get_instance_id() if is_instance_valid(source) else 0
	_actions = actions.duplicate(true)
	_children = children.duplicate()
	_enter_guard = enter_guard
	_exit_guard = exit_guard


func is_from(source: Object) -> bool:
	return is_instance_valid(source) and _source_id == source.get_instance_id()


func is_pending() -> bool:
	return _pending


func dispatch() -> bool:
	return dispatch_all([self])


static func dispatch_all(publications: Array) -> bool:
	var flattened: Array[FinalizedPublicationBatch] = []
	var seen: Dictionary = {}
	for publication in publications:
		if not publication is FinalizedPublicationBatch:
			return false
		if not _collect(publication as FinalizedPublicationBatch, flattened, seen):
			return false

	var actions: Array[Dictionary] = []
	var enter_guards: Array[Callable] = []
	var exit_guards: Array[Callable] = []
	for publication in flattened:
		publication._pending = false
		actions.append_array(publication._actions)
		if not publication._enter_guard.is_null():
			enter_guards.append(publication._enter_guard)
		if not publication._exit_guard.is_null():
			exit_guards.push_front(publication._exit_guard)

	for guard in enter_guards:
		if guard.is_valid():
			guard.call()
	var event_bus_states: Dictionary = {}
	for action in actions:
		var event_bus: Variant = action.get("event_bus")
		if is_instance_valid(event_bus) and not event_bus_states.has(event_bus):
			event_bus_states[event_bus] = (event_bus as Node).is_blocking_signals()
	for action in actions:
		_dispatch_action(action)
	for event_bus in event_bus_states:
		if is_instance_valid(event_bus):
			(event_bus as Node).set_block_signals(bool(event_bus_states[event_bus]))
	for guard in exit_guards:
		if guard.is_valid():
			guard.call()
	return true


static func _collect(
	publication: FinalizedPublicationBatch,
	flattened: Array[FinalizedPublicationBatch],
	seen: Dictionary
) -> bool:
	if not publication._pending:
		return false
	var instance_id := publication.get_instance_id()
	if seen.has(instance_id):
		return false
	seen[instance_id] = true
	for child in publication._children:
		if (
			not child is FinalizedPublicationBatch
			or not is_instance_valid(child)
			or not _collect(child as FinalizedPublicationBatch, flattened, seen)
		):
			return false
	flattened.append(publication)
	return true


static func _dispatch_action(action: Dictionary) -> void:
	var local_target: Variant = action.get("local_target")
	var local_signal := StringName(str(action.get("local_signal", "")))
	var arguments: Array = action.get("arguments", [])
	if (
		is_instance_valid(local_target)
		and not local_signal.is_empty()
		and (local_target as Object).has_signal(local_signal)
	):
		(local_target as Object).callv("emit_signal", [local_signal] + arguments)
	var event_bus: Variant = action.get("event_bus")
	var bus_signal := StringName(str(action.get("bus_signal", "")))
	if (
		is_instance_valid(event_bus)
		and not bus_signal.is_empty()
		and (event_bus as Object).has_signal(bus_signal)
	):
		(event_bus as Node).set_block_signals(false)
		(event_bus as Object).callv("emit_signal", [bus_signal] + arguments)
