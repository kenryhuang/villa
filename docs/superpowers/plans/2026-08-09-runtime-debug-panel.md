# Runtime Debug Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Debug-build-only runtime panel that atomically edits player level, elapsed days, gold, stamina, and every inventory item without immediately saving.

**Architecture:** A focused `DebugStateEditor` owns snapshot, validation, transaction, rollback, and EventBus refresh behavior. A separate `DebugPanel` owns only draft UI state and emits apply requests; `Main` creates and wires both only in Debug builds, while HUD exposes a small entry button.

**Tech Stack:** Godot 4.7, GDScript, `.tscn` Control scenes, existing `TestAssert` headless test runners.

---

## File map

- Create `scripts/debug/debug_state_editor.gd`: authoritative debug snapshot, validation, atomic apply, rollback, and refresh events.
- Create `scripts/ui/debug_panel.gd`: modal open/close, draft form, filters, dynamic item rows, and apply result rendering.
- Create `scenes/ui/debug_panel.tscn`: centered two-tab Debug UI and local styles.
- Create `tests/test_debug_state_editor.gd`: state editor unit tests with real inventory and focused system doubles.
- Create `tests/test_debug_panel.gd`: panel scene contract and draft interaction tests.
- Create `tests/run_debug_panel_tests.gd`: headless runner for the feature.
- Modify `scripts/ui/hud.gd`: Debug-panel request signal and availability configuration.
- Modify `scenes/ui/hud.tscn`: shared Debug actions container with reset and panel buttons.
- Modify `scripts/main.gd`: Debug-only construction and wiring.
- Modify `tests/test_hud_action_bar.gd`: HUD entry behavior regression tests.
- Modify `tests/test_runtime_ui_scenes.gd`: authored Debug panel scene contract.
- Modify `tests/run_main_gameplay_integration_tests.gd`: include Debug panel behavior in the main regression suite.

### Task 1: State snapshots and validation

**Files:**
- Create: `scripts/debug/debug_state_editor.gd`
- Create: `tests/test_debug_state_editor.gd`
- Create: `tests/run_debug_panel_tests.gd`

- [ ] **Step 1: Write the failing snapshot and validation tests**

Add a `GameStateDouble`, `SeasonDouble`, cursor doubles, and a real `InventorySystem`. Assert that `snapshot()` returns level, elapsed days (`total_days - 1`), gold, stamina, and every `GameData` item with current quantities. Assert that `validate()` rejects negative values, unknown IDs, unsafe dates, and inventory combinations requiring more than `max_slots`.

```gdscript
var snapshot := editor.snapshot()
assertions.equal(snapshot.level, 3, "snapshot reads level")
assertions.equal(snapshot.elapsed_days, 8, "snapshot converts total day to elapsed day")
assertions.equal(snapshot.items.wood.quantity, 12, "snapshot reads inventory totals")

var invalid := snapshot.duplicate(true)
invalid.elapsed_days = -1
assertions.equal(editor.validate(invalid).reason, "invalid_elapsed_days", "negative elapsed days are rejected")

invalid = snapshot.duplicate(true)
for item_id in invalid.items:
	invalid.items[item_id].quantity = 99
assertions.equal(editor.validate(invalid).reason, "inventory_capacity", "oversized target inventory is rejected")
```

- [ ] **Step 2: Run the feature runner and verify RED**

Run:

```powershell
godot --headless --path . --script res://tests/run_debug_panel_tests.gd
```

Expected: FAIL because `res://scripts/debug/debug_state_editor.gd` does not exist.

- [ ] **Step 3: Implement configuration, snapshot, and pure validation**

Implement this public surface:

```gdscript
class_name DebugStateEditor
extends RefCounted

const GameDataScript := preload("res://scripts/core/game_data.gd")
const EconomyLimitsScript := preload("res://scripts/core/economy_limits.gd")
const PlayerStateScript := preload("res://scripts/data/player_state.gd")

func configure(game_state, season, inventory, production, market, npc, daily, resources, event_bus) -> bool
func snapshot() -> Dictionary
func validate(draft: Dictionary) -> Dictionary
func apply(draft: Dictionary) -> Dictionary
```

`configure()` must verify required properties and methods. `snapshot()` must return stable item records keyed by item ID, each containing `id`, `name`, `category`, `max_stack`, and `quantity`. `validate()` must require exact integer values, clamp nothing silently, use elapsed day range `0..EconomyLimits.MAX_SAFE_DATE - 1`, and calculate required stacks with each definition's `max_stack`.

