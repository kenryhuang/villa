# Inventory, One-Shot Building, and Carrot Visuals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore a mouse-visible backpack entry, move building details into icon tooltips, make placement one-shot, and replace carrot with two-stage hand-painted sprites.

**Architecture:** VillaHud exposes a backpack request and owns hover-only building descriptions; Main coordinates modal visibility; PlayerActionController clears building selection after a successful transaction. Carrot joins the existing two-stage crop contract so logical stages 0–2 alias one seed scene and stage 3 uses one mature scene.

**Tech Stack:** Godot 4.7.1, GDScript, Control/CanvasLayer scenes, existing TestAssert runners, built-in imagegen, 1024×1024 transparent PNG.

**Baseline:** `run_hud_shell_tests.gd`, `run_multi_crop_model_tests.gd`, and `run_multi_crop_art_tests.gd` pass. `run_main_gameplay_integration_tests.gd` has two pre-existing failures: automatic grain seed mapping and stored-crop contract delivery. No task may introduce additional failures.

---

### Task 1: Mouse-visible backpack entry

**Files:**
- Modify: `scenes/ui/hud.tscn`
- Modify: `scripts/ui/hud.gd`
- Modify: `scripts/main.gd`
- Modify: `tests/test_hud_action_bar.gd`
- Modify: `tests/test_main_item_container_wiring.gd`
- Modify: `tests/test_runtime_ui_scenes.gd`

- [ ] **Step 1: Write failing HUD and Main integration tests**

Add scene assertions for `EconomyActions/InventoryButton`, require the button text to contain `背包` and `I`, and connect to the real HUD signal before emitting a native left click:

```gdscript
var inventory_requests := 0
hud.inventory_requested.connect(func() -> void: inventory_requests += 1)
var inventory_button := hud.get_node("EconomyActions/InventoryButton") as Button
inventory_button.pressed.emit()
assertions.equal(inventory_requests, 1, "backpack button emits one inventory request")
```

In Main wiring coverage, require HUD's `inventory_requested` signal to be connected and call `_on_inventory_requested()` with lightweight modal doubles. Assert other open modals close, the inventory toggles open, and a second request toggles it closed.

- [ ] **Step 2: Run the focused runners and verify RED**

Run:

```powershell
& 'C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Links\godot_console.exe' --headless --path . --script tests/run_action_mode_debug_day_regression_tests.gd
```

Expected: failures report the missing `InventoryButton`, missing `inventory_requested` signal, or missing Main handler.

- [ ] **Step 3: Add the HUD button and request signal**

Add the button beside Market and Notification:

```ini
[node name="InventoryButton" type="Button" parent="EconomyActions"]
custom_minimum_size = Vector2(138, 50)
layout_mode = 2
theme_override_font_sizes/font_size = 20
text = "背包 I"
tooltip_text = "打开背包（I / Tab）"
```

Add and connect the public request in `VillaHud`:

```gdscript
signal inventory_requested

@onready var inventory_button: Button = $EconomyActions/InventoryButton

func _on_inventory_pressed() -> void:
	inventory_requested.emit()
```

Connect `inventory_button.pressed` idempotently in `_ready()`.

- [ ] **Step 4: Route the request through Main**

Connect the HUD signal in `_setup_ui()` and implement:

```gdscript
func _on_inventory_requested() -> void:
	if inventory_ui == null:
		_publish_hud_message("inventory", "error", "背包界面尚未就绪")
		return
	if bool(inventory_ui.get("_is_open")):
		inventory_ui.close()
		return
	for modal in [map_ui, build_ui, shop_ui, building_economy_ui]:
		if modal != null and modal.has_method("close"):
			modal.close()
	if economy_notification_ui != null:
		economy_notification_ui.hide_center()
	inventory_ui.open()
```

Do not modify InventorySystem or the existing `I/Tab/Escape` input path.

- [ ] **Step 5: Run focused tests and verify GREEN**

Expected: HUD and Main wiring assertions pass with no new parser errors.

- [ ] **Step 6: Commit**

```powershell
git add scenes/ui/hud.tscn scripts/ui/hud.gd scripts/main.gd tests/test_hud_action_bar.gd tests/test_main_item_container_wiring.gd tests/test_runtime_ui_scenes.gd
git commit -m "feat: restore mouse backpack entry"
```

### Task 2: Hover-only building details and one-shot placement

**Files:**
- Modify: `scenes/ui/hud.tscn`
- Modify: `scripts/ui/hud.gd`
- Modify: `scripts/actors/player_action_controller.gd`
- Modify: `tests/test_hud_action_bar.gd`
- Modify: `tests/test_player_action_controller.gd`

- [ ] **Step 1: Write failing tooltip and one-shot placement tests**

Require `BottomBar/BuildCostBar` to be absent. Configure a real building palette button and assert its tooltip contains building name, footprint, available/required material quantities, and missing quantity when applicable:

```gdscript
assertions.truthy(hud.get_node_or_null("BottomBar/BuildCostBar") == null, "build details are not permanently shown")
assertions.truthy(button.tooltip_text.contains("占地"), "building tooltip includes footprint")
assertions.truthy(button.tooltip_text.contains("木材"), "building tooltip includes material name")
assertions.truthy(button.tooltip_text.contains("42/100"), "building tooltip includes available and required counts")
assertions.truthy(button.tooltip_text.contains("缺 58"), "building tooltip includes shortage")
```

Replace the continuous-build expectation with:

```gdscript
var placed := controller.perform_build_action(8, 9)
assertions.truthy(placed != null, "successful placement returns an instance")
assertions.equal(controller.get_action_mode(), PlayerActionController.ActionMode.BUILDING, "placement keeps building mode")
assertions.equal(controller.get_selected_slot(), -1, "placement clears building selection")
assertions.truthy(not building.build_mode, "placement leaves no preview shadow")
```

Keep the rejection test and assert failed placement retains the selected slot and preview.

- [ ] **Step 2: Run action-mode regression tests and verify RED**

Run:

```powershell
& 'C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Links\godot_console.exe' --headless --path . --script tests/run_action_mode_debug_day_regression_tests.gd
```

Expected: failures show `BuildCostBar` still exists and successful affordable placement still restores preview.

- [ ] **Step 3: Remove the permanent build-cost strip**

Delete `BuildCostBar`, `CostRow`, `BuildingLabel`, and `Costs` from `hud.tscn`. Remove their onready fields, `_refresh_build_cost_bar()`, `_create_cost_entry()`, and every call that refreshes the strip.

Retain `_refresh_building_tooltip()` as the only descriptive outlet. Its final format must be:

```gdscript
button.tooltip_text = "%s\n占地 %d × %d\n%s" % [
	str(source.get("name", building_id)),
	footprint.x,
	footprint.y,
	"、".join(cost_parts),
]
```

For unavailable buildings, append the diagnostic reason instead of creating a persistent label.

- [ ] **Step 4: Make successful placement one-shot**

Replace the post-success continuous-build branch in `perform_build_action()` with:

```gdscript
inventory_changed.emit()
if building_system.is_in_build_mode():
	building_system.exit_preview_mode()
_selected_slot = -1
_last_building_slot = -1
selection_changed.emit(-1, "未选择建筑")
palette_changed.emit(_action_mode, -1)
return placed
```

Do not clear state on any failed placement path.

- [ ] **Step 5: Run focused tests and verify GREEN**

Expected: action-mode/debug-day runner passes; failed placement remains retryable and successful placement is unselected with no preview.

- [ ] **Step 6: Commit**

```powershell
git add scenes/ui/hud.tscn scripts/ui/hud.gd scripts/actors/player_action_controller.gd tests/test_hud_action_bar.gd tests/test_player_action_controller.gd
git commit -m "fix: make building placement one shot"
```

### Task 3: Carrot two-stage painted asset contract

**Files:**
- Modify: `tests/test_multi_crop_art_assets.gd`
- Modify: `tests/test_multi_crop_models.gd`
- Modify: `scripts/main.gd`
- Replace: `assets/crops/carrot/carrot_stage_0_seed.tscn`
- Replace: `assets/crops/carrot/carrot_stage_3_mature.tscn`
- Replace: `assets/crops/carrot/painted/stage_0/variant_0_front.png`
- Replace: `assets/crops/carrot/painted/stage_0/variant_0_back.png`
- Replace: `assets/crops/carrot/painted/stage_3/variant_0_front.png`
- Replace: `assets/crops/carrot/painted/stage_3/variant_0_back.png`
- Delete: carrot stage 1/2 scenes, stage 1/2 painted PNGs, stage 0/3 variant 1/2 PNGs, and unreferenced carrot material resources

- [ ] **Step 1: Move carrot into the failing two-stage test contract**

Change both crop test files to:

```gdscript
const TWO_STAGE_CROP_IDS: Array[String] = ["potato", "tomato", "lavender", "rose", "carrot"]
const LEGACY_FOUR_STAGE_CROP_IDS: Array[String] = [
	"strawberry", "blueberry", "watermelon", "sunflower", "pumpkin",
	"apple", "peach", "grape", "lemon",
]
```

The existing two-stage assertions then require exactly two scenes, four 1024-square alpha PNGs, one front/back path per scene, no procedural meshes, and logical mapping seed/seed/seed/mature.

- [ ] **Step 2: Run asset and model runners and verify RED**

Run:

```powershell
& 'C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Links\godot_console.exe' --headless --path . --script tests/run_multi_crop_art_tests.gd
& 'C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Links\godot_console.exe' --headless --path . --script tests/run_multi_crop_model_tests.gd
```

Expected: carrot fails because intermediate scenes, extra variants, procedural meshes, and four-stage mapping still exist.

- [ ] **Step 3: Generate four carrot PNGs with the built-in imagegen tool**

Inspect the grain front/back seed and mature references at original resolution. Generate one image per requested asset, with the corresponding grain direction as a style/composition reference.

Seed prompt:

```text
Use case: stylized-concept
Asset type: 3D farming-game billboard crop sprite
Primary request: Create an isolated hand-painted carrot seed-state sprite.
Subject: a small natural cluster of tiny tan-brown carrot seeds resting on a few crumbs of soil; clearly seeds, not orange roots.
Style/medium: match the reference's soft cozy painterly brushwork, warm natural highlights, readable silhouette and camera angle.
Composition/framing: centered near the lower middle, same ground contact and generous transparent padding as the grain seed reference; [front/back] view.
Constraints: genuinely transparent 1024×1024 background; consistent bottom anchor; no sprout, leaves, carrot root, pot, scenery, text, border, watermark or black background.
```

Mature prompt:

```text
Use case: stylized-concept
Asset type: 3D farming-game billboard crop sprite
Primary request: Create an isolated mature carrot crop cluster.
Subject: a compact cluster of three mature carrots growing at the soil line, with layered feathery green leaves and small visible orange root shoulders; botanically recognizable as carrots.
Style/medium: match the reference's soft cozy painterly brushwork, warm highlights, natural shading and clean readable outline.
Composition/framing: centered bottom anchor, gameplay-readable occupied height, [front/back] view.
Constraints: genuinely transparent 1024×1024 background; no pot, scenery, text, border, watermark, black background, long bare stems or geometric shapes.
```

Use `view_image` after every generation. Reject opaque corners, clipped leaves, thin-line seeds, mismatched scale, wrong anatomy, or inconsistent ground anchors. Move the selected project-bound outputs into the four exact asset paths.

- [ ] **Step 4: Author minimal two-stage carrot scenes and mapping**

Add `carrot` to `Main.TWO_STAGE_CROP_IDS`. Replace each retained scene with a root-only cluster:

```ini
[gd_scene load_steps=2 format=3]

[ext_resource path="res://scripts/visual/crop_sprite_cluster.gd" type="Script" id="1"]

[node name="CarrotStage0Seed" type="Node3D"]
script = ExtResource("1")
back_texture_paths = Array[String](["res://assets/crops/carrot/painted/stage_0/variant_0_back.png"])
front_texture_paths = Array[String](["res://assets/crops/carrot/painted/stage_0/variant_0_front.png"])
canvas_world_height = 0.45
```

The mature scene uses the stage 3 paths and `canvas_world_height = 1.05`.

- [ ] **Step 5: Audit and remove only obsolete carrot assets**

Use `rg` to prove candidate stage 1/2 scenes, variant 1/2 PNGs, and carrot materials have no references after the retained scenes are replaced. Resolve every deletion target beneath `assets/crops/carrot/` before deleting it. Remove exact verified files without globs and leave every other crop untouched.

- [ ] **Step 6: Import and verify GREEN**

Launch Godot headlessly once to refresh imports, then rerun both carrot-related runners. Expected: all art and model checks pass, including the four logical-stage aliases.

- [ ] **Step 7: Commit**

```powershell
git add tests/test_multi_crop_art_assets.gd tests/test_multi_crop_models.gd scripts/main.gd
git add -A assets/crops/carrot
git commit -m "feat: repaint carrot as two-stage crop"
```

### Task 4: Integrated verification and visual review

**Files:**
- Modify: `tests/capture_farming_visual.gd` only if the current capture does not expose carrot seed and mature views

- [ ] **Step 1: Run focused behavioral suites**

```powershell
& 'C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Links\godot_console.exe' --headless --path . --script tests/run_hud_shell_tests.gd
& 'C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Links\godot_console.exe' --headless --path . --script tests/run_action_mode_debug_day_regression_tests.gd
& 'C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Links\godot_console.exe' --headless --path . --script tests/run_inventory_storage_ui_tests.gd
& 'C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Links\godot_console.exe' --headless --path . --script tests/run_multi_crop_art_tests.gd
& 'C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Links\godot_console.exe' --headless --path . --script tests/run_multi_crop_model_tests.gd
```

Expected: every focused suite exits 0.

- [ ] **Step 2: Run the integrated baseline suite**

```powershell
& 'C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Links\godot_console.exe' --headless --path . --script tests/run_main_gameplay_integration_tests.gd
```

Expected: no more than the same two documented baseline failures; no new failure may be accepted.

- [ ] **Step 3: Capture and inspect HUD and carrot visuals**

Run the existing HUD and farming capture scripts. Inspect at original resolution that the backpack button is visible and does not overlap other HUD controls, no build-cost strip remains, and carrot seed/mature sprites have transparent backgrounds, readable silhouettes and aligned ground anchors.

- [ ] **Step 4: Check repository state and commit capture coverage if changed**

```powershell
git diff --check
git status --short
```

If capture code changed:

```powershell
git add tests/capture_farming_visual.gd
git commit -m "test: capture carrot two-stage visuals"
```

- [ ] **Step 5: Re-read the design and verify every acceptance criterion**

Confirm mouse backpack access, hover-only building details, one-shot successful placement, retryable failed placement, and carrot seed/seed/seed/mature mapping from fresh test and visual evidence.
