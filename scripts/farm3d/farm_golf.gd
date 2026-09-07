extends Node3D

const Course = preload("res://scripts/farm3d/golf_course_data.gd")
const Art = preload("res://scripts/farm3d/golf_course_visual.gd")
const Visual = preload("res://scripts/farm3d/golf_visual.gd")
enum Phase { OFF, WALK, ADDRESS, SWING, FLIGHT, HOLED, FINISHED }
var phase := Phase.OFF
var session: Farm3DSession
var player: Farm3DPlayer
var hud: CanvasLayer
var course: Node3D
var visual: Node3D
var ball := Farm3DGolfBall.new()
var gesture := Farm3DGolfSwing.new()
var round_state: Farm3DGolfRound
var club := 0
var direction := Vector3.FORWARD
var contact_height := -.6
var stance_distance := .8
var _orbiting := false
var _orbit_yaw := 0.0
var _orbit_pitch := .42
var _orbit_distance := 6.2
var _contact_display: Control
var _stroke_display: Control
var _stroke_readout: Label
var shot: Dictionary = {}
var swing_seconds := 0.0
var watch_camera := false
var _camera: Camera3D
var _previous_camera: Camera3D
var _panel: PanelContainer
var _title: Label
var _info: Label
var _hint: Label
var _power: ProgressBar
var _action: Button
var _feedback := ""
var _feedback_time := 0.0
var _audio: AudioStreamPlayer
var _particles: CPUParticles3D
var _clock := 0.0
var _hud_timer := 0.0

func configure(farm_session: Farm3DSession, farmer: Farm3DPlayer, farm_hud: CanvasLayer) -> void:
	name = "Golf"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	session = farm_session
	player = farmer
	hud = farm_hud
	round_state = session.golf_round
	course = Art.new()
	add_child(course)
	course.configure(session)
	visual = Visual.new()
	add_child(visual)
	visual.configure(player)
	_camera = Camera3D.new()
	_camera.fov = 48
	_camera.far = 400
	add_child(_camera)
	_build_hud()
	for modal in [hud.windmill_view,hud.food_workshop_view,hud.market_view,hud.inventory_ui,hud.history_panel]:
		modal.visibility_changed.connect(func():
			if modal.visible:
				release_control()
				_panel.hide()
		)
	_build_feedback()
	session.state_loaded.connect(_restore)
	_restore()

func _restore() -> void:
	release_control()
	round_state = session.golf_round
	ball.place(round_state.ball)
	if course.market_site != session.market_site:
		course.configure(session)
	phase = Phase.HOLED if round_state.active and round_state.scores.size() > round_state.hole else Phase.WALK if round_state.active else Phase.OFF
	visual.clear_trail()
	visual.ball_mesh.visible = round_state.active and phase != Phase.HOLED
	visual.marker.visible = visual.ball_mesh.visible
	course.score_label.text = "个人最佳 %d 杆 · 免费借杆" % round_state.best if round_state.best > 0 else "免费练习 · 鼠标后拉、前推挥杆"
	_update_hud()

func is_controlling() -> bool:
	return phase in [Phase.ADDRESS,Phase.SWING] or watch_camera

func near_entrance() -> bool:
	return player.global_position.distance_to(Art.ground(Course.ENTRANCE)+Vector3.BACK) < 4.0

func start_round() -> bool:
	if not near_entrance() or hud.is_modal_open() or round_state.active:
		return false
	get_parent().cancel_selection()
	round_state.start()
	ball.place(round_state.ball)
	phase = Phase.WALK
	_feedback_message("已借球杆，走到 1 号发球台，球旁按 E 准备")
	_save()
	_update_hud()
	return true

