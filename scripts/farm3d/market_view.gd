extends Control

signal closed
const PanelScene = preload("res://scenes/ui/economy/market_panel.tscn")
const Layout = preload("res://scripts/ui/economy_layout.gd")
var market_panel: MarketPanel
var _session: Node
var _window: PanelContainer
var _wallet: Label
var _back: Button

func configure(session: Node) -> void:
	_session = session
	name = "MarketView"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = preload("res://assets/ui/economy/economy_theme.tres").duplicate()
	theme.set_constant("outline_size", "Label", 0)
	var dimmer := ColorRect.new()
	dimmer.color = Color(0.04, .08, .06, .62)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dimmer)
	_window = PanelContainer.new()
	_window.theme_type_variation = &"EconomyCompactCard"
	add_child(_window)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_window.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.text = "农庄市集"
	title.add_theme_font_size_override("font_size", 24)
	header.add_child(title)
	_wallet = Label.new()
	_wallet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wallet.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_wallet)
	_back = Button.new()
	_back.text = "返回货物"
	_back.pressed.connect(func(): market_panel.handle_top_escape())
	header.add_child(_back)
	var close := Button.new()
	close.text = "离开市集 · Esc"
	close.custom_minimum_size = Vector2(180, 44)
	close.pressed.connect(close_market)
	header.add_child(close)
	market_panel = PanelScene.instantiate()
	market_panel.set_script(preload("res://scripts/farm3d/market_panel.gd"))
	market_panel.theme = theme
	market_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(market_panel)
	market_panel.configure(session.inventory, session.economy, session.market)
	market_panel.trade_panel.snapshot_changed.connect(_after_trade)
	resized.connect(_layout)
	session.state_loaded.connect(close_market)
	hide()
	_layout.call_deferred()

func open_market() -> void:
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	market_panel.refresh_market()
	_layout()

func close_market() -> void:
	market_panel.trade_panel.dismiss_confirmation()
	hide()
	closed.emit()

func handle_escape() -> void:
	if not market_panel.handle_top_escape():
		close_market()

func _after_trade() -> void:
	if _session.auto_save:
		if not _session.save_game():
			market_panel.trade_panel._show_feedback("交易已完成，保存失败，请手动保存")

func _process(_delta: float) -> void:
	if not visible:
		return
	_wallet.text = "金币 %d   " % int(get_node("/root/GameState").gold)
	_back.visible = market_panel.get_layout_mode() == "drawer" and market_panel._drawer_open

func _layout() -> void:
	if _window == null:
		return
	var rect := Layout.panel_rect_for(size, Vector2(1400, 850))
	# Choose the breakpoint before minimum sizes can expand the container.
	market_panel.apply_responsive_layout(rect.size - Vector2(48, 90))
	_window.position = rect.position
	_window.size = rect.size
