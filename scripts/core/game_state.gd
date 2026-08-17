extends Node

const LEGACY_HARVEST_SEED := 42
const MIN_HARVEST_SEED := 1
const MAX_HARVEST_SEED := 2147483647

var gold := 100
var player_state
var play_time := 0.0
var harvest_seed := LEGACY_HARVEST_SEED

var _event_bus
var _exp_transaction_owner: WeakRef
var _exp_transaction: Dictionary = {}
var _exp_publication_owner: WeakRef
var _exp_publication: Dictionary = {}
var _exp_event_queue: Array[Dictionary] = []
var _exp_event_dispatch_suspended := false
var _is_dispatching_exp_events := false
var _exp_event_barrier_owner: WeakRef
var _exp_event_generation := 0


func _init() -> void:
	harvest_seed = _generate_harvest_seed()


func _ready() -> void:
	_event_bus = get_node_or_null("/root/EventBus") if is_inside_tree() else null
	player_state = preload("res://scripts/data/player_state.gd").new()
	player_state.stamina = 100
	player_state.max_stamina = 100
	player_state.level = 1
	player_state.exp = 0


func add_gold(amount: int) -> bool:
	if amount <= 0:
		return false
	gold += amount
	if _event_bus:
		_event_bus.gold_changed.emit(gold)
	return true


func spend_gold(amount: int) -> bool:
	if amount <= 0 or amount > gold:
		return false
	gold -= amount
	if _event_bus:
		_event_bus.gold_changed.emit(gold)
	return true


func add_exp(amount: int) -> bool:
	var token := prepare_exp_transaction(amount)
	if token == null or not apply_exp_transaction(token):
		if token != null:
			cancel_exp_transaction(token)
		return false
	var publication := seal_exp_transaction(token)
	if publication == null:
		cancel_exp_transaction(token)
		return false
	publish_exp_publication(publication)
	return true


func prepare_exp_transaction(amount: int) -> RefCounted:
	_recover_abandoned_exp_event_barrier()
	_recover_abandoned_exp_transaction()
	_recover_abandoned_exp_publication()
	if (
		amount <= 0
		or player_state == null
		or _has_exp_transaction()
		or _has_exp_publication()
	):
		return null
	var token := RefCounted.new()
	_exp_transaction_owner = weakref(token)
	_exp_transaction = {
		"amount": amount,
		"before_exp": int(player_state.exp),
		"before_level": int(player_state.level),
		"applied": false,
	}
	call_deferred("_recover_abandoned_exp_transaction")
	return token


func apply_exp_transaction(token: Variant) -> bool:
	if not _owns_exp_transaction(token) or bool(_exp_transaction.applied):
		return false
	var leveled: bool = player_state.add_exp(int(_exp_transaction.amount))
	_exp_transaction.after_exp = int(player_state.exp)
	_exp_transaction.after_level = int(player_state.level)
	_exp_transaction.leveled = leveled
	_exp_transaction.applied = true
	return true


func owns_exp_transaction(token: Variant) -> bool:
	if not _owns_exp_transaction(token):
		return false
	return not bool(_exp_transaction.applied) or _exp_state_matches(_exp_transaction)


func seal_exp_transaction(token: Variant) -> RefCounted:
	if (
		not _owns_exp_transaction(token)
		or not bool(_exp_transaction.applied)
		or _has_exp_publication()
		or not _exp_state_matches(_exp_transaction)
	):
		return null
	var publication := RefCounted.new()
	_exp_publication_owner = weakref(publication)
	_exp_publication = _exp_transaction.duplicate(true)
	_clear_exp_transaction()
	call_deferred("_recover_abandoned_exp_publication")
	return publication


func owns_exp_publication(publication: Variant) -> bool:
	_recover_abandoned_exp_publication()
	return _is_exp_publication_owner(publication) and _exp_state_matches(_exp_publication)


func cancel_exp_transaction(token: Variant) -> bool:
	_recover_abandoned_exp_transaction()
	if not _owns_exp_transaction(token):
		return false
	if bool(_exp_transaction.get("applied", false)):
		_restore_exp_snapshot(_exp_transaction)
	_clear_exp_transaction()
	return true


func cancel_exp_publication(publication: Variant) -> bool:
	if not owns_exp_publication(publication):
		return false
	_restore_exp_snapshot(_exp_publication)
	_clear_exp_publication()
	return true


func publish_exp_publication(publication: Variant) -> void:
	if not can_arm_exp_publication(publication):
		push_error("Invalid experience publication ownership")
		return
	var already_suspended := _exp_event_dispatch_suspended
	var barrier := arm_exp_publication(publication)
	if not already_suspended:
		release_exp_event_barrier(barrier)


func can_arm_exp_publication(
	publication: Variant,
	require_new_barrier: bool = false
) -> bool:
	return (
		owns_exp_publication(publication)
		and (not require_new_barrier or not _exp_event_dispatch_suspended)
	)