`apply()` must begin with an `OS.is_debug_build()` guard and return `{ "ok": false, "reason": "debug_build_required" }` when unavailable. No caller-controlled flag may bypass this guard.

- [ ] **Step 4: Run the feature runner and verify GREEN**

Run the same headless command. Expected: PASS for snapshot and validation checks.

- [ ] **Step 5: Commit Task 1**

```powershell
git add scripts/debug/debug_state_editor.gd tests/test_debug_state_editor.gd tests/run_debug_panel_tests.gd
git commit -m "feat: add debug state validation"
```

### Task 2: Atomic player and inventory application

**Files:**
- Modify: `scripts/debug/debug_state_editor.gd`
- Modify: `tests/test_debug_state_editor.gd`

- [ ] **Step 1: Write failing player, inventory, and rollback tests**

Test that applying level 4 sets experience to `PlayerState.LEVEL_THRESHOLDS[3]`, writes gold/stamina, splits quantities above one stack, preserves quick-slot mappings for retained items, clears mappings for removed items, and emits exact EventBus changes only after success. Add a dependency double whose cursor sync fails and assert every player and inventory field remains unchanged.

```gdscript
var draft := editor.snapshot()
draft.level = 4
draft.gold = 4321
draft.stamina = 17
draft.items.wood.quantity = 130
draft.items.grain_seed.quantity = 0
var result := editor.apply(draft)
assertions.truthy(result.ok, "valid debug state applies")
assertions.equal(game_state.player_state.exp, PlayerState.LEVEL_THRESHOLDS[3], "level applies matching minimum exp")
assertions.equal(inventory.get_item_count("wood"), 130, "inventory splits and restores target quantity")
assertions.equal(inventory.get_quick_item(5), "", "removed quick item mapping clears")
```

- [ ] **Step 2: Run tests and verify RED**

Expected: FAIL because `apply()` does not yet mutate state atomically.

- [ ] **Step 3: Implement target-slot construction and transaction rollback**

Build the complete target slot array before mutation. Sort item IDs, split each quantity by `max_stack`, pad to `inventory.max_slots`, and rebuild quick mappings from the previously mapped item IDs. Capture player, season, cursor, resource, slot, and mapping snapshots before applying. If any cursor/resource call returns false, restore all captured values and return `{ "ok": false, "reason": "transaction_failed" }`.

Only after the transaction succeeds, emit:

```gdscript
event_bus.level_changed.emit(level)
event_bus.exp_gained.emit(0)
event_bus.gold_changed.emit(gold)
event_bus.stamina_changed.emit(stamina)
event_bus.item_added.emit(item_id, positive_delta)
event_bus.item_removed.emit(item_id, removed_delta)
```

Return `{ "ok": true, "reason": "", "message": "调试数据已应用；尚未写入存档" }`. Do not call `SaveManager`.

- [ ] **Step 4: Run tests and verify GREEN**

Expected: all state editor tests pass, including rollback and EventBus delta assertions.

- [ ] **Step 5: Commit Task 2**

```powershell
git add scripts/debug/debug_state_editor.gd tests/test_debug_state_editor.gd
git commit -m "feat: apply debug state atomically"
```

### Task 3: Direct elapsed-day synchronization

**Files:**
- Modify: `scripts/debug/debug_state_editor.gd`
- Modify: `tests/test_debug_state_editor.gd`

- [ ] **Step 1: Write failing day mapping and cursor coherence tests**

Cover elapsed days `0`, `7`, `27`, and `28`. Assert total day, season, day-in-season, unchanged hour/minute, production/NPC cursor calls, market/daily cursor values, and resource snapshot restoration at the target day. Give the daily double a `run_day_calls` counter and assert it remains zero.

```gdscript
draft.elapsed_days = 28
var hour_before := season.hour
var minute_before := season.minute
assertions.truthy(editor.apply(draft).ok, "direct date jump applies")
assertions.equal(season.total_days, 29, "elapsed day maps to one-based total day")
assertions.equal(season.current_season, 0, "day 29 wraps to spring")
assertions.equal(season.current_day, 1, "day 29 is first day of season")
assertions.equal(daily.last_simulated_day, 29, "daily cursor synchronizes")
assertions.equal(daily.run_day_calls, 0, "direct jump never settles skipped days")
assertions.equal([season.hour, season.minute], [hour_before, minute_before], "clock time remains unchanged")
```

- [ ] **Step 2: Run tests and verify RED**

Expected: FAIL on date mapping or one of the cursor expectations.

- [ ] **Step 3: Implement coherent direct jump**

