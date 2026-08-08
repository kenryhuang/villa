# Compact Economy UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the oversized software-like market and production modals with compact centered game panels, equal-size connected tabs, a central seven-day price curve, and responsive layouts that remain above and clear of the HUD.

**Architecture:** Keep every market and production system API unchanged. Extend `EconomyLayout` as the single source of panel geometry, add shared flat theme variations for the shell and tabs, then reorganize the authored Godot scenes while updating their scripts to the new node paths. A dedicated overlay `CanvasLayer` keeps economy modals above the HUD; content panels remain ordinary `Control` nodes so existing class APIs and tests continue to work.

**Tech Stack:** Godot 4.x, GDScript, authored `.tscn` scenes, `Theme`/`StyleBoxFlat`, existing custom test runners, deterministic PNG capture.

---

## File map

- `scripts/ui/economy_layout.gd`: responsive modes, compact panel limits, HUD-aware centered rectangles.
- `assets/ui/economy/economy_theme.tres`: flat paper shell, connected Tab states, compact cards, buttons, focus ring.
- `scenes/ui/shop_ui.tscn`: market shell, overlay layer, equal-size market/order/contract/service Tabs.
- `scripts/ui/shop_ui.gd`: shell resizing, overlay visibility, tab styling and preserved modal behavior.
- `scenes/ui/economy/market_panel.tscn`: compact goods/chart/trade layout.
- `scripts/ui/market_panel.gd`: paths and responsive visibility for the redesigned market panel.
- `scripts/ui/market_price_chart.gd`: smooth seven-day curve, area fill and original-point hover mapping.
- `scenes/ui/economy/trade_panel.tscn`: compact transaction controls and in-panel confirmation.
- `scenes/ui/economy/building_economy_ui.tscn`: compact building shell and overlay layer.
- `scripts/ui/building_economy_ui.gd`: building shell resizing and preserved open/close behavior.
- `scenes/ui/economy/building_production_panel.tscn`: recipe / process preview / queue-storage layout.
- `scripts/ui/building_production_panel.gd`: paths and render helpers for the new layout.
- `tests/test_economy_ui_responsive.gd`: geometry, Tab, layering, overflow and keyboard contracts.
- `tests/test_market_price_chart.gd`: smooth path and hover data contracts.
- `tests/test_building_economy_ui.gd`: production behavior on the new node structure.
- `tests/capture_economy_ui.gd`: deterministic visual states and compact-resolution screenshots.

### Task 1: Lock compact geometry and flat theme contracts

**Files:**
- Modify: `tests/test_economy_ui_responsive.gd`
- Modify: `scripts/ui/economy_layout.gd`
- Modify: `assets/ui/economy/economy_theme.tres`

- [ ] **Step 1: Write failing layout and theme assertions**

Add assertions to `test_economy_ui_responsive.gd` for the two panel limits, centering, bounds clamping, and shared theme variants:

```gdscript
func _test_compact_economy_geometry(assertions: TestAssert) -> void:
	var market_rect := EconomyLayout.panel_rect_for(
		Vector2(1920.0, 1080.0),
		EconomyLayout.MARKET_PANEL_MAX_SIZE
	)
	assertions.truthy(market_rect.size.x <= 1080.0, "market width is capped")
	assertions.truthy(market_rect.size.y <= 600.0, "market height is capped")
	assertions.equal(market_rect.get_center(), Vector2(960.0, 540.0), "market stays centered")
	var compact_rect := EconomyLayout.panel_rect_for(
		Vector2(1280.0, 720.0),
		EconomyLayout.MARKET_PANEL_MAX_SIZE
	)
	assertions.truthy(compact_rect.position.x >= 20.0, "compact market keeps left margin")
	assertions.truthy(compact_rect.position.y >= 20.0, "compact market keeps top margin")
	assertions.truthy(compact_rect.end.x <= 1260.0, "compact market keeps right margin")
	assertions.truthy(compact_rect.end.y <= 700.0, "compact market keeps bottom margin")

func _test_compact_theme(assertions: TestAssert) -> void:
	var theme := load(EconomyLayout.THEME_PATH) as Theme
	for variation in [&"EconomyShell", &"EconomyTab", &"EconomyTabSelected", &"EconomyCompactCard"]:
		assertions.truthy(theme.get_type_variation_base(variation) != &"", "%s exists" % variation)
	var shell := theme.get_stylebox(&"panel", &"EconomyShell") as StyleBoxFlat
	assertions.equal(shell.border_width_left, 1, "shell uses one-pixel border")
	assertions.equal(shell.shadow_size, 8, "shell uses soft compact shadow")
```

