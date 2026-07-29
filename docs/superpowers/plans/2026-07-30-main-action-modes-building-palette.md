# Main Action Modes and Building Palette Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a mouse-accessible farming/building mode switcher, dynamic bottom palettes, keyboard selection, building footprint previews, continuous construction placement, and matching hand-painted tool icons to the main Godot game.

**Architecture:** `PlayerActionController` remains the sole owner of action mode, contextual selection, keyboard input, world preview, and left-click dispatch. `VillaHud` renders the controller state as a mode button, hover menu, and a dynamic six- or nine-button palette; `BuildingSystem` remains the authority for placement validity, resource transactions, footprint visuals, and construction state.

**Tech Stack:** Godot 4.7.1, GDScript, Godot Control/PopupPanel UI, existing headless `TestAssert` runners, built-in image generation with chroma-key removal.

## Global Constraints

- Reuse all nine existing building models and construction-stage assets.
- Farming mode maps `1–6`; building mode maps `1–9`.
- `P` enters farming mode; `B` enters building mode.
- The two modes remember their last valid selection independently.
- `Esc` cancels selection and preview without changing the current mode or its remembered choice.
- Successful construction placement keeps the building type selected and restores the same preview for continuous placement.
- Invalid placement never spends resources or changes grid state.
- Nine building buttons plus the mode button must fit on one row at `1280 × 720`.
- New tool icons are `256 × 256` transparent PNGs in the established warm hand-painted 2.5D style.

---

### Task 1: Contextual action-mode state and keyboard mapping

**Files:**
- Modify: `scripts/actors/player_action_controller.gd`
- Modify: `tests/test_player_action_controller.gd`

**Interfaces:**
- Consumes: existing `select_slot(index: int)`, `BuildingSystem.enter_preview_mode()`, `BuildingSystem.exit_preview_mode()`, and `GridSystem.clear_highlights()`.
- Produces:

```gdscript
enum ActionMode { FARMING, BUILDING }
signal mode_changed(mode: ActionMode)
signal palette_changed(mode: ActionMode, selected_index: int)
func switch_mode(mode: ActionMode) -> bool
func get_action_mode() -> ActionMode
func select_mode_slot(index: int) -> bool
func get_mode_selected_slot(mode: ActionMode) -> int
func cancel_current_selection() -> bool
```

- [ ] **Step 1: Write failing controller tests**

Extend the controller doubles so `BuildingDouble` records preview entry/exit and add assertions:

```gdscript
assertions.equal(controller.get_action_mode(), 0, "controller starts in farming mode")
assertions.truthy(controller.switch_mode(1), "B mode switches to building")
assertions.equal(controller.get_mode_selected_slot(1), 0, "building defaults to barn")
assertions.equal(building.entered_ids, ["barn"], "building selection enters its preview")
assertions.truthy(controller.select_mode_slot(8), "building accepts slot nine")
assertions.equal(building.entered_ids[-1], "fence", "slot nine selects fence")
assertions.truthy(not controller.select_mode_slot(9), "building rejects slot ten")
assertions.truthy(controller.switch_mode(0), "P mode switches back to farming")
assertions.truthy(controller.select_mode_slot(5), "farming accepts slot six")
assertions.truthy(not controller.select_mode_slot(6), "farming rejects slot seven")
assertions.truthy(controller.cancel_current_selection(), "escape contract cancels selection")
assertions.equal(controller.get_selected_slot(), -1, "cancel clears active selection")
assertions.truthy(controller.switch_mode(1), "building mode restores after cancel")
assertions.equal(controller.get_mode_selected_slot(1), 8, "building remembers fence")
```

Also assert that `slot_from_key(KEY_9)` returns `8` only while building mode is active.

- [ ] **Step 2: Run the targeted runner and verify RED**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path /Users/huanggui/UnrealEngine/villa/.worktrees/action-modes-building-palette \
  --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: FAIL because the action-mode API and building key mapping do not exist.

- [ ] **Step 3: Implement the minimal mode state**

Add fixed contextual data:

```gdscript
const BUILDING_IDS: Array[String] = [
    "barn", "greenhouse", "windmill", "chicken_coop", "beehive",
    "well", "workbench", "lamp", "fence",
]

var _action_mode := ActionMode.FARMING
var _active_mode_slot := 0
var _last_farming_slot := 0
var _last_building_slot := 0
```

Implement `switch_mode()` to clean the old preview, restore the target mode's remembered slot, activate the target selection, and emit both mode signals. Implement `select_mode_slot()` as the only mouse/keyboard selection entry point. Preserve `select_slot()` as a farming-compatible wrapper for existing callers.

