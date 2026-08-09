class_name ServicePanel
extends VBoxContainer

const VALID_CATEGORIES := [
	"blueprints", "recipes", "repairs", "upgrades", "maintenance",
	"transport-storage", "land-expansion",
]

@onready var category_buttons := {
	"blueprints": $CategoryBar/Blueprints,
	"recipes": $CategoryBar/Recipes,
	"repairs": $CategoryBar/Repairs,
	"upgrades": $CategoryBar/Upgrades,
	"maintenance": $CategoryBar/Maintenance,
	"transport-storage": $CategoryBar/TransportStorage,
	"land-expansion": $CategoryBar/LandExpansion,
}
@onready var service_cards: VBoxContainer = $ServiceScroll/ServiceCards
@onready var empty_label: Label = $EmptyLabel
@onready var feedback_label: Label = $FeedbackLabel

var selected_category := "blueprints"
var _progression: EconomyProgressionSystem
var _tool_system: ToolSystem
var _production_system: ProductionSystem
var _services_by_id: Dictionary = {}
var selected_service_id := ""


func _ready() -> void:
	for category_id in category_buttons:
		var button: Button = category_buttons[category_id]
		if not button.pressed.is_connected(select_category.bind(category_id)):
			button.pressed.connect(select_category.bind(category_id))
	refresh_services()


func configure(
	progression: EconomyProgressionSystem,
	tool_system: ToolSystem,
	production: ProductionSystem
) -> bool:
	if progression == null or tool_system == null or production == null:
		return false
	_progression = progression
	_tool_system = tool_system
	_production_system = production
	var event_bus := get_node_or_null("/root/EventBus") if is_inside_tree() else null
	if event_bus != null and not event_bus.gold_changed.is_connected(_on_gold_changed):
		event_bus.gold_changed.connect(_on_gold_changed)
	for signal_name in [
		"production_maintenance_changed", "service_unlocked",
		"building_upgrade_changed", "tool_durability_changed", "building_removed",
		"item_added", "item_removed",
	]:
		var refresh := Callable(self, "_on_service_state_changed")
		if event_bus != null and event_bus.has_signal(signal_name) and not event_bus.is_connected(signal_name, refresh):
			event_bus.connect(signal_name, refresh)
	refresh_services()
	return true


func select_category(category_id: String) -> void:
	if category_id not in VALID_CATEGORIES:
		return
	selected_category = category_id
	selected_service_id = ""
	refresh_services()


func select_service(service_id: String) -> bool:
	if _progression == null or service_id.is_empty():
		return false
	var target: Dictionary = {}
	for service in _progression.get_available_services():
		if str(service.get("id", "")) == service_id:
			target = service
			break
	if target.is_empty():
		return false
	var category_id := str(target.get("category", ""))
	if category_id not in VALID_CATEGORIES:
		return false
	selected_category = category_id
	selected_service_id = service_id
	refresh_services()
	var card := _card_for_service(service_id)
	if card != null:
		card.modulate = Color(1.0, 0.92, 0.58, 1.0)
		var scroll := service_cards.get_parent() as ScrollContainer
		if scroll != null and scroll.is_ancestor_of(card):
			scroll.ensure_control_visible(card)
		var action := card.get_node_or_null("ActionButton") as Button
		if action != null and action.is_inside_tree():
			action.grab_focus()
	return card != null


func refresh_services() -> void:
	if not is_node_ready():
		return
	for child in service_cards.get_children():
		service_cards.remove_child(child)
		child.queue_free()
	_services_by_id.clear()
	for category_id in category_buttons:
		category_buttons[category_id].button_pressed = category_id == selected_category
	if _progression == null:
		empty_label.visible = true
		return
	for service in _progression.get_available_services():
		var service_id := str(service.get("id", ""))
		if service_id.is_empty():
			continue
		_services_by_id[service_id] = service
		if str(service.get("category", "")) == selected_category:
			service_cards.add_child(_build_card(service))
	empty_label.visible = service_cards.get_child_count() == 0


func request_service(service_id: String) -> void:
	if _progression == null:
		return
	# Commands may arrive from a control rendered before a save/load or another
	# authority mutation. Always replace the cached view before deciding.
	refresh_services()
	var service: Dictionary = _services_by_id.get(service_id, {})
	if service.is_empty():
		feedback_label.text = "服务不可用"
		return
	if bool(service.get("owned", false)) or not str(service.get("disabled_reason", "")).is_empty():
		feedback_label.text = str(service.get("disabled_reason", "服务不可用"))
		return
	var succeeded := false
	match str(service.get("kind", "")):
		"blueprint", "recipe":
			succeeded = _progression.purchase(service_id)
		"repair":
			succeeded = _progression.repair(str(service.get("target_id", "")))
		"upgrade":
			succeeded = _progression.upgrade(service.get("building"), str(service.get("target_id", "")))
		"maintenance":
			succeeded = _progression.maintain(service.get("building"))
	refresh_services()
	var refreshed: Dictionary = _services_by_id.get(service_id, {})
	var reason := str(refreshed.get("disabled_reason", ""))
	feedback_label.text = (
		("维修已开始" if str(service.get("kind", "")) == "maintenance" else "服务完成")
		if succeeded
		else (reason if not reason.is_empty() else "服务未完成，请检查条件与费用")
	)


func _build_card(service: Dictionary) -> VBoxContainer:
	var card := VBoxContainer.new()
	card.name = "ServiceCard"
	card.custom_minimum_size = Vector2(0.0, 190.0)
	card.add_theme_constant_override("separation", 4)
	card.set_meta("service_id", str(service.get("id", "")))
	card.set_meta("category", str(service.get("category", "")))
	if str(service.get("id", "")) == selected_service_id:
		card.modulate = Color(1.0, 0.92, 0.58, 1.0)
	_add_label(card, "TitleLabel", str(service.get("display_name", service.get("id", "服务"))), 22)
	_add_label(card, "GateLabel", "解锁条件：%s" % str(service.get("gate", "无")), 17)
	_add_label(card, "LevelOwnedLabel", "当前：%s" % str(service.get("current_state", "未拥有")), 17)
	_add_label(card, "CostLabel", _cost_text(service), 17)
	_add_label(card, "EffectLabel", "效果：%s" % str(service.get("effect", "")), 17)
	var reason := str(service.get("disabled_reason", ""))
	var reason_label := _add_label(card, "DisabledReasonLabel", reason, 17)
	reason_label.modulate = Color("#B65C4B")
	var action := Button.new()
	action.name = "ActionButton"
	action.text = "已拥有" if bool(service.get("owned", false)) else "执行服务"
	action.disabled = bool(service.get("owned", false)) or not reason.is_empty()
	action.tooltip_text = reason
	action.pressed.connect(request_service.bind(str(service.get("id", ""))))
	card.add_child(action)
	return card


func _card_for_service(service_id: String) -> Control:
	for card in service_cards.get_children():
		if str(card.get_meta("service_id", "")) == service_id:
			return card as Control
	return null


func _add_label(parent: Node, node_name: String, value: String, font_size: int) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _cost_text(service: Dictionary) -> String:
	var parts: Array[String] = ["金币 %d" % int(service.get("gold_cost", 0))]
	var materials: Dictionary = service.get("materials", {})
	var ids: Array[String] = []
	ids.assign(materials.keys())
	ids.sort()
	for item_id in ids:
		parts.append("%s ×%d" % [item_id, int(materials[item_id])])
	return "费用：%s" % "，".join(parts)


func _on_gold_changed(_gold: int) -> void:
	refresh_services()


func _on_service_state_changed(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
	refresh_services()