func restart_round() -> bool:
	var at_course := Course.BOUNDS.grow(12).has_point(Vector2(player.global_position.x,player.global_position.z))
	if hud.is_modal_open() or (not round_state.active and round_state.scores.is_empty()) or (not at_course and not is_controlling()):
		return false
	get_parent().cancel_selection()
	release_control()
	round_state.start()
	ball.place(round_state.ball)
	phase = Phase.WALK
	shot.clear()
	swing_seconds = 0
	visual.clear_trail()
	_particles.emitting = false
	_audio.stop()
	player.global_position = ball.position+Vector3.RIGHT
	player.velocity = Vector3.ZERO
	enter_address()
	visual.update_ball(ball.position,false,false)
	_feedback_message("已复位到 1 号洞 · 本轮杆数清零，个人最佳保留")
	_save()
	_update_hud()
	return true

func enter_address() -> bool:
	if phase != Phase.WALK or not round_state.active or hud.is_modal_open() or player.global_position.distance_to(ball.position) > 2.8:
		return false
	get_parent().cancel_selection()
	var cup: Vector2 = Course.HOLES[round_state.hole].cup
	direction = Vector3(cup.x-ball.position.x,0,cup.y-ball.position.z).normalized()
	club = 2 if Course.surface(round_state.ball) == "green" else 1 if Course.surface(round_state.ball) == "sand" else 0
	contact_height = 0 if club == 2 else -.6
	stance_distance = .8
	_orbiting = false
	var offset := Vector3.UP.cross(direction)*4.2-direction*3.5
	_orbit_yaw = atan2(offset.x,offset.z)
	_orbit_pitch = .42
	phase = Phase.ADDRESS
	_feedback_time = 0
	player.golf_locked = true
	player.velocity = Vector3.ZERO
	visual.set_equipped(true)
	_previous_camera = get_viewport().get_camera_3d()
	_camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_stance()
	_update_camera()
	visual.set_contact(ball.position,direction,contact_height)
	visual.pose(0,club)
	_update_hud()
	return true

func _stance() -> void:
	var right := Vector3.UP.cross(direction)
	# Face the ball side-on: the target is to the golfer's left. In the
	# default frontal camera the golfer stands to the right of the ball.
	var point := ball.position-right*stance_distance
	point.y = Art.ground(Vector2(point.x,point.z)).y
	player.global_position = point
	player.look_at(point+right,Vector3.UP,true)

func _update_camera(blend := 1.0) -> void:
	var focus := ball.position+Vector3.UP*(.4 if phase == Phase.FLIGHT else .75)
	var offset := Vector3(sin(_orbit_yaw)*cos(_orbit_pitch),sin(_orbit_pitch),cos(_orbit_yaw)*cos(_orbit_pitch))*_orbit_distance
	var desired := focus+offset
	desired.y = maxf(desired.y,Art.ground(Vector2(desired.x,desired.z)).y+.3)
	var query := PhysicsRayQueryParameters3D.create(focus,desired,1|16|32)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		desired = hit.position+(focus-hit.position).normalized()*.25
	_camera.global_position = _camera.global_position.lerp(desired,blend)
	_camera.look_at(focus)

func handle_input(event: InputEvent) -> bool:
	if hud.is_modal_open():
		return false
	if is_controlling():
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = event.pressed
			if _orbiting:
				gesture.cancel()
			return true
		if event is InputEventMouseMotion and _orbiting:
			_orbit_yaw -= event.relative.x*.006
			_orbit_pitch = clampf(_orbit_pitch+event.relative.y*.006,.08,1.25)
			_update_camera()
			return true
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R and restart_round():
			return true
		if event.keycode == KEY_I:
			release_control()
			return false
		if event.keycode == KEY_ESCAPE:
			if is_controlling():
				release_control()
				return true
			if phase == Phase.FINISHED:
				phase = Phase.OFF
				_update_hud()
				return true
		if event.keycode == KEY_E:
			if phase == Phase.WALK:
				return enter_address()
			if phase == Phase.HOLED:
				return next_hole()
			if not round_state.active and near_entrance():
				return start_round()
		if phase == Phase.ADDRESS:
			if event.keycode in [KEY_1,KEY_2,KEY_3]:
				club = int(event.keycode)-KEY_1
				contact_height = 0 if club == 2 else -.6
				gesture.cancel()
				_update_hud()
				return true
			if event.keycode in [KEY_MINUS,KEY_EQUAL]:
				# User-facing sensitivity is local to golf, preserving camera settings.
				session.golf_sensitivity = clampf(session.golf_sensitivity + (.15 if event.keycode == KEY_EQUAL else -.15),.4,2.0)
				_update_hud()
				return true
	if phase == Phase.ADDRESS:
		if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			if not gesture.dragging and not _orbiting:
				contact_height = clampf(contact_height+(.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -.1),-1,1)
			return true
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and not _orbiting:
				gesture.begin(Time.get_ticks_usec()/1000000.0)
			elif gesture.dragging:
				gesture.cancel()
				_feedback_message("已收杆：后拉后保持按住左键，再向前推过击球点")
			return true
		if event is InputEventMouseMotion:
			if gesture.dragging:
				var strike := gesture.motion(event.relative * session.golf_sensitivity,Time.get_ticks_usec()/1000000.0,_short_stroke())
				if not strike.is_empty():
					begin_swing(strike)
			return true
	if is_controlling():
		return not (event is InputEventKey and event.keycode == KEY_G)
	return false

