class_name EconomyUIIntegrationTest
extends RefCounted

const MainScript := preload("res://scripts/main.gd")
const GameDataScript := preload("res://scripts/core/game_data.gd")
const MarketSystemScript := preload("res://scripts/systems/market_system.gd")
const EconomySystemScript := preload("res://scripts/systems/economy_system.gd")
const InventorySystemScript := preload("res://scripts/systems/inventory_system.gd")
const FarmStorageSystemScript := preload("res://scripts/systems/farm_storage_system.gd")
const ItemContainerRouterScript := preload("res://scripts/systems/item_container_router.gd")
const NpcEconomySystemScript := preload("res://scripts/systems/npc_economy_system.gd")
const ProductionSystemScript := preload("res://scripts/systems/production_system.gd")
const ProgressionSystemScript := preload("res://scripts/systems/economy_progression_system.gd")
const NotificationSystemScript := preload("res://scripts/systems/economy_notification_system.gd")
const ProducerStateScript := preload("res://scripts/data/producer_state.gd")
const GridSystemScript := preload("res://scripts/systems/grid_system.gd")
const FarmingSystemScript := preload("res://scripts/systems/farming_system.gd")
const ToolSystemScript := preload("res://scripts/systems/tool_system.gd")
const ModalCoordinatorScript := preload("res://scripts/ui/economy_modal_coordinator.gd")
const ShopScene := preload("res://scenes/ui/shop_ui.tscn")
const HudScene := preload("res://scenes/ui/hud.tscn")
const BuildingEconomyScene := preload("res://scenes/ui/economy/building_economy_ui.tscn")
const NotificationScene := preload("res://scenes/ui/economy/economy_notification_ui.tscn")
const ServiceScene := preload("res://scenes/ui/economy/service_panel.tscn")


class FixedDaySource:
	extends RefCounted
	var total_days := 8


func run(assertions: TestAssert, tree: SceneTree) -> void:
	await _test_market_refresh_is_hidden_gated_and_visible_coalesced(assertions, tree)
	await _test_order_contract_hidden_refresh_waits_for_shop_entry(assertions, tree)
	await _test_visible_order_refreshes_are_coalesced(assertions, tree)
	await _test_visible_contract_refreshes_are_coalesced(assertions, tree)
	await _test_main_owned_routing_contract(assertions, tree)
	await _test_hud_market_sale_and_large_confirmation(assertions, tree)
	await _test_order_delivery_updates_every_authority(assertions, tree)
	await _test_contract_sign_delivery_reload_is_idempotent(assertions, tree)
	await _test_order_contract_panels_follow_farm_storage(assertions, tree)
	await _test_market_panel_follows_routed_storage(assertions, tree)
	await _test_windmill_flour_flow(assertions, tree)
	await _test_coop_feed_egg_flow(assertions, tree)
	await _test_waterwheel_overlay_lifecycle(assertions, tree)
	await _test_blueprint_service_is_idempotent(assertions, tree)
	await _test_merged_notifications_navigate_to_target(assertions, tree)
	await _test_every_modal_restores_original_pause(assertions, tree)


