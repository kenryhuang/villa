class_name MarketPanel
extends PanelContainer

const GameDataScript = preload("res://scripts/core/game_data.gd")
const MarketPriceChartScript = preload("res://scripts/ui/market_price_chart.gd")
const TradePanelScript = preload("res://scripts/ui/trade_panel.gd")
const EconomyLayoutScript = preload("res://scripts/ui/economy_layout.gd")

const CATEGORY_IDS := [
	"raw_materials",
	"crops",
	"processed_materials",
	"food_handicrafts",
	"rare_goods",
]
const SORT_IDS := ["recommended", "rise", "fall", "shortage", "owned_quantity", "name"]
const SORT_LABELS := ["推荐", "涨幅", "跌幅", "紧缺", "持有量", "名称"]

@onready var category_buttons := {
	"raw_materials": $Columns/CatalogColumn/CatalogContent/CategoryTabs/RawMaterials,
	"crops": $Columns/CatalogColumn/CatalogContent/CategoryTabs/Crops,
	"processed_materials": $Columns/CatalogColumn/CatalogContent/CategoryTabs/ProcessedMaterials,
	"food_handicrafts": $Columns/CatalogColumn/CatalogContent/CategoryTabs/FoodHandicrafts,
	"rare_goods": $Columns/CatalogColumn/CatalogContent/CategoryTabs/RareGoods,
}
@onready var sort_option: OptionButton = $Columns/CatalogColumn/CatalogContent/SortMode
@onready var item_list: ItemList = $Columns/CatalogColumn/CatalogContent/ItemList
@onready var item_scroll: ScrollContainer = $Columns/CatalogColumn/CatalogContent/ItemScroll
@onready var item_rows: VBoxContainer = $Columns/CatalogColumn/CatalogContent/ItemScroll/ItemRows
@onready var empty_label: Label = $Columns/CatalogColumn/CatalogContent/EmptyLabel
@onready var item_name_label: Label = $Columns/DetailColumn/DetailContent/DetailHeader/ItemNameLabel
@onready var mid_price_label: Label = $Columns/DetailColumn/DetailContent/PriceMetrics/MidPriceLabel
@onready var buy_price_label: Label = $Columns/DetailColumn/DetailContent/PriceMetrics/BuyPriceLabel
@onready var sell_price_label: Label = $Columns/DetailColumn/DetailContent/PriceMetrics/SellPriceLabel
@onready var stock_label: Label = $Columns/DetailColumn/DetailContent/StockLabel
@onready var trend_label: Label = $Columns/DetailColumn/DetailContent/DetailHeader/TrendLabel
@onready var flow_label: Label = $Columns/DetailColumn/DetailContent/FlowLabel
@onready var price_chart = $Columns/DetailColumn/DetailContent/PriceChart
@onready var tags_label: Label = $Columns/DetailColumn/DetailContent/TagsLabel
@onready var source_use_label: Label = $Columns/DetailColumn/DetailContent/SourceUseLabel
@onready var processing_label: Label = $Columns/DetailColumn/DetailContent/ProcessingLabel
@onready var trade_panel = $Columns/TradePanel

var inventory_ref: InventorySystem
var economy_ref: EconomySystem
var market_ref: MarketSystem
var selected_category := "raw_materials"
var selected_item_id := ""
var sort_mode := "recommended"
var _item_ids: Array[String] = []
var _layout_mode := "three_column"
var _drawer_open := false
var _logical_layout_size := Vector2.ZERO


func _ready() -> void:
	add_to_group(EconomyLayoutScript.RESPONSIVE_GROUP)
	for category_id in category_buttons:
		category_buttons[category_id].pressed.connect(select_category.bind(category_id))
	sort_option.clear()
	for index in range(SORT_IDS.size()):
		sort_option.add_item(SORT_LABELS[index], index)
	sort_option.item_selected.connect(_on_sort_selected)
	item_list.item_selected.connect(_on_item_selected)
	if not resized.is_connected(_on_control_resized):
		resized.connect(_on_control_resized)
	if not get_viewport().size_changed.is_connected(_on_viewport_size_changed):
		get_viewport().size_changed.connect(_on_viewport_size_changed)
	apply_economy_ui_scale(EconomyLayoutScript.get_ui_scale())