func try_world_click(pointer: Vector2) -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null or hud.is_modal_open():
		return false
	var origin := camera.project_ray_origin(pointer)
	var query := PhysicsRayQueryParameters3D.create(origin,origin+camera.project_ray_normal(pointer)*camera.far,1|16|64)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and bool(hit.collider.get_meta("golf_entrance",false)):
		if round_state.active:
			_feedback_message("本轮还在继续，按小地图找到球或下一发球台")
		elif not start_round():
			hud.notify_message("请走到球杆架前借杆",false)
		return true
	return false

func _short_stroke() -> bool:
	return club == 2 or contact_height >= -.05

func _backswing_angle() -> float:
	var pull := gesture.offset.y if gesture.dragging else gesture.peak
	return clampf(pull/Farm3DGolfSwing.FULL_PULL,0,1)*(.75 if _short_stroke() else 2.6)

func begin_swing(value: Dictionary) -> bool:
	if phase != Phase.ADDRESS or not is_finite(float(value.get("power",NAN))) or not is_finite(float(value.get("deviation",NAN))):
		return false
	shot = value.duplicate()
	shot.power = clampf(shot.power,.01,1)
	shot.deviation = clampf(shot.deviation,-.255,.255)
	shot["angle"] = _backswing_angle()
	# A real mouse stroke already moved the club down to the contact gate.
	if shot.has("backswing"):
		shot.angle *= .12
	shot["impact_delay"] = .07 if shot.has("backswing") else .18
	shot["followthrough"] = .65 if _short_stroke() else 2.1
	shot["contact_height"] = contact_height
	phase = Phase.SWING
	swing_seconds = 0
	gesture.cancel()
	visual.hide_aim()
	return true

func _impact() -> void:
	ball.strike(direction.rotated(Vector3.UP,-shot.deviation),shot.power,club,shot.contact_height)
	# Keep saved round state at the last settled checkpoint until this ball stops.
	phase = Phase.FLIGHT
	watch_camera = true
	visual.clear_trail()
	_particles.global_position = ball.position
	_particles.restart()
	_particles.emitting = true
	_audio.pitch_scale = 1.4 if club == 2 else 1.0
	_audio.play()
	var airborne := ball.velocity.dot(Farm3DTerrainProfile.surface_normal(ball.position.x,ball.position.z)) > .3
	_feedback_message("力度 %d%% · %s · %s" % [roundi(shot.power*100),"甜点击球" if absf(shot.deviation) < .001 else ("右偏 %.1f°" if shot.deviation > 0 else "左偏 %.1f°") % rad_to_deg(absf(shot.deviation)),"挑高球" if airborne else "地滚球"])

