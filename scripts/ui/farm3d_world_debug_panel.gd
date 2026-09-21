extends VBoxContainer

signal busy_changed(busy: bool)

const Player = preload("res://scripts/data/player_state.gd")
const SEASONS := ["春", "夏", "秋", "冬"]
var session: Node
var level_input: SpinBox
var season_input: OptionButton
var day_input: SpinBox
var hour_input: SpinBox
var minute_input: SpinBox
var status: Label
var apply_level_button: Button
var apply_time_button: Button
var next_day_button: Button
var stop_button: Button
var busy := false
var _stop := false

func configure(owner: Node) -> void:
	session = owner
	add_theme_constant_override("separation", 12)
	var hint := Label.new()
	hint.text = "编辑时暂停游戏。快进会结算作物、生产与居民生活；当天已过的时刻推进到次日，较早的日期推进到下一年。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color("513b2f"))
	add_child(hint)
	var fields := GridContainer.new()
	fields.columns = 2
	fields.add_theme_constant_override("h_separation", 24)
	fields.add_theme_constant_override("v_separation", 8)
	add_child(fields)
	level_input = _number(fields, "玩家等级", "Level", 1, Player.LEVEL_THRESHOLDS.size())
	_label(fields, "季节")
	season_input = OptionButton.new()
	season_input.name = "Season"
	for season_name in SEASONS: season_input.add_item(season_name)
	fields.add_child(season_input)
	day_input = _number(fields, "季节第几天", "Day", 1, 7)
	hour_input = _number(fields, "小时", "Hour", 6, 23)
	minute_input = _number(fields, "分钟", "Minute", 0, 59)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	add_child(buttons)
	apply_level_button = _button(buttons, "应用等级", "ApplyLevel", apply_level)
	apply_time_button = _button(buttons, "推进到所选时间", "ApplyTime", apply_time)
	next_day_button = _button(buttons, "下一天 06:00", "NextDay", next_day)
	stop_button = _button(buttons, "停止快进", "Stop", func(): _stop = true)
	stop_button.hide()
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", Color("513b2f"))
	add_child(status)
	refresh()

func _label(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color("513b2f"))
	parent.add_child(label)

func _number(parent: Node, text: String, node_name: String, minimum: int, maximum: int) -> SpinBox:
	_label(parent, text)
	var input := SpinBox.new()
	input.name = node_name
	input.min_value = minimum
	input.max_value = maximum
	input.update_on_text_changed = true
	input.custom_minimum_size = Vector2(240, 36)
	parent.add_child(input)
	return input

func _button(parent: Node, text: String, node_name: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func refresh() -> void:
	if busy: return
	level_input.value = session.get_node("/root/GameState").player_state.level
	season_input.select(session.season.current_season)
	day_input.value = session.season.current_day
	hour_input.value = session.season.hour
	minute_input.value = session.season.minute
	status.text = "当前：第 %d 天 · %s季第 %d 天 · %02d:%02d。修改随游戏正常保存。" % [session.season.total_days, SEASONS[session.season.current_season], session.season.current_day, session.season.hour, session.season.minute]

func apply_level() -> void:
	if busy or not OS.is_debug_build(): return
	var player: RefCounted = session.get_node("/root/GameState").player_state
	var level := roundi(level_input.value)
	if player.level != level:
		player.level = level
		player.exp = Player.LEVEL_THRESHOLDS[level - 1]
		session.get_node("/root/EventBus").level_changed.emit(level)
	status.text = "等级已设置为 %d，经验已同步。修改随游戏正常保存。" % level

func target_minute() -> int:
	var current: int = session.living_world.minute()
	var day_of_year := season_input.selected * 7 + roundi(day_input.value) - 1
	var target: int = ((session.season.total_days - 1) / 28 * 28 + day_of_year) * 1080 + (roundi(hour_input.value) - 6) * 60 + roundi(minute_input.value)
	if target < current:
		target += 1080 if day_of_year == (session.season.total_days - 1) % 28 else 28 * 1080
	return target

func apply_time() -> void:
	await advance_to(target_minute())

func next_day() -> void:
	await advance_to(session.season.total_days * 1080)

func advance_to(target: int) -> void:
	if busy or not OS.is_debug_build() or not get_tree().paused: return
	busy = true
	_stop = false
	busy_changed.emit(true)
	for button in [apply_level_button, apply_time_button, next_day_button]: button.disabled = true
	for input in [level_input, day_input, hour_input, minute_input]: input.editable = false
	season_input.disabled = true
	stop_button.show()
	var runtime: Node = session.agent_runtime
	runtime.gateway.cancel_all("debug_state_changed")
	# Settle through the ordinary clock and world systems in bounded frame slices.
	# No remote planning is dispatched for intermediate fast-forward timestamps.
	while true:
		var current: int = session.living_world.minute()
		var caught_up: bool = session.living_world.society.caught_up(current)
		if caught_up and (_stop or current >= target): break
		var remote: bool = runtime.service_enabled
		runtime.service_enabled = false
		get_tree().paused = false
		if caught_up:
			session.season.advance_game_minutes(mini(60, target - current))
		session.living_world.advance()
		get_tree().paused = true
		runtime.service_enabled = remote
		status.text = "正在推进：第 %d 天 · %02d:%02d…" % [session.season.total_days, session.season.hour, session.season.minute]
		await get_tree().process_frame
	var minute: int = session.living_world.minute()
	runtime.scheduler._reset_daily_budget(minute)
	session.living_world.public_plans.scheduler._reset_daily_budget(minute)
	runtime._scheduled_tick_pending = runtime.service_enabled
	busy = false
	for button in [apply_level_button, apply_time_button, next_day_button]: button.disabled = false
	for input in [level_input, day_input, hour_input, minute_input]: input.editable = true
	season_input.disabled = false
	stop_button.hide()
	busy_changed.emit(false)
	refresh()
