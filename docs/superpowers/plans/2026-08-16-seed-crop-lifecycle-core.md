# Seed and Crop Lifecycle Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement authoritative crop metadata, lifecycle states, central farm storage, atomic planting/harvesting, barn-derived capacity, and lossless save migration.

**Architecture:** `CropData` owns explicit planting and lifecycle metadata, `CropInstance` owns persisted state, and `FarmingSystem` owns all environment transitions and deterministic harvest previews. `FarmStorageSystem` owns crop quantities and derives capacity from completed barns plus authoritative upgrade records. `PlayerActionController` coordinates backpack seeds, storage capacity, and farming commits without allowing partial mutation.

**Tech Stack:** Godot 4.7.1, GDScript, JSON save data, existing script-based test runners.

**Design source:** `docs/superpowers/specs/2026-08-16-seed-crop-lifecycle-design.md`

**Next plans:** After this plan, execute `2026-08-16-seed-crop-economy-ui.md`, then `2026-08-16-all-crop-growth-art.md`.

## Global Constraints

- Keep seeds, tools, and non-crop items in `InventorySystem`; store only explicit `category == "crop"` items in `FarmStorageSystem`.
- Never infer crop IDs from `_seed` or `_sapling` suffixes.
- All batch storage operations and planting/harvest coordination are all-or-nothing.
- Capacity loss never deletes stored crops. An overloaded storage can remove items but cannot add items.
- Do not add seed returns, seed makers, drought death, extra recipes, or distributed barn inventories.
- Keep `tmp/` and other unrelated worktree changes untouched.

---

### Task 1: Make crop planting and lifecycle metadata explicit

**Files:**
- Modify: `scripts/data/crop_data.gd`
- Modify: `scripts/core/game_data.gd`
- Modify: `scripts/main.gd`
- Modify: `tests/test_crop_economy.gd`

**Interfaces:**
- Add `CropData.plant_item_id: String`.
- Add `CropData.environment: String`, accepting `outdoor_or_greenhouse` and `greenhouse_only`.
- Add `CropData.lifecycle_type: String`, accepting `annual`, `annual_regrow`, `bush`, `tree`, and `vine`.
- Add `GameData.get_crop_for_plant_item(item_id: String) -> CropData` and reject duplicate mappings during registration.

- [ ] **Step 1: Add failing metadata matrix tests**

Extend `tests/test_crop_economy.gd` with the exact 15-row matrix from design section 4. For every row, assert the crop exists, `plant_item_id`, lifecycle, environment, seasons, growth days, yield, and regrow days match; assert the planting item is `seed`, the crop product is `crop`, and `GameData.get_crop_for_plant_item()` returns exactly that crop.

Also assert unknown IDs return `null`, and registering a second crop with the same `plant_item_id` fails without replacing the original mapping.

- [ ] **Step 2: Run the focused suite and verify failure**

```powershell
godot --headless --path . --script res://tests/run_farming_system_tests.gd
```

Expected: failures mention missing `plant_item_id`, `environment`, `lifecycle_type`, and planting-item lookup.

- [ ] **Step 3: Implement validated fields and lookup**

In `CropData.is_valid()`, require non-empty IDs, accepted enum strings, a positive growth duration, valid yields, non-negative regrow days, and consistency rules:

```gdscript
const ENVIRONMENTS := [&"outdoor_or_greenhouse", &"greenhouse_only"]
const LIFECYCLE_TYPES := [&"annual", &"annual_regrow", &"bush", &"tree", &"vine"]

if plant_item_id.is_empty() or environment not in ENVIRONMENTS:
	return false
if lifecycle_type not in LIFECYCLE_TYPES:
	return false
if lifecycle_type == "annual" and regrow_days != 0:
	return false
if lifecycle_type != "annual" and regrow_days <= 0:
	return false
```

Replace `form`/tag-derived behavior in `Main.default_crop_definitions()` with explicit values from the design matrix. Keep `growth_form` only as a temporary compatibility mirror if old tests or scenes still read it; all new rules must read `lifecycle_type` and `environment`.

- [ ] **Step 4: Delete suffix-based business rules**

