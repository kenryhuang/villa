extends RefCounted

const DebugStateEditorScript := preload("res://scripts/debug/debug_state_editor.gd")
const GameDataScript := preload("res://scripts/core/game_data.gd")
const InventorySystemScript := preload("res://scripts/systems/inventory_system.gd")
const PlayerStateScript := preload("res://scripts/data/player_state.gd")


class GameStateDouble:
	extends RefCounted
	var gold := 700
	var player_state := PlayerStateScript.new()


class SeasonDouble:
	extends RefCounted
	const DAYS_PER_SEASON := 7
	var current_season := 1
	var current_day := 2
	var total_days := 9
	var hour := 11
	var minute := 20


class ProductionDouble:
	extends RefCounted
	var current_day := 9
	var fail_sync := false

	func sync_daily_cursor(day: int) -> bool:
		if fail_sync:
			return false
		current_day = day
		return true

	func get_current_day() -> int:
		return current_day


class MarketDouble:
	extends RefCounted
	var last_settled_day := 9


class NpcDouble:
	extends RefCounted
	var last_simulated_day := 9
	var fail_sync := false

	func sync_daily_cursor(day: int) -> bool:
		if fail_sync:
			return false
		last_simulated_day = day
		return true


class DailyDouble:
	extends RefCounted
	var last_simulated_day := 9
	var run_day_calls := 0

	func run_day(_day: int) -> bool:
		run_day_calls += 1
		return true


class ResourceDouble:
	extends RefCounted
	var cursor := 9
	var restore_calls := 0
	var state: Array = [{"resource_id": "tree-1", "units": 3}]

	func to_resource_dicts() -> Array:
		return state.duplicate(true)

	func restore_resource_dicts(value: Variant, loaded_day: int = 0) -> bool:
		state = (value as Array).duplicate(true)
		cursor = loaded_day
		restore_calls += 1
		return true


class EventBusDouble:
	extends RefCounted
	signal level_changed(new_level: int)
	signal exp_gained(amount: int)
	signal gold_changed(value: int)
	signal stamina_changed(value: int)
	signal item_added(item_id: String, quantity: int)
	signal item_removed(item_id: String, quantity: int)
	signal season_changed(new_season: int)
	signal day_changed(total_day: int)


func run(assertions: TestAssert) -> void:
	_test_snapshot(assertions)
	_test_validation(assertions)


func _test_snapshot(assertions: TestAssert) -> void:
	var fixture := _fixture()
	fixture.game_state.player_state.level = 3
	fixture.game_state.player_state.exp = 250
	assertions.truthy(fixture.inventory.add_item("wood", 12), "debug fixture adds wood")
	assertions.truthy(fixture.inventory.add_item("grain_seed", 4), "debug fixture adds seed")
	var snapshot: Dictionary = fixture.editor.snapshot()
	assertions.equal(snapshot.get("level"), 3, "snapshot reads level")
	assertions.equal(snapshot.get("elapsed_days"), 8, "snapshot converts total day to elapsed day")
	assertions.equal(snapshot.get("gold"), 700, "snapshot reads gold")
	assertions.equal(snapshot.get("stamina"), 100, "snapshot reads stamina")
	assertions.equal(
		(snapshot.items.wood as Dictionary).get("quantity"),
		12,
		"snapshot reads inventory totals"
	)
	assertions.equal(
		(snapshot.items.grain_seed as Dictionary).get("quantity"),
		4,
		"snapshot includes seed quantity"
	)
	assertions.equal(
		(snapshot.items as Dictionary).size(),
		GameDataScript.get_all_items().size(),
		"snapshot includes every registered inventory item"
	)
	fixture.inventory.free()


func _test_validation(assertions: TestAssert) -> void:
	var fixture := _fixture()
	var valid: Dictionary = fixture.editor.snapshot()
	assertions.truthy(bool(fixture.editor.validate(valid).get("ok", false)), "snapshot validates unchanged")

	var invalid := valid.duplicate(true)
	invalid["elapsed_days"] = -1
	assertions.equal(
		fixture.editor.validate(invalid).get("reason"),
		"invalid_elapsed_days",
		"negative elapsed days are rejected"
	)

	invalid = valid.duplicate(true)
	invalid["level"] = 999
	assertions.equal(
		fixture.editor.validate(invalid).get("reason"),
		"invalid_level",
		"out-of-range level is rejected"
	)

	invalid = valid.duplicate(true)
	(invalid.items as Dictionary)["unknown_debug_item"] = {
		"id": "unknown_debug_item", "quantity": 1,
	}
	assertions.equal(
		fixture.editor.validate(invalid).get("reason"),
		"unknown_item",
		"unknown inventory items are rejected"
	)

	invalid = valid.duplicate(true)
	for item_id in invalid.items:
		var record := invalid.items[item_id] as Dictionary
		record["quantity"] = int(record.get("max_stack", 1))
	assertions.equal(
		fixture.editor.validate(invalid).get("reason"),
		"inventory_capacity",
		"oversized target inventory is rejected"
	)

	invalid = valid.duplicate(true)
	invalid["gold"] = -10
	assertions.equal(
		fixture.editor.validate(invalid).get("reason"),
		"invalid_gold",
		"negative gold is rejected"
	)
	fixture.inventory.free()


func _fixture() -> Dictionary:
	var game_state := GameStateDouble.new()
	var season := SeasonDouble.new()
	var inventory := InventorySystemScript.new() as InventorySystem
	var production := ProductionDouble.new()
	var market := MarketDouble.new()
	var npc := NpcDouble.new()
	var daily := DailyDouble.new()
	var resources := ResourceDouble.new()
	var event_bus := EventBusDouble.new()
	var editor := DebugStateEditorScript.new()
	var configured := editor.configure(
		game_state,
		season,
		inventory,
		production,
		market,
		npc,
		daily,
		resources,
		event_bus
	)
	if not configured:
		push_error("DebugStateEditor test fixture failed to configure")
	return {
		"editor": editor,
		"game_state": game_state,
		"season": season,
		"inventory": inventory,
		"production": production,
		"market": market,
		"npc": npc,
		"daily": daily,
		"resources": resources,
		"event_bus": event_bus,
	}