Change `slot_from_key()` to accept `1–6` in farming and `1–9` in building. Handle `P`, `B`, digits, and `Esc` in `_unhandled_input()` in that order.

- [ ] **Step 4: Run the targeted runner and verify GREEN**

Run the command from Step 2.

Expected: controller checks pass with no parse errors.

- [ ] **Step 5: Commit**

```bash
git add scripts/actors/player_action_controller.gd tests/test_player_action_controller.gd
git commit -m "feat: add contextual farming and building modes"
```

---

### Task 2: Dynamic HUD palette and hover mode menu

**Files:**
- Modify: `scenes/ui/hud.tscn`
- Modify: `scripts/ui/hud.gd`
- Modify: `tests/test_hud_action_bar.gd`
- Modify: `tests/test_runtime_ui_scenes.gd`

**Interfaces:**
- Consumes: Task 1 mode API and signals, `InventorySystem.get_item_count()`, `EconomySystem.has_resources()`, and `GameData.get_building()`.
- Produces:

```gdscript
func configure_action_bar(controller: Variant, inventory: Variant, economy: Variant = null) -> void
func rebuild_action_palette() -> void
func set_mode_menu_open(open: bool) -> void
func get_palette_button_count() -> int
```

- [ ] **Step 1: Write failing HUD tests**

Replace assumptions about six authored static children with state-driven assertions:

```gdscript
hud.configure_action_bar(controller, inventory, economy)
assertions.equal(hud.get_palette_button_count(), 6, "farming palette has six buttons")
assertions.equal(hud.mode_button.text, "种植", "mode button shows farming")
controller.switch_mode(PlayerActionController.ActionMode.BUILDING)
assertions.equal(hud.get_palette_button_count(), 9, "building palette has nine buttons")
assertions.equal(hud.mode_button.text, "建造", "mode button shows building")
(hud.quick_bar.get_child(8) as Button).pressed.emit()
assertions.equal(controller.get_mode_selected_slot(1), 8, "mouse selects fence through controller")
hud.set_mode_menu_open(true)
assertions.truthy(hud.mode_menu.visible, "hover contract opens mode menu")
```

Update the runtime scene contract to require:

```gdscript
"BottomBar/ActionRow/ModeButton"
"BottomBar/ActionRow/QuickBar"
"BottomBar/ModeMenu"
```

- [ ] **Step 2: Run the targeted runner and verify RED**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path /Users/huanggui/UnrealEngine/villa/.worktrees/action-modes-building-palette \
  --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: FAIL because the mode controls and dynamic palette API are absent.

- [ ] **Step 3: Author the mode controls**

Change `BottomBar` to contain:

```text
BottomBar
├── ToolLabel
├── ModeMenu
│   └── VBox
│       ├── FarmingModeButton
│       └── BuildingModeButton
└── ActionRow
    ├── ModeButton
    └── QuickBar
```

Use a `PopupPanel` or styled `PanelContainer` anchored above `ModeButton`. Connect mouse enter/exit for the button and menu; close through a short `SceneTreeTimer` only if neither control is hovered. Set all HUD controls to stop mouse input from reaching the world.

- [ ] **Step 4: Implement palette rebuilding**

Use these ordered definitions:

```gdscript
const FARMING_LABELS := ["锄头", "浇水壶", "斧头", "镐", "鱼竿", "谷物种子"]
const BUILDING_IDS := PlayerActionController.BUILDING_IDS
```

`rebuild_action_palette()` frees prior dynamic buttons, creates exactly the contextual count, connects each `pressed` signal to `select_mode_slot(index)`, updates button pressed state, and uses compact `56 × 58` building buttons with `4px` separation.

For building mode, load `BuildingData`, display its short name, footprint and cost tooltip, and modulate the button when `economy.has_resources(data.cost)` is false without disabling it.

- [ ] **Step 5: Run the targeted runner and verify GREEN**

Run the command from Step 2.

Expected: dynamic palette and mouse selection checks pass.

- [ ] **Step 6: Commit**

```bash
git add scenes/ui/hud.tscn scripts/ui/hud.gd tests/test_hud_action_bar.gd tests/test_runtime_ui_scenes.gd
git commit -m "feat: add dynamic action mode palette"
```

---

### Task 3: Main-scene building preview and continuous left-click placement

**Files:**
- Modify: `scripts/actors/player_action_controller.gd`
- Modify: `scripts/main.gd`
- Modify: `scripts/ui/build_ui.gd`
- Modify: `tests/test_main_farming_building_integration.gd`
- Modify: `tests/test_main_pointer_farming.gd`

