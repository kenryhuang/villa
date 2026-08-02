class_name EconomyNotificationsTest
extends RefCounted

const NotificationSystemScript = preload("res://scripts/systems/economy_notification_system.gd")
const NOTIFICATION_UI_SCENE_PATH := "res://scenes/ui/economy/economy_notification_ui.tscn"
const EventBusScript = preload("res://scripts/core/event_bus.gd")
const SaveManagerScript = preload("res://scripts/core/save_manager.gd")
const MarketSystemScript = preload("res://scripts/systems/market_system.gd")
const EconomySystemScript = preload("res://scripts/systems/economy_system.gd")
const MainScript = preload("res://scripts/main.gd")
const HudScene = preload("res://scenes/ui/hud.tscn")

const TEST_SAVE_DIR := "user://task17_economy_notifications/"
const TEST_SAVE_SLOT := 17


class FakeDailySimulation:
	extends Node
	var last_simulated_day := 1


class FakeRouteTarget:
	extends Node
	var selected_id := ""

	func select_item(value: String) -> void:
		selected_id = value

	func select_order(value: String) -> void:
		selected_id = value

	func select_contract(value: String) -> void:
		selected_id = value


class FakeShop:
	extends Node
	var opened_tabs: Array[String] = []
	var market_panel := FakeRouteTarget.new()
	var order_panel := FakeRouteTarget.new()
	var contract_panel := FakeRouteTarget.new()

	func open(tab_id: String = "market") -> void:
		opened_tabs.append(tab_id)


class FakeRouter:
	extends Node
	var calls: Array[Dictionary] = []
	var route_success := true

	func navigate_notification_target(target_type: String, target_id: String) -> bool:
		calls.append({"target_type": target_type, "target_id": target_id})
		return route_success


class FakeBuildingUI:
	extends Node
	var opened: Array[BuildingInstance] = []

	func open_for(building: BuildingInstance) -> bool:
		opened.append(building)
		return true


func run(assertions: TestAssert, tree: SceneTree) -> void:
	run_core(assertions)
	await run_integration(assertions, tree)


func run_core(assertions: TestAssert) -> void:
	_test_record_merge_boundaries_and_retention(assertions)
	_test_read_and_strict_atomic_persistence(assertions)


func run_integration(assertions: TestAssert, tree: SceneTree) -> void:
	_test_real_clock_and_event_bus_connections(assertions, tree)
	_test_save_manager_round_trip_without_replay(assertions, tree)
	await _test_scene_toasts_center_and_hud(assertions, tree)
	_test_main_four_way_routing(assertions)


func _test_record_merge_boundaries_and_retention(assertions: TestAssert) -> void:
	var system = NotificationSystemScript.new()
	var first_id: String = system.push("completed", "生产完成", "风车完成面粉 ×1", 12, "building", "windmill:4:5", 10.0)
	var merged_id: String = system.push("completed", "生产完成", "风车完成面粉 ×2", 13, "building", "windmill:4:5", 12.999)
	assertions.equal(merged_id, first_id, "same kind and target merges at 2.999 seconds")
	var recent: Array[Dictionary] = system.get_recent()
	assertions.equal(recent.size(), 1, "merged messages share one authoritative record")
	assertions.equal(int(recent[0].count), 2, "system merge increments count")
	assertions.equal(str(recent[0].body), "风车完成面粉 ×2", "merge refreshes the latest body")
	assertions.equal(int(recent[0].total_day), 13, "merge refreshes the latest game day")
	assertions.equal(str(recent[0].notification_id), first_id, "merge keeps the stable notification id")
	var cross_day_restored = NotificationSystemScript.new()
	assertions.truthy(cross_day_restored.from_dict(system.to_dict()), "stable first-occurrence id remains valid after a cross-day merge")
	cross_day_restored.free()

	var boundary_system = NotificationSystemScript.new()
	var boundary_first: String = boundary_system.push("completed", "生产完成", "风车完成面粉 ×1", 12, "building", "windmill:4:5", 10.0)
	var boundary_id: String = boundary_system.push("completed", "生产完成", "风车完成面粉 ×3", 12, "building", "windmill:4:5", 13.0)
	assertions.truthy(boundary_id != boundary_first, "exactly three seconds starts a separate record")
	assertions.equal(boundary_system.get_recent().size(), 2, "three-second boundary remains separate")
	boundary_system.free()
	system.push("shortage", "库存紧缺", "木材紧缺", 12, "market_item", "wood", 13.1)
	assertions.equal(system.get_recent().size(), 2, "unrelated kind and target remains separate")

	for index in range(21):
		system.push("unlock", "解锁", "解锁 %d" % index, index + 20, "service", "recipe_%d" % index, 20.0 + index * 3.0)
	recent = system.get_recent(50)
	assertions.equal(recent.size(), 20, "notification state retains only the newest twenty")
	assertions.equal(str(recent[0].body), "解锁 20", "recent records are newest first")
	assertions.equal(str(recent[-1].body), "解锁 1", "retention drops the oldest record")
	var exposed: Array[Dictionary] = system.get_recent()
	exposed[0]["body"] = "mutated"
	assertions.equal(str(system.get_recent()[0].body), "解锁 20", "recent getter is deep copied")
	var json_text := JSON.stringify(system.to_dict())
	assertions.truthy(not json_text.is_empty(), "notification snapshot is JSON safe")
	system.free()


