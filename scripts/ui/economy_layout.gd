class_name EconomyLayout
extends RefCounted

const DRAWER_BREAKPOINT := 1120.0
const MINIMUM_SCALE := 0.8
const MAXIMUM_SCALE := 1.4
const DEFAULT_SCALE := 1.0
const MARKET_PANEL_MAX_SIZE := Vector2(1400.0, 760.0)
const BUILDING_PANEL_MAX_SIZE := Vector2(1400.0, 760.0)
const VIEWPORT_MARGIN := Vector2(20.0, 20.0)
const WINDOW_INSET := 24.0
const CARD_GAP := 16.0
const CONTROL_HEIGHT := 44.0
const LIST_ROW_HEIGHT := 52.0
const THEME_PATH := "res://assets/ui/economy/economy_theme.tres"
const RESPONSIVE_GROUP := &"economy_responsive_ui"

static var _ui_scale := DEFAULT_SCALE


static func mode_for_size(logical_size: Vector2) -> String:
	return "drawer" if logical_size.x < DRAWER_BREAKPOINT else "three_column"


static func clamp_scale(requested_scale: float) -> float:
	if not is_finite(requested_scale):
		return DEFAULT_SCALE
	return clampf(requested_scale, MINIMUM_SCALE, MAXIMUM_SCALE)


static func set_ui_scale(requested_scale: float, tree: SceneTree = null) -> float:
	_ui_scale = clamp_scale(requested_scale)
	var shared_theme := load(THEME_PATH) as Theme
	if shared_theme != null:
		shared_theme.default_base_scale = _ui_scale
	if tree != null:
		for node in tree.get_nodes_in_group(RESPONSIVE_GROUP):
			if node.has_method("apply_economy_ui_scale"):
				node.call("apply_economy_ui_scale", _ui_scale)
	return _ui_scale


static func get_ui_scale() -> float:
	return _ui_scale


static func logical_size_for(physical_size: Vector2, ui_scale: float) -> Vector2:
	return physical_size / clamp_scale(ui_scale)


static func panel_rect_for(viewport_size: Vector2, maximum_size: Vector2) -> Rect2:
	var available := Vector2(
		maxf(1.0, viewport_size.x - VIEWPORT_MARGIN.x * 2.0),
		maxf(1.0, viewport_size.y - VIEWPORT_MARGIN.y * 2.0)
	)
	var panel_size := Vector2(
		minf(maximum_size.x, available.x),
		minf(maximum_size.y, available.y)
	)
	return Rect2((viewport_size - panel_size) * 0.5, panel_size)