func _process(delta: float) -> void:
	if session == null:
		return
	_clock += delta
	_feedback_time = maxf(0,_feedback_time-delta)
	if hud.is_modal_open() and is_controlling():
		release_control()
	if phase == Phase.ADDRESS:
		if not gesture.dragging and not _orbiting:
			var turn := Input.get_axis("move_left","move_right")
			var fine_aim := Input.is_physical_key_pressed(KEY_SHIFT)
			direction = direction.rotated(Vector3.UP,-turn*delta*(.06 if fine_aim else .35))
			var vertical := float(Input.is_physical_key_pressed(KEY_W))-float(Input.is_physical_key_pressed(KEY_S))
			contact_height = clampf(contact_height+vertical*delta*.8,-1,1)
			var distance_step := float(Input.is_physical_key_pressed(KEY_Q))-float(Input.is_physical_key_pressed(KEY_E))
			stance_distance = clampf(stance_distance+distance_step*delta*.3,.68,.98)
			_stance()
		_update_camera()
		visual.set_contact(ball.position,direction,contact_height)
		visual.pose(_backswing_angle() if gesture.dragging else 0,club)
		visual.show_aim(ball.position,direction,club,maxf(.01,gesture.power(_short_stroke())) if gesture.dragging else .65,contact_height)
	elif phase == Phase.SWING:
		_update_camera()
		swing_seconds += delta
		visual.pose(lerpf(float(shot.angle),0,clampf(swing_seconds/float(shot.impact_delay),0,1)),club)
		if swing_seconds >= float(shot.impact_delay):
			_impact()
	elif phase == Phase.FLIGHT:
		swing_seconds += delta
		visual.pose(-smoothstep(float(shot.impact_delay),float(shot.impact_delay)+.52,swing_seconds)*float(shot.followthrough),club)
		if swing_seconds > .9:
			visual.set_equipped(false)
		ball.advance(delta,Course.HOLES[round_state.hole].cup,get_world_3d().direct_space_state)
		if watch_camera:
			_update_camera(1-exp(-delta*8))
		if not ball.moving:
			_settle()
	if round_state.active and phase != Phase.HOLED:
		visual.update_ball(ball.position,phase == Phase.FLIGHT,phase == Phase.WALK)
	else:
		visual.ball_mesh.hide()
		visual.marker.hide()
	_hud_timer -= delta
	if _hud_timer <= 0:
		_hud_timer = .08
		_update_hud()

func _settle() -> void:
	if phase != Phase.FLIGHT or ball.moving or ball.result not in ["rest","penalty","holed"]:
		return
	round_state.strokes += 1
	if ball.result == "penalty":
		round_state.strokes += 1
		ball.place(round_state.ball)
		_feedback_message("出界或入水，罚 1 杆，球已放回本杆起点")
	else:
		round_state.ball = Vector2(ball.position.x,ball.position.z)
	var holed := ball.result == "holed"
	release_control()
	visual.clear_trail()
	if holed:
		round_state.complete_hole()
		phase = Phase.HOLED if round_state.active else Phase.FINISHED
		_feedback_message("进洞！本洞 %d 杆 · %s" % [round_state.strokes,"前往下一发球台" if round_state.active else "三洞完成"])
	else:
		phase = Phase.WALK
	_save()
	_update_hud()

func next_hole() -> bool:
	if phase != Phase.HOLED or round_state.hole >= 2:
		return false
	var next: Vector2 = Course.HOLES[round_state.hole+1].tee
	if player.global_position.distance_to(Art.ground(next)) > 3.0:
		_feedback_message("走到下一洞发球台，按 E 开始")
		return false
	round_state.hole += 1
	round_state.strokes = 0
	round_state.ball = next
	ball.place(next)
	phase = Phase.WALK
	_save()
	return enter_address()

func release_control() -> void:
	gesture.cancel()
	_orbiting = false
	if phase in [Phase.ADDRESS,Phase.SWING]:
		phase = Phase.WALK
	player.golf_locked = false
	visual.set_equipped(false)
	if _camera.current:
		if is_instance_valid(_previous_camera):
			_previous_camera.make_current()
		else:
			get_parent().get_parent().follow_camera.make_current()
	watch_camera = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _panel != null:
		hud._menu.show()

func _exit_tree() -> void:
	if is_instance_valid(player):
		player.golf_locked = false
	if is_controlling():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func target_point() -> Vector3:
	if phase == Phase.HOLED:
		return Art.ground(Course.HOLES[mini(2,round_state.hole+1)].tee)
	return ball.position

