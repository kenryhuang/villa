extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(50).timeout.connect(func(): push_error("Market test timed out"); quit(1))
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _frames(count := 3) -> void:
	for i in count:
		await physics_frame
		await process_frame

func _press(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)

func _write(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

func _run() -> void:
	root.size = Vector2i(1440, 960)
	var farm := (load("res://scenes/farm3d/main.tscn") as PackedScene).instantiate()
	root.add_child(farm)
	await _frames()
	var session = farm.get_node("FarmSession")
	var interaction = farm.get_node("FarmInteraction")
	var hud = interaction.hud
	var view = hud.market_view
	var market = session.market
	var player = session.player
	var building = interaction.market_building
	var wallet = root.get_node("GameState")
	session.season.set_process(false)
	session.save_path = "user://farm3d_market_test.json"
	player.set_physics_process(false)
	farm.set_process(false)
	var camera := Camera3D.new()
	farm.add_child(camera)
	camera.position = building.position + Vector3(9, 8, 13)
	camera.look_at(building.position + Vector3(0, 1.6, 0))
	camera.make_current()
	player.position = building.position + Vector3(0, 0, 4.5)
	await _frames(8)
	_check(not view.visible, "Market starts closed without a menu entry")
	_check(hud.category_buttons.size() == 3, "Market adds no toolbar category")
	_check(session.market_site == Vector2(-12, 12), "New farm market is on the southwest village land")
	_check(building.get_node_or_null("MarketPickTarget") != null, "Market has a world click target")
	_check(building.find_children("*", "MeshInstance3D", true, false).size() > 50, "Market includes roof, counters, crates and produce geometry")
	for cell in session.MarketSite.cells(session.grid, session.market_site):
		_check(cell.state == GridCell.State.DECORATION, "Market footprint is reserved from planting/building")
	var pointer: Vector2 = camera.unproject_position(building.position + Vector3(0, 1.8, 2.5))
	_check(interaction.market_at_pointer(pointer), "Camera ray picks the actual market building")
	player.position = Vector3.ZERO
	_check(not interaction.open_market() and not view.visible, "Distant clicks cannot trade remotely")
	player.position = building.position + Vector3(0, 0, -3)
	_check(not interaction.open_market(), "Rear wall cannot be used to trade through the building")
	player.position = building.position + Vector3(0, 0, 4.5)
	if "--capture-market" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/validation/market-3d-building.png")
	interaction.select_target("farmland", "dry")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = pointer
	root.push_input(click, true)
	await _frames(8)
	_check(view.visible and player.ui_blocked, "Real mouse click opens trade and blocks player movement")
	_check(interaction.target_id.is_empty(), "Opening market cancels farming placement")
	_check(not interaction.perform(interaction.front_cell()).ok, "Trading prevents world edits")
	_check(view.market_panel is MarketPanel and view.market_panel.trade_panel is TradePanel, "3D uses the original catalog and trade UI")
	_check(view.market_panel.market_ref == market and session.economy._market_ref == market, "UI and economy share the authoritative market")
	for row in view.market_panel.item_rows.get_children():
		_check(not row.get_node("Content/Icon").texture is PlaceholderTexture2D, "Market catalog uses real or neutral goods icons")
	view.market_panel.select_item("wood")
	var trade = view.market_panel.trade_panel
	var gold: int = wallet.gold
	var stock: int = market.get_stock("wood")
	var owned: int = session.inventory.get_item_count("wood")
	var quote: int = market.quote_buy("wood", 2)
	trade.quantity_spin.value = 2
	trade.request_buy()
	_check(wallet.gold == gold - quote, "Buy uses original batch quote and shared wallet")
	_check(market.get_stock("wood") == stock - 2 and session.inventory.get_item_count("wood") == owned + 2, "Buy transfers exactly matching stock to backpack")
	_check(int(market.get_item_state("wood").demand) == 2, "Buy contributes to original demand pressure")
	session.inventory.add_item("creek_crucian", 2)
	view.market_panel.select_item("creek_crucian")
	gold = wallet.gold
	stock = market.get_stock("creek_crucian")
	quote = market.quote_sell("creek_crucian", 1)
	trade.request_sell()
	_check(wallet.gold == gold + quote and session.inventory.get_item_count("creek_crucian") == 1, "Caught fish can be sold from the same backpack")
	_check(market.get_stock("creek_crucian") == stock + 1, "Fish sale returns goods to market stock")
	wallet.gold = 0
	var before: Dictionary = market.to_dict()
	var slots: Array = session.inventory.slots.duplicate(true)
	_check(not session.economy.buy_item("wood", 1), "Insufficient gold rejects purchase")
	_check(market.to_dict() == before and session.inventory.slots == slots and wallet.gold == 0, "Rejected trade leaves stock, backpack and wallet unchanged")
	wallet.gold = 50000
	_check(not session.economy.buy_item("wood", market.get_stock("wood") + 1), "Finite stock rejects oversize purchase")
	_check(not session.economy.sell_item("wood", 9999), "Cannot sell goods absent from backpack")
	view.market_panel.select_item("wood")
	trade.quantity_spin.value = min(40, market.get_stock("wood"))
	trade.request_buy()
	_check(trade.confirmation_layer.visible, "Large trade keeps original price-impact confirmation")
	_press(KEY_ESCAPE)
	_check(not trade.confirmation_layer.visible and view.visible, "First Esc dismisses confirmation while keeping market open")
	view.market_panel.select_item("wood")
	await _frames(8)
	_check(view._window.get_global_rect().end.x <= root.size.x and view._window.get_global_rect().end.y <= root.size.y, "Market window fits desktop viewport")
	if "--capture-market" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/validation/market-3d-trading.png")
	_press(KEY_ESCAPE)
	_check(not view.visible and not player.ui_blocked, "Esc exits market and restores movement")
	var day: int = session.season.total_days
	var history_size: int = market.get_history("wood").size()
	session.rest()
	_check(market.last_settled_day == day + 1 and session.npc_economy.last_simulated_day == day + 1, "Rest runs original NPC economy and daily market settlement")
	_check(market.get_history("wood").size() == history_size + 1 and int(market.get_item_state("wood").demand) == 0, "Day settlement appends price history and clears daily pressure")
	before = market.to_dict()
	session._settle_market_day(day + 1)
	_check(market.to_dict() == before, "Repeated day event does not double settle")
	_check(session.save_game(), "3D save writes market economy state")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(session.save_path))
	var saved_npc: Dictionary = session.npc_economy.to_dict()
	gold = wallet.gold
	session.economy.buy_item("wood", 1)
	session.rest()
	_check(session.load_game(), "Saved market restores successfully")
	_check(market.to_dict() == before and session.npc_economy.to_dict() == saved_npc and wallet.gold == gold, "Reload restores prices, stock, NPC balances and player gold together")
	var invalid := saved.duplicate(true)
	invalid.market.items.wood.stock = -1
	_write(session.save_path, invalid)
	_check(not session.load_game() and market.to_dict() == before and wallet.gold == gold, "Corrupt market save is rejected before changing live state")
	invalid = saved.duplicate(true)
	invalid.market.last_settled_day += 1
	_check(not session._valid_save(invalid), "Incoherent market/day cursor is rejected")
	var legacy := saved.duplicate(true)
	legacy.version = 2
	for field in ["market", "npc_economy", "market_site", "golf", "agents"]:
		legacy.erase(field)
	var occupied: GridCell = session.MarketSite.cells(session.grid, Vector2(-12, 12))[0]
	legacy.grid.cells.append({"gx": occupied.gx, "gz": occupied.gz, "state": GridCell.State.FARMLAND, "watered": true})
	_write(session.save_path, legacy)
	_check(session.load_game(), "Pre-market v2 save migrates")
	_check(session.market_site != Vector2(-12, 12) and occupied.state == GridCell.State.FARMLAND and occupied.watered, "Legacy crops displace the market without losing farmland")
	_check(building.position.x == session.market_site.x and building.position.z == session.market_site.y, "Market model follows migrated site")
	_check(market.last_settled_day == session.season.total_days, "Legacy migration starts economics at the saved day")
	_check(session.save_game() and session.load_game(), "Migrated market location remains stable on reload")
	player.position = building.position + Vector3(0, 0, 4.5)
	interaction.open_market()
	_press(KEY_I)
	_check(not view.visible and hud.inventory_ui.visible, "Opening backpack closes trade cleanly")
	hud.close_panels()
	# Exercise actual container sizing, not just the requested layout mode.
	root.content_scale_size = Vector2i(900, 720)
	root.size = Vector2i(900, 720)
	await _frames(5)
	interaction.open_market()
	await _frames(5)
	view.market_panel.select_item("wood")
	await _frames(5)
	_check(view.market_panel.get_layout_mode() == "drawer" and view.market_panel._drawer_open, "Original narrow-screen details drawer remains available")
	_check(view._window.get_global_rect().end.x <= 900 and view._window.get_global_rect().end.y <= 720, "Small-window trading fits within the viewport")
	_check(trade.buy_button.is_visible_in_tree(), "Small-window trade actions remain accessible")
	if "--capture-market" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/validation/market-3d-narrow.png")
	view.close_market()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(session.save_path))
	farm.queue_free()
	await _frames(2)
	print("3D MARKET: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
