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


class EconomyDouble:
	extends RefCounted
	var state := {
		"last_processed_day": 9,
		"orders": [{"order_id": "preserved-until-date-change"}],
		"contracts": [],
	}
	var reset_calls: Array[int] = []

	func to_dict() -> Dictionary:
		return state.duplicate(true)

	func from_dict(value: Dictionary) -> bool:
		state = value.duplicate(true)
		return true

	func reset_order_state(day: int) -> bool:
		reset_calls.append(day)
		state = {"last_processed_day": day, "orders": [], "contracts": []}
		return true


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
	_test_unchanged_apply_emits_no_events(assertions)
	_test_apply_player_and_inventory(assertions)
	_test_apply_rolls_back_on_cursor_failure(assertions)
	_test_direct_elapsed_day_jump(assertions)


func _test_unchanged_apply_emits_no_events(assertions: TestAssert) -> void:
	var fixture := _fixture()
	fixture.game_state.player_state.level = 3
	fixture.game_state.player_state.exp = 275
	var events := _record_state_events(fixture.event_bus)
	var result: Dictionary = fixture.editor.apply(fixture.editor.snapshot())
	assertions.truthy(bool(result.get("ok", false)), "unchanged debug snapshot applies")
	assertions.equal(
		fixture.game_state.player_state.exp,
		275,
		"unchanged level preserves progress within the current level"
	)
	assertions.equal(fixture.economy.reset_calls, [], "unchanged date preserves active orders and contracts")
	for event_name in events:
		assertions.equal(
			(events[event_name] as Array).size(),
			0,
			"unchanged debug snapshot emits no %s event" % event_name
		)
	fixture.inventory.free()


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


func _test_apply_player_and_inventory(assertions: TestAssert) -> void:
	var fixture := _fixture()
	assertions.truthy(fixture.inventory.add_item("wood", 12), "apply fixture adds wood")
	assertions.truthy(fixture.inventory.add_item("grain_seed", 4), "apply fixture adds seed")
	assertions.truthy(fixture.inventory.set_quick_slot(0, 0), "apply fixture maps wood")
	assertions.truthy(fixture.inventory.set_quick_slot(1, 5), "apply fixture maps seed")
	var added_events: Array = []
	var removed_events: Array = []
	var state_events := _record_state_events(fixture.event_bus)
	fixture.event_bus.item_added.connect(
		func(item_id: String, quantity: int) -> void:
			added_events.append([item_id, quantity])
	)
	fixture.event_bus.item_removed.connect(
		func(item_id: String, quantity: int) -> void:
			removed_events.append([item_id, quantity])
	)
	var draft: Dictionary = fixture.editor.snapshot()
	draft["level"] = 4
	draft["gold"] = 4321
	draft["stamina"] = 17
	(draft.items.wood as Dictionary)["quantity"] = 130
	(draft.items.grain_seed as Dictionary)["quantity"] = 0
	var result: Dictionary = fixture.editor.apply(draft)
	assertions.truthy(bool(result.get("ok", false)), "valid debug state applies")
	assertions.equal(fixture.game_state.player_state.level, 4, "debug apply writes level")
	assertions.equal(
		fixture.game_state.player_state.exp,
		PlayerStateScript.LEVEL_THRESHOLDS[3],
		"level applies matching minimum experience"
	)
	assertions.equal(fixture.game_state.gold, 4321, "debug apply writes gold")
	assertions.equal(fixture.game_state.player_state.stamina, 17, "debug apply writes stamina")
	assertions.equal(fixture.inventory.get_item_count("wood"), 130, "inventory restores target quantity")
	assertions.equal(fixture.inventory.get_item_count("grain_seed"), 0, "zero quantity removes item")
	assertions.equal(fixture.inventory.get_quick_item(0), "wood", "retained quick item stays mapped")
	assertions.equal(fixture.inventory.get_quick_item(5), "", "removed quick item mapping clears")
	assertions.equal(added_events, [["wood", 118]], "apply emits exact positive item delta")
	assertions.equal(removed_events, [["grain_seed", 4]], "apply emits exact removed item delta")
	assertions.equal(state_events.level, [4], "apply emits one changed level refresh")
	assertions.equal(state_events.exp, [0], "changed level refreshes derived experience once")
	assertions.equal(state_events.gold, [4321], "apply emits one changed gold refresh")
	assertions.equal(state_events.stamina, [17], "apply emits one changed stamina refresh")
	assertions.equal(state_events.day, [], "non-date apply emits no formal day event")
	assertions.equal(
		str(result.get("message", "")),
		"调试数据已应用；尚未写入存档",
		"apply explains that state is not saved"
	)
	fixture.inventory.free()


