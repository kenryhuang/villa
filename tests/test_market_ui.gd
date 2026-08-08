extends RefCounted

const GameDataScript = preload("res://scripts/core/game_data.gd")
const MODAL_SCRIPT_PATH := "res://scripts/ui/economy_modal_coordinator.gd"
const SHOP_SCENE_PATH := "res://scenes/ui/shop_ui.tscn"
const MARKET_SCENE_PATH := "res://scenes/ui/economy/market_panel.tscn"
const TRADE_SCENE_PATH := "res://scenes/ui/economy/trade_panel.tscn"
const TRADE_SCRIPT_PATH := "res://scripts/ui/trade_panel.gd"


class SignalCounter:
	extends RefCounted
	var count := 0

	func record() -> void:
		count += 1


func run(assertions: TestAssert, tree: SceneTree) -> void:
	_test_scene_contracts(assertions)
	_test_trade_thresholds(assertions)
	_test_modal_coordinator(assertions, tree)
	await _test_hud_market_request(assertions, tree)
	await _test_market_snapshot_and_transactions(assertions, tree)


func _test_scene_contracts(assertions: TestAssert) -> void:
	_check_scene(assertions, SHOP_SCENE_PATH, [
		"TopBar/GoldLabel",
		"ScrollContainer/GridContainer",
		"CloseButton",
		"ScreenLayer/ModalLayer",
		"ScreenLayer/ModalLayer/HubPanel/Margin/Shell/Header/TitleLabel",
		"ScreenLayer/ModalLayer/HubPanel/Margin/Shell/Header/MarketStatusLabel",
		"ScreenLayer/ModalLayer/HubPanel/Margin/Shell/Header/GoldLabel",
		"ScreenLayer/ModalLayer/HubPanel/Margin/Shell/Header/DateLabel",
		"ScreenLayer/ModalLayer/HubPanel/Margin/Shell/Header/CloseButton",
		"ScreenLayer/ModalLayer/HubPanel/Margin/Shell/Tabs/MarketTab",
		"ScreenLayer/ModalLayer/HubPanel/Margin/Shell/Tabs/OrdersTab",
		"ScreenLayer/ModalLayer/HubPanel/Margin/Shell/Tabs/ContractsTab",
		"ScreenLayer/ModalLayer/HubPanel/Margin/Shell/Tabs/ServicesTab",
		"ScreenLayer/ModalLayer/HubPanel/Margin/Shell/PageHost/MarketPanel",
	])
	_check_scene(assertions, MARKET_SCENE_PATH, [
		"Columns/CatalogColumn/CatalogContent/CategoryTabs/RawMaterials",
		"Columns/CatalogColumn/CatalogContent/CategoryTabs/Crops",
		"Columns/CatalogColumn/CatalogContent/CategoryTabs/ProcessedMaterials",
		"Columns/CatalogColumn/CatalogContent/CategoryTabs/FoodHandicrafts",
		"Columns/CatalogColumn/CatalogContent/CategoryTabs/RareGoods",
		"Columns/CatalogColumn/CatalogContent/SortMode",
		"Columns/CatalogColumn/CatalogContent/ItemList",
		"Columns/CatalogColumn/CatalogContent/ItemScroll/ItemRows",
		"Columns/DetailColumn/DetailContent/DetailHeader/ItemNameLabel",
		"Columns/DetailColumn/DetailContent/PriceMetrics/MidPriceLabel",
		"Columns/DetailColumn/DetailContent/PriceMetrics/BuyPriceLabel",
		"Columns/DetailColumn/DetailContent/PriceMetrics/SellPriceLabel",
		"Columns/DetailColumn/DetailContent/StockLabel",
		"Columns/DetailColumn/DetailContent/DetailHeader/TrendLabel",
		"Columns/DetailColumn/DetailContent/FlowLabel",
		"Columns/DetailColumn/DetailContent/PriceChart",
		"Columns/DetailColumn/DetailContent/TagsLabel",
		"Columns/TradePanel",
	])
	_check_scene(assertions, TRADE_SCENE_PATH, [
		"Content/SummaryGrid/PlayerQuantityLabel",
		"Content/SummaryGrid/MarketQuantityLabel",
		"Content/QuantityRow/QuantitySpin",
		"Content/QuantityRow/MaxButton",
		"Content/SummaryGrid/ReferencePriceLabel",
		"Content/SummaryGrid/BuyTotalLabel",
		"Content/SummaryGrid/SellTotalLabel",
		"Content/SummaryGrid/ImpactLabel",
		"Content/StatusArea/DisabledReasonLabel",
		"Content/Actions/BuyButton",
		"Content/Actions/SellButton",
		"ConfirmationLayer/Content/VBox/FirstUnitLabel",
		"ConfirmationLayer/Content/VBox/LastUnitLabel",
		"ConfirmationLayer/Content/VBox/TotalLabel",
		"ConfirmationLayer/Content/VBox/PressureLabel",
	])


