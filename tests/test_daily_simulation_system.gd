extends RefCounted

const DailySimulationSystem = preload("res://scripts/systems/daily_simulation_system.gd")
const EconomySystemScript = preload("res://scripts/systems/economy_system.gd")
const MarketSystemScript = preload("res://scripts/systems/market_system.gd")


class ProductionDouble:
	extends Node
	var calls: Array

	func _init(recorded_calls: Array) -> void:
		calls = recorded_calls

	func apply_daily_effects(day: int) -> void:
		calls.append("production.apply:%d" % day)

	func finish_daily_outputs(day: int) -> void:
		calls.append("production.finish:%d" % day)


class FarmingDouble:
	extends Node
	var calls: Array

	func _init(recorded_calls: Array) -> void:
		calls = recorded_calls

	func on_day_changed(day: int) -> void:
		calls.append("farming.grow:%d" % day)


class NpcDouble:
	extends Node
	var calls: Array

	func _init(recorded_calls: Array) -> void:
		calls = recorded_calls

	func simulate_day(day: int) -> void:
		calls.append("npc.simulate:%d" % day)


class EconomyDouble:
	extends Node
	var calls: Array

	func _init(recorded_calls: Array) -> void:
		calls = recorded_calls

	func advance_order_deadlines(day: int) -> void:
		calls.append("economy.expire:%d" % day)

	func generate_demand_orders(day: int) -> void:
		calls.append("economy.orders:%d" % day)


class MarketDouble:
	extends Node
	var calls: Array

	func _init(recorded_calls: Array) -> void:
		calls = recorded_calls

	func can_settle_day(_day: int) -> bool:
		return true

	func settle_day(day: int) -> bool:
		calls.append("market.settle:%d" % day)
		return true


class RejectingSettlementMarketDouble:
	extends Node
	var calls: Array

	func _init(recorded_calls: Array) -> void:
		calls = recorded_calls

	func can_settle_day(_day: int) -> bool:
		return false

	func settle_day(day: int) -> bool:
		calls.append("market.settle:%d" % day)
		return false


class SaveDouble:
	extends Node
	var calls: Array
	var current_slot := 0
	var succeeds := true

	func _init(recorded_calls: Array, save_succeeds: bool = true) -> void:
		calls = recorded_calls
		succeeds = save_succeeds

	func save_game(slot: int = 0) -> bool:
		calls.append("save:%d" % slot)
		return succeeds


func run(assertions: TestAssert, tree: SceneTree) -> void:
	_test_unconfigured_coordinator_rejects_days(assertions)
	_test_empty_real_market_is_rejected(assertions)
	_test_exact_order_and_idempotence(assertions)
	_test_incoherent_real_market_rejects_before_mutation(assertions)
	_test_rejected_settlement_preflight_is_retry_safe(assertions)
	_test_failed_autosave_does_not_replay_partial_day(assertions)
	_test_single_authoritative_listener(assertions, tree)
	_test_order_processing_split(assertions)


func _test_unconfigured_coordinator_rejects_days(assertions: TestAssert) -> void:
	var daily := DailySimulationSystem.new()
	assertions.truthy(not daily.run_day(1), "unconfigured coordinator rejects a day")
	assertions.equal(daily.last_simulated_day, 0, "rejected unconfigured day preserves progress")
	daily.free()


func _test_empty_real_market_is_rejected(assertions: TestAssert) -> void:
	var calls: Array = []
	var farming := FarmingDouble.new(calls)
	var economy := EconomyDouble.new(calls)
	var market := MarketSystemScript.new()
	var save := SaveDouble.new(calls)
	var daily := DailySimulationSystem.new()
	assertions.truthy(
		not daily.configure(null, farming, null, economy, market, save),
		"daily coordinator rejects an unconfigured real market"
	)
	assertions.truthy(not daily.run_day(2), "empty market cannot consume a day")
	assertions.equal(calls, [], "empty market performs no daily work or save")
	for dependency in [farming, economy, market, save, daily]:
		dependency.free()


func _test_exact_order_and_idempotence(assertions: TestAssert) -> void:
	var calls: Array = []
	var production := ProductionDouble.new(calls)
	var farming := FarmingDouble.new(calls)
	var npc := NpcDouble.new(calls)
	var economy := EconomyDouble.new(calls)
	var market := MarketDouble.new(calls)
	var save := SaveDouble.new(calls)
	var daily := DailySimulationSystem.new()
	assertions.truthy(
		daily.configure(production, farming, npc, economy, market, save),
		"daily coordinator accepts compatible dependencies"
	)
	assertions.truthy(daily.run_day(2), "new day is simulated")
	assertions.equal(calls, [
		"production.apply:2",
		"farming.grow:2",
		"production.finish:2",
		"npc.simulate:2",
		"economy.expire:2",
		"market.settle:2",
		"economy.orders:2",
		"save:0",
	], "daily systems run in deterministic order")
	var calls_after_first_day := calls.duplicate()
	assertions.truthy(not daily.run_day(2), "same day is rejected")
	assertions.equal(calls, calls_after_first_day, "rejected day performs no work")
	assertions.equal(daily.last_simulated_day, 2, "coordinator records the consumed day")
	for dependency in [production, farming, npc, economy, market, save, daily]:
		dependency.free()


