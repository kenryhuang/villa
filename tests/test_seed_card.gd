extends RefCounted

const SeedCardScene := preload("res://scenes/ui/seed_card.tscn")


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var card = SeedCardScene.instantiate()
	tree.root.add_child(card)
	var selected: Array[String] = []
	card.seed_selected.connect(func(item_id: String) -> void: selected.append(item_id))
	card.configure({
		"plant_item_id": "grain_seed",
		"display_name": "谷物种子",
		"quantity": 24,
		"growth_text": "成熟 3 天",
		"season_text": "春 / 秋",
		"environment_text": "露天与温室",
		"status_text": "当前可播种",
		"disabled": false,
		"icon": null,
	})
	assertions.truthy(card.get_node("Content/Icon").custom_minimum_size.x >= 68.0, "seed icon is readable")
	assertions.truthy(card.get_node("Content/Details/NameRow/Name").get_theme_font_size("font_size") >= 21, "seed name uses large text")
	assertions.truthy(card.get_node("Content/Details/Metadata").get_theme_font_size("font_size") >= 15, "seed metadata stays readable")
	assertions.truthy(card.get_node("Content/Details/Status").get_theme_font_size("font_size") >= 15, "seed status stays readable")
	assertions.equal(card.get_node("Content/Details/NameRow/Quantity").text, "×24", "seed quantity is prominent")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	card.gui_input.emit(click)
	assertions.equal(selected, ["grain_seed"], "whole-card click selects seed")
	card.configure({
		"plant_item_id": "lemon_sapling",
		"display_name": "柠檬树苗",
		"quantity": 1,
		"growth_text": "成熟 5 天",
		"season_text": "温室",
		"environment_text": "仅温室",
		"status_text": "仅限温室",
		"disabled": true,
		"icon": null,
	})
	card.gui_input.emit(click)
	assertions.equal(selected, ["grain_seed"], "disabled card ignores whole-card click")
	assertions.truthy(card.get_node("Content/Details/Status").get_theme_color("font_color").r > 0.6, "disabled reason uses an error color")
	card.free()
