# Production Chain Connection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect manual gathering, all 17 buildings, every registered recipe, construction, production storage, blueprint navigation, and market-facing inventory into one reachable gameplay chain.

**Architecture:** Keep `InventorySystem`, `BuildingSystem`, `ProductionSystem`, and `EconomyProgressionSystem` authoritative. Add a read-only `BuildingCatalog` for stable categories and palette entries, make build availability a single `BuildingSystem` diagnostic, and route locked buildings/recipes to the existing service panel. Extend existing gathering, recipe, save, and indicator paths without adding input warehouses or logistics simulation.

**Tech Stack:** Godot 4.7.1, typed GDScript, `.tscn` UI scenes, project-local headless test runners, Git.

**Design reference:** `docs/superpowers/specs/2026-08-06-production-chain-connection-design.md`

---

## File map

- `scripts/core/game_data.gd` — authoritative building metadata and final construction costs.
- `scripts/core/building_catalog.gd` — stable categories/order and read-only palette queries.
- `scripts/data/building_data.gd` — runtime projection of static building metadata.
- `scripts/core/recipe_database.gd` — reachable production recipes and corrected station IDs.
- `scripts/systems/economy_progression_system.gd` — all blueprint/recipe services, lock details, and migration.
- `scripts/systems/building_system.gd` — unified blueprint/resource availability preflight and preview guard.
- `scripts/actors/player_action_controller.gd` — category-aware building selection and Q/E category cycling.
- `scripts/ui/action_palette_button.gd` — distinct ready/missing/locked/invalid visual states.
- `scripts/ui/hud.gd`, `scenes/ui/hud.tscn` — categorized build palette, lock detail, and unlock signal.
- `scripts/ui/build_ui.gd` — legacy full build menu backed by the same catalog and availability result.
- `scripts/ui/service_panel.gd`, `scripts/ui/shop_ui.gd`, `scripts/main.gd` — service deep links for buildings and recipes.
- `scripts/world/resource_catalog.gd`, `scripts/world/world.gd`, `scripts/world/tree_instance.gd` — clay, sand, and renewable fiber supply.
- `scripts/buildings/building_instance.gd`, `scripts/systems/production_system.gd` — world output/full/maintenance indicators.
- `scripts/ui/building_production_panel.gd`, `scripts/ui/building_economy_ui.gd` — locked-recipe navigation.
- `scripts/core/save_manager.gd` — post-load placed-building blueprint reconciliation.
- `tests/test_building_catalog.gd` — catalog, cost, item-reference, and dependency-closure tests.
- Existing building/economy/resource/UI/save tests — behavior and regression coverage.

## Task 1: Create the authoritative building catalog and construction ladder

**Files:**
- Create: `scripts/core/building_catalog.gd`
- Create: `tests/test_building_catalog.gd`
- Modify: `scripts/core/game_data.gd`
- Modify: `scripts/data/building_data.gd`
- Modify: `tests/run_building_system_tests.gd`

- [x] **Step 1: Write the failing catalog tests**

Add `BuildingCatalogTest.run()` assertions that:

```gdscript
const EXPECTED_CATEGORIES := ["basic", "production", "farming", "resource", "decoration"]
const EXPECTED_IDS := [
    "workbench", "stone_kiln", "barn", "well",
    "windmill", "furnace", "food_workshop", "textile_machine",
    "chicken_coop", "beehive", "greenhouse", "waterwheel",
    "lumberyard", "quarry", "mine", "lamp", "fence",
]

func run(assertions) -> void:
    assertions.equal(BuildingCatalog.categories(), EXPECTED_CATEGORIES, "catalog exposes stable categories")
    var ids := BuildingCatalog.all_building_ids()
    assertions.equal(ids.size(), 17, "catalog exposes all buildings")
    assertions.equal(ids, EXPECTED_IDS, "catalog order is stable")
    var seen := {}
    for building_id in ids:
        assertions.truthy(not seen.has(building_id), "%s appears once" % building_id)
        seen[building_id] = true
        var source := GameData.get_building(building_id)
        assertions.truthy(source.has("category"), "%s has category" % building_id)
        assertions.truthy(source.has("palette_order"), "%s has palette order" % building_id)
        for item_id in source.cost:
            assertions.truthy(GameData.get_item(item_id) != null, "%s cost item exists" % item_id)
            assertions.truthy(int(source.cost[item_id]) > 0, "%s cost is positive" % item_id)
            assertions.truthy(item_id != "iron", "%s does not use legacy iron" % building_id)
```