Call both helpers from the existing `run()` method.

- [ ] **Step 2: Run the responsive suite and verify failure**

Run:

```powershell
godot_console --headless --path . --script res://tests/run_economy_system_tests.gd
```

Expected: FAIL because `MARKET_PANEL_MAX_SIZE`, `panel_rect_for`, and the new theme variations do not exist.

- [ ] **Step 3: Add the geometry API**

Add to `economy_layout.gd`:

```gdscript
const MARKET_PANEL_MAX_SIZE := Vector2(1080.0, 600.0)
const BUILDING_PANEL_MAX_SIZE := Vector2(980.0, 560.0)
const VIEWPORT_MARGIN := Vector2(20.0, 20.0)

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
```

The overlay layer solves the “HUD draws above the menu” defect. The capped centered rectangle prevents the modal itself from expanding over the full HUD; exact visible HUD intersection checks are added after the authored scene is available.

- [ ] **Step 4: Add flat shared style variations**

In `economy_theme.tres`, define `StyleBoxFlat` resources with these exact values and expose them as variations:

```text
EconomyShell: paper #F4E3BA, 1 px #49362A at 28% alpha, radius 12, shadow #49362A at 16% alpha, shadow_size 8, shadow_offset (0,4)
EconomyCompactCard: #FFF2D5 at 88% alpha, 1 px #49362A at 24% alpha, radius 8
EconomyTab: #D7BC82, 1 px #49362A at 28% alpha, top radii 8, bottom radii 0
EconomyTabSelected: #F4E3BA, left/top/right border 1 px, bottom border 0, top radii 8, bottom radii 0
```

Use `EconomyTab` and `EconomyTabSelected` as `Button`-based theme variations, keep 20 px button text, and keep the existing 2 px green focus style.

- [ ] **Step 5: Re-run and commit**

Run the economy system suite; expected: PASS.

```powershell
git add scripts/ui/economy_layout.gd assets/ui/economy/economy_theme.tres tests/test_economy_ui_responsive.gd
git commit -m "feat: add compact economy UI layout tokens"
```

### Task 2: Build compact layered shells and connected equal-size Tabs

**Files:**
- Modify: `tests/test_economy_ui_responsive.gd`
- Modify: `scenes/ui/shop_ui.tscn`
- Modify: `scripts/ui/shop_ui.gd`
- Modify: `scenes/ui/economy/building_economy_ui.tscn`
- Modify: `scripts/ui/building_economy_ui.gd`

- [ ] **Step 1: Write failing shell assertions**

Add a helper that instantiates both shells and verifies overlay layer, maximum size, equal Tab size, selected style, and stable positions:

```gdscript
func _test_compact_shells(assertions: TestAssert, tree: SceneTree) -> void:
	var shop := (load("res://scenes/ui/shop_ui.tscn") as PackedScene).instantiate() as ShopUI
	tree.root.add_child(shop)
	var shop_layer := shop.get_node("ScreenLayer") as CanvasLayer
	assertions.truthy(shop_layer.layer > 1, "shop renders above HUD CanvasLayer")
	var market_tab := shop.get_node("ScreenLayer/ModalLayer/HubPanel/Margin/Shell/Tabs/MarketTab") as Button
	var orders_tab := shop.get_node("ScreenLayer/ModalLayer/HubPanel/Margin/Shell/Tabs/OrdersTab") as Button
	assertions.equal(market_tab.custom_minimum_size, Vector2(104.0, 42.0), "market tab has fixed size")
	assertions.equal(orders_tab.custom_minimum_size, market_tab.custom_minimum_size, "tabs have equal size")
	shop.free()
	var building := (load("res://scenes/ui/economy/building_economy_ui.tscn") as PackedScene).instantiate() as BuildingEconomyUI
	tree.root.add_child(building)
	assertions.truthy((building.get_node("ScreenLayer") as CanvasLayer).layer > 1, "building modal renders above HUD")
	building.free()
```

Update existing node paths in this test from `ModalLayer/...` to `ScreenLayer/ModalLayer/...`.