func arm_exp_publication(publication: Variant) -> RefCounted:
	if not _is_exp_publication_owner(publication):
		push_error("Invalid experience publication ownership at commit point")
		return null
	var committed := _exp_publication.duplicate(true)
	_clear_exp_publication()
	var event := {
		"amount": int(committed.amount),
		"leveled": bool(committed.leveled),
		"after_level": int(committed.after_level),
		"generation": _exp_event_generation,
	}
	event.make_read_only()
	_exp_event_queue.append(event)
	if _exp_event_dispatch_suspended:
		return null
	var barrier := RefCounted.new()
	_exp_event_barrier_owner = weakref(barrier)
	_exp_event_dispatch_suspended = true
	call_deferred("_recover_abandoned_exp_event_barrier")
	return barrier


func release_exp_event_barrier(barrier: Variant) -> void:
	if not _is_exp_event_barrier_owner(barrier):
		return
	_exp_event_barrier_owner = null
	_exp_event_dispatch_suspended = false
	_drain_exp_event_queue()


func _exp_state_matches(transaction: Dictionary) -> bool:
	return (
		player_state != null
		and int(player_state.exp) == int(transaction.get("after_exp", -1))
		and int(player_state.level) == int(transaction.get("after_level", -1))
	)


func _restore_exp_snapshot(transaction: Dictionary) -> void:
	player_state.exp = int(transaction.before_exp)
	player_state.level = int(transaction.before_level)


func _clear_exp_transaction() -> void:
	_exp_transaction_owner = null
	_exp_transaction.clear()


func _clear_exp_publication() -> void:
	_exp_publication_owner = null
	_exp_publication.clear()


func _has_exp_publication() -> bool:
	return _exp_publication_owner != null and _exp_publication_owner.get_ref() != null


func _is_exp_publication_owner(publication: Variant) -> bool:
	return (
		publication is RefCounted
		and _exp_publication_owner != null
		and _exp_publication_owner.get_ref() == publication
	)


func _recover_abandoned_exp_publication() -> void:
	if _exp_publication_owner != null and _exp_publication_owner.get_ref() == null:
		_restore_exp_snapshot(_exp_publication)
		_clear_exp_publication()


func _has_exp_transaction() -> bool:
	return _exp_transaction_owner != null and _exp_transaction_owner.get_ref() != null


func _owns_exp_transaction(token: Variant) -> bool:
	return (
		token is RefCounted
		and _exp_transaction_owner != null
		and _exp_transaction_owner.get_ref() == token
	)


func _recover_abandoned_exp_transaction() -> void:
	if _exp_transaction_owner == null or _exp_transaction_owner.get_ref() != null:
		return
	if bool(_exp_transaction.get("applied", false)):
		_restore_exp_snapshot(_exp_transaction)
	_clear_exp_transaction()


func _is_exp_event_barrier_owner(barrier: Variant) -> bool:
	return (
		barrier is RefCounted
		and _exp_event_barrier_owner != null
		and _exp_event_barrier_owner.get_ref() == barrier
	)


func _recover_abandoned_exp_event_barrier() -> void:
	if _exp_event_barrier_owner == null or _exp_event_barrier_owner.get_ref() != null:
		return
	_exp_event_barrier_owner = null
	_exp_event_dispatch_suspended = false
	_drain_exp_event_queue()


func _drain_exp_event_queue() -> void:
	if _is_dispatching_exp_events or _exp_event_dispatch_suspended:
		return
	_is_dispatching_exp_events = true
	while not _exp_event_queue.is_empty() and not _exp_event_dispatch_suspended:
		var event: Dictionary = _exp_event_queue.pop_front()
		if _event_bus:
			_event_bus.exp_gained.emit(int(event.amount))
			if int(event.generation) != _exp_event_generation:
				continue
			if bool(event.leveled):
				_event_bus.level_changed.emit(int(event.after_level))
	_is_dispatching_exp_events = false


func invalidate_exp_state_for_replacement() -> void:
	_exp_event_generation += 1
	_exp_transaction_owner = null
	_exp_transaction.clear()
	_exp_publication_owner = null
	_exp_publication.clear()
	_exp_event_barrier_owner = null
	_exp_event_dispatch_suspended = false
	_exp_event_queue.clear()


func set_harvest_seed(value: int) -> bool:
	if not is_valid_harvest_seed(value):
		return false
	harvest_seed = value
	return true


static func is_valid_harvest_seed(value: Variant) -> bool:
	return (
		typeof(value) == TYPE_INT
		and int(value) >= MIN_HARVEST_SEED
		and int(value) <= MAX_HARVEST_SEED
	)


static func _generate_harvest_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi_range(MIN_HARVEST_SEED, MAX_HARVEST_SEED)


func reset_to_new_game() -> void:
	invalidate_exp_state_for_replacement()
	gold = 100
	harvest_seed = _generate_harvest_seed()
	player_state.stamina = 100
	player_state.max_stamina = 100
	player_state.level = 1
	player_state.exp = 0
	play_time = 0.0
	if _event_bus:
		_event_bus.gold_changed.emit(gold)
		_event_bus.stamina_changed.emit(player_state.stamina)
		_event_bus.level_changed.emit(player_state.level)
		_event_bus.exp_gained.emit(0)
