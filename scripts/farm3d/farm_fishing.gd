extends Node3D

signal state_changed

const Location = preload("res://scripts/farm3d/fishing_location.gd")
const Visual = preload("res://scripts/farm3d/fishing_visual.gd")
const BITE_CHANCE := .72
const CAST_TIME := 1.1
const BITE_TIME := 2.2
const REEL_TIME := 1.25
const LAND_TIME := 1.15
enum State { STOWED, READY, CASTING, WAITING, BITE, REELING, LANDING, RECOVERING }
const CATCH_TABLES := {
	"river": [["creek_crucian",50.0],["river_perch",35.0],["rainbow_trout",15.0]],
	"lake": [["carp",50.0],["creek_crucian",35.0],["night_catfish",15.0]],
}

var state := State.STOWED
var location: Dictionary = {}
var available_location: Dictionary = {}
var visual: Node3D
var elapsed := 0.0
var duration := 0.0
var catch_id := ""
var rng := RandomNumberGenerator.new()
var _session: Node
var _player: Farm3DPlayer
var _hud: CanvasLayer
var _reservation: Variant
var _will_bite := false
var _scan_seconds := 0.0
var _recover_message := ""

func configure(session: Node, player: Farm3DPlayer, hud: CanvasLayer) -> void:
	_session = session
	_player = player
	_hud = hud
	rng.randomize()
	visual = Visual.new()
	visual.name = "FishingVisual"
	add_child(visual)
	visual.configure(player)
	refresh_location()
	_update_hud()

func is_equipped() -> bool:
	return state != State.STOWED

func refresh_location() -> void:
	available_location = Location.find_location(_player,_session.grid)
	_hud.fishing_button.disabled = available_location.is_empty() and not is_equipped()
	_hud.fishing_button.tooltip_text = "需站在平缓干燥的河岸或湖岸，且抛线前方无遮挡" if available_location.is_empty() else "此处可钓鱼，选择鱼竿后按 E 或左键甩竿"

func equip() -> bool:
	refresh_location()
	if available_location.is_empty() or _hud.is_modal_open():
		return false
	location = available_location.duplicate(true)
	_player.look_at(Vector3(location.water.x,_player.global_position.y,location.water.z),Vector3.UP,true)
	_player.velocity = Vector3.ZERO
	_player.fishing_locked = true
	visual.set_equipped(true)
	var farm := get_parent().get_parent()
	if farm.has_method("_apply_camera_rotation") and not farm.overview_enabled:
		# Look over the shoulder so the farmer and near bank do not hide the float.
		farm.yaw = atan2(_player.global_basis.z.x,_player.global_basis.z.z)+PI-.45
		farm.pitch_angle = deg_to_rad(-28)
		farm.get_node("CameraRig/Pitch/SpringArm3D").spring_length = 7.5
		farm._apply_camera_rotation()
	_transition(State.READY,0)
	return true

func act() -> Dictionary:
	if _hud.is_modal_open():
		return {"ok":false,"reason":"ui_blocked"}
	if state == State.READY:
		return _cast()
	if state == State.BITE:
		_transition(State.REELING,REEL_TIME)
		return {"ok":true,"reason":""}
	if state == State.WAITING:
		_recover("收竿太早，还没有鱼咬钩")
		return {"ok":false,"reason":"early_reel"}
	return {"ok":false,"reason":"busy"}

func _cast() -> Dictionary:
	if not _location_valid():
		cancel("此处无法抛线，请重新选择岸边位置")
		return {"ok":false,"reason":"invalid_location"}
	catch_id = _choose_catch()
	_reservation = _session.inventory.reserve_item_capacity(catch_id,1)
	if _reservation == null:
		_hud.notify_message("背包已满，请腾出渔获空间后再甩竿",false)
		return {"ok":false,"reason":"inventory_full"}
	_will_bite = rng.randf() < BITE_CHANCE
	_transition(State.CASTING,CAST_TIME)
	return {"ok":true,"reason":""}