func configure(
	inventory: InventorySystem,
	economy: EconomySystem,
	market: MarketSystem
) -> bool:
	inventory_ref = inventory
	economy_ref = economy
	market_ref = market
	if inventory_ref == null or economy_ref == null or market_ref == null:
		return false
	trade_panel.configure(inventory_ref, economy_ref, market_ref)
	if not trade_panel.is_connected("snapshot_changed", _on_trade_snapshot_changed):
		trade_panel.connect("snapshot_changed", _on_trade_snapshot_changed)
	_rebuild_item_list()
	return true


func select_category(category: String) -> void:
	if category not in CATEGORY_IDS:
		return
	selected_category = category
	_rebuild_item_list()


func set_sort_mode(mode: String) -> void:
	if mode not in SORT_IDS:
		return
	sort_mode = mode
	var option_index := SORT_IDS.find(mode)
	if sort_option != null and sort_option.selected != option_index:
		sort_option.select(option_index)
	_rebuild_item_list()


func select_item(next_item_id: String) -> void:
	if market_ref == null or market_ref.get_item_state(next_item_id).is_empty():
		return
	selected_item_id = next_item_id
	var row := _item_ids.find(selected_item_id)
	if row >= 0:
		item_list.select(row)
	for item_row in item_rows.get_children():
		var select_button := item_row.get_node_or_null("Content/SelectButton") as Button
		if select_button != null:
			select_button.button_pressed = str(item_row.get_meta("item_id", "")) == selected_item_id
	if _layout_mode == "drawer":
		open_details_drawer()
	refresh_snapshot()


func refresh_snapshot() -> void:
	if market_ref == null or selected_item_id.is_empty():
		_show_empty_detail()
		return
	var state := market_ref.get_item_state(selected_item_id)
	if state.is_empty():
		_show_empty_detail()
		return
	var definition: Dictionary = GameDataScript.get_item(selected_item_id)
	var mid := int(state.get("mid_price", 0))
	var buy_price := market_ref.quote_buy(selected_item_id, 1)
	var sell_price := market_ref.quote_sell(selected_item_id, 1)
	var history := market_ref.get_history(selected_item_id)
	item_name_label.text = str(definition.get("name", selected_item_id))
	mid_price_label.text = "中间价：%d" % mid
	buy_price_label.text = "买入价：%d" % buy_price
	sell_price_label.text = "卖出价：%d" % sell_price
	stock_label.text = "库存：%d / 目标 %d　%s" % [
		int(state.get("stock", 0)),
		int(state.get("target_stock", 0)),
		_stock_status(state),
	]
	trend_label.text = "趋势：%s" % _trend_text(history)
	flow_label.text = "今日供给 %d　今日需求 %d　流动量 %d" % [
		int(state.get("supply", 0)),
		int(state.get("demand", 0)),
		int(state.get("daily_liquidity", 0)),
	]
	price_chart.set_series(
		history,
		_history_dates(history.size()),
		_history_reasons(history, state, definition)
	)
	tags_label.text = "标签：%s　季节 —　事件 —　NPC需求 %s" % [
		str(definition.get("volatility", "stable")),
		"活跃" if int(state.get("demand", 0)) > 0 else "平稳",
	]
	source_use_label.text = "主要来源：农庄生产／采集　主要用途：建造／加工／交易"
	processing_label.text = "加工参考：按当前行情估算，不承诺最终利润"
	trade_panel.set_item(selected_item_id)


func handle_top_escape() -> bool:
	if trade_panel.handle_top_escape():
		return true
	if _layout_mode == "drawer" and _drawer_open:
		_drawer_open = false
		_apply_drawer_visibility()
		return true
	return false


func apply_responsive_layout(logical_size: Vector2) -> void:
	_logical_layout_size = logical_size
	var next_mode: String = EconomyLayoutScript.mode_for_size(logical_size)
	if next_mode == _layout_mode:
		_apply_drawer_visibility()
		return
	_layout_mode = next_mode
	if _layout_mode == "three_column":
		_drawer_open = false
	_apply_drawer_visibility()


func apply_economy_ui_scale(ui_scale: float) -> void:
	# Child minimum widths may make this container wider than the space the shell
	# actually owns. Base the breakpoint on the centered modal's available width
	# so a narrow window cannot accidentally select the three-card layout.
	var physical_size := size
	if get_parent() != null and get_parent().name == &"PageHost":
		physical_size = EconomyLayoutScript.panel_rect_for(
			get_viewport_rect().size,
			EconomyLayoutScript.MARKET_PANEL_MAX_SIZE
		).size
	elif physical_size.x <= 0.0:
		physical_size = get_viewport_rect().size
	apply_responsive_layout(EconomyLayoutScript.logical_size_for(physical_size, ui_scale))


func get_layout_mode() -> String:
	return _layout_mode