func _check_scene(assertions: TestAssert, path: String, nodes: Array[String]) -> void:
	assertions.truthy(ResourceLoader.exists(path), "market UI scene exists: %s" % path)
	if not ResourceLoader.exists(path):
		return
	var packed := load(path) as PackedScene
	assertions.truthy(packed != null, "market UI scene loads: %s" % path)
	if packed == null:
		return
	var instance := packed.instantiate()
	for node_path in nodes:
		assertions.truthy(instance.has_node(node_path), "%s has %s" % [path, node_path])
	instance.free()


func _test_trade_thresholds(assertions: TestAssert) -> void:
	assertions.truthy(ResourceLoader.exists(TRADE_SCRIPT_PATH), "trade panel script exists")
	if not ResourceLoader.exists(TRADE_SCRIPT_PATH):
		return
	var trade_script: Script = load(TRADE_SCRIPT_PATH)
	assertions.truthy(
		trade_script.call("needs_confirmation", 20, 20, 100, 1000, 10, 9),
		"daily liquidity triggers confirmation"
	)
	assertions.truthy(
		trade_script.call("needs_confirmation", 1, 20, 600, 1000, 10, 10),
		"half-wallet spend triggers confirmation"
	)
	assertions.truthy(
		trade_script.call("needs_confirmation", 10, 100, 100, 1000, 10, 8),
		"ten-percent tail drop triggers confirmation"
	)
	assertions.truthy(
		not trade_script.call("needs_confirmation", 1, 20, 10, 1000, 10, 10),
		"ordinary trade stays immediate"
	)
	assertions.equal(trade_script.call("impact_for", 1, 20), "none", "small trade has no impact")
	assertions.equal(trade_script.call("impact_for", 4, 20), "light", "moderate trade has light impact")
	assertions.equal(trade_script.call("impact_for", 10, 20), "clear", "large trade has clear impact")
	assertions.equal(trade_script.call("impact_for", 20, 20), "severe", "liquidity trade has severe impact")
	assertions.equal(trade_script.call("localized_impact", "none"), "无明显影响", "no impact is player-facing Chinese")
	assertions.equal(trade_script.call("localized_impact", "light"), "轻微", "light impact is player-facing Chinese")
	assertions.equal(trade_script.call("localized_impact", "clear"), "明显", "clear impact is player-facing Chinese")
	assertions.equal(trade_script.call("localized_impact", "severe"), "剧烈", "severe impact is player-facing Chinese")
	assertions.truthy(trade_script.call("needs_sell_confirmation", 20, 20, 10, 10), "sell liquidity threshold still confirms")
	assertions.truthy(trade_script.call("needs_sell_confirmation", 1, 20, 10, 9), "sell tail drop still confirms")
	assertions.truthy(not trade_script.call("needs_sell_confirmation", 1, 20, 10, 10), "ordinary sell ignores wallet-only threshold")
	assertions.truthy(trade_script.has_method("safe_quantity"), "trade exposes bounded quantity normalization")
	if trade_script.has_method("safe_quantity"):
		assertions.equal(trade_script.call("safe_quantity", NAN, 60, 2), 0, "NaN quantity is rejected")
		assertions.equal(trade_script.call("safe_quantity", 1.0e30, 60, 2), 60, "huge quantity clamps to authoritative availability")
		assertions.equal(trade_script.call("safe_quantity", 1.0e30, 1000000000, 1000000000), 999, "huge authoritative counts remain hard capped")


