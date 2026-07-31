# Building Material Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add always-visible material counts, structured building placement diagnostics, cost details, actionable failure feedback, and true material-based building-button disabling.

**Architecture:** `EconomySystem` exposes exact resource reports; `BuildingSystem` owns structured placement diagnostics and transactional placement results; `PlayerActionController` turns rejected user actions into one feedback signal and debug log; `VillaHud` renders material inventory, cost state, disabled buttons, and a reusable Toast. Existing boolean and instance-returning building APIs remain compatibility wrappers.

**Tech Stack:** Godot 4.7, GDScript, `.tscn` UI scenes, local SVG textures, project-native headless test runners.

---

## File Structure

- Modify `scripts/systems/economy_system.gd`: expose exact required/available/missing resource reports.
- Modify `scripts/systems/building_system.gd`: add diagnostic and transaction APIs while preserving existing wrappers.
- Modify `scripts/actors/player_action_controller.gd`: reject unaffordable selection, emit feedback, handle continuous-build exhaustion, and print debug-only action failures.
- Modify `scripts/ui/hud.gd`: bind inventory events, render costs, disable buttons, and manage the Toast.
- Modify `scripts/ui/action_palette_button.gd`: make visual availability and actual button disabled state consistent.
- Modify `scenes/ui/hud.tscn`: author the top material panel, selected-building cost bar, and failure Toast.
- Create `assets/ui/material_icons/wood.svg`, `stone.svg`, `iron.svg`, `glass.svg`: font-independent material icons.
- Modify `tests/test_building_system_complete.gd`: verify diagnostic codes, shortage values, compatibility, and transaction results.
- Modify `tests/test_player_action_controller.gd`: verify selection rejection, feedback, and continuous build behavior.
- Modify `tests/test_hud_action_bar.gd`: verify material display, disabled buttons, tooltips, cost bar, and Toast reuse.
- Modify `tests/test_main_farming_building_integration.gd`: verify real inventory-to-HUD updates after placement.

### Task 1: Exact Resource Reports and Placement Diagnostics

**Files:**
- Modify: `tests/test_building_system_complete.gd`
- Modify: `scripts/systems/economy_system.gd`
- Modify: `scripts/systems/building_system.gd`

- [ ] **Step 1: Write failing diagnostic tests**

Add a resource-aware economy double and assertions that express the desired APIs:

```gdscript
class EconomyDouble:
    extends RefCounted
    var holdings := {"wood": 250, "stone": 150, "iron": 50, "glass": 50}

    func get_resource_report(cost: Dictionary) -> Dictionary:
        var report := {}
        for item_id in cost:
            var required := int(cost[item_id])
            var available := int(holdings.get(item_id, 0))
            report[item_id] = {
                "required": required,
                "available": available,
                "missing": maxi(required - available, 0),
            }
        return report

    func has_resources(cost: Dictionary) -> bool:
        for entry in get_resource_report(cost).values():
            if int(entry.missing) > 0:
                return false
        return true
```

Add assertions for:

```gdscript
var road_diagnostic: Dictionary = system.diagnose_placement(barn, 3, 3)
assertions.equal(road_diagnostic.code, "road", "road diagnostic is specific")
assertions.equal(road_diagnostic.blocked_cell.grid, Vector2i(3, 3), "diagnostic identifies blocked cell")

economy.holdings.wood = 42
var resource_diagnostic: Dictionary = system.diagnose_placement(barn, 8, 8)
assertions.equal(resource_diagnostic.code, "insufficient_resources", "resource diagnostic is specific")
assertions.equal(resource_diagnostic.missing_resources.wood.required, 100, "resource report includes requirement")
assertions.equal(resource_diagnostic.missing_resources.wood.available, 42, "resource report includes inventory")
assertions.equal(resource_diagnostic.missing_resources.wood.missing, 58, "resource report includes shortage")
assertions.equal(system.can_place(barn, 8, 8), resource_diagnostic.allowed, "can_place wraps diagnostic")
```

Cover `out_of_bounds`, `invalid_terrain`, `occupied`, `planted`, `water`, `decoration`, and a valid mixed wasteland/farmland footprint. Add a `try_place_building()` assertion that returns `placed`, `instance`, and `diagnostic`.