Register the test in `tests/run_building_system_tests.gd` immediately after `BuildingDataTest`.

- [x] **Step 2: Run the focused suite and verify RED**

Run:

```powershell
godot --headless --path . --script res://tests/run_building_system_tests.gd
```

Expected: FAIL because `building_catalog.gd`, category metadata, and the new cost ladder do not exist.

- [x] **Step 3: Implement catalog metadata and exact costs**

Create `BuildingCatalog` as a stateless helper:

```gdscript
class_name BuildingCatalog
extends RefCounted

const GameDataScript = preload("res://scripts/core/game_data.gd")
const CATEGORY_ORDER := ["basic", "production", "farming", "resource", "decoration"]

static func categories() -> Array[String]:
    return CATEGORY_ORDER.duplicate()

static func building_ids_for_category(category_id: String) -> Array[String]:
    var rows: Array[Dictionary] = []
    for source in GameDataScript.get_all_buildings():
        if str(source.get("category", "basic")) == category_id:
            rows.append(source)
    rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        var order_delta := int(a.get("palette_order", 0)) - int(b.get("palette_order", 0))
        return str(a.id) < str(b.id) if order_delta == 0 else order_delta < 0
    )
    var ids: Array[String] = []
    for row in rows:
        ids.append(str(row.id))
    return ids

static func all_building_ids() -> Array[String]:
    var ids: Array[String] = []
    for category_id in CATEGORY_ORDER:
        ids.append_array(building_ids_for_category(category_id))
    return ids
```

Add `category` and `palette_order` to all 17 `GameData.BUILDINGS` entries. Replace construction costs with the exact section 8 table from the design, including `lamp: {"lamp": 1, "plank": 1}` and no `iron` references. Add matching exported fields to `BuildingData` and populate them in `from_dictionary()`.

- [x] **Step 4: Run catalog and building suites GREEN**

Run the focused building runner. Expected: PASS and exactly 17 catalog IDs.

- [x] **Step 5: Commit**

```powershell
git add scripts/core/building_catalog.gd scripts/core/game_data.gd scripts/data/building_data.gd tests/test_building_catalog.gd tests/run_building_system_tests.gd
git commit -m "feat: add complete building catalog and cost ladder"
```

## Task 2: Close recipe and item-source gaps

**Files:**
- Modify: `scripts/core/recipe_database.gd`
- Modify: `tests/test_recipe_database.gd`
- Modify: `tests/test_building_catalog.gd`

- [x] **Step 1: Write failing recipe reachability tests**

Add assertions for:

```gdscript
assertions.equal(RecipeDatabase.get_recipe("bread").station, "food_workshop", "bread has a real station")
assertions.equal(RecipeDatabase.get_recipe("honey_cake").station, "food_workshop", "cake has a real station")
assertions.equal(RecipeDatabase.get_recipe("glass_jar").outputs, {"glass_jar": 2}, "jar recipe exists")
assertions.equal(RecipeDatabase.get_recipe("glass_bottle").outputs, {"glass_bottle": 2}, "bottle recipe exists")
for recipe in RecipeDatabase.get_all_recipes():
    assertions.truthy(not GameData.get_building(str(recipe.station)).is_empty(), "%s station exists" % recipe.id)
    for item_id in recipe.inputs.keys() + recipe.outputs.keys():
        assertions.truthy(GameData.get_item(str(item_id)) != null, "%s item exists" % item_id)
```

Add a source closure in `test_building_catalog.gd` starting with `wood`, `fiber`, `stone`, `clay`, `sand`, `coal`, all ores, crops, honey, beeswax, egg, feather, and market-only `salt`; repeatedly add recipe outputs whose inputs are available, then assert every recipe output becomes available.

- [x] **Step 2: Run economy tests and verify RED**

Run:

```powershell
godot --headless --path . --script res://tests/run_economy_system_tests.gd
```

Expected: FAIL for the absent container recipes and orphan `kitchen` station.

- [x] **Step 3: Implement the minimal recipe fixes**

Add:

```gdscript
"glass_jar": _recipe("glass_jar", "玻璃罐", "furnace", {"glass": 1}, {"glass_jar": 2}, 120, 1),
"glass_bottle": _recipe("glass_bottle", "玻璃瓶", "furnace", {"glass": 1}, {"glass_bottle": 2}, 120, 1),
```

