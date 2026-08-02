class_name EconomyModalCoordinator
extends RefCounted

var _modal_owner: WeakRef
var _previous_pause_state := false
var _previous_process_mode := Node.PROCESS_MODE_INHERIT


func acquire(modal_owner: Node) -> bool:
	if modal_owner == null or not modal_owner.is_inside_tree():
		return false
	if _current_owner() != null:
		return false
	_modal_owner = weakref(modal_owner)
	_previous_pause_state = modal_owner.get_tree().paused
	_previous_process_mode = modal_owner.process_mode
	modal_owner.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	modal_owner.get_tree().paused = true
	return true


func release(modal_owner: Node) -> bool:
	var current := _current_owner()
	if current == null or current != modal_owner:
		return false
	if modal_owner.is_inside_tree():
		modal_owner.get_tree().paused = _previous_pause_state
		modal_owner.process_mode = _previous_process_mode
	_modal_owner = null
	return true


func is_owned_by(modal_owner: Node) -> bool:
	return _current_owner() == modal_owner


func _current_owner() -> Node:
	return _modal_owner.get_ref() as Node if _modal_owner != null else null