**Interfaces:**
- Consumes: Task 1 selection state, `BuildingSystem.update_preview_position()`, `get_preview_can_place()`, and `place_selected_building()`.
- Produces: a single world-preview invariant and continuous placement behavior.

- [ ] **Step 1: Write failing main-scene integration tests**

Extend the pointer test:

```gdscript
main.action_controller.switch_mode(PlayerActionController.ActionMode.BUILDING)
main.action_controller.select_mode_slot(0)
main.action_controller.call("_input", motion)
main.action_controller._process(0.0)
assertions.truthy(main.building_system.is_in_build_mode(), "building mode owns preview")
assertions.equal(
    main.building_system.get_preview_marker_count(),
    6,
    "barn preview shows its 3x2 footprint"
)
```

Find one valid and one blocked origin. Snapshot resource counts and grid states. Assert blocked left click leaves both unchanged. Click the valid origin and assert:

```gdscript
assertions.equal(placed.construction_stage, BuildingInstance.ConstructionStage.FOUNDATION)
assertions.equal(main.building_system.get_selected_building_id(), "barn")
assertions.truthy(main.building_system.is_in_build_mode(), "preview continues after placement")
```

Switch to farming and assert `BuildingPreview.visible == false`; cancel and assert the cell highlight is hidden.

- [ ] **Step 2: Run the targeted runner and verify RED**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path /Users/huanggui/UnrealEngine/villa/.worktrees/action-modes-building-palette \
  --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: FAIL because placement currently exits build mode and does not restore continuous preview.

- [ ] **Step 3: Implement contextual pointer processing**

In `_process()`:

```gdscript
if _action_mode == ActionMode.BUILDING:
    grid_system.clear_highlights()
    if _active_mode_slot >= 0 and ground_point is Vector3:
        building_system.update_preview_position(ground_point.x, ground_point.z)
    return
```

In pointer action dispatch, route building mode before interaction targets. On successful placement, capture the building ID, call `enter_preview_mode(id)`, and update the new preview at the same ground point. On failure, retain the existing preview.

When switching back to farming, exit building preview before restoring the farming slot. When cancelling building selection, exit preview and do not reactivate it until another slot click or mode re-entry.

- [ ] **Step 4: Disable legacy `BuildUI` global input**

Add:

```gdscript
@export var keyboard_shortcut_enabled := true
```

Guard its `_unhandled_input()` with this property. In `main.gd`, set it to `false`, configure the HUD with `economy_system`, and leave `BuildUI` hidden for compatibility.

- [ ] **Step 5: Run the targeted runner and verify GREEN**

Run the command from Step 2.

Expected: pointer, invalid placement, construction-stage, continuous-preview, mode cleanup, and prior farming checks all pass.

- [ ] **Step 6: Commit**

```bash
git add scripts/actors/player_action_controller.gd scripts/main.gd scripts/ui/build_ui.gd \
  tests/test_main_farming_building_integration.gd tests/test_main_pointer_farming.gd
git commit -m "feat: integrate building placement into main pointer flow"
```

---

### Task 4: Hand-painted tool icons and palette imagery

**Files:**
- Create: `assets/ui/action_icons/hoe.png`
- Create: `assets/ui/action_icons/watering_can.png`
- Create: `assets/ui/action_icons/axe.png`
- Create: `assets/ui/action_icons/pickaxe.png`
- Create: `assets/ui/action_icons/fishing_rod.png`
- Modify: `scripts/ui/hud.gd`
- Modify: `tests/test_hud_action_bar.gd`

**Interfaces:**
- Consumes: built-in image generation, the installed chroma-key removal helper, existing building front PNGs, and existing grain painted PNGs.
- Produces: five alpha PNG tool icons and populated button icons in both modes.

- [ ] **Step 1: Write failing asset and binding tests**

For every tool icon path:

```gdscript
assertions.truthy(ResourceLoader.exists(path), "tool icon imports: %s" % path)
var texture := load(path) as Texture2D
assertions.equal(texture.get_width(), 256, "tool icon width is 256")
assertions.equal(texture.get_height(), 256, "tool icon height is 256")
```

After configuring farming mode, assert all six buttons have non-null icons. After switching to building mode, assert all nine buttons use non-null building icons.

- [ ] **Step 2: Run the targeted runner and verify RED**

Run the main gameplay runner.

Expected: FAIL because the five icon files do not exist and palette buttons do not bind images.

- [ ] **Step 3: Generate five source icons**

