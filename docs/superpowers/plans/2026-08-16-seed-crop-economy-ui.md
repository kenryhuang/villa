# Seed, Crop Economy, and UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route seed and crop commerce through their authoritative containers, support atomic mixed-container consumption, and deliver the seed selector plus backpack/farm-storage UI.

**Architecture:** A stateless `ItemContainerRouter` maps explicit `GameData.category` values to either `InventorySystem` or `FarmStorageSystem`. `EconomySystem` owns transaction snapshots and uses the router for market and delivery flows; `ProductionSystem` uses the same router for recipe inputs. UI reads quantities and capacity through public APIs and subscribes to committed events rather than inspecting container fields.

**Tech Stack:** Godot 4.7.1, GDScript, Godot Control scenes, existing economy and UI test runners.

**Prerequisite:** Complete `2026-08-16-seed-crop-lifecycle-core.md` and verify all suites at its Task 8 boundary.

**Design source:** `docs/superpowers/specs/2026-08-16-seed-crop-lifecycle-design.md`, sections 5, 8-10, 13-15.

## Global Constraints

- `seed` routes to the backpack, `crop` routes to farm storage, and all existing categories continue to route to the backpack.
- The router uses `GameData.category`; it never guesses from item IDs.
- A transaction spanning both containers preflights both, snapshots both, and either commits both or restores both.
- The storage tab is read-only for movement: no drag/drop or transfer to backpack.
- Keep existing market prices, liquidity, order generation, recipes, and keyboard shortcuts unless this plan explicitly changes them.

---

### Task 1: Add a typed item-container router

**Files:**
- Create: `scripts/systems/item_container_router.gd`
- Create: `tests/test_item_container_router.gd`
- Modify: `tests/run_economy_system_tests.gd`

**Interfaces:**
- `configure(inventory: InventorySystem, storage: FarmStorageSystem) -> bool`
- `container_kind(item_id: String) -> StringName`
- `get_count(item_id: String) -> int`
- `can_add(items: Dictionary) -> Dictionary`
- `add_items(items: Dictionary) -> bool`
- `can_remove(items: Dictionary) -> Dictionary`
- `remove_items(items: Dictionary) -> bool`
- `snapshot_for(items: Dictionary) -> Dictionary`
- `restore_snapshot(snapshot: Dictionary) -> bool`

- [ ] **Step 1: Write failing routing and mixed-batch tests**

Assert `grain_seed` routes to inventory, `grain` to storage, and `wood` to inventory. Unknown items must return a stable `unknown_item` failure. Test a mixed dictionary such as `{"grain": 2, "wood": 3}` for successful add/remove and for rollback when either destination rejects.

Require structured preflight results:

```gdscript
{
	"ok": false,
	"reason": "storage_capacity",
	"missing_capacity": 2,
	"item_id": "grain",
}
```

Backpack capacity failure uses `inventory_capacity`; missing removals use `insufficient_crop` or `insufficient_seed` for those categories and the existing generic resource failure for other items.

- [ ] **Step 2: Register the test and verify failure**

```powershell
godot --headless --path . --script res://tests/run_economy_system_tests.gd
```

- [ ] **Step 3: Implement normalization, partitioning, and rollback**

Partition a normalized input dictionary once, then call each container's batch preflight. For inventory, use `preflight_add_items()` and a snapshot of slots/mappings; for storage, use its dictionary snapshot. Block `EventBus` during multi-container mutation and emit committed container-specific events only after both mutations succeed.

- [ ] **Step 4: Run and commit**

```powershell
godot --headless --path . --script res://tests/run_economy_system_tests.gd
git add scripts/systems/item_container_router.gd tests/test_item_container_router.gd tests/run_economy_system_tests.gd
git commit -m "feat: route items to authoritative containers"
```

---

### Task 2: Route market purchases and sales atomically

**Files:**
- Modify: `scripts/systems/economy_system.gd`
- Modify: `scripts/main.gd`
- Modify: `tests/test_economy_transactions.gd`
- Modify: `tests/test_market_system.gd`

