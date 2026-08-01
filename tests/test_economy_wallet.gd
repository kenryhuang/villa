extends RefCounted

const EconomySystem = preload("res://scripts/systems/economy_system.gd")
const InventorySystem = preload("res://scripts/systems/inventory_system.gd")


class WalletDouble:
	extends Node

	var gold := 100

	func add_gold(amount: int) -> bool:
		if amount <= 0:
			return false
		gold += amount
		return true

	func spend_gold(amount: int) -> bool:
		if amount <= 0 or amount > gold:
			return false
		gold -= amount
		return true


func run(assertions: TestAssert) -> void:
	var inventory := InventorySystem.new()
	var wallet := WalletDouble.new()
	var economy := EconomySystem.new()
	assertions.truthy(economy.configure(inventory, wallet), "wallet injection succeeds")
	assertions.truthy(economy.spend_gold(30), "spending delegates")
	assertions.equal(wallet.gold, 70, "one wallet changes")
	assertions.truthy(economy.add_gold(10), "income delegates")
	assertions.equal(wallet.gold, 80, "same wallet changes")
	assertions.truthy(not economy.configure(inventory, null), "missing wallet rejected")