func _test_incoherent_real_market_rejects_before_mutation(assertions: TestAssert) -> void:
	var calls: Array = []
	var farming := FarmingDouble.new(calls)
	var economy := EconomyDouble.new(calls)
	var market := MarketSystemScript.new()
	var save := SaveDouble.new(calls)
	var daily := DailySimulationSystem.new()
	assertions.truthy(market.configure([_wood_definition()]), "cursor fixture configures market")
	assertions.truthy(market.settle_day(5), "cursor fixture advances market ahead")
	assertions.truthy(
		daily.configure(null, farming, null, economy, market, save),
		"cursor fixture configures coordinator"
	)
	daily.last_simulated_day = 3
	var market_before := market.to_dict()
	assertions.truthy(not daily.run_day(4), "incoherent market cursor rejects day before mutation")
	assertions.equal(calls, [], "cursor rejection performs no farming, orders, or save")
	assertions.equal(market.to_dict(), market_before, "cursor rejection preserves market")
	assertions.equal(daily.last_simulated_day, 3, "cursor rejection preserves simulated day")
	for dependency in [farming, economy, market, save, daily]:
		dependency.free()


func _test_rejected_settlement_preflight_is_retry_safe(assertions: TestAssert) -> void:
	var calls: Array = []
	var production := ProductionDouble.new(calls)
	var farming := FarmingDouble.new(calls)
	var npc := NpcDouble.new(calls)
	var economy := EconomyDouble.new(calls)
	var market := RejectingSettlementMarketDouble.new(calls)
	var save := SaveDouble.new(calls)
	var daily := DailySimulationSystem.new()
	assertions.truthy(
		daily.configure(production, farming, npc, economy, market, save),
		"settlement preflight fixture configures"
	)
	assertions.truthy(not daily.run_day(2), "rejected settlement preflight stops day")
	assertions.truthy(not daily.run_day(2), "rejected settlement retry also stops day")
	assertions.equal(calls, [], "settlement preflight rejection performs no work on retries")
	assertions.equal(daily.last_simulated_day, 0, "settlement preflight does not record day")
	for dependency in [production, farming, npc, economy, market, save, daily]:
		dependency.free()


func _test_failed_autosave_does_not_replay_partial_day(assertions: TestAssert) -> void:
	var calls: Array = []
	var farming := FarmingDouble.new(calls)
	var economy := EconomyDouble.new(calls)
	var market := MarketDouble.new(calls)
	var save := SaveDouble.new(calls, false)
	var daily := DailySimulationSystem.new()
	assertions.truthy(
		daily.configure(null, farming, null, economy, market, save),
		"production and NPC economy are optional during this phase"
	)
	assertions.truthy(daily.run_day(6), "completed mutations consume the day when autosave fails")
	var calls_after_failed_save := calls.duplicate()
	assertions.truthy(not daily.run_day(6), "failed autosave cannot replay a consumed day")
	assertions.equal(calls, calls_after_failed_save, "failed autosave retry performs no mutations")
	for dependency in [farming, economy, market, save, daily]:
		dependency.free()


func _test_single_authoritative_listener(assertions: TestAssert, tree: SceneTree) -> void:
	var calls: Array = []
	var daily := DailySimulationSystem.new()
	var production := ProductionDouble.new(calls)
	var farming := FarmingDouble.new(calls)
	var npc := NpcDouble.new(calls)
	var economy := EconomyDouble.new(calls)
	var market := MarketDouble.new(calls)
	var save := SaveDouble.new(calls)
	tree.root.add_child(daily)
	assertions.truthy(
		daily.configure(production, farming, npc, economy, market, save),
		"tree coordinator configures"
	)
	assertions.truthy(
		daily.configure(production, farming, npc, economy, market, save),
		"repeated coordinator configuration succeeds"
	)
	var event_bus := tree.root.get_node_or_null("EventBus")
	var coordinator_connections := 0
	if event_bus != null:
		for connection in event_bus.day_changed.get_connections():
			var callable: Callable = connection.get("callable", Callable())
			if callable.is_valid() and callable.get_object() == daily:
				coordinator_connections += 1
	assertions.equal(coordinator_connections, 1, "coordinator connects to day changes exactly once")
	for path in [
		"res://scripts/systems/farming_system.gd",
		"res://scripts/systems/economy_system.gd",
		"res://scripts/core/save_manager.gd",
	]:
		var source := FileAccess.get_file_as_string(path)
		assertions.truthy(
			not source.contains("day_changed.connect"),
			"legacy gameplay day listener is removed from %s" % path
		)
	daily.free()
	for dependency in [production, farming, npc, economy, market, save]:
		dependency.free()


func _test_order_processing_split(assertions: TestAssert) -> void:
	var economy := EconomySystemScript.new()
	economy.advance_order_deadlines(7)
	assertions.equal(economy.get_order_count(), 0, "deadline advancement is safe before dependency injection")
	economy.generate_demand_orders(7)
	assertions.equal(economy.get_order_count(), 0, "demand generation creates nothing without real NPC shortages")
	economy.free()


func _wood_definition() -> Dictionary:
	return {
		"id": "wood",
		"base_price": 100,
		"initial_stock": 10,
		"target_stock": 10,
		"daily_liquidity": 10,
	}