**Interfaces:**
- Extend `EconomySystem.configure(inventory, wallet, market, npc, router)`.
- Keep `EconomySystem.buy_item(item_id, quantity) -> bool` and `sell_item(item_id, quantity) -> bool` as the public trade commands, now backed by routed transactions.
- Add `get_owned_quantity(item_id: String) -> int` for all economy UI.
- Add `quote_trade_failure(item_id, quantity, is_buy) -> Dictionary` or equivalent stable preflight API.

- [ ] **Step 1: Add failing seed/crop transaction tests**

Test seed buy/sell changes only inventory; crop buy/sell changes only storage. Cover insufficient gold, market stock, inventory full, storage full with exact missing capacity, overloaded storage, insufficient source quantity, market commit failure, container commit failure, and wallet overflow. Every failed path must preserve wallet, market, inventory slots/mappings, and storage items.

- [ ] **Step 2: Verify failures against current inventory-only code**

```powershell
godot --headless --path . --script res://tests/run_economy_system_tests.gd
```

- [ ] **Step 3: Replace direct inventory calls with router transactions**

For buy: preflight market, target container, and wallet; snapshot all three domains; spend gold; commit market; add via router; restore all snapshots on failure. For sell: preflight source and market; remove via router; commit market; add gold; restore all snapshots on failure.

Retain existing market transaction and event blocking behavior. Remove assumptions that all routed containers expose quick-slot mapping transactions.

- [ ] **Step 4: Wire Main and commit**

Instantiate/configure one router after inventory and storage, pass it to `EconomySystem`, and expose it only to systems that need category routing.

```powershell
godot --headless --path . --script res://tests/run_economy_system_tests.gd
godot --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
git add scripts/systems/economy_system.gd scripts/main.gd tests/test_economy_transactions.gd tests/test_market_system.gd
git commit -m "feat: trade seeds and crops from correct storage"
```

---

### Task 3: Route orders, contracts, and production inputs

**Files:**
- Modify: `scripts/systems/economy_system.gd`
- Modify: `scripts/systems/production_system.gd`
- Modify: `scripts/ui/shop_ui.gd`
- Modify: `tests/test_economy_orders.gd`
- Modify: `tests/test_production_system.gd`
- Modify: `tests/test_economy_ui_integration.gd`

**Interfaces:**
- Economy order/contract delivery reads item quantities through `ItemContainerRouter`.
- Production preflight/start/add-input accepts the configured router rather than a caller-selected inventory source.
- Production outputs continue to use their existing output buffers; only player-provided recipe inputs are routed here.

- [ ] **Step 1: Add failing delivery and mixed-recipe tests**

Add a crop order that removes only farm storage and a seed order that removes only inventory. Add a synthetic recipe requiring `grain` plus `wood`; preflight must report both shortages, success removes both, and an injected second-container failure restores both exactly. Verify NPC receipt, reward gold, job state, and events also roll back.

- [ ] **Step 2: Run economy and building suites**

```powershell
godot --headless --path . --script res://tests/run_economy_system_tests.gd
godot --headless --path . --script res://tests/run_building_system_tests.gd
```

- [ ] **Step 3: Implement shared mixed-container transactions**

Replace `_inventory_ref.has_item/remove_item` in `_transfer_player_delivery()` with router preflight/snapshot/remove/restore. Replace production input loops with one router batch operation. Keep maintenance/building-cost spending on existing economy resource routing so crop ingredients also work if a future cost explicitly includes them.

- [ ] **Step 4: Update UI dependencies and commit**

Update `ShopUI.configure()` and order/contract panels to query `EconomySystem.get_owned_quantity()` rather than receiving an inventory solely for ownership counts. Preserve inventory references only where a panel genuinely edits backpack mappings.

```powershell
godot --headless --path . --script res://tests/run_economy_system_tests.gd
godot --headless --path . --script res://tests/run_building_system_tests.gd
godot --headless --path . --script res://tests/run_economy_ui_tests.gd
git add scripts/systems/economy_system.gd scripts/systems/production_system.gd scripts/ui/shop_ui.gd tests/test_economy_orders.gd tests/test_production_system.gd tests/test_economy_ui_integration.gd
git commit -m "feat: consume crop inputs from farm storage"
```

