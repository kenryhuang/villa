class_name ActionPaletteButton
extends Button

@onready var icon_rect: TextureRect = $Icon
@onready var shortcut_label: Label = $ShortcutLabel
@onready var name_label: Label = $NameLabel


func configure(shortcut: int, display_name: String, texture: Texture2D) -> void:
	shortcut_label.text = str(shortcut)
	name_label.text = display_name
	icon_rect.texture = texture


func set_selected(selected: bool) -> void:
	set_pressed_no_signal(selected)


func set_available(available: bool) -> void:
	icon_rect.modulate = (
		Color.WHITE if available else Color(0.48, 0.48, 0.48, 0.82)
	)
	name_label.modulate = Color.WHITE
	shortcut_label.modulate = Color.WHITE


func set_shortcut_visible(visible: bool) -> void:
	shortcut_label.visible = visible