Before emitting any event, calculate:

```gdscript
var target_total_days := elapsed_days + 1
season.total_days = target_total_days
season.current_day = elapsed_days % season.DAYS_PER_SEASON + 1
season.current_season = floori(float(elapsed_days) / season.DAYS_PER_SEASON) % 4
daily.last_simulated_day = target_total_days
market.last_settled_day = target_total_days
production.sync_daily_cursor(target_total_days)
npc.sync_daily_cursor(target_total_days)
resources.restore_resource_dicts(resource_snapshot, target_total_days)
```

After all calls succeed, emit `season_changed` only if the season changed and then `day_changed(target_total_days)`. Cursors must already equal the target, so connected daily simulation does not run it.

- [ ] **Step 4: Run tests and verify GREEN**

Expected: all direct-day and previous atomic state tests pass.

- [ ] **Step 5: Commit Task 3**

```powershell
git add scripts/debug/debug_state_editor.gd tests/test_debug_state_editor.gd
git commit -m "feat: synchronize debug date jumps"
```

### Task 4: Debug panel scene and draft UI

**Files:**
- Create: `scenes/ui/debug_panel.tscn`
- Create: `scripts/ui/debug_panel.gd`
- Create: `tests/test_debug_panel.gd`
- Modify: `tests/run_debug_panel_tests.gd`
- Modify: `tests/test_runtime_ui_scenes.gd`

- [ ] **Step 1: Write the failing scene and interaction tests**

Require these nodes:

```text
Overlay/Center/Panel/Layout/Header/Title
Overlay/Center/Panel/Layout/Header/CloseButton
Overlay/Center/Panel/Layout/Tabs/PlayerState/Fields/Level
Overlay/Center/Panel/Layout/Tabs/PlayerState/Fields/ElapsedDays
Overlay/Center/Panel/Layout/Tabs/PlayerState/Fields/Gold
Overlay/Center/Panel/Layout/Tabs/PlayerState/Fields/Stamina
Overlay/Center/Panel/Layout/Tabs/Inventory/Toolbar/Search
Overlay/Center/Panel/Layout/Tabs/Inventory/Toolbar/Category
Overlay/Center/Panel/Layout/Tabs/Inventory/ItemScroll/ItemRows
Overlay/Center/Panel/Layout/Footer/Status
Overlay/Center/Panel/Layout/Footer/RefreshButton
Overlay/Center/Panel/Layout/Footer/CancelButton
Overlay/Center/Panel/Layout/Footer/ApplyButton
```

Instantiate the scene, call `configure(snapshot)`, open it, modify fields, verify `build_draft()`, filter by text/category without losing draft quantities, emit apply once, refresh, and close with no apply.

- [ ] **Step 2: Run tests and verify RED**

Expected: FAIL because the panel scene and script do not exist.

- [ ] **Step 3: Author the compact two-tab scene**

Use a `CanvasLayer` root with a full-rect translucent `ColorRect`, a centered `PanelContainer` with minimum size `Vector2(860, 620)`, and a `TabContainer`. The outer panel uses 14-pixel corner radii and a 1-pixel border; tab content panels remain rectangular. Keep the footer outside the tab content so controls stay visible while the item list scrolls.

- [ ] **Step 4: Implement draft state and dynamic item rows**

Expose:

```gdscript
signal apply_requested(draft: Dictionary)

func configure(snapshot: Dictionary) -> bool
func open(snapshot: Dictionary = {}) -> void
func close() -> void
func refresh_from_snapshot(snapshot: Dictionary) -> void
func build_draft() -> Dictionary
func show_apply_result(result: Dictionary, refreshed_snapshot: Dictionary = {}) -> void
func get_visible_item_ids() -> Array[String]
```

Each dynamic row stores its `item_id` in metadata and connects one `SpinBox.value_changed` callback into an `_item_quantities` dictionary. Search is case-insensitive across Chinese name and internal ID. Category `OptionButton` starts with “全部” and uses stable category ordering. Input changes set a visible “未应用” marker; refresh resets it.

- [ ] **Step 5: Run feature and runtime UI tests and verify GREEN**

```powershell
godot --headless --path . --script res://tests/run_debug_panel_tests.gd
godot --headless --path . --script res://tests/test_runtime_ui_scenes.gd
```

Expected: both exit 0 with the panel scene and draft tests passing.

- [ ] **Step 6: Commit Task 4**

```powershell
git add scenes/ui/debug_panel.tscn scripts/ui/debug_panel.gd tests/test_debug_panel.gd tests/run_debug_panel_tests.gd tests/test_runtime_ui_scenes.gd
git commit -m "feat: add runtime debug panel UI"
```