- [ ] **Step 2: Run and verify failure**

Run the economy system suite. Expected: FAIL because `ScreenLayer` does not exist and Tabs still use different oversized button geometry.

- [ ] **Step 3: Author the market shell**

In `shop_ui.tscn`:

- Keep `ShopUI` as the scripted `Control` root.
- Insert `CanvasLayer` named `ScreenLayer` with `layer = 20`.
- Move `ModalLayer` under `ScreenLayer`.
- Center `HubPanel` using script-assigned offsets; set `theme_type_variation = &"EconomyShell"`.
- Reduce header title to 26 px, status text to 18 px, and close control to a 42×42 `×` button.
- Give every Tab `custom_minimum_size = Vector2(104, 42)`, `toggle_mode = true`, and `theme_type_variation = &"EconomyTab"`.
- Reduce the modal shade to `Color(0.129, 0.102, 0.086, 0.28)`.

Update every authored path in `shop_ui.gd` with the `ScreenLayer/` prefix. Add:

```gdscript
func _apply_compact_rect() -> void:
	if not is_node_ready():
		return
	var rect := EconomyLayoutScript.panel_rect_for(
		get_viewport_rect().size,
		EconomyLayoutScript.MARKET_PANEL_MAX_SIZE
	)
	var panel := $ScreenLayer/ModalLayer/HubPanel as Control
	panel.position = rect.position
	panel.size = rect.size

func _apply_tab_styles() -> void:
	for tab_id in tab_buttons:
		var button := tab_buttons[tab_id] as Button
		button.theme_type_variation = (
			&"EconomyTabSelected" if tab_id == selected_tab else &"EconomyTab"
		)
```

Call `_apply_compact_rect()` on ready/open/viewport resize. Call `_apply_tab_styles()` after every successful `select_tab()`.

- [ ] **Step 4: Author the building shell**

Apply the same `ScreenLayer` structure in `building_economy_ui.tscn`, use `EconomyLayout.BUILDING_PANEL_MAX_SIZE`, and add equal 104×42 production/status Tabs above `PageHost`. Update `building_economy_ui.gd` paths, visibility handling and resizing without changing `open_for`, `close`, or panel routing APIs.

The root `Control.visible` contract remains authoritative. `open()`/`open_for()` sets both the root and `ScreenLayer` visible; `close()` hides both so a `CanvasLayer` child cannot remain visible after its parent `Control` closes.

- [ ] **Step 5: Re-run and commit**

Run:

```powershell
godot_console --headless --path . --script res://tests/run_economy_system_tests.gd
godot_console --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: both PASS.

```powershell
git add scenes/ui/shop_ui.tscn scripts/ui/shop_ui.gd scenes/ui/economy/building_economy_ui.tscn scripts/ui/building_economy_ui.gd tests/test_economy_ui_responsive.gd
git commit -m "feat: add compact layered economy shells"
```

### Task 3: Draw the seven-day market history as a smooth central curve

**Files:**
- Modify: `tests/test_market_price_chart.gd`
- Modify: `scripts/ui/market_price_chart.gd`

- [ ] **Step 1: Write failing smooth-path tests**

Add:

```gdscript
var anchors := PackedVector2Array([
	Vector2(0.0, 1.0), Vector2(0.5, 0.25), Vector2(1.0, 0.0)
])
var smooth: PackedVector2Array = chart_script.call("smooth_points", anchors)
assertions.truthy(smooth.size() > anchors.size(), "curve tessellation adds intermediate points")
assertions.equal(smooth[0], anchors[0], "smooth curve preserves first observation")
assertions.equal(smooth[-1], anchors[-1], "smooth curve preserves latest observation")
assertions.equal(
	chart_script.call("smooth_points", PackedVector2Array([Vector2(0.5, 0.5)])),
	PackedVector2Array([Vector2(0.5, 0.5)]),
	"single observation stays a point"
)
```

- [ ] **Step 2: Run and verify failure**

Run:

```powershell
godot_console --headless --path . --script res://tests/test_runtime_ui_scenes.gd
```

Expected: FAIL because `smooth_points` does not exist.

- [ ] **Step 3: Implement deterministic smoothing and area fill**

Add a static curve helper that preserves original endpoints:

```gdscript
static func smooth_points(anchors: PackedVector2Array) -> PackedVector2Array:
	if anchors.size() <= 1:
		return anchors
	var curve := Curve2D.new()
	for index in range(anchors.size()):
		var point := anchors[index]
		var previous := anchors[maxi(0, index - 1)]
		var following := anchors[mini(anchors.size() - 1, index + 1)]
		var tangent := (following - previous) * 0.18
		curve.add_point(point, -tangent, tangent)
	var baked := curve.tessellate(5, 2.0)
	if not baked.is_empty():
		baked[0] = anchors[0]
		baked[-1] = anchors[-1]
	return baked