func _test_read_and_strict_atomic_persistence(assertions: TestAssert) -> void:
	var system = NotificationSystemScript.new()
	var first_id: String = system.push("order_due", "订单临期", "订单即将到期", 5, "order", "npc:wood:4", 1.0)
	var second_id: String = system.push("contract_breached", "合同未完成", "今日尚未交付", 5, "contract", "npc:wood:4:6", 1.1)
	assertions.equal(system.get_unread_count(), 2, "new records are unread")
	assertions.truthy(system.mark_read(first_id), "mark read changes an unread record")
	assertions.truthy(not system.mark_read(first_id), "mark read does nothing when already read")
	assertions.equal(system.get_unread_count(), 1, "reading only changes unread state")
	var after_read: Array[Dictionary] = system.get_recent()
	assertions.equal(int(after_read[0].count), 1, "reading does not change notification count")
	assertions.equal(str(after_read[0].body), "今日尚未交付", "reading does not change content")
	system.mark_all_read()
	assertions.equal(system.get_unread_count(), 0, "mark all clears every unread flag")

	var valid: Dictionary = system.to_dict()
	var restored = NotificationSystemScript.new()
	assertions.truthy(restored.from_dict(valid), "strict notification snapshot restores")
	assertions.equal(restored.to_dict(), valid, "notification snapshot round trips exactly")
	var before: Dictionary = restored.to_dict()
	var malformed_cases: Array[Dictionary] = []
	var unknown_kind := valid.duplicate(true)
	unknown_kind.records[0].kind = "mystery"
	malformed_cases.append(unknown_kind)
	var unknown_target := valid.duplicate(true)
	unknown_target.records[0].target_type = "moon"
	malformed_cases.append(unknown_target)
	var bad_count := valid.duplicate(true)
	bad_count.records[0].count = 0
	malformed_cases.append(bad_count)
	var duplicate_id := valid.duplicate(true)
	duplicate_id.records.append(duplicate_id.records[0].duplicate(true))
	malformed_cases.append(duplicate_id)
	var bad_day := valid.duplicate(true)
	bad_day.records[0].total_day = -1
	malformed_cases.append(bad_day)
	for malformed in malformed_cases:
		assertions.truthy(not restored.from_dict(malformed), "malformed notification snapshot is rejected")
		assertions.equal(restored.to_dict(), before, "rejected snapshot preserves prior state atomically")

	var loaded = NotificationSystemScript.new()
	assertions.truthy(loaded.from_dict(valid), "load fixture restores")
	var post_load_id: String = loaded.push("contract_breached", "合同未完成", "新会话提醒", 5, "contract", "npc:wood:4:6", 1.2)
	assertions.truthy(post_load_id != second_id, "load clears transient merge windows")
	assertions.equal(loaded.get_recent().size(), 3, "load never merges against persisted monotonic time")
	loaded.free()
	restored.free()
	system.free()