func _test_modal_coordinator(assertions: TestAssert, tree: SceneTree) -> void:
	assertions.truthy(ResourceLoader.exists(MODAL_SCRIPT_PATH), "economy modal coordinator exists")
	if not ResourceLoader.exists(MODAL_SCRIPT_PATH):
		return
	var coordinator_script: Script = load(MODAL_SCRIPT_PATH)
	var coordinator = coordinator_script.new()
	var owner := Control.new()
	var stranger := Control.new()
	tree.root.add_child(owner)
	tree.root.add_child(stranger)
	tree.paused = false
	assertions.truthy(coordinator.acquire(owner), "modal owner acquires unpaused tree")
	assertions.truthy(tree.paused, "modal acquire pauses unpaused tree")
	assertions.equal(owner.process_mode, Node.PROCESS_MODE_WHEN_PAUSED, "modal owner processes while paused")
	assertions.truthy(not coordinator.acquire(owner), "duplicate acquire is idempotently rejected")
	assertions.truthy(not coordinator.release(stranger), "non-owner cannot release modal")
	assertions.truthy(tree.paused, "non-owner release preserves pause")
	assertions.truthy(coordinator.release(owner), "modal owner releases modal")
	assertions.truthy(not tree.paused, "release restores prior unpaused state")
	assertions.truthy(not coordinator.release(owner), "duplicate release is idempotently rejected")

	tree.paused = true
	assertions.truthy(coordinator.acquire(owner), "modal owner acquires previously paused tree")
	assertions.truthy(coordinator.release(owner), "modal owner releases previously paused tree")
	assertions.truthy(tree.paused, "release restores prior paused state")
	tree.paused = false
	owner.free()
	stranger.free()

	var removed_owner := Control.new()
	removed_owner.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(removed_owner)
	assertions.truthy(coordinator.acquire(removed_owner), "removal fixture acquires unpaused tree")
	tree.root.remove_child(removed_owner)
	assertions.truthy(not tree.paused, "owner removal restores prior unpaused state")
	assertions.equal(removed_owner.process_mode, Node.PROCESS_MODE_ALWAYS, "owner removal restores process mode")
	tree.paused = true
	removed_owner.free()
	assertions.truthy(tree.paused, "free after removal does not restore pause twice")
	tree.paused = false

	var freed_owner := Control.new()
	tree.root.add_child(freed_owner)
	tree.paused = true
	assertions.truthy(coordinator.acquire(freed_owner), "free fixture acquires previously paused tree")
	freed_owner.free()
	assertions.truthy(tree.paused, "owner free restores prior paused state")
	tree.paused = false
	var next_owner := Control.new()
	tree.root.add_child(next_owner)
	assertions.truthy(coordinator.acquire(next_owner), "owner free clears coordinator ownership")
	assertions.truthy(coordinator.release(next_owner), "new owner releases after prior owner free")
	assertions.truthy(not tree.paused, "new owner release restores its own pause snapshot")
	next_owner.free()


func _test_hud_market_request(assertions: TestAssert, tree: SceneTree) -> void:
	var hud_scene := load("res://scenes/ui/hud.tscn") as PackedScene
	if hud_scene == null:
		return
	var hud := hud_scene.instantiate()
	tree.root.add_child(hud)
	await tree.process_frame
	assertions.truthy(hud.has_signal("market_requested"), "HUD exposes market_requested")
	assertions.truthy(hud.has_node("EconomyActions/MarketButton"), "HUD has top-right market button")
	assertions.truthy(hud.has_node("EconomyActions/NotificationButton"), "HUD has notification count button")
	if (
		hud.has_signal("market_requested")
		and hud.has_node("EconomyActions/MarketButton")
	):
		var counter := SignalCounter.new()
		hud.connect("market_requested", counter.record)
		var market_button := hud.get_node("EconomyActions/MarketButton") as Button
		market_button.pressed.emit()
		assertions.equal(counter.count, 1, "one market press emits exactly one request")
	if (
		hud.has_node("EconomyActions/MarketButton")
		and hud.has_node("EconomyActions/NotificationButton")
		and hud.has_node("DebugResetButton")
	):
		var market_rect: Rect2 = hud.get_node("EconomyActions/MarketButton").get_global_rect()
		var notice_rect: Rect2 = hud.get_node("EconomyActions/NotificationButton").get_global_rect()
		var debug_rect: Rect2 = hud.get_node("DebugResetButton").get_global_rect()
		assertions.truthy(not market_rect.intersects(debug_rect), "market button does not overlap debug reset")
		assertions.truthy(not notice_rect.intersects(debug_rect), "notification button does not overlap debug reset")
	hud.free()