func open_details_drawer() -> void:
	if _layout_mode != "drawer":
		return
	_drawer_open = true
	_apply_drawer_visibility()
	var first_trade_control := $Columns/TradePanel/Content/QuantityRow/QuantitySpin as Control
	if first_trade_control != null and first_trade_control.is_visible_in_tree():
		first_trade_control.grab_focus()


func _apply_drawer_visibility() -> void:
	if not is_node_ready():
		return
	if _layout_mode == "three_column":
		$Columns/CatalogColumn.visible = true
		$Columns/DetailColumn.visible = true
		$Columns/TradePanel.visible = true
		_set_compact_detail(false)
		return
	$Columns/CatalogColumn.visible = not _drawer_open
	$Columns/DetailColumn.visible = _drawer_open
	$Columns/TradePanel.visible = _drawer_open
	_set_compact_detail(true)


func _set_compact_detail(compact: bool) -> void:
	var logical_height := _logical_layout_size.y
	if logical_height <= 0.0:
		logical_height = EconomyLayoutScript.logical_size_for(
			size,
			EconomyLayoutScript.get_ui_scale()
		).y
	var show_chart := not compact or logical_height >= 420.0
	price_chart.visible = show_chart
	$Columns/DetailColumn/DetailContent/ChartTitle.visible = show_chart
	tags_label.visible = false
	source_use_label.visible = false
	processing_label.visible = false


func _on_viewport_size_changed() -> void:
	apply_economy_ui_scale(EconomyLayoutScript.get_ui_scale())


func _on_control_resized() -> void:
	apply_economy_ui_scale(EconomyLayoutScript.get_ui_scale())


func _rebuild_item_list() -> void:
	if not is_node_ready() or market_ref == null:
		return
	var candidates: Array[Dictionary] = []
	for definition in GameDataScript.get_market_items():
		if _category_for(str(definition.get("category", ""))) != selected_category:
			continue
		if market_ref.get_item_state(str(definition.get("id", ""))).is_empty():
			continue
		candidates.append(definition)
	candidates.sort_custom(_compare_items)
	item_list.clear()
	for child in item_rows.get_children():
		child.free()
	_item_ids.clear()
	for definition in candidates:
		var candidate_id := str(definition.get("id", ""))
		var state := market_ref.get_item_state(candidate_id)
		var history: Array = state.get("history", [])
		var row_text := "%s　卖 %d　%s　%s　持有 %d" % [
			str(definition.get("name", candidate_id)),
			market_ref.quote_sell(candidate_id, 1),
			_trend_text(history),
			_stock_status(state),
			inventory_ref.get_item_count(candidate_id),
		]
		item_list.add_item(row_text)
		item_list.set_item_metadata(item_list.item_count - 1, candidate_id)
		item_rows.add_child(_create_item_row(definition, state, history, row_text))
		_item_ids.append(candidate_id)
	empty_label.visible = _item_ids.is_empty()
	$Columns/CatalogColumn/CatalogContent/ItemScroll.visible = not _item_ids.is_empty()
	if _item_ids.is_empty():
		selected_item_id = ""
		_show_empty_detail()
		return
	if selected_item_id not in _item_ids:
		selected_item_id = _item_ids[0]
	select_item(selected_item_id)


func _compare_items(a: Dictionary, b: Dictionary) -> bool:
	var a_id := str(a.get("id", ""))
	var b_id := str(b.get("id", ""))
	var a_state := market_ref.get_item_state(a_id)
	var b_state := market_ref.get_item_state(b_id)
	match sort_mode:
		"rise":
			return _trend_delta(a_state) > _trend_delta(b_state)
		"fall":
			return _trend_delta(a_state) < _trend_delta(b_state)
		"shortage":
			return _stock_ratio(a_state) < _stock_ratio(b_state)
		"owned_quantity":
			return inventory_ref.get_item_count(a_id) > inventory_ref.get_item_count(b_id)
		"name":
			return str(a.get("name", a_id)) < str(b.get("name", b_id))
		_:
			var a_score := int(a_state.get("demand", 0)) - int(a_state.get("supply", 0))
			var b_score := int(b_state.get("demand", 0)) - int(b_state.get("supply", 0))
			if a_score == b_score:
				return a_id < b_id
			return a_score > b_score