Add the planting lookup to `GameData`, maintain it when crops register, and replace every production call to `PlayerActionController.crop_id_for_plant_item()` with the explicit lookup. Remove the static suffix-trimming helper after tests no longer reference it.

- [ ] **Step 5: Run tests and commit**

```powershell
godot --headless --path . --script res://tests/run_farming_system_tests.gd
git add scripts/data/crop_data.gd scripts/core/game_data.gd scripts/main.gd tests/test_crop_economy.gd
git commit -m "feat: define explicit crop lifecycle metadata"
```

Expected: farming suite exits 0.

---

### Task 2: Add the authoritative central farm storage

**Files:**
- Create: `scripts/systems/farm_storage_system.gd`
- Create: `tests/test_farm_storage_system.gd`
- Modify: `tests/run_farming_system_tests.gd`
- Modify: `scripts/core/event_bus.gd`

**Interfaces:**
- `configure(capacity_provider: Callable = Callable()) -> bool`
- `get_count(item_id: String) -> int`
- `get_items() -> Dictionary`
- `get_used_capacity() -> int`
- `get_total_capacity() -> int`
- `get_missing_capacity(items: Dictionary) -> int`
- `can_add(items: Dictionary) -> bool`, `add_items(items: Dictionary) -> bool`
- `can_remove(items: Dictionary) -> bool`, `remove_items(items: Dictionary) -> bool`
- `to_dict() -> Dictionary`, `validate_dict(data: Dictionary) -> bool`, `from_dict(data: Dictionary) -> bool`
- `restore_items_unchecked(items: Dictionary) -> bool` for validated save load and migration only.

- [ ] **Step 1: Write failing storage contract tests**

Cover empty state, quantities, used capacity, batch add/remove, exact missing capacity, rejection without partial mutation, invalid quantities, unknown IDs, non-crop IDs, serialization, and restoration above current capacity. Use a mutable test capacity provider so tests can lower capacity after adding items.

Required overload assertions:

```gdscript
capacity.value = 2
assertions.truthy(storage.restore_items_unchecked({"grain": 3}))
assertions.equal(storage.get_used_capacity(), 3)
assertions.truthy(not storage.can_add({"grain": 1}))
assertions.truthy(storage.remove_items({"grain": 1}))
assertions.equal(storage.get_used_capacity(), 2)
```

- [ ] **Step 2: Register the test and verify it fails to preload**

Add `TestFarmStorageSystem` to `tests/run_farming_system_tests.gd`, then run the farming suite. Expected: missing script/preload failure.

- [ ] **Step 3: Implement storage normalization and atomic mutation**

Normalize all dictionaries before mutation. Reject floats, booleans, values outside the safe integer range, zero/negative quantities, unknown items, and non-crop categories. Calculate capacity against the entire requested dictionary before changing `items`.

Emit only after successful commits:

```gdscript
signal contents_changed(changes: Dictionary)
signal capacity_changed(used: int, total: int)
```

Add equivalent `farm_storage_changed(changes)` and `farm_storage_capacity_changed(used, total)` signals to `EventBus`; do not emit them on failed operations.

- [ ] **Step 4: Run tests and commit**

```powershell
godot --headless --path . --script res://tests/run_farming_system_tests.gd
git add scripts/systems/farm_storage_system.gd scripts/core/event_bus.gd tests/test_farm_storage_system.gd tests/run_farming_system_tests.gd
git commit -m "feat: add central farm storage"
```

---

### Task 3: Persist crop lifecycle state

**Files:**
- Modify: `scripts/data/crop_instance.gd`
- Modify: `scripts/systems/grid_system.gd`
- Modify: `tests/test_crop_economy.gd`
- Modify: `tests/test_grid_system.gd`

**Interfaces:**
- Add `CropInstance.LifecycleState { GROWING, MATURE, DORMANT, WITHERED }`.
- Add `set_lifecycle_state(next_state: int) -> bool` and `derive_active_state() -> int`.
- Persist `lifecycle_state` in `to_dict()` / `from_dict()`.

- [ ] **Step 1: Add failing state and save tests**

Assert new plants start `GROWING`; reaching `growth_days` sets `MATURE`; mature progress no longer advances; dormant and withered instances do not advance; `derive_active_state()` returns growing/mature based on retained progress; all four states round-trip; invalid state values reject the entire grid dictionary.