func _test_market_snapshot_and_transactions(assertions: TestAssert, tree: SceneTree) -> void:
	if not ResourceLoader.exists(SHOP_SCENE_PATH) or not ResourceLoader.exists(MARKET_SCENE_PATH):
		return
	var inventory := InventorySystem.new()
	var market := MarketSystem.new()
	var economy := EconomySystem.new()
	tree.root.add_child(inventory)
	tree.root.add_child(market)
	tree.root.add_child(economy)
	assertions.truthy(market.configure(GameDataScript.get_market_items()), "market UI fixture configures real market")
	var wallet := tree.root.get_node_or_null("GameState")
	assertions.truthy(wallet != null, "market UI fixture finds authoritative wallet")
	if wallet == null:
		economy.free()
		market.free()
		inventory.free()
		return
	var previous_gold := int(wallet.gold)
	wallet.gold = 1000
	assertions.truthy(economy.configure(inventory, wallet, market), "market UI fixture configures real economy")
	assertions.truthy(inventory.add_item("wood", 2), "market UI fixture gives player wood")

	var shop_scene := load(SHOP_SCENE_PATH) as PackedScene
	var shop = shop_scene.instantiate()
	tree.root.add_child(shop)
	await tree.process_frame
	assertions.truthy(shop.call("configure", inventory, economy, market), "economy hub configures")
	shop.call("open")
	assertions.truthy(tree.paused, "economy hub pauses the tree")
	assertions.truthy(shop.visible, "economy hub opens visibly")
	assertions.truthy(shop.call("select_tab", "orders"), "economy hub selects orders tab")
	shop.call("close")
	assertions.truthy(not tree.paused, "economy hub close restores unpaused tree")
	shop.call("open")
	assertions.equal(shop.get("selected_tab"), "orders", "economy hub preserves selected tab")
	assertions.truthy(shop.call("select_tab", "market"), "economy hub returns to market tab")

	var market_panel = shop.get_node("ScreenLayer/ModalLayer/HubPanel/Margin/Shell/PageHost/MarketPanel")
	# This fixture verifies the layered Escape behavior of the compact drawer.
	# Pin its logical width instead of depending on the headless runner's window.
	market_panel.call("apply_responsive_layout", Vector2(900.0, 720.0))
	market_panel.call("select_category", "raw_materials")
	market_panel.call("select_item", "wood")
	market_panel.call("refresh_snapshot")
	assertions.equal(market_panel.get("selected_category"), "raw_materials", "market preserves selected category")
	assertions.equal(market_panel.get("selected_item_id"), "wood", "market preserves selected item")
	assertions.truthy(market_panel.get_node("Columns/DetailColumn/DetailContent/DetailHeader/ItemNameLabel").text.contains("木材"), "wood selection shows name")
	assertions.truthy(market_panel.get_node("Columns/DetailColumn/DetailContent/PriceMetrics/MidPriceLabel").text.contains(str(market.get_mid_price("wood"))), "wood selection shows mid price")
	assertions.truthy(market_panel.get_node("Columns/DetailColumn/DetailContent/PriceMetrics/BuyPriceLabel").text.contains(str(market.quote_buy("wood", 1))), "wood selection shows buy price")
	assertions.truthy(market_panel.get_node("Columns/DetailColumn/DetailContent/PriceMetrics/SellPriceLabel").text.contains(str(market.quote_sell("wood", 1))), "wood selection shows sell price")
	assertions.truthy(market_panel.get_node("Columns/DetailColumn/DetailContent/StockLabel").text.contains(str(market.get_stock("wood"))), "wood selection shows finite market stock")
	var wood_state := market.get_item_state("wood")
	var flow_text: String = market_panel.get_node("Columns/DetailColumn/DetailContent/FlowLabel").text
	for field in ["supply", "demand", "daily_liquidity"]:
		assertions.truthy(flow_text.contains(str(wood_state[field])), "wood selection shows %s" % field)
	assertions.truthy(market_panel.get_node("Columns/DetailColumn/DetailContent/TagsLabel").text.contains("essential"), "wood selection shows market tags")
	var chart = market_panel.get_node("Columns/DetailColumn/DetailContent/PriceChart")
	assertions.equal(chart.get("history").size(), market.get_history("wood").size(), "chart uses only observed 1-7 day history")
	assertions.equal(chart.get("dates").size(), chart.get("history").size(), "market binds one date per observed price")
	assertions.equal(chart.get("change_reasons").size(), chart.get("history").size(), "market binds one reason per observed price")
	assertions.truthy(not str(chart.get("dates")[0]).is_empty(), "market history date is explicit")
	assertions.truthy(not str(chart.get("change_reasons")[0]).is_empty(), "market history reason is explicit")
	_test_market_row_affordances(assertions, market_panel, market)

	var trade = market_panel.get_node("Columns/TradePanel")
	var quantity_spin := trade.get_node("Content/QuantityRow/QuantitySpin") as SpinBox
	assertions.truthy(not quantity_spin.allow_greater, "quantity spin rejects values above authoritative maximum")
	quantity_spin.value = 2
	trade.call("refresh_quote")
	assertions.truthy(trade.get_node("Content/SummaryGrid/PlayerQuantityLabel").text.contains("2"), "trade shows player quantity")
	assertions.truthy(trade.get_node("Content/SummaryGrid/MarketQuantityLabel").text.contains(str(market.get_stock("wood"))), "trade shows market quantity")
	assertions.truthy(trade.get_node("Content/SummaryGrid/BuyTotalLabel").text.contains(str(market.quote_buy("wood", 2))), "trade shows slippage-adjusted buy total")
	assertions.truthy(trade.get_node("Content/SummaryGrid/SellTotalLabel").text.contains(str(market.quote_sell("wood", 2))), "trade shows slippage-adjusted sell total")
	_test_stale_confirmation_and_quantity_safety(assertions, market_panel, trade, inventory, market, wallet)
	_test_market_rows_refresh_after_trade(assertions, market_panel, trade, inventory, market, wallet)

	quantity_spin.value = 1
	wallet.gold = market.quote_buy("wood", 1)
	trade.call("refresh_quote")
	var owned_before_low_gold_sell := inventory.get_item_count("wood")
	trade.call("request_sell")
	assertions.truthy(not trade.get_node("ConfirmationLayer").visible, "low-wallet ordinary sell does not confirm for wallet ratio")
	assertions.equal(inventory.get_item_count("wood"), owned_before_low_gold_sell - 1, "low-wallet ordinary sell executes immediately")
	trade.call("dismiss_confirmation")
	wallet.gold = market.quote_buy("wood", 1)
	trade.call("refresh_quote")
	var owned_before_low_gold_buy := inventory.get_item_count("wood")
	trade.call("request_buy")
	assertions.truthy(trade.get_node("ConfirmationLayer").visible, "same low-wallet buy confirms for half-wallet spend")
	assertions.equal(inventory.get_item_count("wood"), owned_before_low_gold_buy, "confirmed buy waits for player approval")
	trade.call("dismiss_confirmation")
	wallet.gold = 1000
	trade.call("refresh_quote")

	quantity_spin.value = 1
	trade.call("refresh_quote")
	var gold_before := int(wallet.gold)
	var owned_before := inventory.get_item_count("wood")
	var stock_before := market.get_stock("wood")
	var buy_total_before := market.quote_buy("wood", 1)
	trade.call("request_buy")
	assertions.equal(int(wallet.gold), gold_before - buy_total_before, "successful buy refreshes gold in same frame")
	assertions.equal(inventory.get_item_count("wood"), owned_before + 1, "successful buy refreshes inventory in same frame")
	assertions.equal(market.get_stock("wood"), stock_before - 1, "successful buy refreshes stock in same frame")
	assertions.truthy(trade.get_node("Content/SummaryGrid/PlayerQuantityLabel").text.contains(str(owned_before + 1)), "successful buy redraws player quantity in same frame")
	assertions.truthy(trade.get_node("Content/SummaryGrid/MarketQuantityLabel").text.contains(str(stock_before - 1)), "successful buy redraws stock in same frame")
	assertions.truthy(
		market_panel.get_node("Columns/DetailColumn/DetailContent/StockLabel").text.contains(str(stock_before - 1)),
		"successful buy redraws market detail stock in same frame"
	)

	wallet.gold = 0
	trade.call("refresh_quote")
	gold_before = int(wallet.gold)
	owned_before = inventory.get_item_count("wood")
	stock_before = market.get_stock("wood")
	var rejected_total := market.quote_buy("wood", 1)
	trade.call("request_buy")
	assertions.equal(int(wallet.gold), gold_before, "failed buy preserves gold")
	assertions.equal(inventory.get_item_count("wood"), owned_before, "failed buy preserves inventory")
	assertions.equal(market.get_stock("wood"), stock_before, "failed buy preserves market stock")
	assertions.equal(
		trade.get_node("Content/Actions/BuyButton").tooltip_text,
		"金币不足 %d" % rejected_total,
		"failed buy shows exact disabled reason"
	)

	wallet.gold = 1000
	quantity_spin.value = int(wood_state.daily_liquidity)
	trade.call("refresh_quote")
	trade.call("request_buy")
	assertions.truthy(trade.get_node("ConfirmationLayer").visible, "large trade opens confirmation")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	shop.call("_unhandled_input", escape)
	assertions.truthy(not trade.get_node("ConfirmationLayer").visible, "first Escape closes only trade confirmation")
	assertions.truthy(shop.visible and tree.paused, "closing top confirmation keeps economy hub open")
	shop.call("_unhandled_input", escape)
	assertions.truthy(shop.visible and tree.paused, "second Escape closes only the narrow-screen detail drawer")
	assertions.truthy(market_panel.get_node("Columns/CatalogColumn").visible, "closing detail drawer restores product list")
	shop.call("_unhandled_input", escape)
	assertions.truthy(not shop.visible, "third Escape closes economy hub after drawer")
	assertions.truthy(not tree.paused, "Escape close restores prior pause")

	shop.call("open")
	assertions.equal(market_panel.get("selected_category"), "raw_materials", "reopen preserves market category")
	assertions.equal(market_panel.get("selected_item_id"), "wood", "reopen preserves market item")
	shop.call("close")
	wallet.gold = previous_gold
	shop.free()
	economy.free()
	market.free()
	inventory.free()


