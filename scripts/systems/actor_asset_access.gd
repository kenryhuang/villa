extends RefCounted

## Access the original transaction implementation and reservations, never copy balances.
var port: AgentInteractionSystem
var resolve_port: Callable
var economy: Node
var wallet: Node
var inventory: InventorySystem

func configure(npc_economy: Node, player_wallet: Node, player_inventory: InventorySystem) -> void:
	economy = npc_economy
	wallet = player_wallet
	inventory = player_inventory
	port = AgentInteractionSystem.new()
	port._economy = economy
	port.configure_player_assets(inventory, wallet)

func current() -> AgentInteractionSystem:
	return resolve_port.call() if resolve_port.is_valid() else port

func exists(actor: String) -> bool:
	if actor == "village_market": return _merchant_market() != null
	return actor == "player" or economy.has_npc(actor)

func can_apply(actor: String, items: Dictionary, gold: int) -> bool:
	if not exists(actor): return false
	if actor == "village_market":
		var market := _merchant_market()
		if market == null or not market._can_direct_mutate() or int(market.merchant.cash) + gold < 0 or int(market.merchant.cash) + gold > 9007199254740991: return false
		for id in items:
			if not market._items.has(id) or market.get_stock(id) + int(items[id]) < 0 or market.get_stock(id) + int(items[id]) > 9007199254740991: return false
		return true
	var balance := int(wallet.gold) if actor == "player" else int(economy.get_npc_state(actor).gold)
	if gold > 0 and balance > 9007199254740991 - gold: return false
	return current().can_apply_actor_asset_delta(actor, items, gold)

func apply(actor: String, items: Dictionary, gold: int) -> bool:
	if actor == "village_market":
		if not can_apply(actor, items, gold): return false
		var market := _merchant_market()
		market.merchant.cash = int(market.merchant.cash) + gold
		market.merchant.asset_net = int(market.merchant.asset_net) + gold
		for id in items:
			market._items[id].stock = market.get_stock(id) + int(items[id])
			market.merchant.cost_basis[id] = maxi(0, int(market.merchant.cost_basis.get(id, 0)) + int(items[id]) * int(market._items[id].base_price))
		market.Merchant.record(market.merchant, "contract_assets", {"gold": gold, "items": items})
		return true
	return can_apply(actor, items, gold) and current().apply_actor_asset_delta(actor, items, gold)

func snapshot(actor: String) -> Dictionary:
	if actor == "village_market": return _merchant_market().to_dict()
	return current().snapshot_actor_assets(actor)

func restore(actor: String, value: Dictionary) -> void:
	if actor == "village_market":
		_merchant_market().from_dict(value)
		return
	current().restore_actor_assets(actor, value)

func available_items(actor: String) -> Dictionary:
	var counts := {}
	if actor == "village_market":
		var market := _merchant_market()
		if market != null:
			for id in market._items: counts[id] = market.get_stock(id)
		return counts
	if actor == "player":
		for slot in inventory.slots:
			if not slot.is_empty(): counts[str(slot.item_id)] = current().available_item(actor, str(slot.item_id))
	else:
		for id in economy.get_npc_state(actor).inventory:
			counts[id] = current().available_item(actor, id)
	return counts

func _merchant_market() -> Node:
	if economy == null: return null
	var market: Node = economy.get("_market_system")
	return market if market != null and not market.merchant.is_empty() else null
