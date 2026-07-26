class_name PuzzleSystem
extends Node

## 解谜系统 - 管理所有谜题

signal puzzle_solved_signal(puzzle_id: String)

var _puzzles: Dictionary = {}  # puzzle_id → {solved, reward_gold, reward_items}
var _event_bus


func _ready() -> void:
	_event_bus = get_node_or_null("/root/EventBus")


func register_puzzle(puzzle_id: String, reward_gold: int = 0, reward_items: Array = []) -> void:
	_puzzles[puzzle_id] = {
		"solved": false,
		"reward_gold": reward_gold,
		"reward_items": reward_items,
	}


func solve_puzzle(puzzle_id: String) -> void:
	var puzzle = _puzzles.get(puzzle_id)
	if puzzle == null:
		push_error("Unknown puzzle: %s" % puzzle_id)
		return
	if puzzle.solved:
		return

	puzzle.solved = true
	_grant_rewards(puzzle)

	if _event_bus:
		_event_bus.puzzle_solved.emit(puzzle_id)

	puzzle_solved_signal.emit(puzzle_id)


func _grant_rewards(puzzle: Dictionary) -> void:
	# 金币奖励
	if puzzle.reward_gold > 0:
		var economy = get_node_or_null("/root/EconomySystem")
		if economy:
			economy.add_gold(puzzle.reward_gold)

	# 物品奖励
	if not puzzle.reward_items.is_empty():
		var inventory = get_node_or_null("/root/InventorySystem")
		if inventory:
			for item_id in puzzle.reward_items:
				inventory.add_item(item_id)


func is_solved(puzzle_id: String) -> bool:
	var puzzle = _puzzles.get(puzzle_id)
	if puzzle == null:
		return false
	return puzzle.solved


func get_solved_count() -> int:
	var count := 0
	for p in _puzzles.values():
		if p.solved:
			count += 1
	return count


func get_total_count() -> int:
	return _puzzles.size()
