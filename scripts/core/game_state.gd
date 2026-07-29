extends Node

var gold := 100
var player_state
var play_time := 0.0

var _event_bus


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
	if amount <= 0:
		return false
	var leveled: bool = player_state.add_exp(amount)
	if _event_bus:
		_event_bus.exp_gained.emit(amount)
		if leveled:
			_event_bus.level_changed.emit(player_state.level)
	return true
