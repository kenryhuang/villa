extends SceneTree
const Data = preload("res://scripts/core/game_data.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	if "--farm-test" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(60).timeout.connect(func(): push_error("Chicken coop tests timed out"); quit(1))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func frames() -> void:
	for i in 3:
		await physics_frame
		await process_frame

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event,true)

func advance_day(session: Farm3DSession, day: int) -> void:
	while session.season.total_days < day:
		session.rest()

func run() -> void:
	root.size = Vector2i(1440,960)
	var farm: Node3D = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(farm)
	farm.set_process(false)
	var session: Farm3DSession = farm.farm_session
	session.season.set_process(false)
	session.living_world.set_process(false)
	session.player.set_physics_process(false)
	check(not session.auto_save and not session.auto_restore,"Test cannot overwrite the player save")
	session.save_path = "res://tmp/chicken-coop/test-save.json"
	var interaction = farm.get_node("FarmInteraction")
	var hud = interaction.hud
	var view = hud.chicken_coop_view
	var original := BuildingData.from_dictionary(Data.get_building("chicken_coop"))
	var data := session.buildings._resolve_data(original)
	check(data.scene_path == "res://scenes/farm3d/buildings/chicken_coop.tscn" and original.scene_path == "res://scenes/buildings/chicken_coop.tscn","Only 3D scene changes; original 2D chicken coop remains")
	check(data.cost == original.cost and data.footprint == Vector2i(3,3),"Original 3x3 footprint and cost remain")
	session.player.position = session.grid.get_cell(32,31).world_position_3d()+Vector3.LEFT*1.2
	var planks := session.inventory.get_item_count("plank")
	var placed := session.buildings.try_place_building("chicken_coop",32,31)
	check(placed.placed,"Coop places through the actual building system")
	if not placed.placed: quit(1); return
	var coop: BuildingInstance = placed.instance
	check(session.inventory.get_item_count("plank") == planks-8,"Construction charges original plank cost")
	check(not interaction.open_windmill(coop),"Incomplete coop cannot open")
	var model := coop.get_node("VisualRoot/Model")
	for stage in 4:
		coop.restore_construction(stage,stage*3)
		check(model.get_node("Walls").visible == (stage>=2) and model.get_node("Roof").visible == (stage==3),"Model follows all four construction stages")
	coop.complete_construction()
	session.production.set_maintenance_due_day(coop,99)
	check(coop.get_node_or_null("ProductionYard") == null and coop.get_node("VisualRoot").position == Vector3.ZERO,"Modeled run replaces flat yard without shifting footprint")
	for sprite in coop.find_children("*","Sprite3D",true,false): check(not sprite.is_visible_in_tree(),"No legacy image overlaps the 3D coop")
	coop._update_hens(.2)
	check(coop.hens.size() == 2 and coop.hens[0].visible,"Two real modeled hens appear after completion")
	var hen_position: Vector3 = coop.hens[0].position
	coop._update_hens(.5)
	check(coop.hens[0].position.distance_to(hen_position) > .01,"Hens actually walk within the run")
	coop.set_preview_mode(true)
	coop._update_hens(.1)
	check(not coop.hens[0].visible and coop.get_node("Collision").collision_layer == 0,"Placement preview has no living hens or physical blocker")
	coop.set_preview_mode(false)
	check(session.production.get_chicken_coop_snapshot(coop).status == "no_feed","New coop waits for feed")
	session.production.finish_daily_outputs(1)
	check(coop.producer_state.outputs.is_empty(),"No feed means no free eggs")
	session.inventory.add_item("animal_feed",6)
	session.player.position = coop.position+Vector3.FORWARD*2.8
	check(not interaction.open_windmill(coop),"Rear wall cannot operate through the house")
	session.player.position = coop.position+Vector3.BACK*2.7
	var camera := Camera3D.new()
	farm.add_child(camera)
	camera.position = coop.position+Vector3(3.8,3.0,5.8)
	camera.look_at(coop.position+Vector3.UP)
	camera.make_current()
	await frames()
	check(interaction.windmill_at_pointer(camera.unproject_position(coop.position+Vector3.UP)).get("building") == coop,"Pointer detects the modeled coop")
	check(interaction.open_windmill(coop) and paused and hud.is_modal_open(),"Click opens coop and pauses time")
	var feed_before := session.inventory.get_item_count("animal_feed")
	check(view.add_feed(1) and view.add_feed(5),"Both feed controls use shared input transactions")
	check(coop.producer_state.get_input_count("animal_feed") == 6 and session.inventory.get_item_count("animal_feed") == feed_before-6,"Feed is transferred exactly once")
	check(not view.add_feed(1) and coop.producer_state.get_input_count("animal_feed") == 6,"Insufficient feed does not duplicate or lose items")
	key(KEY_D)
	check(not Input.is_action_pressed("move_right"),"Movement is blocked while panel is open")
	root.content_scale_size = Vector2i(900,720)
	root.size = Vector2i(900,720)
	await frames()
	check(view.feed_five.get_global_rect().end.y<720 and view.maintenance_button.get_global_rect().end.y<720,"Feeding and collection stay reachable in a small window")
	key(KEY_ESCAPE)
	check(not paused and not view.visible and not session.player._dialogue_input_blocked and not session.player.ui_blocked,"Escape restores time and player controls")
	root.content_scale_size = Vector2i(1440,960)
	root.size = Vector2i(1440,960)
	advance_day(session,2)
	check(coop.producer_state.outputs == {"egg":2} and coop.producer_state.get_input_count("animal_feed") == 5,"Original daily rule: one feed produces two eggs")
	session.production.finish_daily_outputs(2)
	check(coop.producer_state.outputs == {"egg":2} and coop.producer_state.get_input_count("animal_feed") == 5,"Duplicate day callback does not repeat production")
	advance_day(session,5)
	check(coop.producer_state.outputs == {"egg":6} and coop.producer_state.get_input_count("animal_feed") == 3,"Full six-egg basket pauses before consuming feed")
	check(session.production.get_chicken_coop_snapshot(coop).status == "full","Full state matches production rules")
	check(coop.get_node("EconomyIndicator").pixel_size <= .005 and not coop.get_node("EconomyIndicator").fixed_size,"Full-basket marker stays proportional to the model")
	coop._update_hens(.1)
	check(coop._grain.material_override.albedo_color != Color.WHITE,"Shared building tint preserves grain color")
	check(coop.get_node("BuildingOutputDisplay").get_pile_count() == 1,"Eggs appear in a collectible 3D basket")
	var basket := coop.get_node("BuildingOutputDisplay/Output_egg")
	await frames()
	var hit: Dictionary = interaction.windmill_at_pointer(camera.unproject_position(basket.global_position+Vector3.UP*.23))
	check(hit.get("building") == coop and hit.get("item_id") == "egg","Pointer targets the egg basket independently")
	interaction.open_windmill(coop)
	var inventory_before := session.inventory.get_item_count("egg")
	var slots := session.inventory.slots.duplicate(true)
	for i in session.inventory.slots.size(): session.inventory.slots[i] = {"item_id":"stone","quantity":999}
	view._collect()
	check(coop.producer_state.outputs == {"egg":6},"Full backpack preserves all eggs")
	session.inventory.slots = slots
	view._collect()
	check(session.inventory.get_item_count("egg") == inventory_before+6 and coop.producer_state.outputs.is_empty(),"Collect puts eggs into the original inventory")
	view._collect()
	check(session.inventory.get_item_count("egg") == inventory_before+6,"Repeated collection never duplicates eggs")
	coop.owner_id = "farmer_ahe"
	view.refresh()
	check(view.feed_one.disabled and view.collect_button.disabled and not view.add_feed(1),"NPC-owned coop stays under owner control")
	coop.owner_id = "player"
	view.close_panel()
	session.production.set_maintenance_due_day(coop,5)
	advance_day(session,6)
	check(coop.producer_state.outputs.is_empty() and coop.producer_state.get_input_count("animal_feed") == 3,"Overdue maintenance pauses eggs without consuming feed")
	session.production.set_maintenance_due_day(coop,99)
	advance_day(session,7)
	check(coop.producer_state.outputs == {"egg":2},"Maintained coop resumes the original daily cycle")
	check(interaction.collect_windmill(coop,"egg") and coop.producer_state.outputs.is_empty(),"World basket collection uses the same inventory flow")
	advance_day(session,8)
	check(session.save_game() and session.load_game(),"Coop saves and loads through existing farm storage")
	coop = session.buildings.get_building_at(32,31)
	check(coop != null and coop.has_node("VisualRoot/Model") and coop.hens.size() == 2,"Load restores modeled coop and hens")
	check(coop.producer_state.outputs == {"egg":2} and coop.producer_state.get_input_count("animal_feed") == 1,"Remaining feed and eggs survive save/load")
	session.production.finish_daily_outputs(8)
	check(coop.producer_state.outputs == {"egg":2},"Loading does not duplicate the current day's eggs")
	farm.queue_free()
	await frames()
	print("3D chicken coop: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
