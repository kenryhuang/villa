# Planting Inventory UI Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent every seed consumption from rebuilding hidden UI while keeping visible panels and reopened pages synchronized with authoritative inventory and economy state.

**Architecture:** Each affected panel owns a dirty flag plus a single deferred-refresh flag. Authoritative events mark the panel dirty; visible panels coalesce those events into one deferred refresh, while hidden panels do no expensive work until their existing open/tab-selection entry point performs a forced refresh.

**Tech Stack:** Godot 4, GDScript, SceneTree test runners, EventBus signals, existing `ShopUI` page orchestration.

---

## File map

- Modify `scripts/ui/seed_selector_panel.gd`: gate and coalesce seed-row rebuilding.
- Modify `scripts/ui/market_panel.gd`: gate and coalesce market snapshot rebuilding.
- Modify `scripts/ui/trade_panel.gd`: gate and coalesce quote rebuilding without weakening confirmation invalidation.
- Modify `scripts/ui/order_panel.gd`: gate and coalesce order-row rebuilding.
- Modify `scripts/ui/contract_panel.gd`: gate and coalesce contract-row rebuilding.
- Verify `scripts/ui/shop_ui.gd`: its existing open and tab-selection branches are the forced-refresh boundary; no production change is planned there.
- Modify `tests/test_seed_selector_panel.gd`: cover hidden, reopened, and coalesced seed-selector refresh behavior.
- Modify `tests/test_economy_ui_integration.gd`: cover hidden and reopened market, trade, order, and contract behavior.
- Modify `tests/test_main_farming_building_integration.gd`: cover a real planting command without hidden UI reconstruction.

### Task 1: Seed selector hidden-refresh gate

**Files:**
- Modify: `tests/test_seed_selector_panel.gd` in `run()` and beside `_test_owned_seed_rows_and_selection`
- Modify: `scripts/ui/seed_selector_panel.gd:24-30,70-84,117-127,337-340`

- [ ] **Step 1: Write the failing hidden/reopen test**

Add the test call to `run()` and implement a fixture-based test that records row instance IDs, changes authoritative inventory while the panel is closed, and verifies no hidden rebuild occurs before reopening:

```gdscript
await _test_hidden_inventory_change_refreshes_only_on_reopen(assertions, tree)


func _test_hidden_inventory_change_refreshes_only_on_reopen(
	assertions: TestAssert,
	tree: SceneTree
) -> void:
	var fixture := await _make_fixture(tree)
	var panel = fixture.panel
	panel.open_for_cell(fixture.cell)
	await tree.process_frame
	var before_ids := _seed_row_instance_ids(panel)
	panel.close()
	assertions.truthy(
		fixture.inventory.remove_item("grain_seed", 1),
		"hidden selector fixture removes one seed"
	)
	await tree.process_frame
	assertions.equal(
		_seed_row_instance_ids(panel),
		before_ids,
		"hidden selector does not rebuild rows after seed removal"
	)
	panel.open_for_cell(fixture.cell)
	await tree.process_frame
	assertions.equal(
		(_row(panel, "grain_seed").get_node("Quantity") as Label).text,
		"×2",
		"reopened selector reads the latest seed quantity"
	)
	_free_fixture(fixture)
	await tree.process_frame


func _seed_row_instance_ids(panel: Node) -> Array[int]:
	var ids: Array[int] = []
	for row_value in panel.seed_rows.get_children():
		var row := row_value as Node
		if row.has_meta("plant_item_id"):
			ids.append(row.get_instance_id())
	return ids
```

- [ ] **Step 2: Run the selector test and verify RED**

Run:

```powershell
godot --headless --path . --script res://tests/run_seed_selector_panel_tests.gd
```

Expected: FAIL because `_on_inventory_item_changed()` immediately calls `_refresh()` even when the selector is closed, changing the saved row instance IDs.

- [ ] **Step 3: Implement the minimal dirty/coalesced refresh state**

Add state and route seed inventory events through one deferred refresh:

```gdscript
var _refresh_pending := false
var _refresh_scheduled := false


func _refresh() -> void:
	_refresh_pending = false
	# Preserve the existing row rebuild and selection-status body below.


func _on_inventory_item_changed(item_id: String, _quantity: int) -> void:
	var item_data: Variant = GameDataScript.get_item(item_id)
	if not item_data is Dictionary or str((item_data as Dictionary).get("category", "")) != "seed":
		return
	_refresh_pending = true
	if not visible or _refresh_scheduled:
		return
	_refresh_scheduled = true
	call_deferred("_flush_queued_refresh")


func _flush_queued_refresh() -> void:
	_refresh_scheduled = false
	if visible and is_inside_tree() and _refresh_pending:
		_refresh()


func _exit_tree() -> void:
	_refresh_scheduled = false
	_disconnect_authoritative_signals()
```

