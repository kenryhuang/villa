extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(60).timeout.connect(func(): push_error("Commission activity UI timeout"); quit(1))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func run() -> void:
	var scene: Node = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	var s: Node = scene.farm_session
	check(not s.auto_save and not s.auto_restore, "Test never accesses the player save")
	scene.set_process(false)
	s.season.set_process(false)
	s.agent_runtime.set_process(false)
	s.living_world.set_process(false)
	var work: RefCounted = s.living_world.work
	var ui: Control = scene.get_node("FarmInteraction").hud.commission_view
	var names := {"learning": "原料选配培训", "visit": "拜访朋友", "companionship": "陪伴朋友", "date": "约会", "rest": "休息", "sleep": "睡眠", "eat": "用餐", "drink": "饮水", "future_activity": "未知活动（future_activity）"}
	var statuses := {"traveling": "前往现场", "working": "进行中", "completed": "已完成", "cancelled": "已取消", "future_status": "未知状态（future_status）"}
	# Exercise the real open_panel -> refresh -> _work_cards path for every kind/status.
	for kind in names:
		for status in statuses:
			work.activities = {"ui-fixture": {"id": "ui-fixture", "actor_id": "lao_li", "kind": kind, "status": status, "worked": 12, "partner": "farmer_ahe", "deadline": 1000}}
			ui.open_panel()
			var expected := "%s · %s · 已投入 12 分钟 · %s" % [s.living_world.actor_name("lao_li"), names[kind], statuses[status]]
			var found := false
			for child in ui.lists[3].get_children():
				if child is Label and child.text == expected: found = true
			check(found, "Activity card renders %s/%s" % [kind, status])
			check(ui.lists[3].get_child(-1) is VBoxContainer, "Work form still renders after activity cards")
			ui.close_panel()
	work.activities = {"ui-fixture": {"actor_id": "lao_li", "kind": "future_activity", "status": "working"}}
	check(work.activity_label("lao_li") == "未知活动（future_activity）", "Nameplate handles future activity kinds")
	check(not paused and not s.player._dialogue_input_blocked, "Closing panel restores time and input")
	work.activities.clear()
	print("Commission activity UI: %d checks, %d failures" % [checks, failures])
	scene.free()
	quit(0 if failures == 0 else 1)