Add a legacy crop fixture without `lifecycle_state`; it must be accepted only through save migration, not silently guessed by `CropInstance.from_dict()`.

- [ ] **Step 2: Run grid and farming suites and verify failures**

```powershell
godot --headless --path . --script res://tests/run_grid_system_tests.gd
godot --headless --path . --script res://tests/run_farming_system_tests.gd
```

- [ ] **Step 3: Implement the state machine at the instance boundary**

Make `advance_growth()` return whether the visual stage or lifecycle changed. It may run only in `GROWING`; clamp progress; transition to `MATURE`; leave `is_watered_today` reset to the daily coordinator. Update `is_mature()` to read the state, not only progress.

Increment the grid serialization version. Keep version conversion in `SaveManager`, so `GridSystem.validate_dict()` validates only its current canonical format.

- [ ] **Step 4: Run tests and commit**

```powershell
godot --headless --path . --script res://tests/run_grid_system_tests.gd
godot --headless --path . --script res://tests/run_farming_system_tests.gd
git add scripts/data/crop_instance.gd scripts/systems/grid_system.gd tests/test_crop_economy.gd tests/test_grid_system.gd
git commit -m "feat: persist crop lifecycle states"
```

---

### Task 4: Move environment rules and harvest previews into FarmingSystem

**Files:**
- Modify: `scripts/systems/farming_system.gd`
- Modify: `scripts/systems/grid_system.gd`
- Modify: `scripts/systems/production_system.gd`
- Modify: `scripts/main.gd`
- Modify: `tests/test_farming_system.gd`
- Modify: `tests/test_farming_system_complete.gd`
- Modify: `tests/test_crop_economy.gd`
- Modify: `tests/test_production_system.gd`

**Interfaces:**
- `preview_plant(cell, plant_item_id) -> Dictionary` with `ok`, `reason`, and `crop_data`.
- `preview_harvest(cell) -> Dictionary` with deterministic items, exp, post-progress, post-lifecycle, and post-cell-state.
- `commit_harvest(cell, preview) -> Dictionary` rejects stale previews.
- `set_greenhouse_cells(cells, paused_cells := []) -> void` distinguishes active and maintenance-paused coverage.
- `clear_withered(cell) -> bool` clears without output.

- [ ] **Step 1: Write failing lifecycle transition tests**

Cover all stable planting reasons, `+1.0` dry and `+1.5` watered growth, mature stability, annual/annual-regrow withering, bush/tree/vine dormancy and restoration, greenhouse-only rejection, greenhouse maintenance freeze with mature harvest allowed, greenhouse demolition re-evaluation, and withered clearing.

Add a deterministic preview test that calls preview twice before commit and after a capacity-like rejection; dictionaries must be byte-for-byte equal and `harvest_count` unchanged.

- [ ] **Step 2: Run and observe state-rule failures**

```powershell
godot --headless --path . --script res://tests/run_farming_system_tests.gd
```

- [ ] **Step 3: Implement transitions before daily growth**

For each planted cell, first determine active greenhouse, paused greenhouse, or outdoor status. Apply environment transition before granting progress. Paused greenhouse cells keep their current state and progress, while mature crops remain harvestable. Reset watering after the daily decision.

Expose both completed greenhouse coverage and maintenance-paused coverage from `ProductionSystem`. In `Main`, refresh both sets after building registration, maintenance changes, construction completion, demolition, and save restore; pass them together to `FarmingSystem.set_greenhouse_cells()`. Keep connected-waterwheel auto-watering limited to active greenhouses.

Use stage 2 for dormant visuals. Add one shared visual-state modulate path for dormant and withered states; do not create extra bitmap paths. Ensure a mature crop rejected by the caller remains visually mature.

- [ ] **Step 4: Make GridSystem a mutation primitive**

Remove public harvest-rule ownership from `GridSystem.preview_harvest()` and `harvest_crop()`. Add narrow snapshot/apply helpers used by `FarmingSystem.commit_harvest()` so the preview contains every post-state value and stale state is detectable before mutation.

- [ ] **Step 5: Run tests and commit**