```

In `_draw()`, keep `_hover_points` built only from the original normalized observations. Draw a 12%-alpha green polygon under `smooth_points(_hover_points)`, draw the smooth line at 2 px, draw the latest original node gold, and draw other nodes only on hover. Preserve the current tooltip text and hit radius.

- [ ] **Step 4: Re-run and commit**

Run the runtime UI suite; expected: PASS.

```powershell
git add scripts/ui/market_price_chart.gd tests/test_market_price_chart.gd
git commit -m "feat: render smooth market price curves"
```

### Task 4: Rebuild the market content as goods, curve and transaction columns

**Files:**
- Modify: `tests/test_economy_ui_responsive.gd`
- Modify: `tests/test_market_ui.gd`
- Modify: `scenes/ui/economy/market_panel.tscn`
- Modify: `scenes/ui/economy/trade_panel.tscn`
- Modify: `scripts/ui/market_panel.gd`
- Modify: `scripts/ui/trade_panel.gd`

- [ ] **Step 1: Write failing authored-layout assertions**

Verify the market column ratios, chart minimum size, compact category row and compact trade controls:

```gdscript
var market := (load("res://scenes/ui/economy/market_panel.tscn") as PackedScene).instantiate()
var catalog := market.get_node("Columns/CatalogColumn") as Control
var detail := market.get_node("Columns/DetailColumn") as Control
var trade := market.get_node("Columns/TradePanel") as Control
assertions.equal(catalog.size_flags_stretch_ratio, 0.24, "goods column uses compact ratio")
assertions.equal(detail.size_flags_stretch_ratio, 0.49, "curve owns the center")
assertions.equal(trade.size_flags_stretch_ratio, 0.27, "trade column stays compact")
assertions.truthy((market.get_node("Columns/DetailColumn/PriceChart") as Control).custom_minimum_size.y >= 190.0, "central curve is prominent")
assertions.truthy(market.has_node("Columns/CatalogColumn/CategoryTabs"), "categories use compact segmented controls")
market.free()
```

- [ ] **Step 2: Run and verify failure**

Run the economy system suite. Expected: FAIL on old ratios, old category list and chart height.

- [ ] **Step 3: Author the compact market panel**

In `market_panel.tscn`:

- Set column stretch ratios to 0.24 / 0.49 / 0.27 with 10 px separation.
- Replace the vertical `CategoryList` with `CategoryTabs`, an `HBoxContainer` holding the same five buttons at 18 px text.
- Keep `ItemScroll/ItemRows` and dynamic button generation.
- Move price summary into one compact header row, keep `PriceChart` as the central flexible control with a 190 px minimum height in wide mode.
- Move supply, demand and stock into one footer row.
- Remove the source/use/processing paragraphs from the default view; expose the information through the existing item-row tooltip instead.
- Use `EconomyCompactCard` on all three columns.

Update `market_panel.gd` node paths for `CategoryTabs` and the compact header/footer labels. In drawer mode, show catalog first; selecting a product shows detail plus trade in one vertical `ScrollContainer`. Keep chart visible when the drawer has at least 420 px available height and hide it below that threshold.

- [ ] **Step 4: Compact the trade panel**

In `trade_panel.tscn`, keep the same node names used by `trade_panel.gd` but reduce redundant labels into two rows: holdings/market stock and buy/sell prices. Keep `QuantitySpin`, Max, Buy, Sell, disabled reason, feedback, and confirmation node names unchanged. Limit the confirmation content to the trade column and apply `EconomyCompactCard`.

- [ ] **Step 5: Re-run and commit**

Run economy system and runtime UI tests; expected: PASS.

```powershell
git add scenes/ui/economy/market_panel.tscn scenes/ui/economy/trade_panel.tscn scripts/ui/market_panel.gd scripts/ui/trade_panel.gd tests/test_economy_ui_responsive.gd tests/test_market_ui.gd
git commit -m "feat: redesign compact market controls"
```

### Task 5: Rebuild production as recipe, process and queue/storage sections

**Files:**
- Modify: `tests/test_building_economy_ui.gd`
- Modify: `tests/test_economy_ui_responsive.gd`
- Modify: `scenes/ui/economy/building_production_panel.tscn`
- Modify: `scripts/ui/building_production_panel.gd`

- [ ] **Step 1: Write failing production-layout assertions**

Add authored-node checks while retaining the existing lifecycle assertions:

```gdscript
var panel := (load("res://scenes/ui/economy/building_production_panel.tscn") as PackedScene).instantiate()
assertions.truthy(panel.has_node("Sections/RecipeColumn/RecipeList"), "production has recipe column")
assertions.truthy(panel.has_node("Sections/ProcessColumn/Flow/InputItems"), "production shows input flow")
assertions.truthy(panel.has_node("Sections/ProcessColumn/Flow/OutputItems"), "production shows output flow")
assertions.truthy(panel.has_node("Sections/RightColumn/QueueCard/QueueSlots"), "production shows queue card")
assertions.truthy(panel.has_node("Sections/RightColumn/StorageCard/StorageList"), "production shows storage card")
panel.free()
```

- [ ] **Step 2: Run and verify failure**

Run:

```powershell
godot_console --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: FAIL because the new `Sections` structure does not exist.