---

### Task 4: Add backpack and farm-storage tabs

**Files:**
- Modify: `scripts/ui/inventory_ui.gd`
- Modify: `scenes/ui/inventory_ui.tscn`
- Create: `tests/test_inventory_storage_ui.gd`
- Modify: `tests/run_main_gameplay_integration_tests.gd`

**Interfaces:**
- Extend `InventoryUI.configure(inventory, farm_storage)`.
- Add `select_tab(tab_id: StringName) -> bool` for `backpack` and `farm_storage`.
- Add read-only storage sorting by name and quantity using the existing UI sort convention where available.

- [ ] **Step 1: Write failing scene and behavior tests**

Assert the scene has a two-option tab control, backpack grid/quick bar remain present, storage rows show crop name and quantity, and capacity text displays `used / total`. Assert overload applies a warning style and text, storage events refresh an open storage tab, and storage rows cannot be assigned to quick slots or dragged into the backpack.

- [ ] **Step 2: Run main integration tests and verify missing nodes**

```powershell
godot --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
```

- [ ] **Step 3: Build the tabbed inventory scene**

Use a compact `TabBar` or two-option tab container at the top of the existing centered panel. Keep the current backpack grid and quick bar under the backpack content node. Add an unframed storage content node with capacity header, sort menu, and scrollable crop rows. Do not create cards inside the panel.

Connect `item_added/item_removed` only to backpack refresh and farm-storage signals only to storage refresh. Preserve the currently selected tab across refreshes and while reopening during the same session.

- [ ] **Step 4: Run UI and viewport checks**

```powershell
godot --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
godot --headless --path . --script res://tests/run_economy_ui_responsive_tests.gd
```

Expected: no clipped tabs, rows, capacity label, or quick-bar text in existing desktop/mobile fixtures.

- [ ] **Step 5: Commit**

```powershell
git add scripts/ui/inventory_ui.gd scenes/ui/inventory_ui.tscn tests/test_inventory_storage_ui.gd tests/run_main_gameplay_integration_tests.gd
git commit -m "feat: add farm storage inventory tab"
```

---

### Task 5: Add the dedicated seed selector

**Files:**
- Create: `scripts/ui/seed_selector_panel.gd`
- Create: `scenes/ui/seed_selector_panel.tscn`
- Modify: `scripts/ui/hud.gd`
- Modify: `scenes/ui/hud.tscn`
- Modify: `scripts/actors/player_action_controller.gd`
- Modify: `scripts/main.gd`
- Create: `tests/test_seed_selector_panel.gd`
- Modify: `tests/test_hud_action_bar.gd`
- Modify: `tests/run_main_gameplay_integration_tests.gd`

**Interfaces:**
- `SeedSelectorPanel.configure(inventory, farming, action_controller) -> bool`.
- `open_for_cell(cell: GridCell = null) -> void` and `select_seed(plant_item_id: String) -> bool`.
- Controller signal `seed_selection_requested(cell)` and persisted session selection `selected_plant_item_id`.

- [ ] **Step 1: Add failing selector tests**

Assert only owned positive-quantity `seed` items appear; each maps through `CropData.plant_item_id`; rows display icon/name, quantity, first growth days, seasons, and environment. For a target cell, incompatible seeds remain visible but selection confirmation is disabled with `wrong_season`, `greenhouse_required`, or other stable reason.

Assert selecting does not move or consume an item. The HUD seed slot must show the selected seed icon and total backpack quantity, update when quantity changes, and retain the selected ID after its count reaches zero so the panel can explain `no_seed` until another seed is selected.

- [ ] **Step 2: Run HUD/main tests and verify failure**

```powershell
godot --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
```

- [ ] **Step 3: Implement selection independent of quick-slot mappings**

Make slot 6 the planting mode command, not a pointer to a backpack slot index. Opening planting mode requests the selector; controller planting reads `selected_plant_item_id` and revalidates ownership/mapping/environment on every action. Migrate an existing quick-slot 6 seed mapping into initial selection at startup/load, then clear that obsolete mapping without disturbing slots 1-5.

