class_name OrderContractUITest
extends RefCounted

const ORDER_SCRIPT_PATH := "res://scripts/ui/order_panel.gd"
const CONTRACT_SCRIPT_PATH := "res://scripts/ui/contract_panel.gd"
const ORDER_SCENE_PATH := "res://scenes/ui/economy/order_panel.tscn"
const CONTRACT_SCENE_PATH := "res://scenes/ui/economy/contract_panel.tscn"
const SHOP_SCENE_PATH := "res://scenes/ui/shop_ui.tscn"
const HUD_SCENE_PATH := "res://scenes/ui/hud.tscn"
const EconomySystemScript = preload("res://scripts/systems/economy_system.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const MarketSystemScript = preload("res://scripts/systems/market_system.gd")
const NpcEconomySystemScript = preload("res://scripts/systems/npc_economy_system.gd")
const DailySimulationSystemScript = preload("res://scripts/systems/daily_simulation_system.gd")
const SaveManagerScript = preload("res://scripts/core/save_manager.gd")
const TEST_SAVE_DIR := "user://task15_order_contract_ui/"
const TEST_SAVE_SLOT := 15


func run(assertions: TestAssert, tree: SceneTree) -> void:
	_test_required_scripts_and_static_status(assertions)
	_test_contract_list_and_deadline_helpers(assertions)
	_test_scene_contracts(assertions)
	if not _resources_exist():
		return
	await _test_visible_selection_guards(assertions, tree)
	await _test_order_delivery_and_state(assertions, tree)
	await _test_contract_confirmation_and_delivery(assertions, tree)
	await _test_large_contract_ui_delivery(assertions, tree)
	await _test_same_day_real_save_load(assertions, tree)


func _resources_exist() -> bool:
	return (
		ResourceLoader.exists(ORDER_SCRIPT_PATH)
		and ResourceLoader.exists(CONTRACT_SCRIPT_PATH)
		and ResourceLoader.exists(ORDER_SCENE_PATH)
		and ResourceLoader.exists(CONTRACT_SCENE_PATH)
	)


func _test_required_scripts_and_static_status(assertions: TestAssert) -> void:
	assertions.truthy(ResourceLoader.exists(ORDER_SCRIPT_PATH), "order panel script exists")
	assertions.truthy(ResourceLoader.exists(CONTRACT_SCRIPT_PATH), "contract panel script exists")
	if not ResourceLoader.exists(ORDER_SCRIPT_PATH):
		return
	var script: Script = load(ORDER_SCRIPT_PATH)
	assertions.equal(script.call("status_for", {"completed": true}, 0, 2), "completed", "completed wins")
	assertions.equal(script.call("status_for", {"expires_day": 1}, 5, 2), "expired", "past deadline expires")
	assertions.equal(
		script.call("status_for", {"quantity": 5, "expires_day": 3}, 5, 2),
		"deliverable",
		"owned quantity enables delivery"
	)
	assertions.equal(
		script.call("status_for", {"quantity": 5, "expires_day": 3}, 2, 2),
		"accepted",
		"short inventory remains accepted"
	)


func _test_contract_list_and_deadline_helpers(assertions: TestAssert) -> void:
	if not ResourceLoader.exists(CONTRACT_SCRIPT_PATH):
		return
	var script: Script = load(CONTRACT_SCRIPT_PATH)
	assertions.truthy(script.has_method("list_section_for"), "contract panel exposes authoritative list classification")
	assertions.truthy(script.has_method("next_deadline_day"), "contract panel exposes next outstanding deadline")
	if not script.has_method("list_section_for") or not script.has_method("next_deadline_day"):
		return
	assertions.equal(script.call("list_section_for", {"signed": true, "completed": false, "expired": false, "start_day": 1}, 1), "active", "live signed contract stays active")
	assertions.equal(script.call("list_section_for", {"signed": true, "completed": true, "expired": false, "start_day": 1}, 1), "", "completed contract leaves active list")
	assertions.equal(script.call("list_section_for", {"signed": true, "completed": false, "expired": true, "start_day": 1}, 2), "", "expired contract leaves active list")
	assertions.equal(script.call("list_section_for", {"signed": false, "completed": false, "expired": false, "start_day": 1}, 2), "", "past-start unsigned contract leaves available list")
	var contract := {"start_day": 1, "end_day": 3, "delivered_days": [1]}
	assertions.equal(script.call("next_deadline_day", contract, 1), 2, "today's completed delivery advances the next deadline")
	contract["delivered_days"] = []
	assertions.equal(script.call("next_deadline_day", contract, 1), 1, "undelivered today remains the next deadline")
	contract["delivered_days"] = [1, 2, 3]
	assertions.equal(script.call("next_deadline_day", contract, 1), -1, "fully delivered contract has no next deadline")


func _test_scene_contracts(assertions: TestAssert) -> void:
	_check_scene(assertions, ORDER_SCENE_PATH, [
		"Columns/Filters/All",
		"Columns/Filters/Daily",
		"Columns/Filters/Urgent",
		"Columns/Filters/Event",
		"Columns/Filters/Construction",
		"Columns/Filters/Completed",
		"Columns/Orders/OrderScroll/OrderRows",
		"Columns/Orders/EmptyState",
		"Columns/Details/NpcLabel",
		"Columns/Details/TitleLabel",
		"Columns/Details/ItemLabel",
		"Columns/Details/OwnedLabel",
		"Columns/Details/DeadlineLabel",
		"Columns/Details/PremiumLabel",
		"Columns/Details/DetailLabel",
		"Columns/Details/ErrorLabel",
		"Columns/Details/DeliverButton",
	])
	_check_scene(assertions, CONTRACT_SCENE_PATH, [
		"Content/ActiveTitle",
		"Content/ActiveScroll/ActiveList",
		"Content/ActiveEmpty",
		"Content/AvailableTitle",
		"Content/AvailableScroll/AvailableList",
		"Content/AvailableEmpty",
		"Content/Details/DailyProgressLabel",
		"Content/Details/NextDeadlineLabel",
		"Content/Details/BreachesLabel",
		"Content/Details/TotalIncomeLabel",
		"Content/Details/ErrorLabel",
		"Content/Details/DeliveryQuantity",
		"Content/Details/SignButton",
		"Content/Details/DeliverButton",
	])
	var shop_scene := load(SHOP_SCENE_PATH) as PackedScene
	if shop_scene != null:
		var shop := shop_scene.instantiate()
		assertions.truthy(
			shop.has_node("ModalLayer/HubPanel/Margin/Shell/PageHost/OrderPanel"),
			"shop embeds the real order panel"
		)
		assertions.truthy(
			shop.has_node("ModalLayer/HubPanel/Margin/Shell/PageHost/ContractPanel"),
			"shop embeds the real contract panel"
		)
		assertions.truthy(
			shop.has_node("ModalLayer/SignConfirmationLayer"),
			"contract confirmation belongs to ShopUI ModalLayer"
		)
		shop.free()


func _check_scene(assertions: TestAssert, path: String, nodes: Array[String]) -> void:
	assertions.truthy(ResourceLoader.exists(path), "order/contract UI scene exists: %s" % path)
	if not ResourceLoader.exists(path):
		return
	var packed := load(path) as PackedScene
	assertions.truthy(packed != null, "order/contract UI scene loads: %s" % path)
	if packed == null:
		return
	var instance := packed.instantiate()
	for node_path in nodes:
		assertions.truthy(instance.has_node(node_path), "%s has %s" % [path, node_path])
	instance.free()


func _test_visible_selection_guards(assertions: TestAssert, tree: SceneTree) -> void:
	var game_state := tree.root.get_node_or_null("GameState")
	assertions.truthy(game_state != null, "selection guard integration uses the real GameState autoload")
	if game_state == null:
		return
	var game_state_snapshot := _snapshot_game_state(game_state)
	game_state.gold = 100
	var fixture := _fixture(game_state)
	var economy: EconomySystem = fixture.economy
	var inventory: InventorySystem = fixture.inventory
	var npc: NpcEconomySystem = fixture.npc
	for node in [fixture.market, npc, inventory, economy]:
		tree.root.add_child(node)
	var order_panel := (load(ORDER_SCENE_PATH) as PackedScene).instantiate()
	tree.root.add_child(order_panel)
	var contract_panel := (load(CONTRACT_SCENE_PATH) as PackedScene).instantiate()
	tree.root.add_child(contract_panel)
	await tree.process_frame
	assertions.truthy(order_panel.call("configure", economy, npc, inventory), "selection guard configures order panel")
	order_panel.call("set_filter", "urgent")
	order_panel.call("select_order", "tiejiang_zhang:iron_ore:1")
	order_panel.call("set_filter", "daily")
	var daily_orders: Array = order_panel.call("get_visible_orders")
	assertions.truthy(not daily_orders.is_empty(), "daily filter provides a visible replacement selection")
	assertions.truthy(order_panel.get("selected_order_id") != "tiejiang_zhang:iron_ore:1", "filter change drops a hidden urgent selection")
	if not daily_orders.is_empty():
		assertions.equal(order_panel.get("selected_order_id"), daily_orders[0].get("order_id", ""), "filter change selects the first visible row")
	var hidden_order_assets := {
		"gold": game_state.gold,
		"owned": inventory.get_item_count("iron_ore"),
		"npc": npc.get_npc_state("tiejiang_zhang").inventory.get("iron_ore", 0),
		"completed": _record_for(economy.get_orders(), "order_id", "tiejiang_zhang:iron_ore:1").completed,
	}
	order_panel.call("request_delivery", "tiejiang_zhang:iron_ore:1")
	assertions.equal({
		"gold": game_state.gold,
		"owned": inventory.get_item_count("iron_ore"),
		"npc": npc.get_npc_state("tiejiang_zhang").inventory.get("iron_ore", 0),
		"completed": _record_for(economy.get_orders(), "order_id", "tiejiang_zhang:iron_ore:1").completed,
	}, hidden_order_assets, "a hidden urgent order cannot be delivered from the daily section")
	order_panel.call("set_filter", "event")
	assertions.equal(order_panel.get("selected_order_id"), "", "empty order filter clears selection")
	assertions.equal(order_panel.get_node("Columns/Details/TitleLabel").text, "选择订单查看详情", "empty order filter clears detail")
	assertions.truthy(order_panel.get_node("Columns/Details/DeliverButton").disabled, "empty order filter disables delivery")

	assertions.truthy(contract_panel.call("configure", economy, inventory), "selection guard configures contract panel")
	contract_panel.call("select_contract", "lao_li:grain:1:3")
	var state := economy.to_dict()
	state.last_processed_day = 4
	for order in state.orders:
		if not bool(order.completed):
			order.expired = true
	var completed_contract: Dictionary = state.contracts[0]
	completed_contract.signed = true
	completed_contract.delivered_days = [1, 2, 3]
	completed_contract.breaches = 0
	completed_contract.completed = true
	completed_contract.expired = false
	var expired_contract := _second_contract()
	expired_contract.signed = true
	expired_contract.breaches = 3
	expired_contract.expired = true
	state.contracts.append(expired_contract)
	assertions.truthy(economy.from_dict(state), "completed and expired selection fixture restores")
	contract_panel.call("refresh_contracts")
	assertions.equal(contract_panel.get_node("Content/ActiveScroll/ActiveList").get_child_count(), 0, "completed and expired contracts leave the active section")
	assertions.equal(contract_panel.get_node("Content/AvailableScroll/AvailableList").get_child_count(), 0, "completed and expired contracts leave the available section")
	assertions.equal(contract_panel.get("selected_contract_id"), "", "refresh clears a contract that no longer belongs to a visible section")
	assertions.equal(contract_panel.get_node("Content/Details/TitleLabel").text, "选择合同查看详情", "hidden contract refresh clears detail")
	assertions.truthy(contract_panel.get_node("Content/Details/SignButton").disabled, "hidden contract refresh disables signing")
	assertions.truthy(contract_panel.get_node("Content/Details/DeliverButton").disabled, "hidden contract refresh disables delivery")
	contract_panel.free()
	order_panel.free()
	_free_fixture_from_tree(fixture, tree)
	_restore_game_state(game_state, game_state_snapshot)


func _test_order_delivery_and_state(assertions: TestAssert, tree: SceneTree) -> void:
	var game_state := tree.root.get_node_or_null("GameState")
	assertions.truthy(game_state != null, "order acceptance uses the real GameState autoload")
	if game_state == null:
		return
	var game_state_snapshot := _snapshot_game_state(game_state)
	game_state.gold = 100
	var fixture := _fixture(game_state)
	var economy: EconomySystem = fixture.economy
	var inventory: InventorySystem = fixture.inventory
	var npc: NpcEconomySystem = fixture.npc
	for node in [fixture.market, npc, inventory, economy]:
		tree.root.add_child(node)
	var hud := (load(HUD_SCENE_PATH) as PackedScene).instantiate()
	tree.root.add_child(hud)
	var panel := (load(ORDER_SCENE_PATH) as PackedScene).instantiate()
	tree.root.add_child(panel)
	await tree.process_frame
	assertions.truthy(panel.call("configure", economy, npc, inventory), "order panel configures real systems")
	assertions.truthy(panel.call("configure", economy, npc, inventory), "order panel reconfigure is idempotent")
	var event_bus := tree.root.get_node_or_null("EventBus")
	if event_bus != null:
		assertions.equal(_connection_count(event_bus, "order_updated", panel), 1, "reconfigure keeps one order signal connection")
	panel.call("set_filter", "urgent")
	panel.call("select_order", "tiejiang_zhang:iron_ore:1")
	var snapshot: Array = panel.call("get_visible_orders")
	assertions.equal(snapshot.size(), 1, "urgent filter shows the stable urgent order")
	var order := _record_for(economy.get_orders(), "order_id", "tiejiang_zhang:iron_ore:1")
	var order_quantity := int(order.get("quantity", 0))
	var order_reward := int(order.get("reward_gold", 0))
	if not snapshot.is_empty():
		snapshot[0]["quantity"] = 999
	assertions.equal(_record_for(economy.get_orders(), "order_id", "tiejiang_zhang:iron_ore:1").quantity, order_quantity, "panel snapshots cannot mutate economy records")
	assertions.truthy(panel.get_node("Columns/Details/NpcLabel").text.contains("铁匠"), "order detail shows NPC identity")
	assertions.truthy(panel.get_node("Columns/Details/ItemLabel").text.contains("铁矿"), "order detail shows requested item")
	assertions.truthy(panel.get_node("Columns/Details/OwnedLabel").text.contains("%d/%d" % [order_quantity, order_quantity]), "order detail shows requested and owned quantity")
	assertions.truthy(panel.get_node("Columns/Details/DetailLabel").text.contains("缺少"), "order detail uses a real shortage reason")
	assertions.truthy(inventory.remove_item("iron_ore", 1), "failed-order fixture removes one required item")
	var failed_order_assets := {
		"gold": fixture.wallet.gold,
		"owned": inventory.get_item_count("iron_ore"),
		"npc": npc.get_npc_state("tiejiang_zhang").inventory.get("iron_ore", 0),
	}
	panel.call("request_delivery", "tiejiang_zhang:iron_ore:1")
	assertions.equal(fixture.wallet.gold, failed_order_assets.gold, "failed order preserves gold")
	assertions.equal(inventory.get_item_count("iron_ore"), failed_order_assets.owned, "failed order preserves player inventory")
	assertions.equal(npc.get_npc_state("tiejiang_zhang").inventory.get("iron_ore", 0), failed_order_assets.npc, "failed order preserves NPC inventory")
	assertions.truthy(panel.get_node("Columns/Details/ErrorLabel").text.contains("缺少铁矿 ×1"), "failed order shows the exact shortage reason")
	assertions.truthy(inventory.add_item("iron_ore", 1), "order fixture restores the required item")
	var gold_before: int = int(fixture.wallet.gold)
	var npc_before := int(npc.get_npc_state("tiejiang_zhang").inventory.get("iron_ore", 0))
	panel.call("request_delivery", "tiejiang_zhang:iron_ore:1")
	assertions.equal(inventory.get_item_count("iron_ore"), 0, "order delivery removes player inventory in the same frame")
	assertions.equal(int(npc.get_npc_state("tiejiang_zhang").inventory.get("iron_ore", 0)), npc_before + order_quantity, "order delivery updates real NPC inventory")
	assertions.equal(fixture.wallet.gold, gold_before + order_reward, "order delivery updates wallet once")
	assertions.equal(hud.get_node("TopBar/StatusRow/GoldLabel").text, "💰 %d" % (gold_before + order_reward), "real gold_changed updates HUD in the delivery frame")
	assertions.equal(_record_for(economy.get_orders(), "order_id", "tiejiang_zhang:iron_ore:1").completed, true, "order row follows authoritative completed state")
	assertions.truthy(_combined_text(panel.get_node("Columns/Orders/OrderScroll/OrderRows")).contains("已完成"), "order row refreshes completed state")
	assertions.equal(hud.get_node("EconomyActions/NotificationButton").text, "通知 1", "successful order adds one unread HUD notification")
	panel.call("request_delivery", "tiejiang_zhang:iron_ore:1")
	assertions.equal(fixture.wallet.gold, gold_before + order_reward, "duplicate order click cannot pay twice")
	assertions.equal(hud.get_node("EconomyActions/NotificationButton").text, "通知 1", "duplicate order click adds no unread notification")
	assertions.truthy(panel.get_node("Columns/Details/ErrorLabel").text.contains("已完成"), "failed repeat delivery shows exact completed reason")
	assertions.equal(panel.get("selected_filter"), "urgent", "order filter survives refresh")
	assertions.equal(panel.get("selected_order_id"), "tiejiang_zhang:iron_ore:1", "order stable selection survives refresh")
	panel.free()
	hud.free()
	_free_fixture_from_tree(fixture, tree)
	_restore_game_state(game_state, game_state_snapshot)


func _test_contract_confirmation_and_delivery(assertions: TestAssert, tree: SceneTree) -> void:
	var game_state := tree.root.get_node_or_null("GameState")
	assertions.truthy(game_state != null, "contract acceptance uses the real GameState autoload")
	if game_state == null:
		return
	var game_state_snapshot := _snapshot_game_state(game_state)
	game_state.gold = 100
	var fixture := _fixture(game_state)
	var economy: EconomySystem = fixture.economy
	var inventory: InventorySystem = fixture.inventory
	var npc: NpcEconomySystem = fixture.npc
	for node in [fixture.market, npc, inventory, economy]:
		tree.root.add_child(node)
	var hud := (load(HUD_SCENE_PATH) as PackedScene).instantiate()
	tree.root.add_child(hud)
	var shop := (load(SHOP_SCENE_PATH) as PackedScene).instantiate()
	tree.root.add_child(shop)
	await tree.process_frame
	assertions.truthy(
		shop.call("configure", inventory, economy, fixture.market, null, null, null, npc),
		"shop configures order and contract dependencies"
	)
	shop.call("select_tab", "orders")
	var order_panel := shop.get_node("ModalLayer/HubPanel/Margin/Shell/PageHost/OrderPanel")
	order_panel.call("set_filter", "urgent")
	order_panel.call("select_order", "tiejiang_zhang:iron_ore:1")
	shop.call("select_tab", "contracts")
	shop.call("select_tab", "orders")
	assertions.equal(order_panel.get("selected_filter"), "urgent", "order filter survives a tab round trip")
	assertions.equal(order_panel.get("selected_order_id"), "tiejiang_zhang:iron_ore:1", "order selection survives a tab round trip")
	shop.call("open", "contracts")
	assertions.truthy(tree.paused, "contract page remains interactive while economy hub pauses")
	var panel := shop.get_node("ModalLayer/HubPanel/Margin/Shell/PageHost/ContractPanel")
	panel.call("select_contract", "lao_li:grain:1:3")
	panel.call("request_sign", "lao_li:grain:1:3")
	assertions.truthy(shop.get_node("ModalLayer/SignConfirmationLayer").visible, "signing opens exactly one ShopUI confirmation")
	assertions.equal((economy.get_contracts() as Array)[0].signed, false, "sign request alone creates no obligation")
	shop.call("confirm_contract_sign")
	assertions.equal((economy.get_contracts() as Array)[0].signed, true, "confirmed signing creates one cross-day obligation")
	assertions.truthy(not shop.get_node("ModalLayer/SignConfirmationLayer").visible, "successful confirmation closes")
	var gold_before: int = int(fixture.wallet.gold)
	var npc_before := int(npc.get_npc_state("lao_li").inventory.get("grain", 0))
	var pre_delivery_assets := _assets(fixture)
	panel.call("request_delivery", "lao_li:grain:1:3", 9223372036854775807)
	assertions.equal(_assets(fixture), pre_delivery_assets, "extreme pre-delivery quantity changes no assets")
	assertions.truthy(panel.get_node("Content/Details/ErrorLabel").text.contains("每日必须交付 5"), "extreme pre-delivery quantity shows the exact bound")
	panel.call("request_delivery", "lao_li:grain:1:3", 5)
	assertions.truthy(not shop.get_node("ModalLayer/SignConfirmationLayer").visible, "daily delivery never opens confirmation")
	assertions.equal(inventory.get_item_count("grain"), 0, "contract delivery removes one authoritative daily quantity")
	assertions.equal(int(npc.get_npc_state("lao_li").inventory.get("grain", 0)), npc_before + 5, "contract delivery updates real NPC inventory")
	assertions.equal(fixture.wallet.gold, gold_before + 50, "contract daily delivery pays once")
	assertions.equal(hud.get_node("TopBar/StatusRow/GoldLabel").text, "💰 %d" % (gold_before + 50), "real contract gold_changed updates HUD in the delivery frame")
	assertions.equal(hud.get_node("EconomyActions/NotificationButton").text, "通知 1", "successful contract delivery adds one unread HUD notification")
	assertions.truthy(panel.get_node("Content/Details/DailyProgressLabel").text.contains("5/5"), "contract row refreshes today's progress")
	var assets_after := _assets(fixture)
	panel.call("request_delivery", "lao_li:grain:1:3", 9223372036854775807)
	assertions.equal(_assets(fixture), assets_after, "extreme contract quantity changes no assets")
	assertions.truthy(panel.get_node("Content/Details/ErrorLabel").text.contains("今日已交付"), "same-day repeat has an exact reason")
	assertions.equal(hud.get_node("EconomyActions/NotificationButton").text, "通知 1", "repeat contract delivery adds no unread notification")

	# A stale confirmation must not sign a changed authoritative snapshot.
	var state := economy.to_dict()
	state.contracts.append(_second_contract())
	assertions.truthy(economy.from_dict(state), "second available contract fixture restores")
	panel.call("refresh_contracts")
	panel.call("request_sign", "xiao_hua:honey:1:3")
	assertions.truthy(economy.sign_contract("xiao_hua:honey:1:3"), "authoritative contract changes before confirmation")
	shop.call("confirm_contract_sign")
	assertions.equal(_record_for(economy.get_contracts(), "contract_id", "xiao_hua:honey:1:3").signed, true, "stale confirmation cannot mutate the externally signed contract")
	assertions.truthy(panel.get_node("Content/Details/ErrorLabel").text.contains("状态已变化"), "stale confirmation explains exact reason")
	shop.call("close")
	assertions.truthy(not tree.paused, "contract hub restores pause state")
	shop.free()
	hud.free()
	_free_fixture_from_tree(fixture, tree)
	_restore_game_state(game_state, game_state_snapshot)


func _test_same_day_real_save_load(assertions: TestAssert, tree: SceneTree) -> void:
	_cleanup_test_save()
	var game_state := tree.root.get_node_or_null("GameState")
	assertions.truthy(game_state != null, "SaveManager acceptance uses the real GameState autoload")
	if game_state == null:
		return
	var game_state_snapshot := _snapshot_game_state(game_state)
	game_state.gold = 100
	var fixture := _fixture(game_state)
	var economy: EconomySystem = fixture.economy
	var inventory: InventorySystem = fixture.inventory
	var manager := SaveManagerScript.new()
	manager.save_directory = TEST_SAVE_DIR
	var daily := DailySimulationSystemScript.new()
	daily.last_simulated_day = 1
	for node in [fixture.market, fixture.npc, inventory, economy, daily, manager]:
		tree.root.add_child(node)
	assertions.truthy(
		manager.configure_economy(fixture.market, daily, null, null, fixture.npc, economy),
		"real SaveManager path configures order and contract state"
	)
	assertions.truthy(economy.sign_contract("lao_li:grain:1:3"), "same-day load fixture signs once")
	assertions.truthy(economy.deliver_contract("lao_li:grain:1:3", 5), "same-day load fixture delivers once")
	assertions.truthy(manager.save_game(TEST_SAVE_SLOT), "real SaveManager path saves delivered contract")
	var assets_before := _assets(fixture)
	var contract_before := _record_for(economy.get_contracts(), "contract_id", "lao_li:grain:1:3")
	assertions.truthy(manager.load_game(TEST_SAVE_SLOT), "real SaveManager path loads once on the same day")
	assertions.truthy(manager.load_game(TEST_SAVE_SLOT), "real SaveManager path can reload the same day")
	var contract_after := _record_for(economy.get_contracts(), "contract_id", "lao_li:grain:1:3")
	assertions.equal(contract_after.get("delivered_days", []), contract_before.get("delivered_days", []), "same-day load adds no delivery payment record")
	assertions.equal(contract_after.get("breaches", -1), contract_before.get("breaches", -2), "same-day load adds no breach")
	assertions.equal(_assets(fixture), assets_before, "same-day load adds no payment or item transfer")
	var panel := (load(CONTRACT_SCENE_PATH) as PackedScene).instantiate()
	tree.root.add_child(panel)
	await tree.process_frame
	assertions.truthy(panel.call("configure", economy, inventory), "reloaded contract panel configures from real state")
	panel.call("select_contract", "lao_li:grain:1:3")
	panel.call("request_delivery", "lao_li:grain:1:3", 5)
	assertions.equal(_assets(fixture), assets_before, "reloaded UI cannot duplicate same-day payment")
	assertions.truthy(panel.get_node("Content/Details/ErrorLabel").text.contains("今日已交付"), "reloaded UI shows exact same-day reason")
	panel.free()
	for node in [manager, daily]:
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()
	_free_fixture_from_tree(fixture, tree)
	_cleanup_test_save()
	_restore_game_state(game_state, game_state_snapshot)


func _test_large_contract_ui_delivery(assertions: TestAssert, tree: SceneTree) -> void:
	var game_state := tree.root.get_node_or_null("GameState")
	assertions.truthy(game_state != null, "large contract acceptance uses the real GameState autoload")
	if game_state == null:
		return
	var game_state_snapshot := _snapshot_game_state(game_state)
	game_state.gold = 100
	var fixture := _fixture(game_state)
	var economy: EconomySystem = fixture.economy
	var inventory: InventorySystem = fixture.inventory
	var npc: NpcEconomySystem = fixture.npc
	assertions.truthy(inventory.remove_item("grain", 5), "large contract fixture clears the small grain stack")
	assertions.truthy(inventory.add_item("grain", 1000), "large contract fixture owns 1,000 grain across slots")
	var state := economy.to_dict()
	state.contracts = [_large_contract_record()]
	assertions.truthy(economy.from_dict(state), "legacy 1,000-unit contract restores")
	for node in [fixture.market, npc, inventory, economy]:
		tree.root.add_child(node)
	var hud := (load(HUD_SCENE_PATH) as PackedScene).instantiate()
	tree.root.add_child(hud)
	var panel := (load(CONTRACT_SCENE_PATH) as PackedScene).instantiate()
	tree.root.add_child(panel)
	await tree.process_frame
	assertions.truthy(panel.call("configure", economy, inventory), "large contract configures the real panel")
	panel.call("select_contract", "lao_li:grain:1:3")
	assertions.equal(panel.get_node("Content/Details/DeliveryQuantity").value, 1000.0, "1,000-unit authoritative quantity remains selectable")
	assertions.truthy(not panel.get_node("Content/Details/DeliverButton").disabled, "owned 1,000-unit contract is visibly deliverable")
	var gold_before := int(game_state.gold)
	var npc_before := int(npc.get_npc_state("lao_li").inventory.get("grain", 0))
	panel.call("request_delivery", "lao_li:grain:1:3", 1000)
	assertions.equal(inventory.get_item_count("grain"), 0, "large contract removes all 1,000 items once")
	assertions.equal(int(npc.get_npc_state("lao_li").inventory.get("grain", 0)), npc_before + 1000, "large contract transfers all 1,000 items once")
	assertions.equal(game_state.gold, gold_before + 1000, "large contract pays the real wallet once")
	assertions.equal(hud.get_node("TopBar/StatusRow/GoldLabel").text, "💰 %d" % (gold_before + 1000), "large contract updates HUD gold in the delivery frame")
	assertions.equal(hud.get_node("EconomyActions/NotificationButton").text, "通知 1", "large contract adds one unread notification")
	panel.call("request_delivery", "lao_li:grain:1:3", 1000)
	assertions.equal(game_state.gold, gold_before + 1000, "large contract repeat cannot pay twice")
	assertions.equal(hud.get_node("EconomyActions/NotificationButton").text, "通知 1", "large contract repeat adds no unread notification")
	panel.free()
	hud.free()
	_free_fixture_from_tree(fixture, tree)
	_restore_game_state(game_state, game_state_snapshot)


func _fixture(wallet: Node) -> Dictionary:
	var market := MarketSystemScript.new()
	market.configure([
		_definition("iron_ore", 10),
		_definition("grain", 10),
		_definition("honey", 20),
	])
	var npc := NpcEconomySystemScript.new()
	npc.configure(market, [
		_profile("tiejiang_zhang", "铁匠张", {"iron_ore": 10}),
		_profile("lao_li", "老李", {"grain": 5}),
		_profile("xiao_hua", "小花", {"honey": 2}),
	], [])
	var inventory := InventorySystemScript.new()
	inventory.add_item("iron_ore", 10)
	inventory.add_item("grain", 5)
	var economy := EconomySystemScript.new()
	economy.configure(inventory, wallet, market, npc)
	market.settle_day(1)
	npc.sync_daily_cursor(1)
	economy.advance_order_deadlines(1)
	economy.generate_demand_orders(1)
	var state := economy.to_dict()
	state.contracts.append(_contract_record())
	economy.from_dict(state)
	return {
		"market": market,
		"npc": npc,
		"inventory": inventory,
		"wallet": wallet,
		"economy": economy,
	}


func _definition(item_id: String, price: int) -> Dictionary:
	return {
		"id": item_id,
		"base_price": price,
		"initial_stock": 20,
		"target_stock": 20,
		"daily_liquidity": 10,
	}


func _profile(npc_id: String, display_name: String, targets: Dictionary) -> Dictionary:
	return {
		"id": npc_id,
		"display_name": display_name,
		"gold": 0,
		"inventory": {},
		"essential_targets": {},
		"reserve_targets": targets,
		"production_recipes": [],
		"sale_targets": {},
		"investment_gold_threshold": 1000,
		"import_buffer": false,
	}


func _contract_record() -> Dictionary:
	return {
		"contract_id": "lao_li:grain:1:3",
		"npc_id": "lao_li",
		"item_id": "grain",
		"quantity_per_day": 5,
		"unit_price": 10,
		"reward_gold": 50,
		"start_day": 1,
		"end_day": 3,
		"delivered_days": [],
		"breaches": 0,
		"signed": false,
		"completed": false,
		"expired": false,
	}


func _second_contract() -> Dictionary:
	return {
		"contract_id": "xiao_hua:honey:1:3",
		"npc_id": "xiao_hua",
		"item_id": "honey",
		"quantity_per_day": 2,
		"unit_price": 20,
		"reward_gold": 40,
		"start_day": 1,
		"end_day": 3,
		"delivered_days": [],
		"breaches": 0,
		"signed": false,
		"completed": false,
		"expired": false,
	}


func _large_contract_record() -> Dictionary:
	return {
		"contract_id": "lao_li:grain:1:3",
		"npc_id": "lao_li",
		"item_id": "grain",
		"quantity_per_day": 1000,
		"unit_price": 1,
		"reward_gold": 1000,
		"start_day": 1,
		"end_day": 3,
		"delivered_days": [],
		"breaches": 0,
		"signed": true,
		"completed": false,
		"expired": false,
	}


func _assets(fixture: Dictionary) -> Dictionary:
	return {
		"gold": fixture.wallet.gold,
		"grain": fixture.inventory.get_item_count("grain"),
		"npc_grain": fixture.npc.get_npc_state("lao_li").inventory.get("grain", 0),
	}


func _record_for(records: Array, field: String, record_id: String) -> Dictionary:
	for record in records:
		if record is Dictionary and str(record.get(field, "")) == record_id:
			return record
	return {}


func _connection_count(event_bus: Node, signal_name: String, target: Object) -> int:
	var count := 0
	for connection in event_bus.get_signal_connection_list(signal_name):
		var callable: Callable = connection.get("callable", Callable())
		if callable.is_valid() and callable.get_object() == target:
			count += 1
	return count


func _cleanup_test_save() -> void:
	var path := TEST_SAVE_DIR.path_join("save_%d.json" % TEST_SAVE_SLOT)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var directory := TEST_SAVE_DIR.trim_suffix("/")
	if DirAccess.dir_exists_absolute(directory):
		DirAccess.remove_absolute(directory)


func _combined_text(node: Node) -> String:
	var result: String = str(node.text) if node is Label or node is Button else ""
	for child in node.get_children():
		result += _combined_text(child)
	return result


func _free_fixture_from_tree(fixture: Dictionary, tree: SceneTree) -> void:
	for key in ["economy", "inventory", "npc", "market"]:
		var node: Node = fixture[key]
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()


func _snapshot_game_state(game_state: Node) -> Dictionary:
	return {
		"gold": game_state.gold,
		"play_time": game_state.play_time,
		"stamina": game_state.player_state.stamina,
		"max_stamina": game_state.player_state.max_stamina,
		"level": game_state.player_state.level,
		"exp": game_state.player_state.exp,
	}


func _restore_game_state(game_state: Node, snapshot: Dictionary) -> void:
	game_state.gold = snapshot.gold
	game_state.play_time = snapshot.play_time
	game_state.player_state.stamina = snapshot.stamina
	game_state.player_state.max_stamina = snapshot.max_stamina
	game_state.player_state.level = snapshot.level
	game_state.player_state.exp = snapshot.exp
