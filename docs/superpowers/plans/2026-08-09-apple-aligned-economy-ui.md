# Apple-Aligned Economy UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild market and production panels as a larger 1400×760 iPadOS-inspired card console with aligned widgets, stable hierarchy, and preserved economy behavior.

**Architecture:** Keep all economy system APIs and transaction flows intact. Centralize geometry and design tokens in `EconomyLayout` and the shared theme, then restructure authored scenes around a shared three-column grid. Dynamic product, recipe, queue, and output rows receive explicit height, clipping, and alignment constraints so runtime content cannot resize the shell.

**Tech Stack:** Godot 4.x, GDScript, authored `.tscn` scenes, `Theme`/`StyleBoxFlat`, custom headless test runners, deterministic OpenGL screenshots.

---

## File map

- `scripts/ui/economy_layout.gd`: 1400×760 geometry, grid constants, responsive breakpoint.
- `assets/ui/economy/economy_theme.tres`: warm neutral window, white cards, aligned controls, thin borders.
- `scenes/ui/shop_ui.tscn`: larger shared shell, aligned title/Tabs/status header.
- `scenes/ui/economy/building_economy_ui.tscn`: production shell matching the market dimensions.
- `scenes/ui/economy/market_panel.tscn`: fixed goods / flexible curve / fixed trade card grid.
- `scripts/ui/market_panel.gd`: runtime product-row geometry and responsive state.
- `scenes/ui/economy/trade_panel.tscn`: aligned two-column transaction form.
- `scenes/ui/economy/building_production_panel.tscn`: recipe / process / activity card grid.
- `scripts/ui/building_production_panel.gd`: aligned runtime recipe, queue, and output rows.
- `scripts/ui/market_price_chart.gd`: empty-history presentation and adjusted chart insets.
- `tests/test_economy_ui_responsive.gd`: geometry, tokens, alignment, overflow, resize contracts.
- `tests/test_market_ui.gd`: dynamic product row contract.
- `tests/test_building_economy_ui.gd`: production row and behavior contract.
- `tests/test_market_price_chart.gd`: chart empty-state helper contract.
- `tests/capture_economy_ui.gd`: deterministic final visual states.

### Task 1: Lock the large geometry and Apple-aligned tokens

**Files:**
- Modify: `tests/test_economy_ui_responsive.gd`
- Modify: `scripts/ui/economy_layout.gd`
- Modify: `assets/ui/economy/economy_theme.tres`

- [ ] **Step 1: Write failing geometry and token assertions**

Add assertions for the new maximum size and shared grid:

```gdscript
assertions.equal(EconomyLayout.MARKET_PANEL_MAX_SIZE, Vector2(1400.0, 760.0), "market uses selected comfortable size")
assertions.equal(EconomyLayout.BUILDING_PANEL_MAX_SIZE, Vector2(1400.0, 760.0), "production shell matches market")
assertions.equal(EconomyLayout.CARD_GAP, 16.0, "cards share the 8pt grid")
assertions.equal(EconomyLayout.CONTROL_HEIGHT, 44.0, "controls share one height")
assertions.equal(EconomyLayout.LIST_ROW_HEIGHT, 52.0, "dynamic rows share one height")
var rect := EconomyLayout.panel_rect_for(Vector2(1920.0, 1080.0), EconomyLayout.MARKET_PANEL_MAX_SIZE)
assertions.equal(rect, Rect2(260.0, 160.0, 1400.0, 760.0), "large market remains centered")
```

Extend theme checks:

```gdscript
var shell := theme.get_stylebox(&"panel", &"EconomyShell") as StyleBoxFlat
var card := theme.get_stylebox(&"panel", &"EconomyCompactCard") as StyleBoxFlat
assertions.equal(shell.corner_radius_top_left, 18, "window uses Apple-like radius")
assertions.equal(card.corner_radius_top_left, 14, "cards use aligned radius")
assertions.equal(card.border_width_left, 1, "cards use a hairline")
assertions.equal(theme.default_font_size, 18, "body text stays readable")
```

- [ ] **Step 2: Run the responsive suite and verify the new assertions fail**

Run:

```powershell
godot_console --headless --path . --script res://tests/run_economy_ui_responsive_tests.gd
```

Expected: FAIL on the old 1080×600 and 980×560 limits and old radii.

- [ ] **Step 3: Add shared dimensions**

Update `economy_layout.gd`:

```gdscript
const DRAWER_BREAKPOINT := 1204.0
const MARKET_PANEL_MAX_SIZE := Vector2(1400.0, 760.0)
const BUILDING_PANEL_MAX_SIZE := Vector2(1400.0, 760.0)
const WINDOW_INSET := 24.0
const CARD_GAP := 16.0
const CONTROL_HEIGHT := 44.0
const LIST_ROW_HEIGHT := 52.0
```

Keep `VIEWPORT_MARGIN = Vector2(20, 20)` and the current centered `panel_rect_for()` implementation.

- [ ] **Step 4: Update the shared visual tokens**

Set `EconomyShell` to `#F2F0E9F7`, 18 px radius, 1 px 16%-alpha neutral border, and one 12 px soft shadow. Set `EconomyCompactCard` to `#FFFEFAEB`, 14 px radius, 1 px border, and no heavy shadow. Update control radii to 10 px while preserving 1 px hover/pressed borders and 2 px focus.

- [ ] **Step 5: Re-run and commit**

Run the responsive suite; expected: geometry/token assertions pass while later authored-layout assertions may still fail.

```powershell
git add scripts/ui/economy_layout.gd assets/ui/economy/economy_theme.tres tests/test_economy_ui_responsive.gd
git commit -m "feat: add Apple-aligned economy UI tokens"
```

### Task 2: Align the shared market and production shells

**Files:**
- Modify: `tests/test_economy_ui_responsive.gd`
- Modify: `scenes/ui/shop_ui.tscn`
- Modify: `scenes/ui/economy/building_economy_ui.tscn`

- [ ] **Step 1: Write failing header alignment assertions**

For both real scenes, assert:

```gdscript
assertions.equal(market_tab.custom_minimum_size, Vector2(112.0, 44.0), "top tab uses aligned geometry")
assertions.equal(orders_tab.custom_minimum_size, market_tab.custom_minimum_size, "top tabs remain equal")
assertions.equal(close_button.custom_minimum_size, Vector2(44.0, 44.0), "close aligns with tabs")
assertions.equal((shell as VBoxContainer).get_theme_constant("separation"), 0, "selected tab joins page")
```

After opening at 1920×1080, verify the panel is exactly 1400×760 and all header controls share the header vertical center within 1 px.

- [ ] **Step 2: Run and verify failure**

Run the responsive suite. Expected: FAIL on old 104×42 tabs and 42×42 close controls.

- [ ] **Step 3: Re-author the ShopUI header**

In `shop_ui.tscn`:

- Use a 48 px minimum header.
- Use 28 px title, 18 px contextual labels.
- Set all four Tabs to 112×44.
- Set close to 44×44.
- Keep Tabs immediately adjacent to PageHost.
- Apply 24 px shell content inset through `EconomyShell`; do not add duplicate MarginContainer overrides.

- [ ] **Step 4: Mirror the building header**

Apply the same 48 px header, 112×44 contextual tabs, and 44×44 close button in `building_economy_ui.tscn`. Preserve contextual routing and CanvasLayer visibility synchronization.

- [ ] **Step 5: Re-run and commit**

Run responsive and main gameplay tests. Expected: both PASS.

```powershell
git add scenes/ui/shop_ui.tscn scenes/ui/economy/building_economy_ui.tscn tests/test_economy_ui_responsive.gd
git commit -m "feat: align economy window headers"
```

### Task 3: Rebuild the market as three aligned cards

**Files:**
- Modify: `tests/test_economy_ui_responsive.gd`
- Modify: `tests/test_market_ui.gd`
- Modify: `scenes/ui/economy/market_panel.tscn`
- Modify: `scripts/ui/market_panel.gd`

- [ ] **Step 1: Write failing market-grid assertions**

Assert the authored layout:

```gdscript
assertions.equal(catalog.custom_minimum_size.x, 280.0, "goods card has fixed width")
assertions.equal(detail.custom_minimum_size.x, 520.0, "price card owns the flexible center")
assertions.equal(trade.custom_minimum_size.x, 300.0, "trade card has fixed width")
assertions.equal(columns.get_theme_constant("separation"), 16, "market cards use shared gap")
assertions.equal(category_button.custom_minimum_size.y, 44.0, "category controls align")
```

In `test_market_ui.gd`, assert every generated product row and select button:

```gdscript
assertions.equal(wood_row.custom_minimum_size.y, 52.0, "product rows share one height")
assertions.truthy((wood_row.get_node("Content/SelectButton") as Button).clip_text, "product text cannot resize the card")
```

- [ ] **Step 2: Run and verify failure**