- [ ] **Step 3: Author the three-section production scene**

Replace `ThreeColumns` and bottom `RecipeDetails` with `Sections`:

```text
Sections (HBoxContainer)
  RecipeColumn (EconomyCompactCard, ratio 0.25)
    TitleLabel
    RecipeScroll/RecipeList
  ProcessColumn (EconomyCompactCard, ratio 0.45)
    RecipeNameLabel
    Flow (HBoxContainer)
      InputItems
      ProcessIcon
      OutputItems
    DurationLabel
    PricingLabel
    MissingLabel
    BatchControls/BatchSpinBox, MaxButton, StartButton
  RightColumn (VBoxContainer, ratio 0.30)
    QueueCard/QueueSlots
    StorageCard/StorageList, EmptyLabel, CapacityLabel, CollectAllButton
FeedbackLabel
```

All three sections use 10 px spacing and 18 px body text. The start and collect buttons keep 20 px text and no more than 44 px height.

- [ ] **Step 4: Update rendering paths without changing behavior**

Update `@onready` paths in `building_production_panel.gd`. Add two containers:

```gdscript
@onready var input_items: HBoxContainer = $Sections/ProcessColumn/Flow/InputItems
@onready var output_items: HBoxContainer = $Sections/ProcessColumn/Flow/OutputItems
```

Add `_render_item_flow(container, counts)` that clears the target and creates one compact label per nonzero item:

```gdscript
func _render_item_flow(container: HBoxContainer, counts: Dictionary) -> void:
	_clear_container(container)
	for item_id in counts:
		var amount := int(counts[item_id])
		if amount <= 0:
			continue
		var label := Label.new()
		label.text = "%s ×%d" % [_item_name(str(item_id)), amount]
		label.theme_type_variation = &"EconomySecondary"
		container.add_child(label)
```

Call it from `_build_recipe_detail()` with multiplied inputs and outputs. Preserve `request_start`, `request_collect_item`, `request_collect_all`, queue slot metadata, failure codes and EventBus refreshes.

- [ ] **Step 5: Re-run and commit**

Run main gameplay integration and economy system suites; expected: PASS.

```powershell
git add scenes/ui/economy/building_production_panel.tscn scripts/ui/building_production_panel.gd tests/test_building_economy_ui.gd tests/test_economy_ui_responsive.gd
git commit -m "feat: redesign compact production controls"
```

### Task 6: Add transitions, responsive verification and deterministic captures

**Files:**
- Modify: `scripts/ui/shop_ui.gd`
- Modify: `scripts/ui/building_economy_ui.gd`
- Modify: `tests/test_economy_ui_responsive.gd`
- Modify: `tests/capture_economy_ui.gd`

- [ ] **Step 1: Add failing state-preservation and bounds assertions**