Change `bread` and `honey_cake` station IDs to `food_workshop`. Do not change their inputs, outputs, duration, or tiers.

- [x] **Step 4: Run recipe, building, and economy runners GREEN**

Expected: all item/station/source assertions pass.

- [x] **Step 5: Commit**

```powershell
git add scripts/core/recipe_database.gd tests/test_recipe_database.gd tests/test_building_catalog.gd
git commit -m "feat: close production recipe gaps"
```

## Task 3: Make every blueprint and recipe unlockable, with save migration

**Files:**
- Modify: `scripts/systems/economy_progression_system.gd`
- Modify: `scripts/core/save_manager.gd`
- Modify: `tests/test_economy_progression.gd`
- Modify: `tests/test_economy_save_integration.gd`

- [x] **Step 1: Write failing progression and migration tests**

Cover:

```gdscript
assertions.equal(progression.get_blueprint_service_id("lumberyard"), "blueprint_lumberyard", "lumberyard service is addressable")
assertions.equal(progression.get_blueprint_service_id("food_workshop"), "blueprint_food_workshop", "food workshop service is addressable")
assertions.equal(progression.get_recipe_service_id("machine_parts"), "recipe_machine_parts", "machine parts service is addressable")
for building_id in BuildingCatalog.all_building_ids():
    assertions.truthy(progression.is_blueprint_managed(building_id), "%s has explicit progression" % building_id)
for recipe in RecipeDatabase.get_all_recipes():
    assertions.truthy(progression.can_eventually_unlock_recipe(str(recipe.id)), "%s is reachable" % recipe.id)
```

Add a version-1 fixture to `test_economy_save_integration.gd` with an already placed `lumberyard`, then assert loading succeeds and the new progression state unlocks `lumberyard` without resetting inventory, buildings, or queues.

- [x] **Step 2: Run progression/save tests and verify RED**

Run the economy runner. Expected: FAIL for missing services, missing query methods, and strict version-1 rejection.

- [x] **Step 3: Implement explicit services and lock queries**

Set all 17 entries in `BLUEPRINT_TIERS`; set tier-zero IDs to `workbench`, `stone_kiln`, `beehive`, `well`, `fence`. Add the blueprint and recipe service definitions exactly as specified in design sections 5.3 and 7.3.

Add:

```gdscript
func get_blueprint_service_id(building_id: String) -> String:
    for service_id in BLUEPRINT_SERVICES:
        if str(BLUEPRINT_SERVICES[service_id].target_id) == building_id:
            return str(service_id)
    return ""

func get_recipe_service_id(recipe_id: String) -> String:
    for service_id in RECIPE_SERVICES:
        if str(RECIPE_SERVICES[service_id].target_id) == recipe_id:
            return str(service_id)
    return ""

func get_blueprint_lock_info(building_id: String) -> Dictionary:
    if not is_blueprint_managed(building_id):
        return {"unlocked": false, "reason": "建筑蓝图数据不可用", "service_id": ""}
    if is_blueprint_unlocked(building_id):
        return {"unlocked": true, "reason": "", "service_id": ""}
    var service_id := get_blueprint_service_id(building_id)
    var service: Dictionary = _view_for_static_service(BLUEPRINT_SERVICES.get(service_id, {}))
    return {"unlocked": false, "reason": str(service.get("disabled_reason", "尚未解锁")), "service_id": service_id}
```

`can_eventually_unlock_recipe()` returns true when the recipe is tier-zero for a tier-zero station, granted by a blueprint tier, or has an explicit recipe service.

- [x] **Step 4: Implement v1-to-v2 migration and placed-building reconciliation**

Bump progression `VERSION` to 2. `_parse_dict()` accepts versions 1 and 2, normalizes arrays, adds all tier-zero blueprints/recipes, and preserves valid old unlocks. Add:

```gdscript
func reconcile_placed_buildings(buildings: Array[BuildingInstance]) -> int:
    var added := 0
    for building in buildings:
        if building != null and is_instance_valid(building) and is_blueprint_managed(building.building_id) and not is_blueprint_unlocked(building.building_id):
            unlocked_blueprints[building.building_id] = true
            added += 1
    return added
```

After `SaveManager` restores buildings and progression, call reconciliation before validating the final applied runtime state. Do not charge or refund materials.