func _save() -> void:
	if session.auto_save and not session.save_game():
		hud.notify_message("高尔夫进度保存失败，请手动保存",false)

func _feedback_message(text: String) -> void:
	_feedback = text
	_feedback_time = 4

func _build_hud() -> void:
	_panel = PanelContainer.new()
	_panel.name = "GolfHUD"
	_panel.custom_minimum_size.x = minf(760,hud._ui.size.x-36)
	_panel.add_theme_stylebox_override("panel",hud._style(Color("233b2af5"),Color("c3b17c")))
	hud._ui.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",8)
	_panel.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size",20)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_title)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size",16)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info)
	var contact_row := HBoxContainer.new()
	box.add_child(contact_row)
	_contact_display = Control.new()
	_contact_display.custom_minimum_size = Vector2(60,60)
	contact_row.add_child(_contact_display)
	_contact_display.draw.connect(func():
		_contact_display.draw_circle(Vector2(30,30),24,Color("eee9d7"))
		_contact_display.draw_line(Vector2(8,30),Vector2(52,30),Color("aab69a"),1)
		_contact_display.draw_circle(Vector2(30,30-contact_height*20),5,Color("b96843"))
	)
	var contact_help := Label.new()
	contact_help.text = "W/S 或滚轮：触球点上/下\n下部＋力度：挑高球；中心轻击：推球"
	contact_help.add_theme_font_size_override("font_size",14)
	contact_row.add_child(contact_help)
	_stroke_display = Control.new()
	_stroke_display.custom_minimum_size = Vector2(100,60)
	contact_row.add_child(_stroke_display)
	var stroke_style: StyleBox = hud._style(Color("152c23"),Color("517663"))
	_stroke_display.draw.connect(func():
		var center := Vector2(50,8)
		var width := gesture.corridor()*.6
		_stroke_display.draw_style_box(stroke_style,Rect2(8,2,84,56))
		_stroke_display.draw_rect(Rect2(50-width,5,width*2,50),Color("438c6970"))
		_stroke_display.draw_line(center,Vector2(50,54),Color("d8dfb4"),1)
		_stroke_display.draw_line(Vector2(12,8),Vector2(88,8),Color("d8dfb4"),1)
		if gesture.dragging:
			var point := Vector2(50+clampf(gesture.offset.x*.6,-38,38),8+gesture.offset.y/Farm3DGolfSwing.FULL_PULL*44)
			_stroke_display.draw_line(center,point,Color("93bba0"),2)
			_stroke_display.draw_circle(point,4,Color("b7edaf") if absf(gesture.offset.x) <= gesture.corridor() else Color("f1be73"))
	)
	_stroke_readout = Label.new()
	_stroke_readout.add_theme_font_size_override("font_size",14)
	contact_row.add_child(_stroke_readout)
	_power = ProgressBar.new()
	_power.custom_minimum_size.y = 12
	_power.show_percentage = false
	box.add_child(_power)
	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size",15)
	box.add_child(_hint)
	_action = hud._button("借杆开始  E",Vector2(0,38))
	_action.pressed.connect(func():
		if not round_state.active:
			start_round()
		elif phase == Phase.HOLED:
			next_hole()
		else:
			enter_address()
	)
	box.add_child(_action)
	_panel.hide()

