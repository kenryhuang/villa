class_name SeedCard
extends PanelContainer

signal seed_selected(plant_item_id: String)

@onready var icon_rect: TextureRect = $Content/Icon
@onready var name_label: Label = $Content/Details/NameRow/Name
@onready var quantity_label: Label = $Content/Details/NameRow/Quantity
@onready var metadata_label: Label = $Content/Details/Metadata
@onready var status_label: Label = $Content/Details/Status
@onready var select_button: Button = $Content/SelectButton

var plant_item_id := ""
var disabled := false
var _selected := false


func _ready() -> void:
	if not gui_input.is_connected(_on_card_gui_input):
		gui_input.connect(_on_card_gui_input)
	if not select_button.pressed.is_connected(_request_selection):
		select_button.pressed.connect(_request_selection)
	_update_style()


func configure(data: Dictionary) -> void:
	plant_item_id = str(data.get("plant_item_id", ""))
	disabled = bool(data.get("disabled", false))
	set_meta("plant_item_id", plant_item_id)
	set_meta("disabled_reason", str(data.get("disabled_reason", "")))
	name_label.text = str(data.get("display_name", plant_item_id))
	quantity_label.text = "×%d" % int(data.get("quantity", 0))
	metadata_label.text = "%s　·　%s　·　%s" % [
		str(data.get("growth_text", "")),
		str(data.get("season_text", "")),
		str(data.get("environment_text", "")),
	]
	status_label.text = str(data.get("status_text", ""))
	status_label.add_theme_color_override(
		"font_color",
		Color("e58b7c") if disabled else Color("7bd09a")
	)
	icon_rect.texture = data.get("icon") as Texture2D
	select_button.disabled = disabled
	select_button.text = "不可用" if disabled else "选择"
	select_button.tooltip_text = status_label.text
	mouse_default_cursor_shape = Control.CURSOR_ARROW if disabled else Control.CURSOR_POINTING_HAND
	_update_style()


func set_selected(value: bool) -> void:
	_selected = value
	_update_style()


func _on_card_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_request_selection()


func _request_selection() -> void:
	if disabled or plant_item_id.is_empty():
		return
	seed_selected.emit(plant_item_id)


func _update_style() -> void:
	var style := StyleBoxFlat.new()
	style.content_margin_left = 14.0
	style.content_margin_top = 12.0
	style.content_margin_right = 14.0
	style.content_margin_bottom = 12.0
	style.bg_color = Color(0.075, 0.105, 0.082, 0.94 if not disabled else 0.78)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color("d5ad58") if _selected else Color(0.49, 0.42, 0.24, 0.9)
	if disabled:
		style.border_color = Color(0.47, 0.31, 0.27, 0.86)
	style.corner_radius_top_left = 9
	style.corner_radius_top_right = 9
	style.corner_radius_bottom_left = 9
	style.corner_radius_bottom_right = 9
	add_theme_stylebox_override("panel", style)