func _test_apply_rolls_back_on_cursor_failure(assertions: TestAssert) -> void:
	var fixture := _fixture()
	assertions.truthy(fixture.inventory.add_item("wood", 8), "rollback fixture adds wood")
	var item_events: Array = []
	fixture.event_bus.item_added.connect(
		func(item_id: String, quantity: int) -> void:
			item_events.append([item_id, quantity])
	)
	var draft: Dictionary = fixture.editor.snapshot()
	draft["level"] = 5
	draft["gold"] = 9999
	(draft.items.wood as Dictionary)["quantity"] = 40
	fixture.npc.fail_sync = true
	var result: Dictionary = fixture.editor.apply(draft)
	assertions.equal(result.get("reason"), "transaction_failed", "cursor failure rejects transaction")
	assertions.equal(fixture.game_state.player_state.level, 1, "failed transaction restores level")
	assertions.equal(fixture.game_state.player_state.exp, 0, "failed transaction restores experience")
	assertions.equal(fixture.game_state.gold, 700, "failed transaction restores gold")
	assertions.equal(fixture.inventory.get_item_count("wood"), 8, "failed transaction restores inventory")
	assertions.equal(fixture.production.current_day, 9, "failed transaction restores production cursor")
	assertions.equal(fixture.npc.last_simulated_day, 9, "failed transaction restores NPC cursor")
	assertions.equal(item_events, [], "failed transaction emits no inventory events")
	fixture.inventory.free()


func _test_direct_elapsed_day_jump(assertions: TestAssert) -> void:
	var cases := [
		{"elapsed": 0, "total": 1, "season": 0, "day": 1},
		{"elapsed": 7, "total": 8, "season": 1, "day": 1},
		{"elapsed": 27, "total": 28, "season": 3, "day": 7},
		{"elapsed": 28, "total": 29, "season": 0, "day": 1},
	]
	for case in cases:
		var fixture := _fixture()
		var day_events: Array = []
		var season_events: Array = []
		fixture.event_bus.day_changed.connect(
			func(total_day: int) -> void:
				day_events.append(total_day)
		)
		fixture.event_bus.season_changed.connect(
			func(season: int) -> void:
				season_events.append(season)
		)
		var resource_state_before: Array = fixture.resources.state.duplicate(true)
		var hour_before: int = fixture.season.hour
		var minute_before: int = fixture.season.minute
		var old_season: int = fixture.season.current_season
		var draft: Dictionary = fixture.editor.snapshot()
		draft["elapsed_days"] = int(case.elapsed)
		var result: Dictionary = fixture.editor.apply(draft)
		assertions.truthy(bool(result.get("ok", false)), "elapsed day %d applies" % case.elapsed)
		assertions.equal(fixture.season.total_days, case.total, "elapsed day maps to total day")
		assertions.equal(fixture.season.current_season, case.season, "elapsed day maps to season")
		assertions.equal(fixture.season.current_day, case.day, "elapsed day maps within season")
		assertions.equal(fixture.season.hour, hour_before, "date jump keeps hour")
		assertions.equal(fixture.season.minute, minute_before, "date jump keeps minute")
		assertions.equal(fixture.production.current_day, case.total, "production cursor synchronizes")
		assertions.equal(fixture.npc.last_simulated_day, case.total, "NPC cursor synchronizes")
		assertions.equal(fixture.market.last_settled_day, case.total, "market cursor synchronizes")
		assertions.equal(fixture.daily.last_simulated_day, case.total, "daily cursor synchronizes")
		assertions.equal(fixture.daily.run_day_calls, 0, "direct jump never settles skipped days")
		assertions.equal(
			int(fixture.economy.state.last_processed_day),
			case.total,
			"economy order cursor synchronizes"
		)
		assertions.equal(
			fixture.economy.reset_calls,
			[case.total],
			"date edit relocates orders without processing skipped days"
		)
		assertions.equal(fixture.economy.state.orders, [], "date edit clears date-bound orders")
		assertions.equal(fixture.economy.state.contracts, [], "date edit clears date-bound contracts")
		assertions.equal(fixture.resources.cursor, case.total, "resource cursor synchronizes")
		assertions.equal(fixture.resources.state, resource_state_before, "resource state stays unchanged")
		assertions.equal(day_events, [], "direct date edit never emits formal day_changed")
		assertions.equal(
			season_events,
			[case.season] if old_season != int(case.season) else [],
			"date jump only emits changed season"
		)
		fixture.inventory.free()


func _record_state_events(event_bus: EventBusDouble) -> Dictionary:
	var events := {
		"level": [],
		"exp": [],
		"gold": [],
		"stamina": [],
		"item_added": [],
		"item_removed": [],
		"season": [],
		"day": [],
	}
	event_bus.level_changed.connect(func(value: int) -> void: events.level.append(value))
	event_bus.exp_gained.connect(func(value: int) -> void: events.exp.append(value))
	event_bus.gold_changed.connect(func(value: int) -> void: events.gold.append(value))
	event_bus.stamina_changed.connect(func(value: int) -> void: events.stamina.append(value))
	event_bus.item_added.connect(
		func(item_id: String, quantity: int) -> void:
			events.item_added.append([item_id, quantity])
	)
	event_bus.item_removed.connect(
		func(item_id: String, quantity: int) -> void:
			events.item_removed.append([item_id, quantity])
	)
	event_bus.season_changed.connect(func(value: int) -> void: events.season.append(value))
	event_bus.day_changed.connect(func(value: int) -> void: events.day.append(value))
	return events


func _fixture() -> Dictionary:
	var game_state := GameStateDouble.new()
	var season := SeasonDouble.new()
	var inventory := InventorySystemScript.new() as InventorySystem
	var production := ProductionDouble.new()
	var economy := EconomyDouble.new()
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
		economy,
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
		"economy": economy,
		"market": market,
		"npc": npc,
		"daily": daily,
		"resources": resources,
		"event_bus": event_bus,
	}