func _test_market_row_affordances(
	assertions: TestAssert,
	market_panel: Node,
	market: MarketSystem
) -> void:
	if not market_panel.has_node("Columns/CatalogColumn/CatalogContent/ItemScroll/ItemRows"):
		return
	var normal_snapshot := market.to_dict()
	var shortage_snapshot := normal_snapshot.duplicate(true)
	var wood_state: Dictionary = shortage_snapshot["items"]["wood"]
	wood_state["stock"] = 1
	wood_state["demand"] = int(wood_state["daily_liquidity"])
	wood_state["supply"] = 0
	shortage_snapshot["items"]["wood"] = wood_state
	assertions.truthy(market.from_dict(shortage_snapshot), "shortage row fixture restores valid finite market state")
	market_panel.call("select_category", "raw_materials")
	var rows := market_panel.get_node("Columns/CatalogColumn/CatalogContent/ItemScroll/ItemRows")
	var wood_row := _find_item_row(rows, "wood")
	var stone_row := _find_item_row(rows, "stone")
	var fiber_row := _find_item_row(rows, "fiber")
	assertions.truthy(wood_row != null, "market renders a wood row")
	assertions.truthy(stone_row != null, "market renders a normal-stock row")
	assertions.truthy(fiber_row != null, "market renders a fallback-icon row")
	if wood_row != null:
		assertions.truthy(wood_row.get_node("Content/Icon").texture != null, "wood row renders a product icon")
		assertions.equal(wood_row.custom_minimum_size.y, 52.0, "market rows use the aligned list-row height")
		assertions.truthy(
			(wood_row.get_node("Content/SelectButton") as Button).clip_text,
			"long shortage rows clip inside the compact catalog column"
		)
		assertions.equal(
			(wood_row.get_node("Content/SelectButton") as Button).text_overrun_behavior,
			TextServer.OVERRUN_TRIM_ELLIPSIS,
			"long market rows end with a clean ellipsis"
		)
		assertions.equal(wood_row.get_node("Content/StockColorBar").color, Color("#B65C4B"), "finite shortage renders error stock color bar")
		assertions.truthy(wood_row.get_node("Content/UrgentBadge").visible, "finite shortage and real demand show urgent badge")
	if stone_row != null:
		assertions.truthy(not stone_row.get_node("Content/UrgentBadge").visible, "normal stock without demand hides urgent badge")
	if fiber_row != null:
		assertions.truthy(fiber_row.get_node("Content/Icon").texture != null, "missing product art uses a safe placeholder")
		assertions.truthy(bool(fiber_row.get_meta("uses_fallback_icon", false)), "fallback icon is marked consistently")
	assertions.truthy(market.from_dict(normal_snapshot), "market row fixture restores normal state")
	market_panel.call("select_category", "raw_materials")
	market_panel.call("select_item", "wood")


