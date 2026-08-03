extends RefCounted

const GameDataScript = preload("res://scripts/core/game_data.gd")
const GameStateScript = preload("res://scripts/core/game_state.gd")
const CropDataScript = preload("res://scripts/data/crop_data.gd")


func _make_crop_data(id: String):
	var crop = CropDataScript.new()
	crop.crop_id = id
	crop.crop_name = id.capitalize()
	crop.growth_days = 3
	crop.seed_price = 5
	crop.sell_price = 10
	return crop


func run(assertions: TestAssert) -> void:
	# GameData register and lookup
	var data = GameDataScript.new()
	assertions.truthy(data.register_crop(_make_crop_data("turnip")), "first ID registers")
	assertions.truthy(not data.register_crop(_make_crop_data("turnip")), "duplicate rejected")
	assertions.equal(data.get_crop("turnip").crop_name, "Turnip", "lookup returns authored crop")
	assertions.truthy(data.get_crop("nonexistent") == null, "unknown ID returns null")

	# GameState gold
	var state = GameStateScript.new()
	state._ready()
	assertions.equal(state.gold, 100, "initial gold is 100")
	assertions.truthy(state.spend_gold(30), "can spend available gold")
	assertions.equal(state.gold, 70, "spend changes gold")
	assertions.truthy(not state.spend_gold(71), "cannot overspend")
	assertions.truthy(not state.spend_gold(0), "cannot spend zero")
	assertions.truthy(state.add_gold(50), "can add gold")
	assertions.equal(state.gold, 120, "gold after add")

	# GameState player
	assertions.equal(state.player_state.stamina, 100, "player stamina initialized")
	assertions.equal(state.player_state.level, 1, "player level initialized")
	assertions.equal(state.player_state.exp, 0, "player exp initialized")

	# GameState exp
	assertions.truthy(state.add_exp(50), "can add exp")
	assertions.equal(state.player_state.exp, 50, "exp added to player")
	state.free()
	data.free()
