extends RefCounted

const PANEL_SCENE_PATH := "res://scenes/ui/economy/service_panel.tscn"
const SHOP_SCENE_PATH := "res://scenes/ui/shop_ui.tscn"
const ProgressionScript = preload("res://scripts/systems/economy_progression_system.gd")
const ToolSystemScript = preload("res://scripts/systems/tool_system.gd")
const ProductionSystemScript = preload("res://scripts/systems/production_system.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const MarketSystemScript = preload("res://scripts/systems/market_system.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")
const BuildingDataScript = preload("res://scripts/data/building_data.gd")
const ProducerStateScript = preload("res://scripts/data/producer_state.gd")


class DaySource:
	extends RefCounted
	var total_days := 1


func run(assertions: TestAssert, tree: SceneTree) -> void:
	_test_scene_contract(assertions)
	_test_categories_cards_transactions_and_shop_route(assertions, tree)


func _test_scene_contract(assertions: TestAssert) -> void:
	assertions.truthy(ResourceLoader.exists(PANEL_SCENE_PATH), "service panel scene exists")
	if not ResourceLoader.exists(PANEL_SCENE_PATH):
		return
	var packed := load(PANEL_SCENE_PATH) as PackedScene
	assertions.truthy(packed != null, "service panel scene loads")
	if packed == null:
		return
	var panel := packed.instantiate()
	for path in [
		"CategoryBar/Blueprints", "CategoryBar/Recipes", "CategoryBar/Repairs",
		"CategoryBar/Upgrades", "CategoryBar/Maintenance",
		"CategoryBar/TransportStorage", "CategoryBar/LandExpansion",
		"ServiceScroll/ServiceCards", "EmptyLabel", "FeedbackLabel",
	]:
		assertions.truthy(panel.has_node(path), "service panel has %s" % path)
	panel.free()


func _test_categories_cards_transactions_and_shop_route(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	if not ResourceLoader.exists(PANEL_SCENE_PATH):
		return
	var wallet := tree.root.get_node_or_null("GameState")
	if wallet == null:
		return
	var original_gold := int(wallet.gold)
	var original_level := int(wallet.player_state.level)
	var inventory := InventorySystemScript.new() as InventorySystem
	inventory.reset_slots()
	var tool := ToolSystemScript.new() as ToolSystem
	tool.configure(null, inventory, null)
	var production := ProductionSystemScript.new() as ProductionSystem
	var building := _building("windmill", 4, 5)
	production.register_building(building)
	var day := DaySource.new()
	var progression = ProgressionScript.new()
	assertions.truthy(progression.configure(tool, production, inventory, day, wallet), "service progression configures")
	var panel := (load(PANEL_SCENE_PATH) as PackedScene).instantiate()
	tree.root.add_child(panel)
	assertions.truthy(panel.configure(progression, tool, production), "service panel configures")
	assertions.truthy(panel.configure(progression, tool, production), "service panel repeated configure is idempotent")
	assertions.truthy(panel.has_method("select_service"), "service panel exposes deep-link selection")
	if panel.has_method("select_service"):
		assertions.truthy(panel.call("select_service", "blueprint_furnace"), "service can be deep-linked")
		assertions.equal(panel.selected_category, "blueprints", "deep link selects category")
		assertions.equal(panel.get("selected_service_id"), "blueprint_furnace", "deep link records target")
	var event_bus := tree.root.get_node_or_null("EventBus")
	if event_bus != null:
		var refresh_connections := 0
		for connection in event_bus.get_signal_connection_list("gold_changed"):
			if connection.callable.get_object() == panel:
				refresh_connections += 1
		assertions.equal(refresh_connections, 1, "repeated configure owns one gold refresh signal")

	var categories := [
		"blueprints", "recipes", "repairs", "upgrades", "maintenance",
		"transport-storage", "land-expansion",
	]
	for category in categories:
		panel.select_category(category)
		panel.refresh_services()
		var cards := panel.get_node("ServiceScroll/ServiceCards")
		assertions.truthy(cards.get_child_count() > 0, "%s renders at least one real card" % category)
		for card in cards.get_children():
			assertions.equal(str(card.get_meta("category", "")), category, "%s filter contains only its category" % category)
			for child_name in ["GateLabel", "LevelOwnedLabel", "CostLabel", "EffectLabel", "ActionButton", "DisabledReasonLabel"]:
				assertions.truthy(card.has_node(child_name), "%s card has %s" % [category, child_name])

	production.set_maintenance_due_day(building, production.get_current_day() + 1)
	var maintenance_service_id := "maintenance_%s" % ProductionSystemScript.building_key(building)
	var maintenance_service := _service(progression, maintenance_service_id)
	assertions.equal(maintenance_service.get("current_state"), "可提前维修", "service overview exposes warning repair")
	wallet.gold = int(maintenance_service.get("gold_cost", 0))
	for item_id in maintenance_service.get("materials", {}):
		inventory.add_item(str(item_id), int(maintenance_service.materials[item_id]))
	panel.select_category("maintenance")
	panel.refresh_services()
	var maintenance_card := _card(panel, maintenance_service_id)
	assertions.truthy(
		maintenance_card != null and not maintenance_card.get_node("ActionButton").disabled,
		"service overview allows warning-period repair"
	)
	if maintenance_card != null:
		maintenance_card.get_node("ActionButton").pressed.emit()
	assertions.equal(production.get_maintenance_state(building), "repairing", "service overview starts timed repair")
	maintenance_service = _service(progression, maintenance_service_id)
	assertions.truthy(
		str(maintenance_service.get("current_state", "")).begins_with("维修中"),
		"service overview shows remaining repair seconds"
	)

	wallet.gold = 1000
	wallet.player_state.level = 1
	day.total_days = 1
	panel.select_category("blueprints")
	panel.refresh_services()
	var owned_card := _card(panel, "blueprint_windmill")
	assertions.truthy(owned_card != null, "locked windmill blueprint card exists")
	if owned_card != null:
		assertions.truthy(not owned_card.get_node("DisabledReasonLabel").text.is_empty(), "gated blueprint displays disabled reason")
	var before_disabled := int(wallet.gold)
	panel.request_service("blueprint_windmill")
	assertions.equal(int(wallet.gold), before_disabled, "disabled service deducts no gold")

	day.total_days = 8
	wallet.player_state.level = 2
	var service := _service(progression, "blueprint_windmill")
	wallet.gold = 0
	panel.refresh_services()
	var poor_card := _card(panel, "blueprint_windmill")
	assertions.truthy(
		poor_card != null and poor_card.get_node("DisabledReasonLabel").text.contains("金币不足"),
		"eligible unaffordable service shows exact gold reason"
	)
	wallet.gold = 1000
	panel.refresh_services()
	var material_card := _card(panel, "blueprint_windmill")
	assertions.truthy(
		material_card != null and material_card.get_node("DisabledReasonLabel").text.contains("缺少"),
		"eligible service shows exact missing-material reason"
	)
	for item_id in service.materials:
		inventory.add_item(str(item_id), int(service.materials[item_id]))
	panel.refresh_services()
	var eligible_card := _card(panel, "blueprint_windmill")
	var before_purchase := int(wallet.gold)
	assertions.truthy(eligible_card != null, "eligible blueprint card survives refresh")
	if eligible_card != null:
		assertions.truthy(eligible_card.get_node("CostLabel").text.contains(str(service.gold_cost)), "card displays exact gold cost")
		for item_id in service.materials:
			assertions.truthy(
				eligible_card.get_node("CostLabel").text.contains("%s ×%d" % [item_id, int(service.materials[item_id])]),
				"card displays exact %s material cost" % item_id
			)
		eligible_card.get_node("ActionButton").pressed.emit()
	assertions.equal(int(wallet.gold), before_purchase - int(service.gold_cost), "one card press deducts exact gold once after repeated configure")
	assertions.truthy(progression.is_blueprint_unlocked("windmill"), "service card calls authoritative purchase API")
	var after_owned := int(wallet.gold)
	panel.request_service("blueprint_windmill")
	assertions.equal(int(wallet.gold), after_owned, "owned service request cannot deduct twice")
	panel.refresh_services()
	var purchased_card := _card(panel, "blueprint_windmill")
	if purchased_card != null:
		assertions.truthy(purchased_card.get_node("LevelOwnedLabel").text.contains("已拥有"), "owned card displays owned state")
		assertions.truthy(purchased_card.get_node("ActionButton").disabled, "owned card action is disabled")

	var market := MarketSystemScript.new() as MarketSystem
	var economy := EconomySystem.new()
	assertions.truthy(market.configure(GameDataScript.get_market_items()), "service shop market configures")
	assertions.truthy(economy.configure(inventory, wallet, market), "service shop economy configures")
	var shop := (load(SHOP_SCENE_PATH) as PackedScene).instantiate()
	tree.root.add_child(shop)
	assertions.truthy(
		shop.configure(inventory, economy, market, progression, tool, production),
		"ShopUI injects real service dependencies"
	)
	assertions.truthy(shop.select_tab("services"), "ShopUI preserves services route")
	assertions.truthy(
		shop.get_node("ScreenLayer/ModalLayer/HubPanel/Margin/Shell/PageHost/ServicesPage").get_script() != null,
		"ShopUI services page is a real scripted panel"
	)

	shop.free()
	economy.free()
	market.free()
	panel.free()
	progression.free()
	building.free()
	production.free()
	tool.free()
	inventory.free()
	wallet.gold = original_gold
	wallet.player_state.level = original_level


func _building(id: String, gx: int, gz: int) -> BuildingInstance:
	var building := BuildingInstance.new()
	building.authored_building_id = id
	building.data = BuildingDataScript.from_dictionary(GameDataScript.get_building(id))
	building.grid_x = gx
	building.grid_z = gz
	building.producer_state = ProducerStateScript.new(id)
	return building


func _service(progression: Node, service_id: String) -> Dictionary:
	for service in progression.get_available_services():
		if str(service.id) == service_id:
			return service
	return {}


func _card(panel: Node, service_id: String) -> Node:
	for card in panel.get_node("ServiceScroll/ServiceCards").get_children():
		if str(card.get_meta("service_id", "")) == service_id:
			return card
	return null