func _test_market_refresh_is_hidden_gated_and_visible_coalesced(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var game_state := tree.root.get_node("GameState")
	var saved := _snapshot_wallet(game_state)
	var original_pause := tree.paused
	game_state.gold = 1000
	var inventory := InventorySystemScript.new() as InventorySystem
	var market := MarketSystemScript.new() as MarketSystem
	var economy := EconomySystemScript.new() as EconomySystem
	for node in [inventory, market, economy]:
		tree.root.add_child(node)
	assertions.truthy(
		market.configure([
			_market_definition("grain", 10, 20, 20, 10),
			_market_definition("grain_seed", 4, 20, 20, 10),
		]),
		"market refresh-gating fixture configures the real market"
	)
	assertions.truthy(
		economy.configure(inventory, game_state, market),
		"market refresh-gating fixture configures the real economy"
	)
	assertions.truthy(
		inventory.add_item("grain_seed", 3),
		"market refresh-gating fixture owns tradable seeds"
	)
	var shop := ShopScene.instantiate()
	tree.root.add_child(shop)
	await tree.process_frame
	assertions.truthy(shop.configure(inventory, economy, market), "market refresh-gating fixture configures real ShopUI")
	shop.open("market")
	shop.market_panel.select_category("crops")
	shop.market_panel.select_item("grain_seed")
	await tree.process_frame
	var panel: MarketPanel = shop.market_panel
	var trade: TradePanel = panel.trade_panel
	var hidden_row_ids: Array[int] = _market_row_instance_ids(panel)
	var hidden_quote: String = str(trade.player_quantity_label.text)
	shop.close()
	assertions.truthy(inventory.remove_item("grain_seed", 1), "hidden ShopUI mutation emits real inventory removal")
	await tree.process_frame
	assertions.equal(
		_market_row_instance_ids(panel),
		hidden_row_ids,
		"hidden market keeps existing row instances until its authoritative refresh entry point"
	)
	assertions.equal(
		trade.player_quantity_label.text,
		hidden_quote,
		"hidden trade panel keeps its existing quote until visible"
	)
	shop.open("market")
	await tree.process_frame
	var reopened_seed_row := _find_meta_control(panel.item_rows, "item_id", "grain_seed")
	assertions.equal(
		int(reopened_seed_row.get_meta("owned", -1)),
		2,
		"reopened market page reads the authoritative seed quantity"
	)
	assertions.equal(trade.player_quantity_label.text, "2", "reopened market reads the authoritative seed quantity")

	var visible_row_ids: Array[int] = _market_row_instance_ids(panel)
	var entered_row_ids: Array[int] = []
	var row_enter_callback := func(child: Node) -> void:
		if child.has_meta("item_id"):
			entered_row_ids.append(child.get_instance_id())
	panel.item_rows.child_entered_tree.connect(row_enter_callback)
	assertions.truthy(inventory.add_item("grain_seed", 2), "visible coalescing fixture adds seeds")
	assertions.truthy(inventory.remove_item("grain_seed", 1), "visible coalescing fixture removes seeds")
	assertions.equal(
		_market_row_instance_ids(panel),
		visible_row_ids,
		"same-frame authority changes do not rebuild market rows before the deferred frame"
	)
	await tree.process_frame
	assertions.equal(
		entered_row_ids.size(),
		visible_row_ids.size(),
		"same-frame authority changes perform one complete market-row rebuild"
	)
	assertions.equal(trade.player_quantity_label.text, "3", "coalesced trade quote reads the final authoritative quantity")
	panel.apply_responsive_layout(Vector2(800, 720))
	panel.open_details_drawer()
	assertions.truthy(
		trade.get_parent() == panel.narrow_detail_stack and trade.is_visible_in_tree(),
		"narrow drawer reparents the real visible trade panel into the detail stack"
	)
	game_state.gold = 0
	(tree.root.get_node("EventBus") as Node).gold_changed.emit(0)
	assertions.truthy(
		not trade.buy_button.disabled,
		"same-frame narrow reparent fixture keeps the prior quote before deferred consumption"
	)
	panel.apply_responsive_layout(Vector2(1920, 1080))
	assertions.truthy(
		trade.get_parent() == panel.columns and trade.is_visible_in_tree(),
		"three-column responsive transition reparents the real trade panel back into columns"
	)
	await tree.process_frame
	assertions.truthy(trade.buy_button.disabled, "reparented trade consumes the pending gold quote exactly once")
	assertions.truthy(
		trade.buy_button.tooltip_text.contains("金币不足"),
		"reparented trade exposes the final insufficient-gold reason"
	)
	game_state.gold = 1000
	(tree.root.get_node("EventBus") as Node).gold_changed.emit(1000)
	await tree.process_frame
	assertions.truthy(not trade.buy_button.disabled, "visible trade starts buyable before the responsive hidden-state mutation")
	panel.apply_responsive_layout(Vector2(1000, 720))
	assertions.truthy(not trade.visible, "drawer catalog layout hides the real trade panel")
	game_state.gold = 0
	(tree.root.get_node("EventBus") as Node).gold_changed.emit(0)
	await tree.process_frame
	assertions.truthy(
		not trade.buy_button.disabled,
		"hidden responsive trade keeps its prior buy quote until it is shown"
	)
	panel.apply_responsive_layout(Vector2(1920, 1080))
	assertions.truthy(trade.visible, "three-column layout shows the real trade panel again")
	await tree.process_frame
	assertions.truthy(trade.buy_button.disabled, "shown trade consumes the pending gold quote")
	assertions.truthy(
		trade.buy_button.tooltip_text.contains("金币不足"),
		"shown trade exposes the refreshed insufficient-gold reason"
	)
	if panel.item_rows.child_entered_tree.is_connected(row_enter_callback):
		panel.item_rows.child_entered_tree.disconnect(row_enter_callback)
	shop.close()
	tree.paused = original_pause
	_free_nodes([shop, economy, market, inventory])
	_restore_wallet(game_state, saved)


func _test_order_contract_hidden_refresh_waits_for_shop_entry(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var game_state: Node = tree.root.get_node("GameState")
	var saved: Dictionary = _snapshot_wallet(game_state)
	var fixture: Dictionary = _order_contract_fixture(game_state)
	for node in [
		fixture.market, fixture.npc, fixture.inventory, fixture.storage,
		fixture.router, fixture.economy,
	]:
		tree.root.add_child(node)
	var shop: ShopUI = ShopScene.instantiate()
	tree.root.add_child(shop)
	await tree.process_frame
	assertions.truthy(
		shop.configure(fixture.inventory, fixture.economy, fixture.market, null, null, null, fixture.npc),
		"order-contract hidden-refresh fixture configures real ShopUI"
	)
	assertions.truthy(
		fixture.economy.sign_contract("lao_li:grain:1:3"),
		"order-contract hidden-refresh fixture signs the real grain contract"
	)
	shop.open("orders")
	shop.order_panel.select_order("tiejiang_zhang:iron_ore:1")
	var order_row_ids: Array[int] = _order_row_instance_ids(shop.order_panel)
	assertions.truthy(not order_row_ids.is_empty(), "orders page creates real identified order rows")
	shop.select_tab("contracts")
	shop.contract_panel.select_contract("lao_li:grain:1:3")
	var contract_row_ids: Array[int] = _contract_row_instance_ids(shop.contract_panel)
	assertions.truthy(not contract_row_ids.is_empty(), "contracts page creates real identified contract rows")
	shop.close()
	assertions.truthy(
		fixture.inventory.remove_item("iron_ore", 1),
		"hidden order mutation emits a real inventory removal"
	)
	assertions.truthy(
		fixture.storage.remove_items({"grain": 5}),
		"hidden contract mutation emits a real farm-storage change"
	)
	await tree.process_frame
	assertions.equal(
		_order_row_instance_ids(shop.order_panel),
		order_row_ids,
		"hidden orders keep existing real row instances until ShopUI reopens them"
	)
	assertions.equal(
		_contract_row_instance_ids(shop.contract_panel),
		contract_row_ids,
		"hidden contracts keep existing real row instances until ShopUI reopens them"
	)
	shop.open("orders")
	shop.order_panel.select_order("tiejiang_zhang:iron_ore:1")
	assertions.equal(shop.order_panel.owned_label.text, "持有：9/10", "reopened orders read authoritative inventory ownership")
	assertions.truthy(shop.order_panel.deliver_button.disabled, "reopened orders disable delivery for the authoritative shortage")
	shop.select_tab("contracts")
	shop.contract_panel.select_contract("lao_li:grain:1:3")
	assertions.truthy(shop.contract_panel.deliver_button.disabled, "shown contracts disable delivery for the authoritative storage shortage")
	assertions.truthy(
		shop.contract_panel.deliver_button.tooltip_text.contains("缺少"),
		"shown contracts expose the authoritative storage-shortage reason"
	)
	shop.close()
	_free_nodes([
		shop, fixture.economy, fixture.router, fixture.storage,
		fixture.inventory, fixture.npc, fixture.market,
	])
	_restore_wallet(game_state, saved)


func _test_visible_order_refreshes_are_coalesced(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var game_state: Node = tree.root.get_node("GameState")
	var saved: Dictionary = _snapshot_wallet(game_state)
	var fixture: Dictionary = _order_contract_fixture(game_state)
	for node in [
		fixture.market, fixture.npc, fixture.inventory, fixture.storage,
		fixture.router, fixture.economy,
	]:
		tree.root.add_child(node)
	var shop: ShopUI = ShopScene.instantiate()
	tree.root.add_child(shop)
	await tree.process_frame
	assertions.truthy(
		shop.configure(fixture.inventory, fixture.economy, fixture.market, null, null, null, fixture.npc),
		"visible order coalescing fixture configures real ShopUI"
	)
	shop.open("orders")
	shop.order_panel.select_order("tiejiang_zhang:iron_ore:1")
	var panel: OrderPanel = shop.order_panel
	var row_ids: Array[int] = _order_row_instance_ids(panel)
	var entered_row_ids: Array[int] = []
	var row_enter_callback: Callable = func(child: Node) -> void:
		if child.has_meta("order_id"):
			entered_row_ids.append(child.get_instance_id())
	panel.order_rows.child_entered_tree.connect(row_enter_callback)
	assertions.truthy(fixture.inventory.add_item("iron_ore", 2), "visible orders receive the first real inventory event")
	assertions.truthy(fixture.inventory.remove_item("iron_ore", 1), "visible orders receive the second same-frame inventory event")
	assertions.equal(
		_order_row_instance_ids(panel),
		row_ids,
		"same-frame order events do not rebuild rows before the deferred refresh"
	)
	await tree.process_frame
	assertions.equal(
		entered_row_ids.size(),
		row_ids.size(),
		"same-frame order events perform exactly one complete row rebuild"
	)
	assertions.equal(panel.owned_label.text, "持有：11/10", "coalesced orders display the final authoritative ownership")
	if panel.order_rows.child_entered_tree.is_connected(row_enter_callback):
		panel.order_rows.child_entered_tree.disconnect(row_enter_callback)
	shop.close()
	_free_nodes([
		shop, fixture.economy, fixture.router, fixture.storage,
		fixture.inventory, fixture.npc, fixture.market,
	])
	_restore_wallet(game_state, saved)


func _test_visible_contract_refreshes_are_coalesced(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var game_state: Node = tree.root.get_node("GameState")
	var saved: Dictionary = _snapshot_wallet(game_state)
	var fixture: Dictionary = _order_contract_fixture(game_state)
	for node in [
		fixture.market, fixture.npc, fixture.inventory, fixture.storage,
		fixture.router, fixture.economy,
	]:
		tree.root.add_child(node)
	var shop: ShopUI = ShopScene.instantiate()
	tree.root.add_child(shop)
	await tree.process_frame
	assertions.truthy(
		shop.configure(fixture.inventory, fixture.economy, fixture.market, null, null, null, fixture.npc),
		"visible contract coalescing fixture configures real ShopUI"
	)
	assertions.truthy(
		fixture.economy.sign_contract("lao_li:grain:1:3"),
		"visible contract coalescing fixture signs the real contract"
	)
	shop.open("contracts")
	await tree.process_frame
	shop.contract_panel.select_contract("lao_li:grain:1:3")
	var panel: ContractPanel = shop.contract_panel
	var row_ids: Array[int] = _contract_row_instance_ids(panel)
	var entered_row_ids: Array[int] = []
	var active_enter_callback: Callable = func(child: Node) -> void:
		if child.has_meta("contract_id"):
			entered_row_ids.append(child.get_instance_id())
	var available_enter_callback: Callable = func(child: Node) -> void:
		if child.has_meta("contract_id"):
			entered_row_ids.append(child.get_instance_id())
	panel.active_list.child_entered_tree.connect(active_enter_callback)
	panel.available_list.child_entered_tree.connect(available_enter_callback)
	assertions.truthy(fixture.storage.add_items({"grain": 2}), "visible contracts receive the first real storage event")
	assertions.truthy(fixture.storage.remove_items({"grain": 1}), "visible contracts receive the second same-frame storage event")
	assertions.equal(
		_contract_row_instance_ids(panel),
		row_ids,
		"same-frame contract events do not rebuild rows before the deferred refresh"
	)
	await tree.process_frame
	assertions.equal(
		entered_row_ids.size(),
		row_ids.size(),
		"same-frame contract events perform exactly one complete row rebuild"
	)
	assertions.truthy(not panel.deliver_button.disabled, "coalesced contracts display the final authoritative delivery state")
	if panel.active_list.child_entered_tree.is_connected(active_enter_callback):
		panel.active_list.child_entered_tree.disconnect(active_enter_callback)
	if panel.available_list.child_entered_tree.is_connected(available_enter_callback):
		panel.available_list.child_entered_tree.disconnect(available_enter_callback)
	shop.close()
	_free_nodes([
		shop, fixture.economy, fixture.router, fixture.storage,
		fixture.inventory, fixture.npc, fixture.market,
	])
	_restore_wallet(game_state, saved)


func _test_order_contract_panels_follow_farm_storage(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var game_state := tree.root.get_node("GameState")
	var saved := _snapshot_wallet(game_state)
	game_state.gold = 100
	var fixture := _order_contract_fixture(game_state)
	for node in [
		fixture.market, fixture.npc, fixture.inventory, fixture.storage,
		fixture.router, fixture.economy,
	]:
		tree.root.add_child(node)
	var order_panel := preload("res://scenes/ui/economy/order_panel.tscn").instantiate()
	var contract_panel := preload("res://scenes/ui/economy/contract_panel.tscn").instantiate()
	tree.root.add_child(order_panel)
	tree.root.add_child(contract_panel)
	await tree.process_frame
	assertions.truthy(order_panel.configure(fixture.economy, fixture.npc), "storage refresh fixture configures order panel")
	assertions.truthy(contract_panel.configure(fixture.economy), "storage refresh fixture configures contract panel")
	assertions.truthy(fixture.economy.sign_contract("lao_li:grain:1:3"), "storage refresh fixture signs contract")
	order_panel.select_order("lao_li:grain:1")
	contract_panel.select_contract("lao_li:grain:1:3")
	assertions.equal(order_panel.owned_label.text, "持有：5/5", "order panel starts with farm-storage ownership")
	assertions.truthy(not order_panel.deliver_button.disabled, "stored crop initially enables order delivery")
	assertions.truthy(not contract_panel.deliver_button.disabled, "stored crop initially enables contract delivery")
	assertions.truthy(fixture.storage.remove_items({"grain": 5}), "storage refresh fixture removes crop")
	await tree.process_frame
	assertions.equal(order_panel.owned_label.text, "持有：0/5", "storage removal refreshes order ownership")
	assertions.truthy(order_panel.deliver_button.disabled, "storage removal disables order delivery")
	assertions.truthy(contract_panel.deliver_button.disabled, "storage removal disables contract delivery")
	assertions.truthy(fixture.storage.add_items({"grain": 5}), "storage refresh fixture restores crop")
	await tree.process_frame
	assertions.equal(order_panel.owned_label.text, "持有：5/5", "storage addition refreshes order ownership")
	assertions.truthy(not order_panel.deliver_button.disabled, "storage addition enables order delivery")
	assertions.truthy(not contract_panel.deliver_button.disabled, "storage addition enables contract delivery")
	var event_bus := tree.root.get_node("EventBus")
	assertions.truthy(
		event_bus.farm_storage_changed.is_connected(Callable(order_panel, "_on_storage_changed")),
		"order panel connects one farm-storage refresh callback"
	)
	assertions.truthy(
		event_bus.farm_storage_changed.is_connected(Callable(contract_panel, "_on_storage_changed")),
		"contract panel connects one farm-storage refresh callback"
	)
	tree.root.remove_child(order_panel)
	tree.root.remove_child(contract_panel)
	assertions.truthy(
		not event_bus.farm_storage_changed.is_connected(Callable(order_panel, "_on_storage_changed")),
		"order panel disconnects farm-storage callback on exit"
	)
	assertions.truthy(
		not event_bus.farm_storage_changed.is_connected(Callable(contract_panel, "_on_storage_changed")),
		"contract panel disconnects farm-storage callback on exit"
	)
	_free_nodes([
		contract_panel, order_panel, fixture.economy, fixture.router, fixture.storage,
		fixture.inventory, fixture.npc, fixture.market,
	])
	_restore_wallet(game_state, saved)


func _test_market_panel_follows_routed_storage(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var game_state := tree.root.get_node("GameState")
	var saved := _snapshot_wallet(game_state)
	game_state.gold = 10000
	var inventory := InventorySystemScript.new() as InventorySystem
	var storage := FarmStorageSystemScript.new() as FarmStorageSystem
	var router := ItemContainerRouterScript.new() as ItemContainerRouter
	var market := MarketSystemScript.new() as MarketSystem
	var economy := EconomySystemScript.new() as EconomySystem
	for node in [inventory, storage, router, market, economy]:
		tree.root.add_child(node)
	assertions.truthy(storage.configure(func() -> int: return 4), "market storage fixture configures capacity")
	assertions.truthy(router.configure(inventory, storage), "market storage fixture configures router")
	assertions.truthy(
		market.configure([
			_market_definition("grain", 10, 20, 20, 10),
			_market_definition("grain_seed", 4, 20, 20, 10),
		]),
		"market storage fixture configures market"
	)
	assertions.truthy(economy.configure(inventory, game_state, market, null, router), "market storage fixture configures economy")
	assertions.truthy(storage.add_items({"grain": 3}), "market storage fixture owns crop only in storage")
	assertions.truthy(inventory.add_item("grain_seed", 2), "market storage fixture owns seed only in backpack")
	var shop := ShopScene.instantiate()
	tree.root.add_child(shop)
	await tree.process_frame
	assertions.truthy(shop.configure(inventory, economy, market), "market storage fixture configures real ShopUI")
	shop.market_panel.select_category("crops")
	shop.market_panel.select_item("grain")
	var trade = shop.market_panel.trade_panel
	assertions.equal(trade.player_quantity_label.text, "3", "ShopUI market reads crop quantity from storage")
	assertions.truthy(not trade.sell_button.disabled, "stored crop enables ShopUI sale")
	var grain_row := _find_meta_control(shop.market_panel.item_rows, "item_id", "grain")
	assertions.equal(int(grain_row.get_meta("owned", -1)), 3, "ShopUI row reads crop quantity from storage")
	assertions.truthy(storage.restore_items_unchecked({"grain": 5}), "market storage fixture creates overload")
	trade.quantity_spin.value = 1
	trade.refresh_quote()
	assertions.equal(trade.buy_button.tooltip_text, "农场仓库缺少 2 容量", "ShopUI shows exact overloaded-storage shortage")
	var before := {"gold": int(game_state.gold), "stock": market.get_stock("grain"), "storage": storage.get_items()}
	trade.request_buy()
	assertions.equal(
		{"gold": int(game_state.gold), "stock": market.get_stock("grain"), "storage": storage.get_items()},
		before,
		"ShopUI rejects crop purchase into overloaded storage atomically"
	)
	var event_bus := tree.root.get_node("EventBus")
	assertions.truthy(
		event_bus.farm_storage_changed.is_connected(Callable(shop.market_panel, "_on_storage_changed")),
		"failed-reconfigure fixture starts with market storage authority"
	)
	assertions.truthy(not shop.configure(null, null, null), "ShopUI rejects missing core dependencies")
	assertions.truthy(shop.market_panel.inventory_ref == null, "failed ShopUI configure clears market inventory authority")
	assertions.truthy(shop.market_panel.economy_ref == null, "failed ShopUI configure clears market economy authority")
	assertions.truthy(shop.market_panel.market_ref == null, "failed ShopUI configure clears market price authority")
	assertions.truthy(trade.inventory_ref == null, "failed ShopUI configure clears trade inventory authority")
	assertions.truthy(trade.economy_ref == null, "failed ShopUI configure clears trade economy authority")
	assertions.truthy(trade.market_ref == null, "failed ShopUI configure clears trade market authority")
	assertions.truthy(
		not event_bus.farm_storage_changed.is_connected(Callable(shop.market_panel, "_on_storage_changed")),
		"failed ShopUI configure disconnects market storage events"
	)
	assertions.truthy(
		not event_bus.farm_storage_changed.is_connected(Callable(trade, "_on_storage_changed")),
		"failed ShopUI configure disconnects trade storage events"
	)
	var revoked_before := {"gold": int(game_state.gold), "stock": market.get_stock("grain"), "storage": storage.get_items()}
	trade.quantity_spin.value = 1
	trade.request_sell()
	assertions.equal(
		{"gold": int(game_state.gold), "stock": market.get_stock("grain"), "storage": storage.get_items()},
		revoked_before,
		"failed ShopUI configure revokes stale trading permission"
	)
	assertions.truthy(trade.sell_button.disabled, "failed ShopUI configure leaves trade commands disabled")
	_free_nodes([shop, economy, router, storage, inventory, market])
	_restore_wallet(game_state, saved)


func _test_main_owned_routing_contract(assertions: TestAssert, tree: SceneTree) -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.load_save_on_start = false
	tree.root.add_child(main)
	await tree.process_frame
	var market_button := main.hud.get_node("EconomyActions/MarketButton") as Button
	market_button.pressed.emit()
	assertions.truthy(main.shop_ui.visible, "authored HUD button reaches Main.open_economy_tab")
	assertions.equal(str(main.shop_ui.selected_tab), "market", "Main market route selects authored market tab")
	assertions.truthy(tree.paused, "Main-routed ShopUI owns the pause")
	main.close_economy_modal()
	assertions.truthy(not main.shop_ui.visible, "Main.close_economy_modal closes authored ShopUI")
	assertions.truthy(not tree.paused, "Main.close_economy_modal restores the original running state")
	(main.hud.get_node("EconomyActions/NotificationButton") as Button).pressed.emit()
	assertions.truthy(main.economy_notification_ui.notification_center.visible, "authored notification button opens the notification center")
	main.close_economy_modal()
	assertions.truthy(not main.economy_notification_ui.notification_center.visible, "Main.close_economy_modal closes the notification center")
	assertions.truthy(not tree.paused, "closing the lightweight notification center preserves running state")
	main.free()
	await tree.process_frame


func _test_hud_market_sale_and_large_confirmation(assertions: TestAssert, tree: SceneTree) -> void:
	var game_state := tree.root.get_node("GameState")
	var saved := _snapshot_wallet(game_state)
	game_state.gold = 100
	var inventory := InventorySystemScript.new() as InventorySystem
	var market := MarketSystemScript.new() as MarketSystem
	var economy := EconomySystemScript.new() as EconomySystem
	var shop := ShopScene.instantiate()
	var hud := HudScene.instantiate()
	for node in [inventory, market, economy, shop, hud]:
		tree.root.add_child(node)
	await tree.process_frame
	assertions.truthy(market.configure([_market_definition("wood", 10, 2, 20, 10)]), "market flow configures shortage wood")
	assertions.truthy(economy.configure(inventory, game_state, market), "market flow configures authoritative economy")
	assertions.truthy(inventory.add_item("wood", 15), "market flow owns exact wood fixture")
	assertions.truthy(shop.configure(inventory, economy, market), "market flow configures real ShopUI")
	var main: Variant = MainScript.new()
	main.shop_ui = shop
	main.market_system = market
	main.economy_system = economy
	hud.market_requested.connect(func() -> void: main.open_economy_tab("market"))
	(hud.get_node("EconomyActions/MarketButton") as Button).pressed.emit()
	assertions.truthy(shop.visible and str(shop.selected_tab) == "market", "HUD market action opens the market tab")
	var panel = shop.market_panel
	_press_market_item(panel, "wood")
	var trade = panel.trade_panel
	trade.quantity_spin.value = 2
	var first_sale_total := market.quote_sell("wood", 2)
	var stock_before := market.get_stock("wood")
	var gold_before := int(game_state.gold)
	trade.sell_button.pressed.emit()
	assertions.equal(inventory.get_item_count("wood"), 13, "immediate wood sale removes exact quantity")
	assertions.equal(market.get_stock("wood"), stock_before + 2, "immediate wood sale adds exact market stock")
	assertions.equal(int(game_state.gold), gold_before + first_sale_total, "immediate wood sale credits exact quote")
	assertions.truthy(not trade.confirmation_layer.visible, "ordinary sale stays immediate")

	trade.quantity_spin.value = 10
	var assets_before_large := _trade_assets(inventory, market, game_state, "wood")
	var expected_total := market.quote_sell("wood", 10)
	var expected_first := market.quote_sell("wood", 1)
	var expected_last := expected_total - market.quote_sell("wood", 9)
	trade.sell_button.pressed.emit()
	assertions.truthy(trade.confirmation_layer.visible, "shortage item's liquidity-sized sale opens confirmation")
	assertions.equal(_trade_assets(inventory, market, game_state, "wood"), assets_before_large, "large confirmation changes no authority before consent")
	assertions.equal(int(trade._confirmation_snapshot.first_unit), expected_first, "confirmation stores exact first-unit price")
	assertions.equal(int(trade._confirmation_snapshot.last_unit), expected_last, "confirmation stores exact last-unit price")
	assertions.equal(int(trade._confirmation_snapshot.total), expected_total, "confirmation stores exact total")
	assertions.equal(trade.pressure_label.text, "预计次日供给压力：供给 +10", "confirmation explains exact supply pressure")
	trade.confirmation_confirm_button.pressed.emit()
	assertions.equal(inventory.get_item_count("wood"), 3, "confirmed large sale removes ten wood once")
	assertions.equal(int(game_state.gold), int(assets_before_large.gold) + expected_total, "confirmed large sale pays exact total once")
	shop.close()
	tree.paused = false
	main.free()
	_free_nodes([hud, shop, economy, market, inventory])
	_restore_wallet(game_state, saved)


func _test_order_delivery_updates_every_authority(assertions: TestAssert, tree: SceneTree) -> void:
	var game_state := tree.root.get_node("GameState")
	var saved := _snapshot_wallet(game_state)
	game_state.gold = 100
	var fixture := _order_contract_fixture(game_state)
	for node in [fixture.market, fixture.npc, fixture.inventory, fixture.economy]:
		tree.root.add_child(node)
	var notifications := NotificationSystemScript.new() as EconomyNotificationSystem
	var hud := HudScene.instantiate()
	var panel := preload("res://scenes/ui/economy/order_panel.tscn").instantiate()
	for node in [notifications, hud, panel]:
		tree.root.add_child(node)
	await tree.process_frame
	assertions.truthy(notifications.configure(tree.root.get_node("EventBus"), fixture.market, fixture.economy), "order flow connects notification authority")
	hud.configure_notifications(notifications)
	assertions.truthy(panel.call("configure", fixture.economy, fixture.npc), "order flow configures real panel without inventory ownership")
	var order_id := "tiejiang_zhang:iron_ore:1"
	(_find_meta_button(panel.order_rows, "order_id", order_id) as Button).pressed.emit()
	var order := _record_for(fixture.economy.get_orders(), "order_id", order_id)
	var quantity := int(order.quantity)
	var reward := int(order.reward_gold)
	var npc_before := int(fixture.npc.get_npc_state("tiejiang_zhang").inventory.get("iron_ore", 0))
	var gold_before := int(game_state.gold)
	panel.deliver_button.pressed.emit()
	assertions.equal(fixture.inventory.get_item_count("iron_ore"), 0, "order delivery removes exact player stock")
	assertions.equal(int(fixture.npc.get_npc_state("tiejiang_zhang").inventory.get("iron_ore", 0)), npc_before + quantity, "order delivery transfers exact NPC stock")
	assertions.equal(int(game_state.gold), gold_before + reward, "order delivery credits exact reward")
	assertions.equal(bool(_record_for(fixture.economy.get_orders(), "order_id", order_id).completed), true, "order authority becomes completed")
	assertions.truthy(_combined_text(panel.order_rows).contains("已完成"), "completed order row refreshes locally")
	assertions.equal(notifications.get_unread_count(), 1, "order completion emits one unread notification")
	var notice := notifications.get_recent(1)[0]
	assertions.equal({"kind": notice.kind, "target_type": notice.target_type, "target_id": notice.target_id}, {"kind": "order_completed", "target_type": "order", "target_id": order_id}, "order notification points to exact row")
	_free_nodes([panel, hud, notifications, fixture.economy, fixture.router, fixture.storage, fixture.inventory, fixture.npc, fixture.market])
	_restore_wallet(game_state, saved)


func _test_contract_sign_delivery_reload_is_idempotent(assertions: TestAssert, tree: SceneTree) -> void:
	var game_state := tree.root.get_node("GameState")
	var saved := _snapshot_wallet(game_state)
	game_state.gold = 100
	var fixture := _order_contract_fixture(game_state)
	for node in [fixture.market, fixture.npc, fixture.inventory, fixture.economy]:
		tree.root.add_child(node)
	var shop := ShopScene.instantiate()
	var notifications := NotificationSystemScript.new() as EconomyNotificationSystem
	tree.root.add_child(shop)
	tree.root.add_child(notifications)
	await tree.process_frame
	notifications.configure(tree.root.get_node("EventBus"), fixture.market, fixture.economy)
	assertions.truthy(shop.configure(fixture.inventory, fixture.economy, fixture.market, null, null, null, fixture.npc), "contract flow configures real ShopUI")
	shop.open("contracts")
	var panel = shop.contract_panel
	var contract_id := "lao_li:grain:1:3"
	(_find_meta_button(panel.available_list, "contract_id", contract_id) as Button).pressed.emit()
	panel.sign_button.pressed.emit()
	assertions.equal(bool(_record_for(fixture.economy.get_contracts(), "contract_id", contract_id).signed), false, "contract request alone does not sign")
	assertions.truthy(shop.sign_confirmation_layer.visible and tree.paused, "contract confirmation stays inside the paused ShopUI owner")
	_push_escape(tree)
	await tree.process_frame
	assertions.truthy(not shop.sign_confirmation_layer.visible and shop.visible, "Escape closes only the top contract confirmation")
	assertions.truthy(tree.paused, "closing nested contract confirmation keeps ShopUI pause ownership")
	panel.sign_button.pressed.emit()
	shop.sign_confirm_button.pressed.emit()
	assertions.truthy(bool(_record_for(fixture.economy.get_contracts(), "contract_id", contract_id).signed), "confirmed contract sign button commits")
	var gold_before := int(game_state.gold)
	var npc_before := int(fixture.npc.get_npc_state("lao_li").inventory.get("grain", 0))
	panel.deliver_button.pressed.emit()
	var delivered := _record_for(fixture.economy.get_contracts(), "contract_id", contract_id)
	assertions.equal(delivered.delivered_days, [1], "daily contract records exactly one delivered day")
	assertions.equal(int(delivered.breaches), 0, "successful contract day has no breach")
	assertions.equal(fixture.storage.get_count("grain"), 0, "daily contract removes exact farm-storage goods")
	assertions.equal(int(fixture.npc.get_npc_state("lao_li").inventory.get("grain", 0)), npc_before + 5, "daily contract transfers exact NPC goods")
	assertions.equal(int(game_state.gold), gold_before + 50, "daily contract pays exactly once")
	var assets_after := _contract_assets(fixture, game_state)
	var state_after: Dictionary = fixture.economy.to_dict()
	var notices_after: Dictionary = notifications.to_dict()
	assertions.truthy(fixture.economy.from_dict(state_after), "contract authority reloads serialized state")
	assertions.truthy(notifications.from_dict(notices_after), "notification authority reloads without replay")
	assertions.equal(_contract_assets(fixture, game_state), assets_after, "reload creates no duplicate contract payment or transfer")
	var reloaded := _record_for(fixture.economy.get_contracts(), "contract_id", contract_id)
	assertions.equal(reloaded.delivered_days, [1], "reload preserves one delivery occurrence")
	assertions.equal(int(reloaded.breaches), 0, "reload creates no breach")
	panel.deliver_button.pressed.emit()
	assertions.equal(_contract_assets(fixture, game_state), assets_after, "reloaded UI rejects duplicate same-day delivery")
	assertions.equal(panel.error_label.text, "今日已交付，不能重复结算", "duplicate contract command reloads and shows authoritative reason")
	shop.close()
	assertions.truthy(not tree.paused, "closing ShopUI after contract confirmation restores running state")
	_free_nodes([notifications, shop, fixture.economy, fixture.router, fixture.storage, fixture.inventory, fixture.npc, fixture.market])
	_restore_wallet(game_state, saved)


func _test_windmill_flour_flow(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := _production_fixture(tree)
	_unlock_station(fixture.progression, "windmill")
	fixture.production.set_progression_system(fixture.progression)
	assertions.truthy(fixture.storage.add_items({"grain": 2}), "windmill flow owns two grain in farm storage")
	var windmill := _building("windmill", 4, 5)
	tree.root.add_child(windmill)
	assertions.truthy(fixture.production.register_building(windmill), "windmill registers real producer")
	var ui := BuildingEconomyScene.instantiate()
	tree.root.add_child(ui)
	await tree.process_frame
	assertions.truthy(ui.configure(fixture.production, fixture.inventory, fixture.progression, fixture.grid, ModalCoordinatorScript.new()), "windmill flow configures building UI")
	var main: Variant = MainScript.new()
	main.building_economy_ui = ui
	main._on_building_instance_placed(windmill)
	windmill.interact(null)
	assertions.truthy(ui.is_open(), "BuildingInstance.interacted reaches Main and opens production panel")
	(ui.production_panel.recipe_list.get_node("Recipe_flour") as Button).pressed.emit()
	ui.production_panel.batch_spin_box.value = 1
	ui.production_panel.start_button.pressed.emit()
	assertions.equal(fixture.storage.get_count("grain"), 0, "starting flour consumes exactly two stored grain")
	assertions.equal(windmill.producer_state.jobs.size(), 1, "starting flour creates one queue job")
	assertions.equal(str(windmill.producer_state.jobs[0].recipe_id), "flour", "queue stores flour recipe")
	fixture.production.advance_minutes(360)
	assertions.equal(windmill.producer_state.outputs, {"flour": 1}, "finished windmill stores one flour")
	ui.production_panel.collect_all_button.pressed.emit()
	assertions.equal(fixture.inventory.get_item_count("flour"), 1, "collect transfers one flour to player")
	assertions.equal(windmill.producer_state.outputs, {}, "collect clears windmill output")
	ui.close()
	tree.paused = false
	main.free()
	_free_nodes([ui, windmill])
	_free_production_fixture(fixture)


func _test_coop_feed_egg_flow(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := _production_fixture(tree)
	var coop := _building("chicken_coop", 6, 7)
	tree.root.add_child(coop)
	fixture.production.register_building(coop)
	var ui := BuildingEconomyScene.instantiate()
	tree.root.add_child(ui)
	await tree.process_frame
	ui.configure(fixture.production, fixture.inventory, fixture.progression, fixture.grid, ModalCoordinatorScript.new())
	ui.open_for(coop)
	fixture.production.finish_daily_outputs(1)
	assertions.equal(coop.producer_state.outputs, {}, "unfed coop produces no eggs")
	assertions.truthy(fixture.inventory.add_item("animal_feed", 1), "coop flow owns one feed")
	(ui.status_panel.input_actions.get_child(0) as Button).pressed.emit()
	assertions.equal(fixture.inventory.get_item_count("animal_feed"), 0, "feed action removes exact inventory input")
	assertions.equal(coop.producer_state.get_input_count("animal_feed"), 1, "feed action stores exact coop input")
	fixture.production.finish_daily_outputs(2)
	assertions.equal(coop.producer_state.get_input_count("animal_feed"), 0, "next-day coop consumes one feed")
	assertions.equal(coop.producer_state.outputs, {"egg": 2}, "next-day coop produces two eggs")
	ui.status_panel.collect_all_button.pressed.emit()
	assertions.equal(fixture.inventory.get_item_count("egg"), 2, "coop collection transfers two eggs")
	assertions.equal(coop.producer_state.outputs, {}, "coop collection clears output")
	ui.close()
	tree.paused = false
	_free_nodes([ui, coop])
	_free_production_fixture(fixture)


func _test_waterwheel_overlay_lifecycle(assertions: TestAssert, tree: SceneTree) -> void:
	var fixture := _production_fixture(tree)
	var wheel := _building("waterwheel", 10, 10)
	tree.root.add_child(wheel)
	fixture.grid.get_cell(9, 10).state = GridCell.State.WATER
	for position in [Vector2i(10, 12), Vector2i(12, 10), Vector2i(13, 10)]:
		fixture.grid.get_cell(position.x, position.y).state = GridCell.State.FARMLAND
	fixture.production.register_building(wheel)
	var ui := BuildingEconomyScene.instantiate()
	tree.root.add_child(ui)
	await tree.process_frame
	ui.configure(fixture.production, fixture.inventory, fixture.progression, fixture.grid, ModalCoordinatorScript.new())
	ui.open_for(wheel)
	ui.status_panel.range_preview_button.button_pressed = true
	ui.status_panel.range_preview_button.toggled.emit(true)
	var expected: Array = fixture.production.get_irrigated_cells(wheel)
	assertions.truthy(not expected.is_empty(), "waterwheel fixture has authoritative irrigated cells")
	assertions.equal(ui.range_overlay.cells, expected, "range preview mirrors exact authoritative cells")
	assertions.equal(ui.range_overlay.get_child_count(), expected.size(), "range preview renders one mesh per cell")
	ui.close()
	assertions.equal(ui.range_overlay.cells, [], "closing waterwheel panel clears overlay state")
	assertions.equal(ui.range_overlay.get_child_count(), 0, "closing waterwheel panel clears overlay geometry")
	tree.paused = false
	_free_nodes([ui, wheel])
	_free_production_fixture(fixture)


func _test_blueprint_service_is_idempotent(assertions: TestAssert, tree: SceneTree) -> void:
	var game_state := tree.root.get_node("GameState")
	var saved := _snapshot_wallet(game_state)
	game_state.gold = 500
	game_state.player_state.level = 2
	var fixture := _production_fixture(tree)
	var tool := ToolSystemScript.new() as ToolSystem
	var progression := ProgressionSystemScript.new() as EconomyProgressionSystem
	tree.root.add_child(tool)
	tree.root.add_child(progression)
	assertions.truthy(fixture.inventory.add_item("wood", 30), "service owns exact wood cost")
	assertions.truthy(fixture.inventory.add_item("stone", 20), "service owns exact stone cost")
	assertions.truthy(progression.configure(tool, fixture.production, fixture.inventory, FixedDaySource.new(), game_state), "service configures real progression")
	var panel := ServiceScene.instantiate()
	tree.root.add_child(panel)
	await tree.process_frame
	assertions.truthy(panel.configure(progression, tool, fixture.production), "service panel configures real authorities")
	var stale_button := _find_service_button(panel, "blueprint_windmill")
	progression.set("unlocked_blueprints", {"windmill": true})
	var assets_before_stale := {"gold": game_state.gold, "wood": fixture.inventory.get_item_count("wood"), "stone": fixture.inventory.get_item_count("stone")}
	stale_button.pressed.emit()
	assertions.equal(panel.feedback_label.text, "已拥有", "failed stale service reloads authority before showing its reason")
	assertions.equal({"gold": game_state.gold, "wood": fixture.inventory.get_item_count("wood"), "stone": fixture.inventory.get_item_count("stone")}, assets_before_stale, "stale service failure changes no assets")
	var gold_before := int(game_state.gold)
	var first_button := _find_service_button(panel, "blueprint_chicken_coop")
	first_button.pressed.emit()
	assertions.truthy(progression.is_blueprint_unlocked("chicken_coop"), "blueprint service changes owned state")
	assertions.equal(int(game_state.gold), gold_before - 100, "blueprint charges gold exactly once")
	assertions.equal({"wood": fixture.inventory.get_item_count("wood"), "stone": fixture.inventory.get_item_count("stone")}, {"wood": 22, "stone": 16}, "blueprint consumes exact material cost")
	var after_once := {"gold": game_state.gold, "slots": fixture.inventory.slots.duplicate(true), "state": progression.to_dict()}
	# Replaying the already-connected stale control simulates a delayed duplicate command.
	first_button.pressed.emit()
	assertions.equal({"gold": game_state.gold, "slots": fixture.inventory.slots, "state": progression.to_dict()}, after_once, "owned blueprint repeat is fully idempotent")
	assertions.equal(panel.feedback_label.text, "已拥有", "duplicate service reloads authority before showing its failure reason")
	_free_nodes([panel, progression, tool])
	_free_production_fixture(fixture)
	_restore_wallet(game_state, saved)


func _test_merged_notifications_navigate_to_target(assertions: TestAssert, tree: SceneTree) -> void:
	var system := NotificationSystemScript.new() as EconomyNotificationSystem
	var ui := NotificationScene.instantiate()
	var main: Variant = MainScript.new()
	var building_system := BuildingSystem.new()
	var production_fixture := _production_fixture(tree)
	var building_ui := BuildingEconomyScene.instantiate()
	var windmill := _building("windmill", 4, 5)
	tree.root.add_child(windmill)
	production_fixture.production.register_building(windmill)
	tree.root.add_child(building_ui)
	var buildings: Array[BuildingInstance] = [windmill]
	building_system.set("_buildings", buildings)
	main.building_system = building_system
	main.building_economy_ui = building_ui
	building_ui.configure(production_fixture.production, production_fixture.inventory, production_fixture.progression, production_fixture.grid, ModalCoordinatorScript.new())
	var game_state := tree.root.get_node("GameState")
	var fixture := _order_contract_fixture(game_state)
	for node in [fixture.market, fixture.npc, fixture.inventory, fixture.economy]:
		tree.root.add_child(node)
	var shop := ShopScene.instantiate()
	tree.root.add_child(shop)
	tree.root.add_child(system)
	tree.root.add_child(ui)
	await tree.process_frame
	shop.configure(fixture.inventory, fixture.economy, fixture.market, null, null, null, fixture.npc)
	main.shop_ui = shop
	main.market_system = fixture.market
	main.economy_system = fixture.economy
	assertions.truthy(ui.configure(system, main), "notification flow configures real UI with Main router")
	var notification_id := system.push("completed", "生产完成", "风车完成面粉 ×1", 3, "building", "windmill:4:5", 10.0)
	assertions.equal(system.push("completed", "生产完成", "风车完成面粉 ×2", 3, "building", "windmill:4:5", 11.0), notification_id, "second production notice merges")
	assertions.equal(system.push("completed", "生产完成", "风车完成面粉 ×3", 3, "building", "windmill:4:5", 12.0), notification_id, "third production notice merges")
	assertions.equal(system.get_recent().size(), 1, "three production events keep one record")
	assertions.equal(int(system.get_recent()[0].count), 3, "merged record carries exact count three")
	assertions.truthy(not ui.has_node("ToastStack"), "merged production events use the HUD message stream instead of a toast")
	assertions.equal(ui.get_center_record_count(), 1, "merged production events keep one persistent history card")
	var order_id := "tiejiang_zhang:iron_ore:1"
	var contract_id := "lao_li:grain:1:3"
	var order_notice := system.push("order_due", "订单临期", "铁匠订单即将到期", 3, "order", order_id, 20.0)
	var contract_notice := system.push("contract_breached", "合同提醒", "老李合同待处理", 3, "contract", contract_id, 21.0)
	ui.show_center()
	_click_notification_card(ui, order_notice)
	assertions.equal(str(shop.selected_tab), "orders", "notification control traverses Main order route")
	assertions.equal(str(shop.order_panel.selected_order_id), order_id, "Main order route selects exact authority record")
	ui.show_center()
	_click_notification_card(ui, contract_notice)
	assertions.equal(str(shop.selected_tab), "contracts", "notification control traverses Main contract route")
	assertions.equal(str(shop.contract_panel.selected_contract_id), contract_id, "Main contract route selects exact authority record")
	ui.show_center()
	_click_notification_card(ui, notification_id)
	assertions.truthy(building_ui.is_open(), "notification control traverses Main building route into real UI")
	assertions.equal(building_ui.current_building(), windmill, "building route opens exact BuildingInstance")
	assertions.equal(system.get_unread_count(), 0, "successful target navigation marks merged record read")
	assertions.truthy(not ui.notification_center.visible, "successful target navigation closes notification center")
	main.close_economy_modal()
	assertions.truthy(not building_ui.is_open(), "Main.close_economy_modal closes routed building panel")
	_free_nodes([ui, system, shop, fixture.economy, fixture.router, fixture.storage, fixture.inventory, fixture.npc, fixture.market, building_ui, windmill])
	_free_production_fixture(production_fixture)
	main.free()
	building_system.free()


func _test_every_modal_restores_original_pause(assertions: TestAssert, tree: SceneTree) -> void:
	var game_state := tree.root.get_node("GameState")
	var saved := _snapshot_wallet(game_state)
	var inventory := InventorySystemScript.new() as InventorySystem
	var market := MarketSystemScript.new() as MarketSystem
	var economy := EconomySystemScript.new() as EconomySystem
	market.configure([_market_definition("wood", 10, 20, 20, 10)])
	economy.configure(inventory, game_state, market)
	inventory.add_item("wood", 10)
	var shop := ShopScene.instantiate()
	for node in [inventory, market, economy, shop]:
		tree.root.add_child(node)
	await tree.process_frame
	shop.configure(inventory, economy, market)
	for original_pause in [false, true]:
		tree.paused = original_pause
		shop.open("market")
		assertions.truthy(tree.paused, "ShopUI modal pauses while open")
		shop.close_button.pressed.emit()
		assertions.equal(tree.paused, original_pause, "ShopUI restores original pause=%s" % original_pause)

	var production_fixture := _production_fixture(tree)
	assertions.truthy(
		shop.configure(
			inventory,
			economy,
			market,
			production_fixture.progression,
			production_fixture.tool,
			production_fixture.production
		),
		"modal handoff fixture configures service routing"
	)
	_unlock_station(production_fixture.progression, "windmill")
	production_fixture.production.set_progression_system(production_fixture.progression)
	var windmill := _building("windmill", 1, 1)
	tree.root.add_child(windmill)
	production_fixture.production.register_building(windmill)
	var building_ui := BuildingEconomyScene.instantiate()
	tree.root.add_child(building_ui)
	await tree.process_frame
	building_ui.configure(production_fixture.production, production_fixture.inventory, production_fixture.progression, production_fixture.grid, ModalCoordinatorScript.new())
	for original_pause in [false, true]:
		tree.paused = original_pause
		building_ui.open_for(windmill)
		assertions.truthy(tree.paused, "building economy modal pauses while open")
		building_ui.close_button.pressed.emit()
		assertions.equal(tree.paused, original_pause, "building economy modal restores original pause=%s" % original_pause)

	var main: Variant = MainScript.new()
	main.shop_ui = shop
	main.building_economy_ui = building_ui
	main.market_system = market
	main.economy_system = economy
	for original_pause in [false, true]:
		tree.paused = original_pause
		assertions.truthy(building_ui.open_for(windmill), "building modal opens before Main handoff")
		assertions.truthy(main.open_economy_tab("market"), "Main hands building modal to market tab")
		assertions.truthy(not building_ui.is_open(), "Main market handoff closes building economy UI")
		assertions.truthy(shop.visible and str(shop.selected_tab) == "market", "Main handoff leaves ShopUI as the only economy modal")
		assertions.truthy(tree.paused, "Main modal handoff remains paused without a running-frame gap")
		windmill.get_parent().remove_child(windmill)
		shop.close_button.pressed.emit()
		assertions.equal(tree.paused, original_pause, "closing handed-off ShopUI restores original pause=%s" % original_pause)
		tree.root.add_child(windmill)
	assertions.truthy(
		main.open_economy_tab("services", "blueprint_furnace"),
		"main routes blueprint unlock target to services"
	)
	assertions.equal(shop.service_panel.selected_service_id, "blueprint_furnace", "Main deep link selects requested service")
	shop.close()
	main.free()

	# Nested trade confirmation and notification center must not replace their owner's snapshot.
	tree.paused = false
	shop.open("market")
	_press_market_item(shop.market_panel, "wood")
	shop.market_panel.trade_panel.quantity_spin.value = 10
	shop.market_panel.trade_panel.sell_button.pressed.emit()
	assertions.truthy(shop.market_panel.trade_panel.confirmation_layer.visible, "trade confirmation opens inside ShopUI modal")
	shop.close_button.pressed.emit()
	assertions.truthy(not tree.paused, "closing ShopUI with trade confirmation restores original running state")
	var notification_system := NotificationSystemScript.new() as EconomyNotificationSystem
	var notification_ui := NotificationScene.instantiate()
	tree.root.add_child(notification_system)
	tree.root.add_child(notification_ui)
	await tree.process_frame
	notification_ui.configure(notification_system)
	for original_pause in [false, true]:
		tree.paused = original_pause
		notification_ui.show_center()
		notification_ui.close_button.pressed.emit()
		assertions.equal(tree.paused, original_pause, "notification center preserves original pause=%s" % original_pause)

	tree.paused = false
	_free_nodes([notification_ui, notification_system, building_ui, windmill])
	_free_production_fixture(production_fixture)
	_free_nodes([shop, economy, market, inventory])
	_restore_wallet(game_state, saved)


func _production_fixture(tree: SceneTree) -> Dictionary:
	var grid := GridSystemScript.new() as GridSystem
	var farming := FarmingSystemScript.new() as FarmingSystem
	var inventory := InventorySystemScript.new() as InventorySystem
	var storage := FarmStorageSystemScript.new() as FarmStorageSystem
	var router := ItemContainerRouterScript.new() as ItemContainerRouter
	var production := ProductionSystemScript.new() as ProductionSystem
	var progression := ProgressionSystemScript.new() as EconomyProgressionSystem
	var tool := ToolSystemScript.new() as ToolSystem
	for node in [grid, farming, inventory, storage, router, production, progression, tool]:
		tree.root.add_child(node)
	storage.configure(func() -> int: return 1000)
	router.configure(inventory, storage)
	farming.configure(grid, null, null)
	production.call("configure", grid, farming, null, inventory, router)
	tool.configure(null, inventory, null)
	return {"grid": grid, "farming": farming, "inventory": inventory, "storage": storage, "router": router, "production": production, "progression": progression, "tool": tool}


func _free_production_fixture(fixture: Dictionary) -> void:
	_free_nodes([fixture.tool, fixture.progression, fixture.production, fixture.router, fixture.storage, fixture.inventory, fixture.farming, fixture.grid])


func _unlock_station(progression: EconomyProgressionSystem, station: String) -> void:
	var state := progression.to_dict()
	if station not in state.unlocked_blueprints:
		state.unlocked_blueprints.append(station)
	for recipe in preload("res://scripts/core/recipe_database.gd").get_recipes_for_station(station):
		if str(recipe.id) not in state.unlocked_recipes:
			state.unlocked_recipes.append(str(recipe.id))
	progression.from_dict(state)


func _building(building_id: String, gx: int, gz: int) -> BuildingInstance:
	var building := BuildingInstance.new()
	var definition: Dictionary = GameDataScript.get_building(building_id)
	building.authored_building_id = building_id
	building.data = BuildingData.from_dictionary(definition)
	building.grid_x = gx
	building.grid_z = gz
	if building.data != null and str(building.data.effect) == "crafting":
		building.producer_state = ProducerStateScript.new(str(definition.get("station", building_id)))
	return building


func _order_contract_fixture(wallet: Node) -> Dictionary:
	var market := MarketSystemScript.new() as MarketSystem
	market.configure([
		_market_definition("iron_ore", 10, 20, 20, 10),
		_market_definition("grain", 10, 20, 20, 10),
		_market_definition("honey", 20, 20, 20, 10),
	])
	var npc := NpcEconomySystemScript.new() as NpcEconomySystem
	npc.configure(market, [
		_npc_profile("tiejiang_zhang", "铁匠张", {"iron_ore": 10}),
		_npc_profile("lao_li", "老李", {"grain": 5}),
		_npc_profile("xiao_hua", "小花", {"honey": 2}),
	], [])
	var inventory := InventorySystemScript.new() as InventorySystem
	var storage := FarmStorageSystemScript.new() as FarmStorageSystem
	var router := ItemContainerRouterScript.new() as ItemContainerRouter
	storage.configure(func() -> int: return 1000)
	router.configure(inventory, storage)
	inventory.add_item("iron_ore", 10)
	storage.add_items({"grain": 5})
	var economy := EconomySystemScript.new() as EconomySystem
	economy.configure(inventory, wallet, market, npc, router)
	market.settle_day(1)
	npc.sync_daily_cursor(1)
	economy.advance_order_deadlines(1)
	economy.generate_demand_orders(1)
	var state := economy.to_dict()
	state.contracts.append({
		"contract_id": "lao_li:grain:1:3", "npc_id": "lao_li", "item_id": "grain",
		"quantity_per_day": 5, "unit_price": 10, "reward_gold": 50,
		"start_day": 1, "end_day": 3, "delivered_days": [], "breaches": 0,
		"signed": false, "completed": false, "expired": false,
	})
	economy.from_dict(state)
	return {"market": market, "npc": npc, "inventory": inventory, "storage": storage, "router": router, "economy": economy}


func _market_definition(item_id: String, price: int, stock: int, target: int, liquidity: int) -> Dictionary:
	return {"id": item_id, "base_price": price, "initial_stock": stock, "target_stock": target, "daily_liquidity": liquidity}


func _npc_profile(npc_id: String, display_name: String, targets: Dictionary) -> Dictionary:
	return {
		"id": npc_id, "display_name": display_name, "gold": 0, "inventory": {},
		"essential_targets": {}, "reserve_targets": targets, "production_recipes": [],
		"sale_targets": {}, "investment_gold_threshold": 1000, "import_buffer": false,
	}


func _record_for(records: Array, field: String, record_id: String) -> Dictionary:
	for record in records:
		if record is Dictionary and str(record.get(field, "")) == record_id:
			return record
	return {}


func _trade_assets(inventory: InventorySystem, market: MarketSystem, wallet: Node, item_id: String) -> Dictionary:
	return {"owned": inventory.get_item_count(item_id), "stock": market.get_stock(item_id), "gold": int(wallet.gold)}


func _contract_assets(fixture: Dictionary, wallet: Node) -> Dictionary:
	return {
		"grain": fixture.storage.get_count("grain"), "gold": int(wallet.gold),
		"npc_grain": int(fixture.npc.get_npc_state("lao_li").inventory.get("grain", 0)),
	}


func _combined_text(node: Node) -> String:
	var result := str(node.text) if node is Label or node is Button else ""
	for child in node.get_children():
		result += _combined_text(child)
	return result


func _find_meta_button(root_node: Node, key: String, value: String) -> Button:
	if root_node is Button and str(root_node.get_meta(key, "")) == value:
		return root_node as Button
	for child in root_node.get_children():
		var found := _find_meta_button(child, key, value)
		if found != null:
			return found
	return null


func _press_market_item(panel: MarketPanel, item_id: String) -> void:
	var row := _find_meta_control(panel.item_rows, "item_id", item_id)
	if row != null:
		(row.get_node("Content/SelectButton") as Button).pressed.emit()


func _find_service_button(panel: ServicePanel, service_id: String) -> Button:
	for card in panel.service_cards.get_children():
		if str(card.get_meta("service_id", "")) == service_id:
			return card.get_node("ActionButton") as Button
	return null


func _click_notification_card(ui: EconomyNotificationUI, notification_id: String) -> void:
	var card := _find_meta_control(ui.record_list, "notification_id", notification_id)
	if card == null:
		return
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	card.gui_input.emit(event)


func _push_escape(tree: SceneTree) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	tree.root.push_input(event)


func _find_meta_control(root_node: Node, key: String, value: String) -> Control:
	if root_node is Control and str(root_node.get_meta(key, "")) == value:
		return root_node as Control
	for child in root_node.get_children():
		var found := _find_meta_control(child, key, value)
		if found != null:
			return found
	return null


func _market_row_instance_ids(panel: MarketPanel) -> Array[int]:
	var ids: Array[int] = []
	for child in panel.item_rows.get_children():
		if child.has_meta("item_id"):
			ids.append(child.get_instance_id())
	return ids


func _order_row_instance_ids(panel: OrderPanel) -> Array[int]:
	var ids: Array[int] = []
	for child in panel.order_rows.get_children():
		if child.has_meta("order_id"):
			ids.append(child.get_instance_id())
	return ids


func _contract_row_instance_ids(panel: ContractPanel) -> Array[int]:
	var ids: Array[int] = []
	for list in [panel.active_list, panel.available_list]:
		for child in list.get_children():
			if child.has_meta("contract_id"):
				ids.append(child.get_instance_id())
	return ids


func _snapshot_wallet(wallet: Node) -> Dictionary:
	return {"gold": wallet.gold, "level": wallet.player_state.level}


func _restore_wallet(wallet: Node, snapshot: Dictionary) -> void:
	wallet.gold = snapshot.gold
	wallet.player_state.level = snapshot.level


func _free_nodes(nodes: Array) -> void:
	for node in nodes:
		if node != null and is_instance_valid(node):
			node.free()