- [x] **Step 5: Run economy/save suites GREEN**

Expected: all services addressable; v1 and v2 fixtures load; invalid future versions still fail atomically.

- [x] **Step 6: Commit**

```powershell
git add scripts/systems/economy_progression_system.gd scripts/core/save_manager.gd tests/test_economy_progression.gd tests/test_economy_save_integration.gd
git commit -m "feat: complete production progression and migration"
```

## Task 4: Centralize building availability and protect preview entry

**Files:**
- Modify: `scripts/systems/building_system.gd`
- Modify: `scripts/ui/build_ui.gd`
- Modify: `tests/test_building_system_complete.gd`
- Modify: `tests/test_build_ui_build_mode.gd`

- [x] **Step 1: Write failing availability tests**

Assert that `diagnose_availability("furnace")` returns `blueprint_locked` before unlock, `insufficient_resources` after unlock without materials, and `ok` after adding exact materials. Assert `enter_preview_mode()` returns false in the first two states and true only in the third.

- [x] **Step 2: Run building tests and verify RED**

Expected: locked or unfunded buildings currently enter preview because `enter_preview_mode()` only validates scene data.

- [x] **Step 3: Implement one availability diagnostic**

Add:

```gdscript
func diagnose_availability(building: Variant) -> Dictionary:
    var resolved := _resolve_data(building)
    if not _is_valid_building_data(resolved):
        return _diagnostic(false, "invalid_building", "建筑数据不可用")
    if progression_ref != null and bool(progression_ref.call("is_blueprint_managed", resolved.building_id)) and not bool(progression_ref.call("is_blueprint_unlocked", resolved.building_id)):
        var info: Dictionary = progression_ref.call("get_blueprint_lock_info", resolved.building_id)
        var locked := _diagnostic(false, "blueprint_locked", str(info.get("reason", "尚未解锁蓝图")))
        locked["building_id"] = resolved.building_id
        locked["unlock_service_id"] = str(info.get("service_id", ""))
        return locked
    return diagnose_resources(resolved)
```

Use it in `enter_preview_mode()` before changing any preview state, and reuse it at the end of `diagnose_placement()` before commit. `BuildUI` obtains its cards from `BuildingCatalog` and uses this same diagnostic; locked and missing cards remain clickable for feedback, while only `ready` enters preview.

- [x] **Step 4: Run building tests GREEN**

Expected: unavailable selection has no preview or inventory side effects.

- [x] **Step 5: Commit**

```powershell
git add scripts/systems/building_system.gd scripts/ui/build_ui.gd tests/test_building_system_complete.gd tests/test_build_ui_build_mode.gd
git commit -m "feat: unify building availability checks"
```

## Task 5: Add category-aware player building selection

**Files:**
- Modify: `scripts/actors/player_action_controller.gd`
- Modify: `tests/test_player_action_controller.gd`

- [ ] **Step 1: Write failing controller tests**

Test that the default build category is `basic`, its four IDs match the catalog, numeric key 4 resolves, numeric key 5 does not, `cycle_building_category(1)` switches to `production`, and Q/E only cycle categories while building mode is active. Confirm category change exits preview and clears the selected building without changing camera state.

- [ ] **Step 2: Run main gameplay integration runner and verify RED**

Expected: controller exposes one hard-coded 9-item palette and ignores Q/E.

- [ ] **Step 3: Replace hard-coded building arrays with catalog queries**

Add:

```gdscript
signal building_category_changed(category_id: String, category_index: int)
const BuildingCatalogScript = preload("res://scripts/core/building_catalog.gd")
var _building_category_index := 0

func get_building_category() -> String:
    return BuildingCatalogScript.categories()[_building_category_index]

func get_current_building_ids() -> Array[String]:
    return BuildingCatalogScript.building_ids_for_category(get_building_category())

func get_building_id_at(index: int) -> String:
    var ids := get_current_building_ids()
    return ids[index] if index >= 0 and index < ids.size() else ""

func cycle_building_category(direction: int) -> bool:
    if _action_mode != ActionMode.BUILDING or direction == 0:
        return false
    var categories := BuildingCatalogScript.categories()
    _building_category_index = posmod(_building_category_index + signi(direction), categories.size())
    cancel_current_selection()
    building_category_changed.emit(get_building_category(), _building_category_index)
    palette_changed.emit(_action_mode, -1)
    return true
```