- [ ] **Step 2: Run the building suite and verify RED**

Run:

```powershell
godot --headless --path . --script res://tests/run_building_system_tests.gd
```

Expected: FAIL because `get_resource_report`, `diagnose_placement`, and `try_place_building` do not exist.

- [ ] **Step 3: Implement exact resource reporting**

Add to `EconomySystem`:

```gdscript
func get_resource_report(cost_dict: Dictionary) -> Dictionary:
    var report := {}
    for item_id in cost_dict:
        var required := int(cost_dict[item_id])
        var available := (
            _inventory_ref.get_item_count(str(item_id))
            if _inventory_ref != null
            else 0
        )
        report[str(item_id)] = {
            "required": required,
            "available": available,
            "missing": maxi(required - available, 0),
        }
    return report


func get_resource_shortages(cost_dict: Dictionary) -> Dictionary:
    var shortages := {}
    var report := get_resource_report(cost_dict)
    for item_id in report:
        var entry: Dictionary = report[item_id]
        if int(entry.missing) > 0:
            shortages[item_id] = entry
    return shortages
```

Refactor `has_resources()` to return `get_resource_shortages(cost_dict).is_empty()`.

- [ ] **Step 4: Implement placement diagnostics**

Add stable code constants and these public APIs to `BuildingSystem`:

```gdscript
func diagnose_resources(building: Variant) -> Dictionary:
    var resolved := _resolve_data(building)
    if resolved == null or not resolved.is_valid():
        return _diagnostic(false, "invalid_building", "无法建造：建筑数据无效")
    if economy_ref == null or not economy_ref.has_method("has_resources"):
        return _diagnostic(false, "system_unavailable", "建造系统尚未就绪")
    var report: Dictionary = (
        economy_ref.get_resource_report(resolved.cost)
        if economy_ref.has_method("get_resource_report")
        else {}
    )
    var missing := _missing_entries(report)
    if missing.is_empty() and not bool(economy_ref.has_resources(resolved.cost)):
        return _diagnostic(false, "insufficient_resources", "无法建造%s：材料不足" % resolved.display_name)
    if not missing.is_empty():
        return _resource_diagnostic(resolved, missing)
    return _diagnostic(true, "ok", "")


func diagnose_placement(building: Variant, gx: int, gz: int) -> Dictionary:
    var resolved := _resolve_data(building)
    if resolved == null or not resolved.is_valid() or not load(resolved.scene_path) is PackedScene:
        return _diagnostic(false, "invalid_building", "无法建造：建筑数据无效")
    if grid_system_ref == null or economy_ref == null:
        return _diagnostic(false, "system_unavailable", "建造系统尚未就绪")
    for location in _footprint_cells(resolved, gx, gz):
        var cell := grid_system_ref.get_cell(location.x, location.y)
        if cell == null:
            return _blocked_diagnostic(
                resolved, gx, gz, location, -1,
                "out_of_bounds",
                "无法建造%s：目标区域超出地图范围" % resolved.display_name
            )
        if not is_finite(grid_system_ref.get_terrain_height_at_cell(location.x, location.y)):
            return _blocked_diagnostic(
                resolved, gx, gz, location, cell.state,
                "invalid_terrain",
                "无法建造%s：目标地形无效" % resolved.display_name
            )
        if cell.state not in BUILDABLE_STATES:
            return _cell_state_diagnostic(resolved, gx, gz, location, cell.state)
    var resources := diagnose_resources(resolved)
    resources["building_id"] = resolved.building_id
    resources["grid"] = Vector2i(gx, gz)
    return resources


func _diagnostic(allowed: bool, code: String, message: String) -> Dictionary:
    return {
        "allowed": allowed,
        "code": code,
        "message": message,
        "building_id": "",
        "grid": Vector2i(-1, -1),
        "missing_resources": {},
        "blocked_cell": {},
    }


func _blocked_diagnostic(
    data: BuildingData,
    gx: int,
    gz: int,
    location: Vector2i,
    state: int,
    code: String,
    message: String
) -> Dictionary:
    var result := _diagnostic(false, code, message)
    result.building_id = data.building_id
    result.grid = Vector2i(gx, gz)
    result.blocked_cell = {"grid": location, "state": state}
    return result
```

