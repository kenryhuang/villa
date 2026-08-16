extends Node

const LEGACY_HARVEST_SEED := 42
const MIN_HARVEST_SEED := 1
const MAX_HARVEST_SEED := 2147483647

var gold := 100
var player_state
var play_time := 0.0
var harvest_seed := LEGACY_HARVEST_SEED

var _event_bus


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
	if amount <= 0:
		return false
	var leveled: bool = player_state.add_exp(amount)
	if _event_bus:
		_event_bus.exp_gained.emit(amount)
		if leveled:
			_event_bus.level_changed.emit(player_state.level)
	return true


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
