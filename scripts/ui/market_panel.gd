class_name MarketPanel
extends PanelContainer

const GameDataScript = preload("res://scripts/core/game_data.gd")
const MarketPriceChartScript = preload("res://scripts/ui/market_price_chart.gd")
const TradePanelScript = preload("res://scripts/ui/trade_panel.gd")

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
	"raw_materials": $Columns/CatalogColumn/CategoryList/RawMaterials,
	"crops": $Columns/CatalogColumn/CategoryList/Crops,
	"processed_materials": $Columns/CatalogColumn/CategoryList/ProcessedMaterials,
	"food_handicrafts": $Columns/CatalogColumn/CategoryList/FoodHandicrafts,
	"rare_goods": $Columns/CatalogColumn/CategoryList/RareGoods,
}
@onready var sort_option: OptionButton = $Columns/CatalogColumn/SortMode
@onready var item_list: ItemList = $Columns/CatalogColumn/ItemList
@onready var empty_label: Label = $Columns/CatalogColumn/EmptyLabel
@onready var item_name_label: Label = $Columns/DetailColumn/ItemNameLabel
@onready var mid_price_label: Label = $Columns/DetailColumn/MidPriceLabel
@onready var buy_price_label: Label = $Columns/DetailColumn/BuyPriceLabel
@onready var sell_price_label: Label = $Columns/DetailColumn/SellPriceLabel
@onready var stock_label: Label = $Columns/DetailColumn/StockLabel
@onready var trend_label: Label = $Columns/DetailColumn/TrendLabel
@onready var flow_label: Label = $Columns/DetailColumn/FlowLabel
@onready var price_chart = $Columns/DetailColumn/PriceChart
@onready var tags_label: Label = $Columns/DetailColumn/TagsLabel
@onready var source_use_label: Label = $Columns/DetailColumn/SourceUseLabel
@onready var processing_label: Label = $Columns/DetailColumn/ProcessingLabel
@onready var trade_panel = $Columns/TradePanel

var inventory_ref: InventorySystem
var economy_ref: EconomySystem
var market_ref: MarketSystem
var selected_category := "raw_materials"
var selected_item_id := ""
var sort_mode := "recommended"
var _item_ids: Array[String] = []


func _ready() -> void:
	for category_id in category_buttons:
		category_buttons[category_id].pressed.connect(select_category.bind(category_id))
	sort_option.clear()
	for index in range(SORT_IDS.size()):
		sort_option.add_item(SORT_LABELS[index], index)
	sort_option.item_selected.connect(_on_sort_selected)
	item_list.item_selected.connect(_on_item_selected)


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
	if not trade_panel.is_connected("snapshot_changed", refresh_snapshot):
		trade_panel.connect("snapshot_changed", refresh_snapshot)
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
	price_chart.set_history(history)
	tags_label.text = "标签：%s　季节 —　事件 —　NPC需求 %s" % [
		str(definition.get("volatility", "stable")),
		"活跃" if int(state.get("demand", 0)) > 0 else "平稳",
	]
	source_use_label.text = "主要来源：农庄生产／采集　主要用途：建造／加工／交易"
	processing_label.text = "加工参考：按当前行情估算，不承诺最终利润"
	trade_panel.set_item(selected_item_id)


func handle_top_escape() -> bool:
	return trade_panel.handle_top_escape()


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
		_item_ids.append(candidate_id)
	empty_label.visible = _item_ids.is_empty()
	item_list.visible = not _item_ids.is_empty()
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