Map states to codes and Chinese messages:

```gdscript
GridCell.State.ROAD: "road"
GridCell.State.BUILDING: "occupied"
GridCell.State.PLANTED: "planted"
GridCell.State.WATER: "water"
GridCell.State.DECORATION: "decoration"
```

Make `can_place()` return `bool(diagnose_placement(building, gx, gz).allowed)`.

- [ ] **Step 5: Implement transactional placement results**

Extract the current placement body into:

```gdscript
func try_place_building(building: Variant, gx: int, gz: int) -> Dictionary:
    var diagnostic := diagnose_placement(building, gx, gz)
    if not bool(diagnostic.allowed):
        return {"placed": false, "instance": null, "diagnostic": diagnostic}
    var resolved := _resolve_data(building)
    var packed := load(resolved.scene_path) as PackedScene
    var instance := packed.instantiate() as BuildingInstance
    if instance == null:
        return {
            "placed": false,
            "instance": null,
            "diagnostic": _diagnostic(false, "invalid_building", "无法建造：建筑场景无效"),
        }
    var snapshots: Array[Dictionary] = []
    for location in _footprint_cells(resolved, gx, gz):
        var cell := grid_system_ref.get_cell(location.x, location.y)
        snapshots.append({
            "gx": location.x,
            "gz": location.y,
            "previous_state": cell.state,
        })
    instance.configure(resolved, gx, gz, snapshots)
    instance.position = _world_position_for(resolved, gx, gz)
    var applied: Array[Dictionary] = []
    for snapshot in snapshots:
        if not grid_system_ref.set_cell_state(snapshot.gx, snapshot.gz, GridCell.State.BUILDING):
            _restore_snapshots(applied)
            instance.free()
            return {
                "placed": false,
                "instance": null,
                "diagnostic": _diagnostic(false, "grid_commit_failed", "建造提交失败，请重试"),
            }
        applied.append(snapshot)
    if not economy_ref.has_method("spend_resources") or not bool(economy_ref.spend_resources(resolved.cost)):
        _restore_snapshots(snapshots)
        instance.free()
        return {
            "placed": false,
            "instance": null,
            "diagnostic": _diagnostic(false, "resource_commit_failed", "建造提交失败，请重试"),
        }
    buildings_container.add_child(instance)
    _buildings.append(instance)
    _connect_construction_signals(instance)
    instance.start_construction()
    building_placed.emit(resolved.building_id, gx, gz)
    building_instance_placed.emit(instance)
    building_construction_started.emit(instance)
    if _event_bus and _event_bus.has_signal("building_placed"):
        _event_bus.building_placed.emit(instance)
    if _event_bus and _event_bus.has_signal("building_construction_started"):
        _event_bus.building_construction_started.emit(instance)
    if _in_build_mode:
        exit_preview_mode()
    return {
        "placed": true,
        "instance": instance,
        "diagnostic": _diagnostic(true, "ok", ""),
    }
```

Preserve compatibility:

```gdscript
func place_building(building: Variant, gx: int, gz: int) -> BuildingInstance:
    return try_place_building(building, gx, gz).get("instance") as BuildingInstance


func try_place_selected_building(gx: int, gz: int) -> Dictionary:
    if _current_data == null:
        return {
            "placed": false,
            "instance": null,
            "diagnostic": _diagnostic(false, "invalid_building", "未选择建筑"),
        }
    return try_place_building(_current_data, gx, gz)
```

- [ ] **Step 6: Run the building suite and verify GREEN**

Run the building suite again. Expected: `PASS` with all building-system checks.

- [ ] **Step 7: Commit Task 1**

```powershell
git add scripts/systems/economy_system.gd scripts/systems/building_system.gd tests/test_building_system_complete.gd
git commit -m "feat: add building placement diagnostics"
```

### Task 2: Controller Feedback and Material-Gated Selection

**Files:**
- Modify: `tests/test_player_action_controller.gd`
- Modify: `scripts/actors/player_action_controller.gd`

- [ ] **Step 1: Write failing controller tests**

Extend the building double with resource diagnostics and transaction results. Assert:

```gdscript
var feedback_events: Array[Dictionary] = []
controller.build_feedback_requested.connect(
    func(_message: String, details: Dictionary) -> void:
        feedback_events.append(details)
)

building.resource_allowed = false
assertions.falsy(controller.select_mode_slot(0), "unaffordable building cannot be selected")
assertions.equal(controller.get_selected_slot(), -1, "rejected selection stays unselected")
assertions.equal(feedback_events[-1].code, "insufficient_resources", "selection emits material feedback")
```

Add placement rejection, successful continuous placement, and post-placement exhaustion assertions.

- [ ] **Step 2: Run the main gameplay integration suite and verify RED**

Run:

```powershell
godot --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: FAIL because `build_feedback_requested` and resource-gated selection are absent.

- [ ] **Step 3: Implement controller feedback**

Add:

```gdscript
signal build_feedback_requested(message: String, details: Dictionary)
```

Add a public diagnostic helper:

```gdscript
func get_building_resource_diagnostic(index: int) -> Dictionary:
    if index < 0 or index >= BUILDING_IDS.size() or building_system == null:
        return {"allowed": false, "code": "invalid_building", "message": "建筑不可用"}
    if building_system.has_method("diagnose_resources"):
        return building_system.diagnose_resources(BUILDING_IDS[index])
    return {"allowed": true, "code": "ok", "message": ""}
```

Before assigning a building slot, reject a false `allowed` result and emit feedback. Keep farming selection behavior unchanged.

- [ ] **Step 4: Implement transactional build actions and continuous-build exhaustion**

Use `try_place_selected_building()` when available. On failure, emit one feedback signal and print one debug line:

```gdscript
func _emit_build_feedback(details: Dictionary, prefix: String) -> void:
    var message := str(details.get("message", "无法建造"))
    build_feedback_requested.emit(message, details)
    if OS.is_debug_build():
        print("[%s] building=%s grid=%s code=%s details=%s" % [
            prefix,
            str(details.get("building_id", "")),
            str(details.get("grid", Vector2i(-1, -1))),
            str(details.get("code", "unknown")),
            str(details),
        ])
```

After success, call `get_building_resource_diagnostic(_selected_slot)`. Re-enter preview only when allowed; otherwise exit preview, set selection to `-1`, emit selection/palette changes, and request `材料不足，已结束连续建造`.

- [ ] **Step 5: Run the integration suite and verify GREEN**

Expected: all player/controller and main gameplay integration checks pass.

- [ ] **Step 6: Commit Task 2**

```powershell
git add scripts/actors/player_action_controller.gd tests/test_player_action_controller.gd
git commit -m "feat: report rejected building actions"
```

### Task 3: Material Icons and HUD Scene Structure

**Files:**
- Create: `assets/ui/material_icons/wood.svg`
- Create: `assets/ui/material_icons/stone.svg`
- Create: `assets/ui/material_icons/iron.svg`
- Create: `assets/ui/material_icons/glass.svg`
- Modify: `scenes/ui/hud.tscn`
- Modify: `tests/test_hud_action_bar.gd`

- [ ] **Step 1: Write failing HUD structure tests**

Assert authored paths and icon textures:

```gdscript
for item_id in ["wood", "stone", "iron", "glass"]:
    var entry := hud.get_node("MaterialsPanel/MaterialsRow/%s" % item_id.capitalize())
    assertions.truthy(entry.get_node("Icon").texture != null, "%s has a local icon" % item_id)
    assertions.truthy(entry.get_node("Count") is Label, "%s has a count label" % item_id)
    assertions.truthy(not entry.has_node("Name"), "%s has no visible name label" % item_id)

assertions.truthy(hud.get_node("BottomBar/BuildCostBar") is PanelContainer, "selected cost bar is authored")
assertions.truthy(hud.get_node("BottomBar/BuildFeedbackToast") is PanelContainer, "feedback toast is authored")
```

- [ ] **Step 2: Run the HUD suite and verify RED**

Run the main gameplay integration suite. Expected: FAIL because the new nodes and assets do not exist.

- [ ] **Step 3: Create four local SVG material icons**

Create transparent 64×64 icons with project-owned vector shapes:

`wood.svg`:

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <rect x="9" y="18" width="46" height="14" rx="7" fill="#87502f" transform="rotate(24 32 25)"/>
  <rect x="9" y="34" width="46" height="14" rx="7" fill="#9e6237" transform="rotate(-20 32 41)"/>
  <circle cx="51" cy="34" r="7" fill="#d7a66a"/><circle cx="51" cy="34" r="3" fill="#a66b3d"/>
</svg>
```