For 1920×1080, 1600×900 and 1280×720, instantiate each real shell, resize the root, select a non-default Tab/item/recipe, and assert:

```gdscript
assertions.truthy(panel_rect.encloses(content_rect), "all authored content stays inside compact shell")
assertions.equal(shop.selected_tab, expected_tab, "resize preserves selected tab")
assertions.equal(market.selected_item_id, expected_item, "resize preserves selected product")
assertions.equal(market_tab.position.y, orders_tab.position.y, "tab titles share one baseline")
assertions.equal(market_tab.size, orders_tab.size, "tab titles remain equal after resize")
```

Also assert that `ScreenLayer.layer` is greater than the authored HUD layer.

- [ ] **Step 2: Run and verify any failures**

Run economy system and main gameplay suites. Expected: new bounds or animation-state assertions fail before the final responsive fixes.

- [ ] **Step 3: Add short interruptible transitions**

In both shell scripts, centralize animation constants and kill an existing tween before starting another:

```gdscript
const OPEN_DURATION := 0.14
const CLOSE_DURATION := 0.10
const CONTENT_FADE_DURATION := 0.10
var _panel_tween: Tween

func _animate_open(panel: Control) -> void:
	if _panel_tween != null:
		_panel_tween.kill()
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(0.98, 0.98)
	panel.modulate.a = 0.0
	_panel_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_panel_tween.set_parallel(true)
	_panel_tween.tween_property(panel, "scale", Vector2.ONE, OPEN_DURATION)
	_panel_tween.tween_property(panel, "modulate:a", 1.0, OPEN_DURATION)
```

Use a 100 ms alpha crossfade on `PageHost` after Tab selection. Programmatic state changes and interrupted tweens must set the final selected page visible and interactive.

- [ ] **Step 4: Extend deterministic captures**

Update `capture_economy_ui.gd` to save:

```gdscript
const REQUIRED_CAPTURES := [
	"market_normal",
	"market_trade_confirmation",
	"market_compact_1280x720",
	"building_production_running",
	"building_output_ready",
]
```

For each state, wait two process frames after layout and one frame after disabling animations, then write to `.godot/economy-ui-verification/`. Captures must use real scene instances and deterministic fixture data.

- [ ] **Step 5: Run visual capture and inspect PNGs**

Run:

```powershell
godot --path . --display-driver windows --rendering-method gl_compatibility --script res://tests/capture_economy_ui.gd
```

Expected: five required PNGs are created. Inspect them for thin borders, connected selected Tabs, readable Chinese text, prominent central curve, compact production flow and no HUD-over-menu layering.

- [ ] **Step 6: Re-run and commit**

Run economy system and main gameplay suites; expected: PASS.

```powershell
git add scripts/ui/shop_ui.gd scripts/ui/building_economy_ui.gd tests/test_economy_ui_responsive.gd tests/capture_economy_ui.gd
git commit -m "test: verify compact economy UI states"
```

### Task 7: Full regression and final cleanup

**Files:**
- Modify only files required by failures discovered in this task.

- [ ] **Step 1: Run parser/import verification**

```powershell
godot_console --headless --editor --path . --quit-after 2
```

Expected: exit code 0 with no GDScript parse errors or missing scene nodes.

- [ ] **Step 2: Run focused and integration suites**

```powershell
godot_console --headless --path . --script res://tests/test_runtime_ui_scenes.gd
godot_console --headless --path . --script res://tests/run_economy_system_tests.gd
godot_console --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: all three commands exit 0 and print PASS summaries.

- [ ] **Step 3: Run broader gameplay regressions**

```powershell
godot_console --headless --path . --script res://tests/run_building_system_tests.gd
godot_console --headless --path . --script res://tests/run_production_chain_tests.gd
godot_console --headless --path . --script res://tests/run_tests.gd
```

Expected: all commands exit 0.

- [ ] **Step 4: Audit scope and generated artifacts**

```powershell
git status --short
git diff --check
git log --oneline -8
```

Expected: only intentional source, scene, theme, tests and plan changes are present; `.godot` screenshots and imported artifacts are not staged.

- [ ] **Step 5: Commit any final verified corrections**

If Step 1–4 required source corrections, stage only those exact files and commit:

```powershell
git commit -m "fix: finish compact economy UI polish"
```

If no correction is required, do not create an empty commit.