- [ ] **Step 4: Build and wire the panel**

Use a modal panel with one scrollable list and compact metadata columns. Use an icon button to close and a clear confirmation command. Connect through Main; keep keyboard focus and topmost Escape behavior consistent with existing economy modals.

- [ ] **Step 5: Run and commit**

```powershell
godot --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
godot --headless --path . --script res://tests/run_economy_ui_responsive_tests.gd
git add scripts/ui/seed_selector_panel.gd scenes/ui/seed_selector_panel.tscn scripts/ui/hud.gd scenes/ui/hud.tscn scripts/actors/player_action_controller.gd scripts/main.gd tests/test_seed_selector_panel.gd tests/test_hud_action_bar.gd tests/run_main_gameplay_integration_tests.gd
git commit -m "feat: add dedicated seed selector"
```

---

### Task 6: Make market UI storage-aware

**Files:**
- Modify: `scripts/ui/market_panel.gd`
- Modify: `scripts/ui/trade_panel.gd`
- Modify: `scripts/ui/shop_ui.gd`
- Modify: `tests/test_market_ui.gd`
- Modify: `tests/test_economy_ui_integration.gd`

**Interfaces:**
- Market rows and sorting read `EconomySystem.get_owned_quantity(item_id)`.
- Trade confirmation reads the economy preflight result and displays its stable localized reason.

- [ ] **Step 1: Add failing ownership and feedback tests**

Create fixtures where the backpack has zero grain but storage has grain, and the backpack has seeds while storage has none. Assert row ownership, `owned_quantity` sort, detail drawer, sell maximum, and button enablement all use the correct container. Test exact capacity shortage feedback and overloaded storage purchase rejection.

- [ ] **Step 2: Run economy UI suite and verify current inventory reads fail**

```powershell
godot --headless --path . --script res://tests/run_economy_ui_tests.gd
```

- [ ] **Step 3: Replace UI ownership reads**

Remove direct calls to `inventory_ref.get_item_count()` from market/trade ownership display and sorting. Keep direct inventory access only for unrelated inventory-specific interactions. Map stable reasons to concise Chinese feedback, including the exact `missing_capacity` value for storage failures.

- [ ] **Step 4: Run UI suites and commit**

```powershell
godot --headless --path . --script res://tests/run_economy_ui_tests.gd
godot --headless --path . --script res://tests/run_economy_ui_responsive_tests.gd
git add scripts/ui/market_panel.gd scripts/ui/trade_panel.gd scripts/ui/shop_ui.gd tests/test_market_ui.gd tests/test_economy_ui_integration.gd
git commit -m "feat: show routed crop holdings in market"
```

---

### Task 7: Verify economy and UI end to end

- [ ] **Step 1: Run all affected suites**

```powershell
godot --headless --path . --script res://tests/run_economy_system_tests.gd
godot --headless --path . --script res://tests/run_economy_save_integration_tests.gd
godot --headless --path . --script res://tests/run_building_system_tests.gd
godot --headless --path . --script res://tests/run_economy_ui_tests.gd
godot --headless --path . --script res://tests/run_economy_ui_responsive_tests.gd
godot --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
```

- [ ] **Step 2: Perform one headless-to-interactive smoke setup**

Start the project, then verify this flow in a temporary save: buy a seed, select it, plant and grow a crop, harvest into storage, view it in the storage tab, sell it from market, fill storage to block harvest, then remove an item and harvest successfully. Also verify a crop order and a crop production input reduce storage.

Record failures as tests before fixing them. Do not change the approved rules during smoke fixes.

- [ ] **Step 3: Inspect and commit any test-backed integration fixes**

```powershell
git diff --check
git status --short
```

Expected: only intentional changes plus pre-existing `tmp/`. Commit any smoke fix separately with a behavior-specific message.

- [ ] **Step 4: Proceed to art implementation**

Execute `docs/superpowers/plans/2026-08-16-all-crop-growth-art.md` after all six suites exit 0.