`stone.svg`:

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <path d="M7 48 12 30 26 23 38 31 42 49Z" fill="#70808a"/>
  <path d="M28 49 34 22 50 18 59 35 54 50Z" fill="#8798a1"/>
  <path d="m34 22 16-4-8 12-8 7Z" fill="#a9b6bc"/>
</svg>
```

`iron.svg`:

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <path d="m10 44 8-24h30l7 24-8 8H17Z" fill="#6f7880"/>
  <path d="m18 20 8-8h25l-3 8Z" fill="#c5cdd1"/>
  <path d="M17 44h38l-8 8H17Z" fill="#4f5961"/>
</svg>
```

`glass.svg`:

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <rect x="12" y="8" width="40" height="48" rx="4" fill="#87d9e8" fill-opacity=".58" stroke="#d9fbff" stroke-width="4"/>
  <path d="M20 43 42 15M20 30l11-14" stroke="#fff" stroke-width="4" stroke-linecap="round" opacity=".82"/>
</svg>
```

- [ ] **Step 4: Author HUD nodes**

Add:

```text
MaterialsPanel (PanelContainer, top-left below TopBar)
└── MaterialsRow (HBoxContainer)
    ├── Wood (HBoxContainer) -> Icon + Count
    ├── Stone (HBoxContainer) -> Icon + Count
    ├── Iron (HBoxContainer) -> Icon + Count
    └── Glass (HBoxContainer) -> Icon + Count

BottomBar
├── BuildFeedbackToast (PanelContainer, hidden)
│   └── Message (Label)
├── BuildCostBar (PanelContainer, hidden)
│   └── Row (HBoxContainer)
│       ├── Building (Label)
│       └── Costs (HBoxContainer)
├── ToolLabel
└── existing ModeMenu and ActionRow

BuildFeedbackTimer (Timer, one_shot=true, wait_time=2.5)
```

Use the existing cream text, dark green panels, and warm borders. Keep all minimum widths within 1280×720.

- [ ] **Step 5: Run the HUD suite and verify GREEN**

Expected: new scene structure and textures load without parser or resource errors.

- [ ] **Step 6: Commit Task 3**

```powershell
git add assets/ui/material_icons scenes/ui/hud.tscn tests/test_hud_action_bar.gd
git commit -m "feat: add material feedback HUD structure"
```

### Task 4: HUD Runtime Binding, Costs, Disabled Buttons, and Toast

**Files:**
- Modify: `tests/test_hud_action_bar.gd`
- Modify: `scripts/ui/action_palette_button.gd`
- Modify: `scripts/ui/hud.gd`

- [ ] **Step 1: Write failing runtime HUD tests**

Use a real `InventorySystem` with known quantities and a resource-aware building double. Assert:

```gdscript
inventory.add_item("wood", 42)
inventory.add_item("stone", 150)
hud.configure_action_bar(controller, inventory, economy)
assertions.equal(hud.get_material_count_text("wood"), "42", "wood count is visible")

controller.switch_mode(PlayerActionController.ActionMode.BUILDING)
var barn_button := hud.quick_bar.get_child(0) as Button
assertions.truthy(barn_button.disabled, "unaffordable barn is disabled")
assertions.truthy(barn_button.tooltip_text.contains("木材"), "disabled barn keeps cost tooltip")

hud.show_build_feedback("无法建造谷仓：木材还缺 58", {})
var toast := hud.build_feedback_toast
hud.show_build_feedback("无法建造谷仓：目标区域包含道路", {})
assertions.equal(hud.build_feedback_toast, toast, "feedback reuses one toast")
assertions.truthy(toast.visible, "feedback toast is visible")
```

Also assert that adding wood refreshes the count and re-enables the barn after an inventory event.

- [ ] **Step 2: Run the integration suite and verify RED**

Expected: FAIL because material binding, true disabling, cost bar, and Toast behavior are absent.

- [ ] **Step 3: Make availability disable the actual button**

Update `ActionPaletteButton`:

```gdscript
func set_available(available: bool) -> void:
    disabled = not available
    icon_rect.modulate = Color.WHITE if available else Color(0.48, 0.48, 0.48, 0.82)
    name_label.modulate = Color.WHITE
    shortcut_label.modulate = Color.WHITE