func _find_item_row(rows: Node, item_id: String) -> Node:
	for row in rows.get_children():
		if str(row.get_meta("item_id", "")) == item_id:
			return row
	return null


func _test_stale_confirmation_and_quantity_safety(
	assertions: TestAssert,
	market_panel: Node,
	trade: Node,
	inventory: InventorySystem,
	market: MarketSystem,
	wallet: Node
) -> void:
	var quantity_spin := trade.get_node("Content/QuantityRow/QuantitySpin") as SpinBox
	if trade.get_script().has_method("safe_quantity"):
		var safe_snapshot := _asset_snapshot(inventory, market, wallet)
		quantity_spin.value = 1.0e30
		trade.call("request_buy")
		assertions.truthy(quantity_spin.value <= 999.0, "huge spin input is bounded before quoting")
		_assert_assets_equal(assertions, safe_snapshot, inventory, market, wallet, "huge spin input")
		trade.call("dismiss_confirmation")
		quantity_spin.value = NAN
		trade.call("request_buy")
		_assert_assets_equal(assertions, safe_snapshot, inventory, market, wallet, "NaN spin input")

	var normal_snapshot := _full_trade_snapshot(inventory, market, wallet)
	quantity_spin.value = int(market.get_item_state("wood").daily_liquidity)
	trade.call("refresh_quote")
	trade.call("request_buy")
	assertions.truthy(trade.get_node("ConfirmationLayer").visible, "stale quantity fixture opens confirmation")
	var before_quantity_change := _asset_snapshot(inventory, market, wallet)
	quantity_spin.value = 1
	assertions.truthy(not trade.get_node("ConfirmationLayer").visible, "quantity change cancels pending confirmation")
	trade.call("_confirm_pending_trade")
	_assert_assets_equal(assertions, before_quantity_change, inventory, market, wallet, "quantity-changed confirmation")
	_restore_trade_snapshot(normal_snapshot, inventory, market, wallet)
	market_panel.call("select_category", "raw_materials")
	market_panel.call("select_item", "wood")

	quantity_spin.value = int(market.get_item_state("wood").daily_liquidity)
	trade.call("request_buy")
	wallet.gold = int(wallet.gold) - 1
	var before_wallet_confirm := _asset_snapshot(inventory, market, wallet)
	trade.call("_confirm_pending_trade")
	_assert_assets_equal(assertions, before_wallet_confirm, inventory, market, wallet, "wallet-changed confirmation")
	assertions.truthy(trade.get_node("Content/StatusArea/FeedbackLabel").text.contains("状态已变化"), "wallet change requires a fresh confirmation")
	_restore_trade_snapshot(normal_snapshot, inventory, market, wallet)
	market_panel.call("select_category", "raw_materials")
	market_panel.call("select_item", "wood")

	quantity_spin.value = int(market.get_item_state("wood").daily_liquidity)
	trade.call("request_buy")
	assertions.truthy(market.commit_buy("wood", 1), "external stock change fixture commits")
	var before_stock_confirm := _asset_snapshot(inventory, market, wallet)
	assertions.truthy(not trade.get_node("ConfirmationLayer").visible, "authoritative stock signal cancels pending confirmation")
	trade.call("_confirm_pending_trade")
	_assert_assets_equal(assertions, before_stock_confirm, inventory, market, wallet, "stock-changed confirmation")
	_restore_trade_snapshot(normal_snapshot, inventory, market, wallet)
	market_panel.call("select_category", "raw_materials")
	market_panel.call("select_item", "wood")