func _process(delta: float) -> void:
	if _session == null:
		return
	_scan_seconds -= delta
	if _scan_seconds <= 0:
		_scan_seconds = .2
		if state == State.STOWED:
			refresh_location()
		elif not _location_valid():
			cancel("钓位已改变，鱼竿已收起")
	if is_equipped() and _hud.is_modal_open():
		cancel()
	advance(delta)
	if is_equipped():
		visual.update_pose(State.keys()[state],elapsed,duration,location.water,catch_id)
	_update_hud()

func advance(delta: float) -> void:
	if state in [State.STOWED,State.READY] or not is_finite(delta) or delta <= 0:
		return
	if not _location_valid() or _hud.is_modal_open():
		cancel()
		return
	elapsed += delta
	if elapsed < duration:
		return
	# One transition per rendered frame ensures the bite prompt cannot be skipped.
	match state:
		State.CASTING: _transition(State.WAITING,rng.randf_range(3.0,7.0))
		State.WAITING:
			if _will_bite:
				_transition(State.BITE,BITE_TIME)
			else:
				_recover("这一竿没有鱼咬钩，再试一次吧")
		State.BITE: _recover("没来得及拉竿，鱼跑了")
		State.REELING: _transition(State.LANDING,LAND_TIME)
		State.LANDING: _settle_catch()
		State.RECOVERING: _transition(State.READY,0)

func _settle_catch() -> void:
	# Consume the reservation once, after the fish reaches the farmer's hand.
	var token: Variant = _reservation
	_reservation = null
	_transition(State.READY,0)
	if token == null or not _session.inventory.commit_item_capacity_reservation(token):
		_session.inventory.release_item_capacity_reservation(token)
		_hud.notify_message("渔获未能入包，请检查背包后重试",false)
		return
	_hud.notify_message("钓到%s ×1，已收进背包" % _session.item_name(catch_id),true)
	if _session.auto_save:
		_session.save_game()

func _recover(message: String) -> void:
	_release_reservation()
	_recover_message = message
	_hud.notify_message(message,false)
	_transition(State.RECOVERING,.8)

func cancel(message: String = "") -> void:
	_release_reservation()
	if is_instance_valid(_player):
		_player.fishing_locked = false
	if is_instance_valid(visual):
		visual.set_equipped(false)
	location.clear()
	_transition(State.STOWED,0)
	if not message.is_empty():
		_hud.notify_message(message,false)

func _exit_tree() -> void:
	_release_reservation()
	if is_instance_valid(_player):
		_player.fishing_locked = false
	if is_instance_valid(visual):
		visual.set_equipped(false)

func _release_reservation() -> void:
	if _reservation != null and is_instance_valid(_session) and is_instance_valid(_session.inventory):
		_session.inventory.release_item_capacity_reservation(_reservation)
	_reservation = null

func _location_valid() -> bool:
	return not location.is_empty() and _player.global_position.distance_to(location.stand) < .65 and Location.valid_footing(_player,_session.grid) and Location.valid_water(_player,_session.grid,location.water)

func _choose_catch() -> String:
	var rows: Array = CATCH_TABLES[location.body]
	var roll := rng.randf()*100.0
	for row in rows:
		roll -= float(row[1])
		if roll <= 0:
			return str(row[0])
	return str(rows.back()[0])

func _transition(next: State, seconds: float) -> void:
	state = next
	elapsed = 0
	duration = seconds
	_update_hud()
	state_changed.emit()

func _update_hud() -> void:
	if _hud == null:
		return
	var text := ""
	var action := "甩竿  E / 左键"
	match state:
		State.READY: text = "%s钓鱼 · 鱼竿已就绪" % ("湖泊" if location.get("body") == "lake" else "河流")
		State.CASTING: text = "甩竿中…"
		State.WAITING:
			text = "等待咬钩…留意浮漂"
			action = "提前收竿  E"
		State.BITE:
			text = "鱼咬钩了！快拉竿！"
			action = "拉竿！ E / 左键"
		State.REELING: text = "拉竿中…鱼正在挣扎"
		State.LANDING: text = "上鱼！正在收进背包…"
		State.RECOVERING: text = _recover_message
	_hud.set_fishing_status(is_equipped(),text,action,state in [State.READY,State.WAITING,State.BITE],maxf(0,1.0-elapsed/BITE_TIME) if state == State.BITE else -1.0)