Keep `open_for_cell()` calling `_refresh()` before showing the selector. That call reads authoritative inventory and clears `_refresh_pending` every time the selector opens.

- [ ] **Step 4: Add and verify visible-event coalescing**

Extend the test by opening the panel, recording IDs, emitting two seed inventory changes in the same frame, and asserting that rows are unchanged before `process_frame` and rebuilt once afterward. Use the final quantity label, rather than elapsed milliseconds, as the correctness assertion.

Run:

```powershell
godot --headless --path . --script res://tests/run_seed_selector_panel_tests.gd
```

Expected: PASS with no selector failures.

- [ ] **Step 5: Commit the selector change**

```powershell
git add scripts/ui/seed_selector_panel.gd tests/test_seed_selector_panel.gd
git commit -m "perf: defer seed selector inventory refresh"
```

### Task 2: Market and trade hidden-refresh gates

**Files:**
- Modify: `tests/test_economy_ui_integration.gd` in `run()` and near `_test_market_panel_follows_routed_storage`
- Modify: `scripts/ui/market_panel.gd:54-65,108-109,646-658,703-733`
- Modify: `scripts/ui/trade_panel.gd:35-38,76-115,516-561`

- [ ] **Step 1: Write failing market/trade tests**

Create a real `ShopUI` fixture, select a market item, close the shop, then mutate inventory and emit the normal authoritative event. Capture market row instance IDs and the trade owned-quantity label before the event:

```gdscript
shop.open("market")
shop.market_panel.select_category("crops")
shop.market_panel.select_item("grain_seed")
await tree.process_frame
var row_ids_before := _meta_child_instance_ids(shop.market_panel.item_rows, "item_id")
var owned_before := shop.market_panel.trade_panel.player_quantity_label.text
shop.close()
assertions.truthy(inventory.remove_item("grain_seed", 1), "hidden market fixture removes one seed")
await tree.process_frame
assertions.equal(
	_meta_child_instance_ids(shop.market_panel.item_rows, "item_id"),
	row_ids_before,
	"hidden market does not rebuild product rows"
)
assertions.equal(
	shop.market_panel.trade_panel.player_quantity_label.text,
	owned_before,
	"hidden trade panel does not rebuild its quote"
)
shop.open("market")
await tree.process_frame
assertions.equal(
	shop.market_panel.trade_panel.player_quantity_label.text,
	str(economy.get_owned_quantity("grain_seed")),
	"reopened market reads the latest owned quantity"
)
```

Add a helper that returns instance IDs for children carrying the requested metadata key. Also emit two relevant inventory events while the market is visible and verify only one post-frame row replacement occurs.

- [ ] **Step 2: Run the economy UI test and verify RED**

Run:

```powershell
godot --headless --path . --script res://tests/run_economy_ui_tests.gd
```

Expected: FAIL because `MarketPanel._flush_authoritative_refresh()` rebuilds while the parent shop is hidden, and `TradePanel._do_queued_quote_refresh()` refreshes without checking tree visibility.

- [ ] **Step 3: Gate the market snapshot refresh**

Replace the market scheduler with dirty-state semantics while preserving its public forced refresh:

```gdscript
var _authoritative_refresh_pending := false
var _authoritative_refresh_scheduled := false


func refresh_market() -> void:
	_authoritative_refresh_pending = false
	_on_trade_snapshot_changed()


func _schedule_authoritative_refresh() -> void:
	_authoritative_refresh_pending = true
	if not is_visible_in_tree() or _authoritative_refresh_scheduled:
		return
	_authoritative_refresh_scheduled = true
	call_deferred("_flush_authoritative_refresh")


func _flush_authoritative_refresh() -> void:
	_authoritative_refresh_scheduled = false
	if is_inside_tree() and is_visible_in_tree() and _authoritative_refresh_pending:
		refresh_market()
```

Reset both flags in `_exit_tree()`. Keep every existing authoritative connection and event filter intact.

- [ ] **Step 4: Gate trade quote refresh without weakening confirmation safety**

