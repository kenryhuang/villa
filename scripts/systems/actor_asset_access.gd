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
	return actor == "player" or economy.has_npc(actor)

func can_apply(actor: String, items: Dictionary, gold: int) -> bool:
	if not exists(actor): return false
	var balance := int(wallet.gold) if actor == "player" else int(economy.get_npc_state(actor).gold)
	if gold > 0 and balance > 9007199254740991 - gold: return false
	return current().can_apply_actor_asset_delta(actor, items, gold)

func apply(actor: String, items: Dictionary, gold: int) -> bool:
	return can_apply(actor, items, gold) and current().apply_actor_asset_delta(actor, items, gold)

func snapshot(actor: String) -> Dictionary:
	return current().snapshot_actor_assets(actor)

func restore(actor: String, value: Dictionary) -> void:
	current().restore_actor_assets(actor, value)

func available_items(actor: String) -> Dictionary:
	var counts := {}
	if actor == "player":
		for slot in inventory.slots:
			if not slot.is_empty(): counts[str(slot.item_id)] = current().available_item(actor, str(slot.item_id))
	else:
		for id in economy.get_npc_state(actor).inventory:
			counts[id] = current().available_item(actor, id)
	return counts