Run runtime UI and responsive suites. Expected: FAIL on old 220/360/240 widths and 34 px category controls.

- [ ] **Step 3: Author the market card grid**

Update `market_panel.tscn`:

```text
Columns (gap 16)
  CatalogColumn (280, EconomyCompactCard)
  DetailColumn (min 520, expand, EconomyCompactCard)
  TradePanel (300, EconomyCompactCard)
```

Use a `PanelContainer` per card with an inner 16 px margin. Make category controls 44 px, the sort control 44 px, and keep only ItemScroll vertically expanding.

Rebuild the detail card with:

```text
DetailHeader / ItemNameLabel + StockBadge
PriceMetrics / MidMetric + BuyMetric + SellMetric
ChartTitle
PriceChart (expand)
MarketMetrics / Stock + Supply + Demand + Liquidity
```

Keep the existing label node names or update `market_panel.gd` paths in the same change. Do not restore source/use/processing prose.

- [ ] **Step 4: Constrain runtime rows**

In `_create_item_row()` add:

```gdscript
row.custom_minimum_size = Vector2(0.0, EconomyLayoutScript.LIST_ROW_HEIGHT)
row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
content.add_theme_constant_override("separation", 8)
select_button.clip_text = true
select_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
urgent_badge.text = "紧缺"
urgent_badge.custom_minimum_size = Vector2(44.0, 0.0)
```

Keep the full text in the row and button tooltips.

- [ ] **Step 5: Re-run and commit**

Run runtime UI and responsive suites; expected: PASS.

```powershell
git add scenes/ui/economy/market_panel.tscn scripts/ui/market_panel.gd tests/test_market_ui.gd tests/test_economy_ui_responsive.gd
git commit -m "feat: align market card layout"
```

### Task 4: Align the transaction form and confirmation

**Files:**
- Modify: `tests/test_market_ui.gd`
- Modify: `tests/test_economy_ui_responsive.gd`
- Modify: `scenes/ui/economy/trade_panel.tscn`
- Modify: `scripts/ui/trade_panel.gd`

- [ ] **Step 1: Write failing form-geometry assertions**

Assert that QuantitySpin, Max, Buy, and Sell are 44 px high; Buy and Sell have equal width; and the confirmation content rectangle remains enclosed by TradePanel at 1920×1080 and 1280×720.

- [ ] **Step 2: Run and verify failure**

Run runtime UI and responsive suites. Expected: FAIL on inconsistent control geometry.

- [ ] **Step 3: Author the aligned form**

Replace stacked free-form labels with a two-column `GridContainer` named `SummaryGrid`:

```text
持有       30
市场库存   60
参考单价   16
买入总价   18
卖出总价   14
成交影响   无明显影响
```

Keep current label nodes as values so `trade_panel.gd` behavior remains unchanged. Set QuantitySpin, Max, Buy, Sell to 44 px. Reserve 40 px for `DisabledReasonLabel` and `FeedbackLabel` together so updates do not move buttons.

- [ ] **Step 4: Constrain confirmation**

Keep `ConfirmationLayer` anchored to TradePanel. Set `Content` offsets to 12 px on all sides, remove text-driven minimum width, use 22 px title and 18 px body, and retain equal 44 px Confirm/Cancel buttons.

- [ ] **Step 5: Re-run and commit**

Run runtime UI, responsive, and main gameplay suites; expected: PASS.

```powershell
git add scenes/ui/economy/trade_panel.tscn scripts/ui/trade_panel.gd tests/test_market_ui.gd tests/test_economy_ui_responsive.gd
git commit -m "feat: align compact trade form"
```

### Task 5: Rebuild production as three aligned cards

**Files:**
- Modify: `tests/test_building_economy_ui.gd`
- Modify: `tests/test_economy_ui_responsive.gd`
- Modify: `scenes/ui/economy/building_production_panel.tscn`
- Modify: `scripts/ui/building_production_panel.gd`

- [ ] **Step 1: Write failing production-grid assertions**

Assert 280 / 520 / 300 minimum widths, 16 px major gaps, 44 px Batch/Max/Start/Collect controls, and 52 px generated recipe/output rows.

- [ ] **Step 2: Run and verify failure**

Run main gameplay and responsive suites. Expected: FAIL on the current 190/330/230 widths and inconsistent dynamic rows.

- [ ] **Step 3: Author recipe, process, and activity cards**

Update `building_production_panel.tscn`:

```text
Sections (gap 16)
  RecipeCard PanelContainer (280)
    Margin/VBox/Header
    RecipeScroll/RecipeList
  ProcessCard PanelContainer (min 520, expand)
    Margin/VBox/Header
    Flow
    Metrics GridContainer (2 columns)
    MissingLabel (reserved 40)
    BatchControls
  ActivityCard PanelContainer (300)
    Margin/VBox/QueueHeader
    QueueScroll/QueueSlots
    Divider
    StorageHeader
    StorageList
    CapacityLabel
    CollectAllButton
```

Keep the leaf node names used by the script and update `@onready` paths atomically.

- [ ] **Step 4: Align runtime rows**

For recipe buttons:

```gdscript
button.custom_minimum_size.y = EconomyLayoutScript.LIST_ROW_HEIGHT
button.clip_text = true
button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
```

For queue slots, reduce redundant vertical labels into an aligned compact row while retaining `RecipeLabel`, `StateLabel`, `RemainingLabel`, and `ProgressBar` node names. For output rows, set 52 px height and a 72×44 Collect button.

- [ ] **Step 5: Re-run and commit**

Run main gameplay, building, production-chain, and responsive suites; expected: PASS.

```powershell
git add scenes/ui/economy/building_production_panel.tscn scripts/ui/building_production_panel.gd tests/test_building_economy_ui.gd tests/test_economy_ui_responsive.gd
git commit -m "feat: align production card layout"
```

### Task 6: Finish chart states, visual captures, and regression verification

**Files:**
- Modify: `tests/test_market_price_chart.gd`
- Modify: `scripts/ui/market_price_chart.gd`
- Modify: `tests/capture_economy_ui.gd`
- Modify only files required by verified failures.

- [ ] **Step 1: Write the empty-history contract**

Add a deterministic helper assertion:

```gdscript
assertions.equal(chart_script.empty_state_text([]), "历史积累中", "empty chart explains its state")
assertions.equal(chart_script.empty_state_text([16]), "", "available history removes empty state")
```

- [ ] **Step 2: Run and verify failure**

Run runtime UI tests. Expected: FAIL because `empty_state_text()` does not exist.

- [ ] **Step 3: Render the empty state**

Add:

```gdscript
static func empty_state_text(values: Array) -> String:
	return "历史积累中" if values.is_empty() else ""
```

In `_draw()`, draw the centered secondary-color message inside the chart rectangle before returning on empty history. Keep the existing smooth seven-day curve for non-empty history.

- [ ] **Step 4: Generate and inspect final captures**

Run these deterministic states with animations disabled:

```powershell
godot --path . --display-driver windows --rendering-method gl_compatibility --script res://tests/capture_economy_ui.gd -- --state=market_normal --size=1920x1080
godot --path . --display-driver windows --rendering-method gl_compatibility --script res://tests/capture_economy_ui.gd -- --state=market_normal --size=1280x720
godot --path . --display-driver windows --rendering-method gl_compatibility --script res://tests/capture_economy_ui.gd -- --state=market_trade_confirmation --size=1920x1080
godot --path . --display-driver windows --rendering-method gl_compatibility --script res://tests/capture_economy_ui.gd -- --state=running_producer --size=1920x1080
godot --path . --display-driver windows --rendering-method gl_compatibility --script res://tests/capture_economy_ui.gd -- --state=building_output_ready --size=1920x1080
```

Inspect every PNG for aligned card edges, 44 px controls, stable shell bounds, readable text, visible curve, and no content-driven resizing.

- [ ] **Step 5: Run complete verification**

Run:

```powershell
godot_console --headless --editor --path . --quit-after 2
godot_console --headless --path . --script res://tests/test_runtime_ui_scenes.gd
godot_console --headless --path . --script res://tests/run_economy_ui_responsive_tests.gd
godot_console --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
godot_console --headless --path . --script res://tests/run_building_system_tests.gd
godot_console --headless --path . --script res://tests/run_production_chain_tests.gd
godot_console --headless --path . --script res://tests/run_tests.gd
```

Expected: every focused and integration command exits 0. Record the existing independent `run_economy_system_tests.gd` save-fixture timeout separately rather than changing save behavior in this UI task.

- [ ] **Step 6: Commit final verified corrections**

```powershell
git add scripts/ui/market_price_chart.gd tests/test_market_price_chart.gd tests/capture_economy_ui.gd
git commit -m "test: verify Apple-aligned economy UI"
```

Do not commit generated `.godot/` images or regenerated `.uid` files.