```powershell
godot --headless --path . --script res://tests/run_grid_system_tests.gd
godot --headless --path . --script res://tests/run_farming_system_tests.gd
git add scripts/systems/farming_system.gd scripts/systems/grid_system.gd scripts/systems/production_system.gd scripts/main.gd tests/test_farming_system.gd tests/test_farming_system_complete.gd tests/test_crop_economy.gd tests/test_production_system.gd
git commit -m "feat: implement crop environment lifecycle"
```

---

### Task 5: Make planting and harvest storage transactions atomic

**Files:**
- Modify: `scripts/actors/player_action_controller.gd`
- Modify: `scripts/main.gd`
- Modify: `tests/test_player_action_controller.gd`
- Modify: `tests/test_crop_economy.gd`

**Interfaces:**
- Extend `PlayerActionController.configure(..., inventory, farm_storage)`.
- Add `selected_plant_item_id` accessors for the later seed panel.
- Return or expose stable action failure details including `storage_capacity` and `missing_capacity`.

- [ ] **Step 1: Replace harvest doubles with storage-aware failing tests**

Update controller fixtures so planting still consumes the backpack, while harvest targets `FarmStorageSystem`. Assert full storage prevents the farming commit, experience, events, and visual mutation. Inject a storage `add_items()` failure after successful preflight and assert storage and crop snapshots both restore exactly.

- [ ] **Step 2: Verify existing inventory-harvest assumptions fail**

Run the farming suite. Expected: tests still find harvest products in the backpack or the configure signature lacks farm storage.

- [ ] **Step 3: Implement preview, preflight, commit, rollback**

Plant sequence: farming preview, inventory snapshot, remove one selected explicit planting item, create crop, rollback inventory on failure, then emit committed signals.

Harvest sequence:

```text
preview = farming.preview_harvest(cell)
storage.can_add(preview.items)
snapshot storage and crop
storage.add_items(preview.items)
farming.commit_harvest(cell, preview)
rollback both if either commit fails
award exp and emit success only after both commit
```

Do not use `InventorySystem` mapping/event transactions for crop outputs. Keep backpack event behavior for planting seeds.

- [ ] **Step 4: Wire Main and run tests**

Instantiate `FarmStorageSystem` before controller setup, add it to `farm_storage_system`, and pass it to the controller. Do not yet change market or UI wiring; that is the next plan.

```powershell
godot --headless --path . --script res://tests/run_farming_system_tests.gd
godot --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
git add scripts/actors/player_action_controller.gd scripts/main.gd tests/test_player_action_controller.gd tests/test_crop_economy.gd
git commit -m "feat: harvest crops into farm storage"
```

---

### Task 6: Derive storage capacity from completed barns and upgrades

**Files:**
- Modify: `scripts/core/game_data.gd`
- Modify: `scripts/systems/economy_progression_system.gd`
- Modify: `scripts/systems/production_system.gd`
- Modify: `scripts/main.gd`
- Modify: `tests/test_farm_storage_system.gd`
- Modify: `tests/test_economy_progression.gd`
- Modify: `tests/test_production_system.gd`

**Interfaces:**
- `Main._farm_storage_capacity() -> int` computes `200 + completed_barns * 200 + storage_levels * 100`.
- `FarmStorageSystem.refresh_capacity() -> void` emits only when derived capacity changes.
- Barn `storage` upgrades remain capped at level 3 and no longer alter producer output capacity.

- [ ] **Step 1: Add failing capacity formula tests**

Cover no barn, under-construction barn, completed barn, levels 1-3, multiple barns, maintenance pause, demolition, and demolition into overload. Assert each upgrade contributes exactly 100 and each completed barn exactly 200.

- [ ] **Step 2: Update barn definition and progression text**

Change barn description/effect from backpack expansion to central storage. Keep collection radius behavior under an explicit collection key instead of using `inventory_expand` as an implicit capacity effect. In `EconomyProgressionSystem.get_upgrade_quote()`, return `中央仓库容量 +100` for barn storage upgrades; other buildings keep existing output capacity text.

- [ ] **Step 3: Refresh on authoritative events**