func _update_hud() -> void:
	var at_course := Course.BOUNDS.grow(12).has_point(Vector2(player.global_position.x,player.global_position.z))
	var show_panel: bool = not hud.is_modal_open() and ((round_state.active and (at_course or is_controlling())) or phase == Phase.FINISHED or near_entrance())
	_panel.visible = show_panel
	if not show_panel:
		return
	var width := minf(760,hud._ui.size.x-36)
	_panel.custom_minimum_size.x = width
	_panel.size = Vector2(width,0)
	_panel.position = Vector2((hud._ui.size.x-width)*.5,hud._ui.size.y-_panel.size.y-(18 if is_controlling() else hud._menu.size.y+30))
	hud._menu.visible = not is_controlling()
	_power.visible = phase == Phase.ADDRESS
	_contact_display.get_parent().visible = phase == Phase.ADDRESS
	_contact_display.queue_redraw()
	_stroke_display.queue_redraw()
	_power.value = gesture.power(_short_stroke())*100 if gesture.dragging else 0
	_stroke_readout.text = "力度 %d%% · %s\n%s" % [roundi(_power.value),"推球" if _short_stroke() else "挑高",("绿色区内直出" if absf(gesture.offset.x) <= gesture.corridor() else "斜推将偏球") if gesture.dragging else "虚线预览 65% 力度"]
	_action.visible = not is_controlling() and phase != Phase.FINISHED
	if not round_state.active:
		_title.text = "三洞完成 · %d 杆 / 标准 9 杆" % round_state.scores.reduce(func(a,b):return a+b,0) if phase == Phase.FINISHED else "湖西高尔夫 · 免费借杆"
		_info.text = "个人最佳：%d 杆" % round_state.best if round_state.best > 0 else "三洞短场 · 进洞后完成本洞"
		_hint.text = "R 回到 1 号洞重开 · Esc 收起成绩" if phase == Phase.FINISHED else "走到球杆架前，点击开始。后拉鼠标蓄势，前推挥杆。"
		_action.disabled = not near_entrance()
		_action.text = "借杆开始  E"
		return
	var cup: Vector2 = Course.HOLES[round_state.hole].cup
	var distance := Vector2(ball.position.x,ball.position.z).distance_to(cup)
	_title.text = "%d / 3 洞 · %s · %d 杆 · 距洞 %.1f 米" % [round_state.hole+1,Course.HOLES[round_state.hole].name,round_state.strokes+(1 if phase == Phase.FLIGHT else 0),distance]
	if phase == Phase.WALK:
		_title.text += " · 距球 %.1f 米" % player.global_position.distance_to(ball.position)
	_info.text = "%s · A/D 瞄准（Shift 精调）· Q/E 站距 · 1/2/3 换杆 · 灵敏度 %.2f（−/=）" % [Farm3DGolfBall.CLUBS[club].name,session.golf_sensitivity]
	_title.text += " · R 重开"
	_hint.text = _feedback if _feedback_time > 0 else "左键后拉定力度、前推击球，松开取消 · 右键转镜头 · 虚线仅示前段球路 · Esc 退出" if phase == Phase.ADDRESS else "球正在移动 · 右键转镜头，Esc 返回角色" if phase == Phase.FLIGHT else "本洞完成，前往下一洞发球台按 E" if phase == Phase.HOLED else "走到球旁按 E 准备，WASD 行走，Shift 奔跑"
	_action.text = "下一洞  E" if phase == Phase.HOLED else "准备击球  E"
	_action.disabled = player.global_position.distance_to(target_point()) > 2.8 or phase == Phase.FLIGHT

func _build_feedback() -> void:
	_audio = AudioStreamPlayer.new()
	add_child(_audio)
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = 22050
	var pcm := PackedByteArray()
	pcm.resize(4410)
	var rng := RandomNumberGenerator.new()
	rng.seed = 73
	for i in 2205:
		var t := float(i)/22050
		pcm.encode_s16(i*2,int((sin(t*TAU*900)*.45+rng.randf_range(-.3,.3))*exp(-t*65)*22000))
	wave.data = pcm
	_audio.stream = wave
	_audio.volume_db = -10
	_particles = CPUParticles3D.new()
	_particles.amount = 14
	_particles.lifetime = .45
	_particles.one_shot = true
	_particles.explosiveness = 1
	_particles.direction = Vector3.UP
	_particles.spread = 75
	_particles.initial_velocity_min = .6
	_particles.initial_velocity_max = 1.8
	_particles.gravity = Vector3.DOWN*5
	var shape := SphereMesh.new()
	shape.radius = .018
	shape.height = .036
	_particles.mesh = shape
	_particles.color = Color("adc286")
	_particles.emitting = false
	add_child(_particles)