All building selection, labels, diagnostics, continuous placement, and numeric key bounds use `get_building_id_at()` or the current category IDs. In `_unhandled_input()`, map Q to `-1` and E to `+1` only in building mode.

Rename the controller's primary query to `get_building_availability_diagnostic(index)` and make it call `building_system.diagnose_availability(building_id)`. Keep `get_building_resource_diagnostic(index)` as a compatibility alias that forwards to the new method until all existing callers and tests are migrated.

- [ ] **Step 4: Run controller and main gameplay tests GREEN**

- [ ] **Step 5: Commit**

```powershell
git add scripts/actors/player_action_controller.gd tests/test_player_action_controller.gd
git commit -m "feat: add categorized building selection"
```

## Task 6: Build categorized HUD states and service deep links

**Files:**
- Modify: `scripts/ui/action_palette_button.gd`
- Modify: `scripts/ui/hud.gd`
- Modify: `scenes/ui/hud.tscn`
- Modify: `scripts/ui/service_panel.gd`
- Modify: `scripts/ui/shop_ui.gd`
- Modify: `scripts/main.gd`
- Modify: `tests/test_action_palette_button.gd`
- Modify: `tests/test_hud_action_bar.gd`
- Modify: `tests/test_service_panel.gd`
- Modify: `tests/test_economy_ui_integration.gd`
- Modify: `tests/test_main_farming_building_integration.gd`

- [ ] **Step 1: Write failing UI-state and navigation tests**

Cover the four palette states, five category buttons, at most four building cards, material-name fallback, lock detail visibility, and `building_unlock_requested("blueprint_furnace")`. Add service tests for:

```gdscript
assertions.truthy(service_panel.select_service("blueprint_furnace"), "service can be deep-linked")
assertions.equal(service_panel.selected_category, "blueprints", "deep link selects category")
assertions.equal(service_panel.selected_service_id, "blueprint_furnace", "deep link records target")
assertions.truthy(main.open_economy_tab("services", "blueprint_furnace"), "main routes unlock target")
```

- [ ] **Step 2: Run UI runners and verify RED**

Run `run_main_gameplay_integration_tests.gd` and `run_economy_ui_tests.gd`. Expected: no category bar, lock detail, or service-target API.

- [ ] **Step 3: Implement palette states and category bar**

Replace `ActionPaletteButton.set_available()` with a compatible `set_build_state(state)` that keeps `missing_resources` and `locked` clickable, applies green/red/gray modulation, and disables only `invalid`.

Add `BottomBar/BuildCategoryBar` plus `BuildLockPanel` with title, reason, cost, “前往解锁”, and close buttons to `hud.tscn`. `VillaHud.rebuild_action_palette()` reads the controller's current IDs and `GameData` names. Add:

```gdscript
signal building_unlock_requested(service_id: String)

func _on_building_button_pressed(index: int) -> void:
    var diagnostic := action_controller.get_building_availability_diagnostic(index)
    if str(diagnostic.get("code", "")) == "blueprint_locked":
        _show_build_lock_detail(diagnostic)
        return
    action_controller.select_mode_slot(index)
```

Category buttons call `action_controller.set_building_category(category_id)`. Inventory and `service_unlocked` events refresh cards and the cost bar immediately.

- [ ] **Step 4: Implement service selection and Main routing**

`ServicePanel.select_service(service_id)` refreshes services, derives the service category, selects it, rebuilds cards, records `selected_service_id`, and focuses/highlights the matching card. `ShopUI.open(tab_id, target_id)` and `Main.open_economy_tab()` accept service targets. Connect `hud.building_unlock_requested` to `open_economy_tab("services", service_id)`.

- [ ] **Step 5: Run UI and integration tests GREEN**

Expected: all five categories appear; locked cards navigate; buying a service refreshes the palette without scene reload.

- [ ] **Step 6: Commit**

```powershell
git add scripts/ui/action_palette_button.gd scripts/ui/hud.gd scenes/ui/hud.tscn scripts/ui/service_panel.gd scripts/ui/shop_ui.gd scripts/main.gd tests/test_action_palette_button.gd tests/test_hud_action_bar.gd tests/test_service_panel.gd tests/test_economy_ui_integration.gd tests/test_main_farming_building_integration.gd
git commit -m "feat: connect building palette to blueprint services"
```

## Task 7: Add clay, sand, and renewable fiber to real gathering

