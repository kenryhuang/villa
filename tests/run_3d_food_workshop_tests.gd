extends SceneTree
const Data = preload("res://scripts/core/game_data.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(65).timeout.connect(func(): push_error("Food workshop tests timed out"); quit(1))
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func _frames(count := 3) -> void:
	for i in count:
		await physics_frame
		await process_frame

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event,true)

func _run() -> void:
	root.size = Vector2i(1440,960)
	var farm := (load("res://scenes/farm3d/main.tscn") as PackedScene).instantiate()
	root.add_child(farm)
	farm.set_process(false)
	var session: Farm3DSession = farm.farm_session
	var interaction = farm.get_node("FarmInteraction")
	var hud = interaction.hud
	var view = hud.food_workshop_view
	var player = session.player
	player.set_physics_process(false)
	session.season.set_process(false)
	session.save_path = "user://food_workshop_3d_test.json"
	player.position = session.grid.get_cell(32,31).world_position_3d()+Vector3.LEFT*1.2
	var original := BuildingData.from_dictionary(Data.get_building("food_workshop"))
	var data := session.buildings._resolve_data(original)
	_check(data.scene_path == "res://scenes/farm3d/buildings/food_workshop.tscn" and original.scene_path == "res://scenes/buildings/food_workshop.tscn","3D scene override preserves original food workshop")
	_check(data.footprint == Vector2i(4,4) and data.cost == original.cost,"Footprint and construction economy stay unchanged")
	var planks := session.inventory.get_item_count("plank")
	var placed := session.buildings.try_place_building("food_workshop",32,31)
	_check(placed.placed,"Food workshop places through the actual 3D building system")
	if not placed.placed:
		quit(1)
		return
	var workshop: BuildingInstance = placed.instance
	_check(session.inventory.get_item_count("plank") == planks-12,"Original construction cost is charged")
	_check(not interaction.open_windmill(workshop),"Incomplete workshop cannot produce")
	var model := workshop.get_node("VisualRoot/Model")
	for stage in 4:
		workshop.restore_construction(stage,stage*3)
		_check(model.get_node("Walls").visible == (stage >= 2) and model.get_node("Roof").visible == (stage == 3),"Model follows original construction stages")
	for sprite in workshop.find_children("*","Sprite3D",true,false):
		_check(not sprite.is_visible_in_tree(),"Legacy flat artwork does not overlap 3D workshop")
	_check(model.find_children("*","MeshInstance3D",true,false).size() >= 5,"Workshop has real staged 3D geometry")
	player.position = workshop.position+Vector3.FORWARD*3
	_check(not interaction.open_windmill(workshop),"Cannot operate through rear wall")
	player.position = workshop.position+Vector3.BACK*2.8
	var camera := Camera3D.new()
	farm.add_child(camera)
	camera.position = workshop.position+Vector3(4,4,8)
	camera.look_at(workshop.position+Vector3.UP*1.5)
	camera.make_current()
	await _frames()
	var pointer := camera.unproject_position(workshop.position+Vector3.UP*1.5)
	_check(interaction.windmill_at_pointer(pointer).get("building") == workshop,"Raycast finds the food workshop model")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = pointer
	root.push_input(click,true)
	await _frames()
	_check(view.visible and paused and player.ui_blocked,"Clicking workshop opens production and pauses the farm")
	_check(view.recipe_buttons.size() == 10 and view.controller._production == session.production,"All ten original workshop recipes share the original production authority")
	for id in view.recipe_buttons:
		_check(view.recipe_buttons[id].icon != null,"Workshop product has an icon: "+id)
	view.controller.select_recipe("grilled_fish")
	session.inventory.add_item("salt",20)
	session.inventory.add_item("rainbow_trout",2)
	view.controller.refresh_snapshot()
	_check(view.start_button.disabled and view.controller.disabled_reason.contains("普通鱼"),"Rare fish cannot satisfy a common-fish recipe")
	session.inventory.add_item("creek_crucian",1)
	session.inventory.add_item("river_perch",1)
	view.controller.refresh_snapshot()
	_check(view.controller.max_batches == 1 and view.controller.recipe_detail.inputs.get("creek_crucian") == 1 and view.controller.recipe_detail.inputs.get("river_perch") == 1,"UI resolves mixed ordinary fish and includes fish in maximum batches")
	var expected := session.market.quote_sell("salt",1)+session.market.quote_sell("creek_crucian",1)+session.market.quote_sell("river_perch",1)
	_check(view.controller.recipe_detail.input_value == expected,"Recipe pricing includes the actual selected fish")
	view._start()
	_check(workshop.producer_state.jobs.size() == 1 and session.inventory.get_item_count("creek_crucian") == 0 and session.inventory.get_item_count("river_perch") == 0 and session.inventory.get_item_count("rainbow_trout") == 2,"Original recipe transaction consumes mixed common fish and preserves rare fish")
	_key(KEY_ESCAPE)
	_check(not view.visible and not paused and not player.ui_blocked,"Escape restores game clock and player")
	workshop._process(.1)
	_check(workshop._steam.emitting,"Active cooking emits chimney steam")
	session.production.advance_minutes(27)
	_check(workshop.producer_state.outputs.get("grilled_fish") == 2,"Original fish recipe yields two grilled fish after 27 game minutes")
	workshop._process(.1)
	_check(not workshop._steam.emitting,"Steam stops when the cooking queue empties")
	var display := workshop.get_node("BuildingOutputDisplay")
	_check(display.get_pile_count() == 1,"Completed food appears as native output geometry")
	camera.position = workshop.position+Vector3(0,1.5,7)
	camera.look_at(workshop.position+Vector3(0,.4,1.35))
	await _frames()
	var pile := display.get_node("Output_grilled_fish") as Area3D
	_check(interaction.windmill_at_pointer(camera.unproject_position(pile.global_position+Vector3.UP*.25)).get("item_id") == "grilled_fish","Output ray reaches food in front of the building collision")
	var slots := session.inventory.slots.duplicate(true)
	for index in session.inventory.slots.size():
		session.inventory.slots[index] = {"item_id":"stone","quantity":999}
	_check(not interaction.collect_windmill(workshop,"grilled_fish") and workshop.producer_state.outputs.get("grilled_fish") == 2,"Full backpack leaves all prepared food safely stored")
	session.inventory.slots = slots
	_check(interaction.collect_windmill(workshop,"grilled_fish") and session.inventory.get_item_count("grilled_fish") == 2,"Food output collects into the shared backpack")
	_check(not interaction.collect_windmill(workshop,"grilled_fish") and session.inventory.get_item_count("grilled_fish") == 2,"Repeated collection cannot duplicate food")
	var gold: int = root.get_node("GameState").gold
	var quote := session.market.quote_sell("grilled_fish",2)
	_check(session.economy.sell_item("grilled_fish",2) and root.get_node("GameState").gold == gold+quote,"Cooked fish sells through the original market economy")
	# Real upstream windmill output becomes workshop bread.
	player.position = session.grid.get_cell(40,31).world_position_3d()+Vector3.LEFT*1.2
	var mill_result := session.buildings.try_place_building("windmill",40,31)
	_check(mill_result.placed,"Upstream windmill places beside workshop")
	var mill: BuildingInstance = mill_result.instance
	mill.complete_construction()
	session.inventory.add_item("grain",4)
	_check(session.production.start_recipe(mill,"flour",2,session.inventory),"Windmill accepts original grain-to-flour recipe")
	session.production.advance_minutes(54)
	session.production.collect_outputs(mill,session.inventory)
	session.inventory.add_item("egg",1)
	player.position = workshop.position+Vector3.BACK*2.8
	interaction.open_windmill(workshop)
	view.controller.select_recipe("bread")
	view._start()
	_check(workshop.producer_state.jobs.size() == 1,"Collected windmill flour feeds the bread recipe")
	view.close_panel()
	session.production.advance_minutes(27)
	_check(workshop.producer_state.outputs.get("bread") == 2,"Grain-to-flour-to-bread chain produces two loaves")
	session.production.collect_outputs(workshop,session.inventory)
	# Full output-type storage holds completed jobs until goods are collected.
	workshop.producer_state.add_outputs({"fruit_jam":1,"pickles":1,"tomato_sauce":1})
	session.inventory.add_item("flour",2)
	session.inventory.add_item("egg",1)
	session.production.start_recipe(workshop,"bread",1,session.inventory)
	session.production.advance_minutes(27)
	_check(workshop.producer_state.jobs.size() == 1 and not workshop.producer_state.outputs.has("bread"),"Full product storage preserves the completed order")
	session.production.collect_outputs(workshop,session.inventory,"pickles")
	session.production.advance_minutes(1)
	_check(workshop.producer_state.outputs.get("bread") == 2 and workshop.producer_state.jobs.is_empty(),"Freeing storage releases completed bread without losing it")
	session.production.collect_outputs(workshop,session.inventory)
	# Every original workshop recipe can be produced and collected.
	for recipe in RecipeDatabase.get_recipes_for_station("food_workshop"):
		for id in recipe.inputs:
			session.inventory.add_item(id,recipe.inputs[id])
		if not recipe.input_selectors.is_empty():
			session.inventory.add_item("creek_crucian",2)
		_check(session.production.start_recipe(workshop,recipe.id,1,session.inventory),"Original recipe starts: "+recipe.id)
		session.production.advance_minutes(recipe.duration_minutes)
		_check(workshop.producer_state.outputs.get(recipe.id) == recipe.outputs[recipe.id],"Original duration and yield retained: "+recipe.id)
		session.production.collect_outputs(workshop,session.inventory)
	session.inventory.add_item("flour",8)
	session.inventory.add_item("egg",4)
	interaction.open_windmill(workshop)
	view.controller.select_recipe("bread")
	view._start()
	view._start()
	var flour := session.inventory.get_item_count("flour")
	view._start()
	_check(workshop.producer_state.jobs.size() == 2 and session.inventory.get_item_count("flour") == flour,"Full queue does not charge twice")
	view.close_panel()
	session.production.advance_minutes(5)
	var remaining: int = workshop.producer_state.jobs[0].remaining_minutes
	session.production.set_maintenance_due_day(workshop,session.season.total_days)
	session.production.advance_minutes(40)
	_check(workshop.producer_state.jobs[0].remaining_minutes == remaining,"Overdue maintenance pauses existing jobs")
	_check(session.save_game() and session.load_game(),"Food jobs and maintenance save through existing farm storage")
	workshop = session.buildings.get_building_at(32,31)
	_check(workshop != null and workshop.has_node("VisualRoot/Model") and workshop.producer_state.jobs.size() == 2,"Loading restores the modeled workshop and pending production")
	player.position = workshop.position+Vector3.BACK*2.8
	interaction.open_windmill(workshop)
	root.content_scale_size = Vector2i(900,720)
	root.size = Vector2i(900,720)
	await _frames()
	_check(view._narrow and view.start_button.is_visible_in_tree() and view.window.size.x <= 900,"Workshop panel supports narrow windows")
	view._show_tab(0)
	_check(view.recipe_buttons.size() == 10 and view.recipe_buttons.perfume.is_visible_in_tree(),"All recipes remain available in the scrollable narrow list")
	_key(KEY_I)
	_check(hud.inventory_ui.visible and not view.visible and not paused,"Inventory safely closes workshop and restores clock")
	hud.close_panels()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(session.save_path))
	farm.queue_free()
	await _frames()
	print("3D FOOD WORKSHOP: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL "+str(failures),checks])
	quit(0 if failures.is_empty() else 1)