Add `_quote_refresh_pending`. `_on_authoritative_snapshot_changed()` must continue invalidating a visible confirmation immediately, then mark the quote dirty and only queue visible work:

```gdscript
func refresh_quote() -> void:
	_quote_refresh_pending = false
	if not is_node_ready() or _refreshing_quote:
		return
	# Preserve the existing quote-rendering body below.


func _on_authoritative_snapshot_changed() -> void:
	if confirmation_layer != null and confirmation_layer.visible:
		var pending_is_buy := _pending_action == "buy"
		var pending_quantity := int(_confirmation_snapshot.get("quantity", 0))
		var preflight := _trade_preflight(pending_quantity, pending_is_buy)
		var reason := _localized_trade_failure(preflight)
		_invalidate_confirmation(reason if not reason.is_empty() else "状态已变化，请重新确认")
	_quote_refresh_pending = true
	if not is_visible_in_tree() or _quote_refresh_queued:
		return
	_quote_refresh_queued = true
	call_deferred("_do_queued_quote_refresh")


func _do_queued_quote_refresh() -> void:
	_quote_refresh_queued = false
	if is_inside_tree() and is_visible_in_tree() and _quote_refresh_pending:
		refresh_quote()
```

- [ ] **Step 5: Run focused tests and commit**

Run:

```powershell
godot --headless --path . --script res://tests/run_economy_ui_tests.gd
```

Expected: PASS, including hidden/reopen tests and existing trade-confirmation invalidation tests.

Commit:

```powershell
git add scripts/ui/market_panel.gd scripts/ui/trade_panel.gd tests/test_economy_ui_integration.gd
git commit -m "perf: skip hidden market inventory refresh"
```

### Task 3: Order and contract hidden-refresh gates

**Files:**
- Modify: `tests/test_economy_ui_integration.gd` near `_test_order_contract_panels_follow_farm_storage`
- Modify: `scripts/ui/order_panel.gd:42-47,138-167,343-400`
- Modify: `scripts/ui/contract_panel.gd:55-85,151-186,374-427`

- [ ] **Step 1: Write failing hidden/reopen tests**

Use a configured `ShopUI` so parent visibility and page selection match gameplay. Record order and contract row instance IDs, close the shop, remove an owned delivery item, await a frame, and assert the hidden rows are unchanged. Reopen each tab and assert its owned label and button state match the new authoritative quantity:

```gdscript
shop.open("orders")
await tree.process_frame
var order_ids_before := _meta_child_instance_ids(shop.order_panel.order_rows, "order_id")
shop.select_tab("contracts")
await tree.process_frame
var contract_ids_before := _contract_row_instance_ids(shop.contract_panel)
shop.close()
assertions.truthy(fixture.inventory.remove_item("iron_ore", 1), "hidden order fixture removes delivery stock")
assertions.truthy(fixture.storage.remove_items({"grain": 1}), "hidden contract fixture removes delivery stock")
await tree.process_frame
assertions.equal(
	_meta_child_instance_ids(shop.order_panel.order_rows, "order_id"),
	order_ids_before,
	"hidden order page does not rebuild rows"
)
assertions.equal(
	_contract_row_instance_ids(shop.contract_panel),
	contract_ids_before,
	"hidden contract page does not rebuild rows"
)
shop.open("orders")
await tree.process_frame
assertions.truthy(
	shop.order_panel.owned_label.text.contains(str(fixture.economy.get_owned_quantity("iron_ore"))),
	"reopened order page reads latest ownership"
)
```

Then select `contracts` and assert its controls reflect the same authoritative change.

- [ ] **Step 2: Run the economy UI test and verify RED**

Run:

```powershell
godot --headless --path . --script res://tests/run_economy_ui_tests.gd
```

Expected: FAIL because `_queue_refresh()` always schedules row rebuilding and storage events call `refresh_orders()` / `refresh_contracts()` synchronously.

- [ ] **Step 3: Implement identical dirty/coalesced behavior in both panels**

For `OrderPanel`, make `refresh_orders()` clear `_refresh_pending`, and use:

```gdscript
var _refresh_pending := false
var _refresh_queued := false


func _queue_refresh() -> void:
	_refresh_pending = true
	if not is_visible_in_tree() or _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_do_queued_refresh")


func _do_queued_refresh() -> void:
	_refresh_queued = false
	if is_inside_tree() and is_visible_in_tree() and _refresh_pending:
		refresh_orders()


func _on_storage_changed(_changes: Dictionary) -> void:
	_queue_refresh()
```