func _test_real_clock_and_event_bus_connections(assertions: TestAssert, tree: SceneTree) -> void:
	var event_bus := tree.root.get_node_or_null("EventBus")
	assertions.truthy(event_bus != null and event_bus.get_script() == EventBusScript, "test uses the real EventBus autoload")
	if event_bus == null:
		return
	assertions.truthy(event_bus.has_signal("market_caravan_changed"), "EventBus exposes caravan notification source")
	assertions.truthy(event_bus.has_signal("production_feed_shortage"), "EventBus exposes feed shortage source")
	assertions.truthy(event_bus.has_signal("economy_notification_changed"), "EventBus exposes system-owned notification changes")

	var market = MarketSystemScript.new()
	assertions.truthy(market.configure([{
		"id": "wood", "base_price": 100, "initial_stock": 10,
		"target_stock": 10, "daily_liquidity": 10,
	}]), "event notification market fixture configures")
	market.last_settled_day = 4
	var system = NotificationSystemScript.new()
	tree.root.add_child(system)
	assertions.truthy(system.configure(event_bus, market), "notification system accepts real EventBus shapes")
	assertions.truthy(system.configure(event_bus, market), "repeated configure remains idempotent")
	event_bus.emit_signal("market_price_changed", "wood", 110)
	assertions.equal(system.get_recent().size(), 1, "ten-percent price event creates exactly one notification")
	assertions.equal(str(system.get_recent()[0].target_id), "wood", "price event uses stable market item target")
	event_bus.emit_signal("market_stock_changed", "wood", 3)
	event_bus.emit_signal("market_stock_changed", "wood", 8)
	assertions.equal(system.get_recent().size(), 3, "shortage and recovery are distinct notifications")
	event_bus.emit_signal("market_caravan_changed", "summer_caravan", true)
	event_bus.emit_signal("production_feed_shortage", null, "grain")
	assertions.equal(system.get_recent().size(), 5, "caravan and feed signals are subscribed")

	var real_clock_system = NotificationSystemScript.new()
	var real_id: String = real_clock_system.push("unlock", "解锁", "蓝图解锁", 4, "service", "barn")
	var real_merge_id: String = real_clock_system.push("unlock", "解锁", "配方解锁", 4, "service", "barn")
	assertions.equal(real_merge_id, real_id, "production default uses monotonic ticks for immediate merge")
	real_clock_system.free()
	system.free()
	market.free()


func _test_save_manager_round_trip_without_replay(assertions: TestAssert, tree: SceneTree) -> void:
	var market = MarketSystemScript.new()
	assertions.truthy(market.configure([{
		"id": "wood", "base_price": 100, "initial_stock": 10,
		"target_stock": 10, "daily_liquidity": 10,
	}]), "save notification market fixture configures")
	market.last_settled_day = 1
	var daily := FakeDailySimulation.new()
	var notifications = NotificationSystemScript.new()
	notifications.push("shortage", "库存紧缺", "木材紧缺", 1, "market_item", "wood", 1.0)
	var save_manager = SaveManagerScript.new()
	tree.root.add_child(save_manager)
	save_manager.save_directory = TEST_SAVE_DIR
	assertions.truthy(bool(save_manager.call("configure_economy", market, daily, null, null, null, null, null, null, null, notifications)), "SaveManager accepts notification owner")
	assertions.truthy(save_manager.save_game(TEST_SAVE_SLOT), "SaveManager persists notification bundle")
	var pushed_after_load := [0]
	notifications.notification_pushed.connect(func(_record: Dictionary, _merged: bool) -> void: pushed_after_load[0] += 1)
	notifications.push("recovery", "库存恢复", "木材恢复", 1, "market_item", "wood", 4.0)
	assertions.truthy(save_manager.load_game(TEST_SAVE_SLOT), "SaveManager restores notifications")
	assertions.equal(notifications.get_recent().size(), 1, "load restores persisted records")
	assertions.equal(pushed_after_load[0], 1, "load does not replay notification_pushed")

	var gathered: Dictionary = save_manager.call("_gather_save_data")
	assertions.truthy(gathered.has("notifications"), "economy v1 save includes notification field")
	var legacy := gathered.duplicate(true)
	legacy.erase("notifications")
	assertions.truthy(save_manager.call("_apply_save_data", legacy), "legacy economy v1 save defaults notifications")
	assertions.equal(notifications.get_recent().size(), 0, "legacy notification default is empty")
	var partial := {"notifications": gathered.notifications}
	assertions.truthy(not save_manager.call("_apply_save_data", partial), "notification field without economy bundle is rejected")
	assertions.equal(notifications.get_recent().size(), 0, "rejected partial save rolls back notifications")

	save_manager.clear_save(TEST_SAVE_SLOT)
	save_manager.free()
	notifications.free()
	daily.free()
	market.free()