```

- [ ] **Step 4: Bind material inventory and controller feedback**

In `VillaHud`:

```gdscript
const MATERIAL_IDS: Array[String] = ["wood", "stone", "iron", "glass"]
const MATERIAL_NAMES := {
    "wood": "木材",
    "stone": "石头",
    "iron": "铁",
    "glass": "玻璃",
}
```

Connect `EventBus.item_added` and `item_removed` once, refresh the matching count, and call a full action-bar refresh for material items. `refresh_action_bar()` must also refresh all four counts so initial grants, load, and resets are correct.

Connect `action_controller.build_feedback_requested` to `show_build_feedback`.

- [ ] **Step 5: Render tooltips and selected cost state**

Use `GameData` costs and `BuildingSystem.diagnose_resources()` to build:

- Complete tooltip with building name, footprint, required/available amounts, and shortage.
- `BuildCostBar` child entries using the same local material textures.
- Normal cream amount color for sufficient entries.
- Warm red amount color for shortages.

Hide the bar outside building mode or when selected index is `-1`.

- [ ] **Step 6: Implement reusable Toast timing**

```gdscript
func show_build_feedback(message: String, _details: Dictionary = {}) -> void:
    build_feedback_label.text = message
    build_feedback_toast.visible = true
    build_feedback_timer.start()


func _on_build_feedback_timeout() -> void:
    build_feedback_toast.visible = false
```

Connect the authored Timer once in `_ready()`.

- [ ] **Step 7: Run the integration suite and verify GREEN**

Expected: all HUD/controller integration checks pass.

- [ ] **Step 8: Commit Task 4**

```powershell
git add scripts/ui/action_palette_button.gd scripts/ui/hud.gd tests/test_hud_action_bar.gd
git commit -m "feat: show building costs and failure feedback"
```

### Task 5: Real Main-Scene Integration and Final Verification

**Files:**
- Modify: `tests/test_main_farming_building_integration.gd`

- [ ] **Step 1: Write the failing main-scene integration assertions**

Before placing a fence, assert initial material text:

```gdscript
assertions.equal(main.hud.get_material_count_text("wood"), "250", "HUD shows starting wood")
assertions.equal(main.hud.get_material_count_text("stone"), "150", "HUD shows starting stone")
assertions.equal(main.hud.get_material_count_text("iron"), "50", "HUD shows starting iron")
assertions.equal(main.hud.get_material_count_text("glass"), "50", "HUD shows starting glass")
```

After placing a fence, assert wood becomes `240` in both inventory and HUD. Drain wood below ten, refresh through the normal inventory event, and assert the fence button is disabled.

- [ ] **Step 2: Run the integration suite and verify RED**

Expected: FAIL if any real initialization or event ordering is missing.

- [ ] **Step 3: Run focused suites**

```powershell
godot --headless --path . --script res://tests/run_building_system_tests.gd
godot --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: both report `PASS`.

- [ ] **Step 4: Run the complete project suite**

```powershell
godot --headless --path . --script res://tests/run_tests.gd
```

Expected: `PASS` and no new parser/runtime errors. Existing known procedural construction-art fallback warnings may remain.

- [ ] **Step 5: Capture and inspect the main gameplay HUD**

```powershell
godot --headless --path . --script res://tests/capture_main_gameplay_integration.gd
```

Open the emitted PNG and verify:

- Four top material icons and values are legible.
- No material names are visibly rendered in the top panel.
- The cost bar does not collide with the action palette.
- Disabled building icons are visibly gray.
- The Toast sits above the cost bar and does not cover the world target.

- [ ] **Step 6: Run diff and status checks**

```powershell
git diff --check
git status --short
```

Expected: no whitespace errors and only intended implementation/test/assets changes.

- [ ] **Step 7: Commit final integration**

```powershell
git add tests/test_main_farming_building_integration.gd
git commit -m "test: verify building material feedback integration"
```
