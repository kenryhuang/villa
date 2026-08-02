class_name EconomyModalCoordinator
extends RefCounted

var _modal_owner: WeakRef
var _tree: SceneTree
var _tree_exiting_callback := Callable()
var _previous_pause_state := false
var _previous_process_mode := Node.PROCESS_MODE_INHERIT


func acquire(modal_owner: Node) -> bool:
	if modal_owner == null or not modal_owner.is_inside_tree():
		return false
	if _current_owner() != null:
		return false
	_modal_owner = weakref(modal_owner)
	_tree = modal_owner.get_tree()
	_previous_pause_state = _tree.paused
	_previous_process_mode = modal_owner.process_mode
	_tree_exiting_callback = _on_owner_tree_exiting.bind(modal_owner)
	modal_owner.tree_exiting.connect(_tree_exiting_callback, CONNECT_ONE_SHOT)
	modal_owner.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_tree.paused = true
	return true


func release(modal_owner: Node) -> bool:
	var current := _current_owner()
	if current == null or current != modal_owner:
		return false
	_restore_and_clear(modal_owner, true)
	return true


func is_owned_by(modal_owner: Node) -> bool:
	return _current_owner() == modal_owner


func _current_owner() -> Node:
	return _modal_owner.get_ref() as Node if _modal_owner != null else null


func _on_owner_tree_exiting(modal_owner: Node) -> void:
	if _current_owner() == modal_owner:
		_restore_and_clear(modal_owner, false)


func _restore_and_clear(modal_owner: Node, disconnect_signal: bool) -> void:
	if _tree != null:
		_tree.paused = _previous_pause_state
	if is_instance_valid(modal_owner):
		modal_owner.process_mode = _previous_process_mode
		if (
			disconnect_signal
			and _tree_exiting_callback.is_valid()
			and modal_owner.tree_exiting.is_connected(_tree_exiting_callback)
		):
			modal_owner.tree_exiting.disconnect(_tree_exiting_callback)
	_modal_owner = null
	_tree = null
	_tree_exiting_callback = Callable()