func _create_item_row(
	definition: Dictionary,
	state: Dictionary,
	_history: Array,
	row_text: String
) -> PanelContainer:
	var item_id := str(definition.get("id", ""))
	var row := PanelContainer.new()
	row.name = "ItemRow_%s" % item_id
	row.custom_minimum_size = Vector2(0.0, EconomyLayoutScript.LIST_ROW_HEIGHT)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.set_meta("item_id", item_id)
	row.set_meta("stock", int(state.get("stock", 0)))
	row.set_meta("owned", inventory_ref.get_item_count(item_id) if inventory_ref != null else 0)
	row.tooltip_text = "%s；%s" % [_stock_status(state), "紧急需求" if _is_urgent(state) else "供需平稳"]
	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color("#FFF7E6")
	row_style.corner_radius_top_left = 8
	row_style.corner_radius_top_right = 8
	row_style.corner_radius_bottom_left = 8
	row_style.corner_radius_bottom_right = 8
	row.add_theme_stylebox_override("panel", row_style)

	var content := HBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 8)
	row.add_child(content)
	var icon_info := _item_icon_info(definition)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(34.0, 34.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = icon_info.get("texture") as Texture2D
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(icon)
	row.set_meta("uses_fallback_icon", bool(icon_info.get("fallback", false)))

	var select_button := Button.new()
	select_button.name = "SelectButton"
	select_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	select_button.flat = true
	select_button.clip_text = true
	select_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	select_button.toggle_mode = true
	select_button.text = row_text
	select_button.tooltip_text = "选择%s" % str(definition.get("name", item_id))
	select_button.pressed.connect(select_item.bind(item_id))
	select_button.gui_input.connect(_on_product_button_gui_input.bind(select_button, item_id))
	content.add_child(select_button)

	var stock_bar := ColorRect.new()
	stock_bar.name = "StockColorBar"
	stock_bar.custom_minimum_size = Vector2(8.0, 36.0)
	stock_bar.color = _stock_color(state)
	stock_bar.tooltip_text = "库存状态：%s" % _stock_status(state)
	stock_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_child(stock_bar)

	var urgent_badge := Label.new()
	urgent_badge.name = "UrgentBadge"
	urgent_badge.visible = _is_urgent(state)
	urgent_badge.custom_minimum_size = Vector2(44.0, 0.0)
	urgent_badge.text = "紧缺"
	urgent_badge.add_theme_color_override("font_color", Color("#B65C4B"))
	urgent_badge.add_theme_font_size_override("font_size", 16)
	urgent_badge.tooltip_text = "库存紧缺或今日需求达到流动量"
	content.add_child(urgent_badge)
	return row


func _item_icon_info(definition: Dictionary) -> Dictionary:
	var item_id := str(definition.get("id", ""))
	var icon_paths := {
		"wood": "res://assets/ui/material_icons/wood.svg",
		"stone": "res://assets/ui/material_icons/stone.svg",
		"glass": "res://assets/ui/material_icons/glass.svg",
		"iron_ore": "res://assets/ui/material_icons/iron.svg",
		"iron_ingot": "res://assets/ui/material_icons/iron.svg",
		"grain": "res://assets/crops/grain/painted/stage_3/variant_0_front.png",
		"grain_seed": "res://assets/crops/grain/painted/stage_0/variant_0_front.png",
	}
	var icon_path := str(icon_paths.get(item_id, ""))
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		return {"texture": load(icon_path) as Texture2D, "fallback": false}
	var placeholder := PlaceholderTexture2D.new()
	placeholder.size = Vector2(34.0, 34.0)
	return {"texture": placeholder, "fallback": true}


func _stock_color(state: Dictionary) -> Color:
	var ratio := _stock_ratio(state)
	if ratio < 0.35:
		return Color("#B65C4B")
	if ratio < 0.75:
		return Color("#C58B35")
	if ratio > 1.25:
		return Color("#7E9D70")
	return Color("#5F8755")


func _is_urgent(state: Dictionary) -> bool:
	var liquidity := maxi(1, int(state.get("daily_liquidity", 1)))
	var demand := int(state.get("demand", 0))
	var supply := int(state.get("supply", 0))
	return _stock_ratio(state) < 0.35 or (demand >= liquidity and demand > supply)


func _category_for(source_category: String) -> String:
	match source_category:
		"material", "container":
			return "raw_materials"
		"seed", "crop":
			return "crops"
		"processed_material":
			return "processed_materials"
		"output", "product", "crafted_good":
			return "food_handicrafts"
		"rare":
			return "rare_goods"
	return ""


func _trend_text(history: Array) -> String:
	if history.size() < 2 or int(history[-1]) == int(history[-2]):
		return "→ 持平"
	return "↑ 上涨" if int(history[-1]) > int(history[-2]) else "↓ 下跌"


func _trend_delta(state: Dictionary) -> int:
	var history: Array = state.get("history", [])
	return int(history[-1]) - int(history[-2]) if history.size() >= 2 else 0


func _history_dates(history_size: int) -> Array[String]:
	var result: Array[String] = []
	var settled_day := market_ref.last_settled_day if market_ref != null else 1
	var end_day := maxi(1, maxi(history_size, settled_day))
	var start_day := maxi(1, end_day - history_size + 1)
	for index in range(history_size):
		var total_day := start_day + index
		var day_zero := total_day - 1
		var season_names := ["春", "夏", "秋", "冬"]
		var season_index := floori(float(day_zero) / 7.0) % season_names.size()
		var season_name: String = season_names[season_index]
		result.append("%s %d" % [season_name, day_zero % 7 + 1])
	return result


func _history_reasons(
	history: Array,
	state: Dictionary,
	definition: Dictionary
) -> Array[String]:
	var result: Array[String] = []
	var demand := int(state.get("demand", 0))
	var supply := int(state.get("supply", 0))
	var stock := int(state.get("stock", 0))
	var target := maxi(1, int(state.get("target_stock", 1)))
	for index in range(history.size()):
		if index == 0:
			result.append("历史起点（%s）" % str(definition.get("volatility", "stable")))
			continue
		var delta := int(history[index]) - int(history[index - 1])
		if delta > 0:
			if demand > supply:
				result.append("需求高于供给")
			elif stock < target:
				result.append("库存偏紧")
			else:
				result.append("市场价格上涨")
		elif delta < 0:
			if supply > demand:
				result.append("供给高于需求")
			elif stock > target:
				result.append("库存充裕")
			else:
				result.append("市场价格下跌")
		elif demand > supply:
			result.append("需求增加但价格持平")
		elif supply > demand:
			result.append("供给增加但价格持平")
		else:
			result.append("供需稳定")
	return result


func _stock_ratio(state: Dictionary) -> float:
	return float(state.get("stock", 0)) / maxf(1.0, float(state.get("target_stock", 1)))


func _stock_status(state: Dictionary) -> String:
	var ratio := _stock_ratio(state)
	if ratio < 0.35:
		return "紧缺"
	if ratio < 0.75:
		return "偏少"
	if ratio > 1.25:
		return "充裕"
	return "正常"


func _show_empty_detail() -> void:
	item_name_label.text = "当前没有可交易商品"
	mid_price_label.text = "中间价：—"
	buy_price_label.text = "买入价：—"
	sell_price_label.text = "卖出价：—"
	stock_label.text = "库存：—"
	trend_label.text = "趋势：—"
	flow_label.text = "今日供给 —　今日需求 —　流动量 —"
	price_chart.set_history([])
	tags_label.text = "标签：—"
	trade_panel.set_item("")


func _on_sort_selected(index: int) -> void:
	if index >= 0 and index < SORT_IDS.size():
		set_sort_mode(SORT_IDS[index])


func _on_item_selected(index: int) -> void:
	if index >= 0 and index < _item_ids.size():
		select_item(_item_ids[index])


func _on_product_button_gui_input(event: InputEvent, source: Button, source_item_id: String) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode != KEY_UP and event.keycode != KEY_DOWN:
		return
	var current_index := _item_ids.find(source_item_id)
	if current_index < 0 or _item_ids.is_empty():
		return
	var direction := -1 if event.keycode == KEY_UP else 1
	var next_index := clampi(current_index + direction, 0, _item_ids.size() - 1)
	if next_index == current_index:
		source.accept_event()
		return
	var next_item_id := _item_ids[next_index]
	select_item(next_item_id)
	var next_button := _product_button_for(next_item_id)
	if next_button != null and next_button.is_visible_in_tree():
		next_button.grab_focus()
	source.accept_event()


func _product_button_for(target_item_id: String) -> Button:
	for item_row in item_rows.get_children():
		if str(item_row.get_meta("item_id", "")) == target_item_id:
			return item_row.get_node_or_null("Content/SelectButton") as Button
	return null


func _on_trade_snapshot_changed() -> void:
	var preserved_category := selected_category
	var preserved_item := selected_item_id
	var preserved_sort := sort_mode
	var preserved_scroll := item_scroll.scroll_vertical
	selected_category = preserved_category
	selected_item_id = preserved_item
	sort_mode = preserved_sort
	_rebuild_item_list()
	item_scroll.scroll_vertical = preserved_scroll