### Task 5: HUD entry and Main wiring

**Files:**
- Modify: `scenes/ui/hud.tscn`
- Modify: `scripts/ui/hud.gd`
- Modify: `scripts/main.gd`
- Modify: `tests/test_hud_action_bar.gd`
- Modify: `tests/run_main_gameplay_integration_tests.gd`

- [ ] **Step 1: Write failing HUD and Main integration tests**

Replace the standalone reset-button expectation with a `DebugActions` container containing `DebugPanelButton` and `DebugResetButton`. Verify `configure_debug_tools(false)` hides the whole container, `configure_debug_tools(true)` shows it, and each visible button emits only its own signal once. Add a Main integration assertion that Debug builds create `DebugPanel` and can open it from HUD.

- [ ] **Step 2: Run main gameplay tests and verify RED**

```powershell
godot --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: FAIL because the new HUD node/API and Main wiring are absent.

- [ ] **Step 3: Implement HUD Debug actions**

In `hud.gd`, add:

```gdscript
signal debug_panel_requested

@onready var debug_actions: HBoxContainer = $DebugActions
@onready var debug_panel_button: Button = $DebugActions/DebugPanelButton
@onready var debug_reset_button: Button = $DebugActions/DebugResetButton

func configure_debug_tools(available: bool) -> void:
	debug_actions.visible = available

func _on_debug_panel_pressed() -> void:
	if debug_actions.visible:
		debug_panel_requested.emit()
```

Keep `configure_debug_reset()` as a compatibility wrapper around `configure_debug_tools()` until all callers migrate.

- [ ] **Step 4: Implement Debug-only Main composition**

Preload both Debug classes, and in `_setup_ui()` call `_setup_debug_tools()`. In non-Debug builds, hide the HUD actions and return before instantiation. In Debug builds:

```gdscript
debug_state_editor = DebugStateEditorScript.new()
debug_state_editor.configure(
	get_node_or_null("/root/GameState"), season_system, inventory_system,
	production_system, market_system, npc_economy_system,
	daily_simulation_system, world, get_node_or_null("/root/EventBus")
)
debug_panel = DebugPanelScene.instantiate()
debug_panel.name = "DebugPanel"
add_child(debug_panel)
debug_panel.configure(debug_state_editor.snapshot())
```

Connect HUD request to `debug_panel.open(debug_state_editor.snapshot())`. Connect panel apply to `debug_state_editor.apply(draft)`, refresh the panel on success, and call `hud.refresh_action_bar()` after success. Do not inject or call `SaveManager`.

- [ ] **Step 5: Run main gameplay tests and verify GREEN**

Expected: main gameplay integration runner exits 0 and includes Debug entry checks.

- [ ] **Step 6: Commit Task 5**

```powershell
git add scenes/ui/hud.tscn scripts/ui/hud.gd scripts/main.gd tests/test_hud_action_bar.gd tests/run_main_gameplay_integration_tests.gd
git commit -m "feat: wire runtime debug tools"
```

### Task 6: Full verification and visual check

**Files:**
- Modify only if verification exposes a defect in files already listed above.

- [ ] **Step 1: Run feature, UI, gameplay, building, and syntax regressions**

```powershell
godot --headless --path . --script res://tests/run_debug_panel_tests.gd
godot --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
godot --headless --path . --script res://tests/run_building_system_tests.gd
godot --headless --path . --script res://tests/test_runtime_ui_scenes.gd
git diff --check
```

Expected: every command exits 0; existing intentional warning fixtures may log warnings, but there are no test failures or parser errors.

- [ ] **Step 2: Capture the panel at representative viewports**

Add a temporary headless capture harness under `.godot/` or use the existing capture pattern without tracking it. Render the player tab and a filtered inventory tab at 1920×1080 and 1280×720. Inspect that the outer panel stays centered, footer remains visible, input baselines align, and long resource names do not overlap IDs or SpinBoxes.

- [ ] **Step 3: Verify exact Git scope**

```powershell
git status --short
git diff --stat HEAD~4..HEAD
git diff --check HEAD~4..HEAD
```

Confirm the pre-existing stone-kiln atlas and its art regression test remain outside Debug-panel commits unless the user separately requests their commit.

- [ ] **Step 4: Commit any verification-only correction**

If verification required a correction, stage only Debug-panel files and commit:

```powershell
git commit -m "fix: polish runtime debug panel"
```

If no correction was required, do not create an empty commit.