Use one built-in image-generation call per opaque tool. Use the following normalized prompt for each of the five exact subjects listed below:

```text
Use case: stylized-concept
Asset type: 2.5D cozy farming game action-bar icon
Primary request: one centered tool only, using exactly one of the five subjects below
Scene/backdrop: perfectly flat solid #ff00ff chroma-key background
Style/medium: warm hand-painted storybook game asset matching rustic painted farm buildings and trees
Composition/framing: square, centered three-quarter view, generous padding, strong readable silhouette
Lighting/mood: soft warm daylight, gentle painted shading
Materials/textures: aged wood and softly painted metal appropriate to the tool
Constraints: one complete tool, no cropped edges, no cast shadow, no ground plane, no text, no border, no watermark; do not use #ff00ff in the subject
```

Make five separate calls, with these exact `Subject:` lines:

```text
Subject: traditional wooden-handled garden hoe
Subject: rounded farmhouse watering can with handle and spout
Subject: compact wooden-handled felling axe
Subject: compact wooden-handled mining pickaxe
Subject: simple rustic fishing rod with reel and short curved line
```

- [ ] **Step 4: Remove chroma key and validate**

Copy each generated source into `tmp/imagegen/`, then run:

```bash
for tool in hoe watering_can axe pickaxe fishing_rod
do
  python "${CODEX_HOME:-$HOME/.codex}/skills/.system/imagegen/scripts/remove_chroma_key.py" \
    --input "tmp/imagegen/${tool}-source.png" \
    --out "assets/ui/action_icons/${tool}.png" \
    --auto-key border --soft-matte \
    --transparent-threshold 12 --opaque-threshold 220 --despill
done
```

Resize final images to exactly `256 × 256` without changing aspect ratio, inspect all five with the image viewer, and verify alpha corners plus clean subject edges. Retry once with `--edge-contract 1` only if a magenta fringe remains.

- [ ] **Step 5: Bind all palette icons**

Add fixed icon paths for farming mode. Use:

```text
res://assets/crops/grain/painted/stage_0/variant_0_front.png
```

for seed, and:

```gdscript
"res://assets/buildings/painted/%s/%s_front.png" % [building_id, building_id]
```

for buildings. Set `expand_icon = true`, preserve aspect, and size button icons without hiding number/name text.

- [ ] **Step 6: Import and run the targeted runner**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --editor --path /Users/huanggui/UnrealEngine/villa/.worktrees/action-modes-building-palette --quit
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path /Users/huanggui/UnrealEngine/villa/.worktrees/action-modes-building-palette \
  --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: all icon resources import and all palette image checks pass.

- [ ] **Step 7: Commit**

```bash
git add assets/ui/action_icons scripts/ui/hud.gd tests/test_hud_action_bar.gd
git commit -m "art: add hand-painted action palette icons"
```

---

### Task 5: Documentation and complete verification

**Files:**
- Modify: `docs/detailed-design.md`
- Modify: `docs/superpowers/plans/2026-07-30-main-action-modes-building-palette.md`

**Interfaces:**
- Consumes: completed Tasks 1–4.
- Produces: aligned design documentation and fresh verification evidence.

- [ ] **Step 1: Update detailed design**

Document the exact mode mapping, building order, mouse menu, per-mode selection memory, `Esc` behavior, and continuous placement under the main-game input/building sections.

- [ ] **Step 2: Mark completed plan checkboxes**

Change each executed `- [ ]` in this plan to `- [x]` only after its command has passed.

- [ ] **Step 3: Run all system test runners**

```bash
for runner in \
  run_tests.gd \
  run_grid_system_tests.gd \
  run_farming_system_tests.gd \
  run_building_system_tests.gd \
  run_main_gameplay_integration_tests.gd
do
  /Applications/Godot.app/Contents/MacOS/Godot \
    --headless --path /Users/huanggui/UnrealEngine/villa/.worktrees/action-modes-building-palette \
    --script "res://tests/$runner" || exit 1
done
```

Expected: all five runners exit `0`.

- [ ] **Step 4: Run editor parsing and main-scene smoke checks**

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --editor --path /Users/huanggui/UnrealEngine/villa/.worktrees/action-modes-building-palette --quit
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path /Users/huanggui/UnrealEngine/villa/.worktrees/action-modes-building-palette --quit-after 10
git diff --check
```

Expected: every command exits `0`, with no new GDScript parse/runtime error.

- [ ] **Step 5: Commit**

```bash
git add docs/detailed-design.md docs/superpowers/plans/2026-07-30-main-action-modes-building-palette.md
git commit -m "docs: document main action mode controls"
```