func _test_market_rows_refresh_after_trade(
	assertions: TestAssert,
	market_panel: Node,
	trade: Node,
	inventory: InventorySystem,
	market: MarketSystem,
	wallet: Node
) -> void:
	var normal_snapshot := _full_trade_snapshot(inventory, market, wallet)
	var crossing_snapshot: Dictionary = normal_snapshot.market.duplicate(true)
	var wood_state: Dictionary = crossing_snapshot["items"]["wood"]
	wood_state["stock"] = 28
	wood_state["demand"] = 0
	wood_state["supply"] = 0
	crossing_snapshot["items"]["wood"] = wood_state
	assertions.truthy(market.from_dict(crossing_snapshot), "row refresh fixture sets stock boundary")
	wallet.gold = 1000
	market_panel.call("set_sort_mode", "name")
	market_panel.call("select_category", "raw_materials")
	market_panel.call("select_item", "wood")
	var scroll := market_panel.get_node("Columns/CatalogColumn/CatalogContent/ItemScroll") as ScrollContainer
	scroll.scroll_vertical = mini(12, roundi(scroll.get_v_scroll_bar().max_value))
	var scroll_before := scroll.scroll_vertical
	var category_before: String = market_panel.get("selected_category")
	var sort_before: String = market_panel.get("sort_mode")
	var rows := market_panel.get_node("Columns/CatalogColumn/CatalogContent/ItemScroll/ItemRows")
	var old_row := _find_item_row(rows, "wood")
	assertions.truthy(old_row != null, "row refresh fixture finds selected row")
	if old_row != null:
		assertions.equal(int(old_row.get_meta("stock", -1)), 28, "row snapshot stores finite stock")
		assertions.equal(old_row.get_node("Content/StockColorBar").color, Color("#C58B35"), "boundary row begins warning-colored")
		assertions.truthy(not old_row.get_node("Content/UrgentBadge").visible, "boundary row begins without urgent badge")
	var owned_before := inventory.get_item_count("wood")
	var quantity_spin := trade.get_node("Content/QuantityRow/QuantitySpin") as SpinBox
	quantity_spin.value = 1
	trade.call("request_buy")
	var new_row := _find_item_row(rows, "wood")
	assertions.truthy(new_row != null and new_row != old_row, "trade rebuilds item row in same frame")
	if new_row != null:
		assertions.equal(int(new_row.get_meta("stock", -1)), 27, "rebuilt row shows committed stock")
		assertions.equal(int(new_row.get_meta("owned", -1)), owned_before + 1, "rebuilt row shows committed player quantity")
		assertions.equal(new_row.get_node("Content/StockColorBar").color, Color("#B65C4B"), "rebuilt row updates stock color bar")
		assertions.truthy(new_row.get_node("Content/UrgentBadge").visible, "rebuilt row updates urgent badge")
		assertions.truthy(new_row.get_node("Content/SelectButton").button_pressed, "rebuilt row preserves selection")
	assertions.equal(market_panel.get("selected_category"), category_before, "row refresh preserves category")
	assertions.equal(market_panel.get("sort_mode"), sort_before, "row refresh preserves sort mode")
	assertions.equal(scroll.scroll_vertical, scroll_before, "row refresh preserves scroll position")
	_restore_trade_snapshot(normal_snapshot, inventory, market, wallet)
	market_panel.call("set_sort_mode", "recommended")
	market_panel.call("select_category", "raw_materials")
	market_panel.call("select_item", "wood")