func _test_scene_toasts_center_and_hud(assertions: TestAssert, tree: SceneTree) -> void:
	var system = NotificationSystemScript.new()
	var router := FakeRouter.new()
	assertions.truthy(ResourceLoader.exists(NOTIFICATION_UI_SCENE_PATH), "notification UI scene exists")
	if not ResourceLoader.exists(NOTIFICATION_UI_SCENE_PATH):
		system.free()
		router.free()
		return
	var ui: Variant = (load(NOTIFICATION_UI_SCENE_PATH) as PackedScene).instantiate()
	tree.root.add_child(router)
	tree.root.add_child(ui)
	await tree.process_frame
	assertions.truthy(ui.configure(system, router), "notification UI configures from authoritative system")
	for index in range(4):
		system.push("unlock", "解锁", "普通 %d" % index, 2, "service", "service_%d" % index, float(index) * 3.0)
	assertions.equal(ui.get_visible_toast_count(), 3, "toast stack shows at most three cards")
	for card in ui.get_node("ToastStack").get_children():
		assertions.equal(card.mouse_filter, Control.MOUSE_FILTER_PASS, "toast card passes mouse input")
	assertions.equal(ui.mouse_filter, Control.MOUSE_FILTER_IGNORE, "notification root does not block world outside cards")

	var ordinary_id: String = system.push("recovery", "恢复", "普通提醒", 2, "market_item", "wood", 20.0)
	ui.advance_toasts(2.999)
	assertions.truthy(ui.has_toast(ordinary_id), "ordinary toast remains before three seconds")
	ui.set_toast_hovered(ordinary_id, true)
	ui.advance_toasts(10.0)
	assertions.truthy(ui.has_toast(ordinary_id), "hover pauses toast timeout")
	ui.set_toast_hovered(ordinary_id, false)
	ui.advance_toasts(0.001)
	assertions.truthy(not ui.has_toast(ordinary_id), "ordinary toast expires at three seconds")

	var urgent_id: String = system.push("full", "产物已满", "风车仓库已满", 2, "building", "windmill:4:5", 24.0)
	ui.advance_toasts(5.999)
	assertions.truthy(ui.has_toast(urgent_id), "urgent toast remains before six seconds")
	ui.advance_toasts(0.001)
	assertions.truthy(not ui.has_toast(urgent_id), "urgent toast expires at six seconds")

	var target_id: String = system.push("order_due", "订单临期", "订单提醒", 2, "order", "npc:wood:2", 30.0)
	var unread_before: int = system.get_unread_count()
	assertions.truthy(ui.activate_notification(target_id), "target notification activates")
	assertions.equal(router.calls.size(), 1, "target click routes exactly once")
	assertions.equal(system.get_unread_count(), unread_before - 1, "target click marks read exactly once")
	assertions.truthy(not ui.activate_notification(target_id), "already-read activation is idempotent")
	assertions.equal(router.calls.size(), 1, "idempotent activation does not route twice")
	system.push("unlock", "次日解锁", "次日记录", 3, "service", "day3_service", 33.0)
	ui.show_center()
	assertions.truthy(ui.get_node("NotificationCenter").visible, "notification center can open")
	assertions.equal(ui.get_center_record_count(), system.get_recent().size(), "center renders system snapshot without duplicate state")
	assertions.truthy(ui.get_center_day_group_count() >= 2, "center groups records by game day")
	var invalid_target_id: String = system.push("order_due", "订单临期", "失效目标", 4, "order", "missing-order", 34.0)
	router.route_success = false
	var invalid_unread_before := system.get_unread_count()
	assertions.truthy(not ui.activate_notification(invalid_target_id), "failed route rejects activation")
	assertions.equal(system.get_unread_count(), invalid_unread_before, "failed route preserves unread state")
	router.route_success = true
	ui.mark_all_read()
	assertions.equal(system.get_unread_count(), 0, "center mark-all delegates to system")

	var hud = HudScene.instantiate()
	tree.root.add_child(hud)
	await tree.process_frame
	hud.configure_notifications(system)
	for index in range(11):
		system.push("full", "产物已满", "建筑 %d 已满" % index, 3, "building", "windmill:%d:0" % index, 40.0 + index * 3.0)
	assertions.equal(hud.notification_button.text, "[通知 9+]", "HUD caps unread badge visually at 9+")
	assertions.equal(hud.get_urgent_summary_count(), 3, "HUD shows two urgent summaries and one overflow")
	assertions.truthy(hud.get_urgent_summary_text(2).contains("还有 9 条"), "HUD overflow summarizes remaining urgent records")
	assertions.equal(hud.market_button.text, "[市场]", "HUD market action uses specified compact label")

	hud.free()
	ui.free()
	router.free()
	system.free()