Apply the same code to `ContractPanel`, with `refresh_contracts()` in `_do_queued_refresh()`. Reset `_refresh_queued` in each `_exit_tree()`. Existing `ShopUI.open()` and `ShopUI.select_tab()` remain the forced-refresh boundary and clear pending state through the public refresh methods.

- [ ] **Step 4: Run focused tests and commit**

Run:

```powershell
godot --headless --path . --script res://tests/run_economy_ui_tests.gd
```

Expected: PASS, including existing direct-visible storage refresh tests and the new hidden/reopen tests.

Commit:

```powershell
git add scripts/ui/order_panel.gd scripts/ui/contract_panel.gd tests/test_economy_ui_integration.gd
git commit -m "perf: defer hidden order and contract refresh"
```

### Task 4: Main planting integration regression

**Files:**
- Modify: `tests/test_main_farming_building_integration.gd` near the existing real hoe/plant/water flow
- Verify: `scripts/ui/shop_ui.gd:139-211`

- [ ] **Step 1: Add a real planting regression**

Before planting, ensure the seed selector and shop are closed, capture their current row instance IDs, perform a real controller planting action, and await one frame:

```gdscript
action_controller.select_slot(PlayerActionController.SEED_SLOT)
assertions.truthy(main.seed_selector_panel.select_seed("grain_seed"), "main selects the planting seed")
var selector_row_ids_before := _seed_row_instance_ids(main.seed_selector_panel)
var market_row_ids_before := _meta_child_instance_ids(main.shop_ui.market_panel.item_rows, "item_id")
assertions.truthy(action_controller.perform_cell_action(farm_cell), "main player plants grain")
await tree.process_frame
assertions.equal(
	_seed_row_instance_ids(main.seed_selector_panel),
	selector_row_ids_before,
	"planting does not rebuild the closed seed selector"
)
assertions.equal(
	_meta_child_instance_ids(main.shop_ui.market_panel.item_rows, "item_id"),
	market_row_ids_before,
	"planting does not rebuild the closed economy market"
)
assertions.equal(main.inventory_system.get_item_count("grain_seed"), 98, "planting still consumes one seed")
assertions.truthy(farm_cell.crop_instance != null, "planting still commits the crop immediately")
```

Reuse or add local instance-ID helpers. Do not assert elapsed milliseconds; the test must verify absence of unnecessary work deterministically.

- [ ] **Step 2: Run the Main regression**

Run:

```powershell
godot --headless --path . --script res://tests/run_action_mode_debug_day_regression_tests.gd
```

Expected: PASS. The test also confirms the existing `ShopUI.open()` and `ShopUI.select_tab()` forced-refresh branches keep reopened pages current.

- [ ] **Step 3: Commit the integration regression**

```powershell
git add tests/test_main_farming_building_integration.gd
git commit -m "test: cover planting without hidden UI rebuilds"
```

### Task 5: Final verification

**Files:**
- Verify all files changed in Tasks 1-4

- [ ] **Step 1: Run focused suites**

```powershell
godot --headless --path . --script res://tests/run_seed_selector_panel_tests.gd
godot --headless --path . --script res://tests/run_economy_ui_tests.gd
godot --headless --path . --script res://tests/run_action_mode_debug_day_regression_tests.gd
godot --headless --path . --script res://tests/run_non_grain_seed_planting_tests.gd
```

Expected: every command exits `0` with its PASS summary.

- [ ] **Step 2: Run adjacent farming and maintenance suites**

```powershell
godot --headless --path . --script res://tests/run_farming_system_tests.gd
godot --headless --path . --script res://tests/run_maintenance_integration_tests.gd
```

Expected: no new failures. Compare any known baseline failures with the previously recorded branch baseline rather than attributing them to this patch.

- [ ] **Step 3: Run the core suite and inspect the diff**

```powershell
godot --headless --path . --script res://tests/run_tests.gd
git diff --check
git status --short --branch
```

Expected: `git diff --check` produces no output; the core suite has no failures beyond the three previously reproduced baseline failures; status lists only intentional task changes before the final commit.

- [ ] **Step 4: Commit any final test-only adjustment**

If verification required a test-only correction, commit it separately:

```powershell
git add tests
git commit -m "test: complete planting refresh regression coverage"
```

Do not commit unrelated files or modify the known baseline failures as part of this performance fix.