Connect refresh to construction completion, building removal, and committed `building_upgrade_changed`. Ensure removal refresh occurs while the removed building's upgrade record is still readable or pass a computed post-removal total; then clear its upgrade record. Maintenance changes must not affect capacity.

- [ ] **Step 4: Run building and farming suites and commit**

```powershell
godot --headless --path . --script res://tests/run_building_system_tests.gd
godot --headless --path . --script res://tests/run_farming_system_tests.gd
git add scripts/core/game_data.gd scripts/systems/economy_progression_system.gd scripts/systems/production_system.gd scripts/main.gd tests/test_farm_storage_system.gd tests/test_economy_progression.gd tests/test_production_system.gd
git commit -m "feat: derive farm storage capacity from barns"
```

---

### Task 7: Save, validate, and migrate storage and crop states

**Files:**
- Modify: `scripts/core/save_manager.gd`
- Modify: `scripts/main.gd`
- Modify: `tests/test_economy_save_integration.gd`
- Modify: `tests/test_crop_economy.gd`

**Interfaces:**
- Add canonical `farm_storage: {items: Dictionary}` save section.
- Save only storage quantities; capacity remains derived.
- Increment the canonical save/grid version used for lifecycle state.

- [ ] **Step 1: Add failing canonical and legacy save fixtures**

Test current-format round trip, overloaded storage round trip, invalid quantity/category/state rejection with complete rollback, and these legacy cases: crops move from backpack slots into storage, seeds and other items stay in original relative slots, invalid quick mappings are normalized, over-capacity crops are retained, and lifecycle states are derived after greenhouse/building restoration.

- [ ] **Step 2: Verify save integration fails**

```powershell
godot --headless --path . --script res://tests/run_economy_save_integration_tests.gd
```

- [ ] **Step 3: Implement migration as a temporary canonical dictionary**

Migration order must be encoded and tested:

1. Validate the legacy structure.
2. Canonicalize buildings, upgrades, greenhouse coverage, and grid records in temporary dictionaries.
3. Compute capacity context without mutating runtime nodes.
4. Remove crop-category backpack slots into a temporary `farm_storage.items` dictionary.
5. Preserve seeds/other slots and normalize quick mappings.
6. Derive every legacy crop lifecycle from progress, season, environment, and restored greenhouse state.
7. Validate the complete canonical dictionary.
8. Apply it through existing rollback-aware `_apply_save_data()`.

Never call capacity-limited `add_items()` during restore; call validated `restore_items_unchecked()` so overload is preserved.

- [ ] **Step 4: Configure SaveManager and run regression suites**

Pass the storage reference through `SaveManager.configure_economy()`, gather it, validate it, and restore it before UI refresh. Run:

```powershell
godot --headless --path . --script res://tests/run_economy_save_integration_tests.gd
godot --headless --path . --script res://tests/run_grid_system_tests.gd
godot --headless --path . --script res://tests/run_farming_system_tests.gd
godot --headless --path . --script res://tests/run_building_system_tests.gd
godot --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: every command exits 0 and rejected saves leave the pre-load snapshot unchanged.

- [ ] **Step 5: Commit core lifecycle work**

```powershell
git add scripts/core/save_manager.gd scripts/main.gd tests/test_economy_save_integration.gd tests/test_crop_economy.gd
git commit -m "feat: migrate crop inventory into farm storage"
```

---

### Task 8: Verify the core plan boundary

- [ ] **Step 1: Run all affected suites from a clean process**

```powershell
godot --headless --path . --script res://tests/run_grid_system_tests.gd
godot --headless --path . --script res://tests/run_farming_system_tests.gd
godot --headless --path . --script res://tests/run_economy_save_integration_tests.gd
godot --headless --path . --script res://tests/run_building_system_tests.gd
godot --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
```

- [ ] **Step 2: Inspect scope and state**

```powershell
git diff --check
git status --short
git log -8 --oneline
```

Expected: no whitespace errors; only intentional tracked changes and the pre-existing untracked `tmp/`; commits correspond to Tasks 1-7.

- [ ] **Step 3: Proceed to economy and UI plan**

Execute `docs/superpowers/plans/2026-08-16-seed-crop-economy-ui.md`. Do not start bulk crop art until its UI and transaction regression suites pass.