func _test_main_four_way_routing(assertions: TestAssert) -> void:
	var main: Variant = MainScript.new()
	var shop := FakeShop.new()
	var economy = EconomySystemScript.new()
	var route_orders: Array[Dictionary] = [{"order_id": "order-1"}]
	var route_contracts: Array[Dictionary] = [{"contract_id": "contract-1"}]
	economy.set("_orders", route_orders)
	economy.set("_contracts", route_contracts)
	var market = MarketSystemScript.new()
	market.configure([{
		"id": "wood", "base_price": 100, "initial_stock": 10,
		"target_stock": 10, "daily_liquidity": 10,
	}])
	main.shop_ui = shop
	main.economy_system = economy
	main.market_system = market
	assertions.truthy(main.navigate_notification_target("market_item", "wood"), "market item target routes")
	assertions.truthy(main.navigate_notification_target("order", "order-1"), "order target routes")
	assertions.truthy(main.navigate_notification_target("contract", "contract-1"), "contract target routes")
	assertions.equal(shop.market_panel.selected_id, "wood", "market route selects target item")
	assertions.equal(shop.order_panel.selected_id, "order-1", "order route selects target record")
	assertions.equal(shop.contract_panel.selected_id, "contract-1", "contract route selects target record")

	var building_target := "windmill:4:5"
	var building_system := BuildingSystem.new()
	var building := BuildingInstance.new()
	building.authored_building_id = "windmill"
	building.grid_x = 4
	building.grid_z = 5
	var route_buildings: Array[BuildingInstance] = [building]
	building_system.set("_buildings", route_buildings)
	var building_ui := FakeBuildingUI.new()
	main.building_system = building_system
	main.building_economy_ui = building_ui
	var route_calls_before := shop.opened_tabs.size()
	assertions.truthy(main.is_valid_building_notification_target(building_target), "building target syntax routes through Main")
	assertions.truthy(main.navigate_notification_target("building", building_target), "building target routes")
	assertions.equal(building_ui.opened.size(), 1, "building route selects the target exactly once")
	assertions.truthy(not main.navigate_notification_target("market_item", "missing"), "invalid target is rejected")
	assertions.equal(shop.opened_tabs.size(), route_calls_before, "invalid target causes no UI state change")
	assertions.equal(main.notification_route_kind("building", building_target), "building", "building is the fourth route kind")

	market.free()
	economy.free()
	building_ui.free()
	building.free()
	building_system.free()
	shop.free()
	main.free()