func _asset_snapshot(inventory: InventorySystem, market: MarketSystem, wallet: Node) -> Dictionary:
	return {
		"gold": int(wallet.gold),
		"owned": inventory.get_item_count("wood"),
		"stock": market.get_stock("wood"),
	}


func _full_trade_snapshot(inventory: InventorySystem, market: MarketSystem, wallet: Node) -> Dictionary:
	return {
		"gold": int(wallet.gold),
		"slots": inventory.slots.duplicate(true),
		"mappings": inventory.quick_slot_mappings.duplicate(),
		"market": market.to_dict(),
	}


func _restore_trade_snapshot(snapshot: Dictionary, inventory: InventorySystem, market: MarketSystem, wallet: Node) -> void:
	wallet.gold = int(snapshot.gold)
	inventory.restore_state(snapshot.slots, snapshot.mappings)
	market.from_dict(snapshot.market)


func _assert_assets_equal(
	assertions: TestAssert,
	expected: Dictionary,
	inventory: InventorySystem,
	market: MarketSystem,
	wallet: Node,
	message: String
) -> void:
	assertions.equal(int(wallet.gold), int(expected.gold), message + " preserves gold")
	assertions.equal(inventory.get_item_count("wood"), int(expected.owned), message + " preserves inventory")
	assertions.equal(market.get_stock("wood"), int(expected.stock), message + " preserves stock")