**Files:**
- Modify: `scripts/world/resource_catalog.gd`
- Modify: `scripts/world/world.gd`
- Modify: `scripts/world/tree_instance.gd`
- Modify: `tests/test_resource_gathering.gd`
- Modify: `tests/test_gathering_visuals.gd`
- Modify: `tests/test_main_gathering_integration.gd`

- [ ] **Step 1: Write failing resource tests**

Expect 17 surface mineral nodes: the existing 13 plus two clay and two sand nodes. Assert catalog definitions:

```gdscript
assertions.equal(ResourceCatalog.definition("clay").item_id, "clay", "clay is gatherable")
assertions.equal(ResourceCatalog.definition("sand").item_id, "sand", "sand is gatherable")
assertions.equal(ResourceCatalog.definition("clay").max_units, 4, "clay capacity")
assertions.equal(ResourceCatalog.definition("sand").respawn_days, 3, "sand respawn")
```

For an eligible full tree, assert preview and commit return `{"wood": 5, "fiber": 1}` and preserve the 3-second animation/transaction semantics. Assert clay/sand use the same stable-base four-frame atlas, hover circle, pickaxe position, and save round trip as other minerals.

- [ ] **Step 2: Run resource and gathering visual runners RED**

Expected: only 13 minerals exist and tree rewards contain wood only.

- [ ] **Step 3: Implement catalog/world/tree supply**

Add `clay` and `sand` catalog records with `pickaxe`, capacity 4, respawn 3, warm brown/pale gold tint, and mining visual kind. Add stable IDs `clay-00`, `clay-01`, `sand-00`, `sand-01` near riverbanks without reusing legacy IDs.

Update eligible tree rewards:

```gdscript
func preview_reward(tool_id: String) -> Dictionary:
    if not can_gather(tool_id):
        return {}
    return {item_id: remaining_units, "fiber": 1}
```

Keep `remaining_units = 0` and wood quantity 5. The existing atomic multi-item gather preflight must reject the whole gather if the backpack cannot hold both outputs.

- [ ] **Step 4: Run resource, visual, and main gathering suites GREEN**

- [ ] **Step 5: Commit**

```powershell
git add scripts/world/resource_catalog.gd scripts/world/world.gd scripts/world/tree_instance.gd tests/test_resource_gathering.gd tests/test_gathering_visuals.gd tests/test_main_gathering_integration.gd
git commit -m "feat: complete gatherable production inputs"
```

## Task 8: Connect locked recipes and world production indicators

**Files:**
- Modify: `scripts/ui/building_production_panel.gd`
- Modify: `scripts/ui/building_economy_ui.gd`
- Modify: `scripts/buildings/building_instance.gd`
- Modify: `scripts/systems/production_system.gd`
- Modify: `scripts/main.gd`
- Modify: `tests/test_building_economy_ui.gd`
- Modify: `tests/test_production_system.gd`
- Modify: `tests/test_building_instance.gd`

- [ ] **Step 1: Write failing recipe-navigation and indicator tests**

Assert locked recipe rows remain clickable, expose their service ID, and emit `unlock_requested`. For building indicators, assert:

```gdscript
building.set_economy_indicator("collect")
assertions.equal(building.get_economy_indicator(), "collect", "collect indicator is visible")
building.set_economy_indicator("full")
assertions.equal(building.get_economy_indicator(), "full", "full replaces collect")
building.set_economy_indicator("maintenance")
assertions.equal(building.get_economy_indicator(), "maintenance", "maintenance has priority")
```

Production tests assert collection clears `collect/full`, output blocking sets `full`, and overdue maintenance sets `maintenance`.

- [ ] **Step 2: Run building/economy UI tests RED**

- [ ] **Step 3: Implement locked recipe navigation**

Add `signal unlock_requested(service_id: String)` to `BuildingProductionPanel`. Locked recipe buttons remain enabled; pressing them calls `_progression.get_recipe_service_id(recipe_id)` and emits when non-empty. Forward the signal through `BuildingEconomyUI` to `Main`, which closes the building modal and opens `services` at the target.

- [ ] **Step 4: Implement lightweight world indicators**

`BuildingInstance._ensure_nodes()` adds a billboarded `Label3D` named `EconomyIndicator` positioned at the building visual's upper-right. `set_economy_indicator(kind)` maps `collect → 收`, `full → 满`, `maintenance → 修`, empty → hidden, with distinct cream/red/gold colors.

