class_name ActionPaletteButton
extends Button

@onready var icon_rect: TextureRect = $Icon
@onready var shortcut_label: Label = $ShortcutLabel
@onready var name_label: Label = $NameLabel
var build_state := "ready"


func configure(shortcut: int, display_name: String, texture: Texture2D) -> void:
	shortcut_label.text = str(shortcut)
	name_label.text = display_name
	icon_rect.texture = texture


func set_selected(selected: bool) -> void:
	set_pressed_no_signal(selected)


func set_available(available: bool) -> void:
	set_build_state("ready" if available else "invalid")


func set_build_state(state: String) -> void:
	build_state = state if state in ["ready", "missing_resources", "locked", "invalid"] else "invalid"
	disabled = build_state == "invalid"
	match build_state:
		"ready":
			icon_rect.modulate = Color.WHITE
			self_modulate = Color(0.86, 1.0, 0.88, 1.0)
		"missing_resources":
			icon_rect.modulate = Color(1.0, 0.66, 0.60, 0.94)
			self_modulate = Color(1.0, 0.78, 0.72, 1.0)
		"locked":
			icon_rect.modulate = Color(0.48, 0.48, 0.48, 0.82)
			self_modulate = Color(0.68, 0.68, 0.68, 1.0)
		_:
			icon_rect.modulate = Color(0.42, 0.20, 0.20, 0.82)
			self_modulate = Color(0.68, 0.32, 0.32, 1.0)
	name_label.modulate = Color.WHITE
	shortcut_label.modulate = Color.WHITE


func set_shortcut_visible(visible: bool) -> void:
	shortcut_label.visible = visible