Add `ProductionSystem.refresh_indicator(building)` with priority: overdue maintenance, storage full, any output, none. Call it after registration, job completion/output block, passive output, collection, maintenance, load/rebuild, and construction completion.

- [ ] **Step 5: Run production, building, and UI suites GREEN**

- [ ] **Step 6: Commit**

```powershell
git add scripts/ui/building_production_panel.gd scripts/ui/building_economy_ui.gd scripts/buildings/building_instance.gd scripts/systems/production_system.gd scripts/main.gd tests/test_building_economy_ui.gd tests/test_production_system.gd tests/test_building_instance.gd
git commit -m "feat: expose production unlocks and world status"
```

## Task 9: Prove the full vertical chain and finish regression coverage

**Files:**
- Create: `tests/test_production_chain_integration.gd`
- Create: `tests/run_production_chain_tests.gd`
- Modify: `tests/test_economy_ui_responsive.gd`
- Modify: `docs/superpowers/specs/2026-08-06-production-chain-connection-design.md`

- [ ] **Step 1: Write the end-to-end acceptance test**

Use real `InventorySystem`, `BuildingSystem`, `EconomyProgressionSystem`, `ProductionSystem`, `RecipeDatabase`, grid, clock, and save fixtures. The test must:

1. commit real tree and clay/sand/ore gathers;
2. build and finish a workbench and stone kiln;
3. produce and collect plank, rope, charcoal, stone brick, and brick;
4. satisfy and buy the furnace blueprint, then build and finish it;
5. produce and collect glass, jars, bottles, copper ingots, and iron ingots;
6. unlock/build windmill, coop, lumberyard, and quarry;
7. unlock/build food workshop, textile machine, greenhouse, and mine;
8. produce at least one food, textile item, machine part, and advanced building input;
9. sell one product through `EconomySystem` and use another in a construction cost;
10. save/load and compare buildings, construction, queues, outputs, progression, resources, inventory, and market state.

Do not weaken assertions to bypass timing or progression. This is an acceptance test over behavior already introduced test-first in Tasks 1–8, so it may pass on its first run.

- [ ] **Step 2: Run the dedicated runner**

```powershell
godot --headless --path . --script res://tests/run_production_chain_tests.gd
```

- [ ] **Step 3: Handle any acceptance failure through a fresh TDD cycle**

If the acceptance runner fails, stop at the first failing seam, add one focused failing test to the owning Task 1–8 test file, run it to verify the expected RED result, implement the minimal correction, run that focused suite GREEN, and rerun the acceptance test. Do not inject inventory items directly after the initial fixture; every later material must come from gathering, production, passive output, or market purchase.

- [ ] **Step 4: Add responsive assertions**

At 1280×720, 1920×1080, and 3000×2000, assert the category bar, up to four palette buttons, cost bar, and lock panel remain inside the viewport and do not overlap the economy actions.

- [ ] **Step 5: Run the dedicated and impacted runners GREEN**

Run:

```powershell
godot --headless --path . --script res://tests/run_production_chain_tests.gd
godot --headless --path . --script res://tests/run_resource_gathering_tests.gd
godot --headless --path . --script res://tests/run_gathering_visual_tests.gd
godot --headless --path . --script res://tests/run_building_system_tests.gd
godot --headless --path . --script res://tests/run_economy_system_tests.gd
godot --headless --path . --script res://tests/run_economy_ui_tests.gd
godot --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: every command exits 0 with no parse errors or orphan-node warnings.

- [ ] **Step 6: Mark the design implemented and commit**

Change the design status from `待确认` to `已实现`, append the exact verification commands/counts, then:

```powershell
git add tests/test_production_chain_integration.gd tests/run_production_chain_tests.gd tests/test_economy_ui_responsive.gd docs/superpowers/specs/2026-08-06-production-chain-connection-design.md
git commit -m "test: verify complete production chain"
```

## Final verification

- [ ] Run all impacted runners from Task 9 again with fresh output.
- [ ] Run parser/import validation:

```powershell
godot --headless --path . --editor --quit
```

- [ ] Run gameplay smoke:

```powershell
godot --headless --path . --quit-after 10
```

- [ ] Run `git diff --check` and confirm the worktree is clean after commits.
- [ ] Review every design section against the commits and record any intentional deviation.
- [ ] Request code review against the pre-implementation base SHA and resolve all Critical/Important findings.
