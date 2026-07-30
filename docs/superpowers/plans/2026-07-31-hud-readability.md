# HUD Readability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the bottom action icons and top-left status values clearly readable on the existing `3000 × 2000` game canvas while preserving all farming/building interactions.

**Architecture:** Add a focused `ActionPaletteButton` scene that owns icon, shortcut badge, name label, and visual state, then make `VillaHud` instantiate it for both mode and action buttons. Restructure the top status row under a styled `PanelContainer`; controller, inventory, economy, and world-interaction state remain unchanged.

**Tech Stack:** Godot 4.7.1, GDScript, Godot Control nodes and theme overrides, existing `TestAssert` headless runners.

---

## File Map

- Create `scripts/ui/action_palette_button.gd`: reusable presentation and state API for one action tile.
- Create `scenes/ui/action_palette_button.tscn`: authored icon, shortcut, name, and button style hierarchy.
- Create `tests/test_action_palette_button.gd`: component-level sizing, readability, and state tests.
- Modify `tests/run_main_gameplay_integration_tests.gd`: include the component test.
- Modify `scenes/ui/hud.tscn`: styled top status panel, larger bottom layout, and reusable mode tile.
- Modify `scripts/ui/hud.gd`: instantiate/configure action tiles and update paths.
- Modify `tests/test_hud_action_bar.gd`: top-panel and integrated palette contracts.
- Modify `tests/test_runtime_ui_scenes.gd`: new top status node paths.
- Modify `docs/detailed-design.md`: record final HUD metrics and component boundary.

---

### Task 1: Reusable icon-dominant action button

**Files:**
- Create: `scripts/ui/action_palette_button.gd`
- Create: `scenes/ui/action_palette_button.tscn`
- Create: `tests/test_action_palette_button.gd`
- Modify: `tests/run_main_gameplay_integration_tests.gd`

- [ ] **Step 1: Write the failing component test**

Create `tests/test_action_palette_button.gd`:

```gdscript
extends RefCounted

const ButtonScene = preload("res://scenes/ui/action_palette_button.tscn")


func run(assertions: TestAssert, tree: SceneTree) -> void:
	var button = ButtonScene.instantiate()
	tree.root.add_child(button)
	var texture := load("res://assets/ui/action_icons/hoe.png") as Texture2D
	button.configure(1, "锄头", texture)

	assertions.equal(button.custom_minimum_size, Vector2(112, 116), "action tile uses readable size")
	assertions.equal(button.icon_rect.custom_minimum_size, Vector2(84, 84), "icon gets an 84px square")
	assertions.equal(button.icon_rect.texture, texture, "configured icon is displayed")
	assertions.equal(button.shortcut_label.text, "1", "shortcut badge shows key")
	assertions.equal(button.name_label.text, "锄头", "tile shows action name")
	assertions.truthy(
		button.name_label.get_theme_font_size("font_size") >= 22,
		"action name uses readable font"
	)
	assertions.truthy(
		button.name_label.get_theme_constant("outline_size") >= 3,
		"action name has a dark outline"
	)
	assertions.equal(
		button.icon_rect.mouse_filter,
		Control.MOUSE_FILTER_IGNORE,
		"icon cannot consume tile clicks"
	)

	button.set_available(false)
	assertions.truthy(button.icon_rect.modulate != Color.WHITE, "unavailable dims only icon")
	assertions.equal(button.name_label.modulate, Color.WHITE, "unavailable keeps name legible")
	button.set_selected(true)
	assertions.truthy(button.button_pressed, "selected state uses button pressed state")
	button.free()
```

Register it before `HudActionBarTest` in `tests/run_main_gameplay_integration_tests.gd`:

```gdscript
const ActionPaletteButtonTest = preload("res://tests/test_action_palette_button.gd")

# in _run()
ActionPaletteButtonTest.new().run(assertions, self)
```

- [ ] **Step 2: Run the main integration runner and verify RED**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path /Users/huanggui/UnrealEngine/villa/.worktrees/hud-readability \
  --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: parse/load failure because `action_palette_button.tscn` does not exist.

- [ ] **Step 3: Implement the component script**

Create `scripts/ui/action_palette_button.gd`:

```gdscript
class_name ActionPaletteButton
extends Button

@onready var icon_rect: TextureRect = $Icon
@onready var shortcut_label: Label = $ShortcutLabel
@onready var name_label: Label = $NameLabel


func configure(shortcut: int, display_name: String, texture: Texture2D) -> void:
	shortcut_label.text = str(shortcut)
	name_label.text = display_name
	icon_rect.texture = texture


func set_selected(selected: bool) -> void:
	set_pressed_no_signal(selected)


func set_available(available: bool) -> void:
	icon_rect.modulate = Color.WHITE if available else Color(0.48, 0.48, 0.48, 0.82)
	name_label.modulate = Color.WHITE
	shortcut_label.modulate = Color.WHITE


func set_shortcut_visible(visible: bool) -> void:
	shortcut_label.visible = visible
```

- [ ] **Step 4: Author the component scene**

Create `scenes/ui/action_palette_button.tscn` with:

```text
ActionPaletteButton (Button, 112 × 116, toggle_mode=true)
├── Icon (TextureRect, 84 × 84, KEEP_ASPECT_CENTERED)
├── ShortcutLabel (Label, 26px, dark text on warm-gold StyleBoxFlat)
└── NameLabel (Label, 22px cream, 3px dark outline)
```

Use these exact layout constraints:

```gdscript
Icon offsets: left=14, top=5, right=98, bottom=89
ShortcutLabel offsets: left=5, top=5, right=37, bottom=37
NameLabel offsets: left=4, top=88, right=108, bottom=114
```

Set all three child controls to `MOUSE_FILTER_IGNORE`. Give the root button separate deep-olive `normal`, brighter `hover`, and gold-border `pressed` `StyleBoxFlat` resources. The pressed border is `3px`; normal/hover borders are `2px`.

- [ ] **Step 5: Run the targeted runner and verify GREEN**

Run the command from Step 2.

Expected: component checks pass and the runner exits `0`.

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/action_palette_button.gd scenes/ui/action_palette_button.tscn \
  tests/test_action_palette_button.gd tests/run_main_gameplay_integration_tests.gd
git commit -m "feat: add readable action palette button"
```

---

### Task 2: High-contrast top status panel

**Files:**
- Modify: `scenes/ui/hud.tscn`
- Modify: `scripts/ui/hud.gd`
- Modify: `tests/test_hud_action_bar.gd`
- Modify: `tests/test_runtime_ui_scenes.gd`

- [ ] **Step 1: Write failing top-panel tests**

Add near the start of `tests/test_hud_action_bar.gd` after the HUD is added:

```gdscript
assertions.truthy(hud.get_node("TopBar") is PanelContainer, "top status owns a background panel")
var status_labels: Array[Label] = [
	hud.gold_label,
	hud.level_label,
	hud.season_label,
	hud.time_label,
]
for label in status_labels:
	assertions.truthy(label.get_theme_font_size("font_size") >= 32, "status font is readable")
	assertions.truthy(label.get_theme_constant("outline_size") >= 4, "status font is outlined")
	assertions.equal(label.get_theme_color("font_color"), Color("fff1d0"), "status text is cream")
assertions.truthy(hud.stamina_bar.custom_minimum_size.y >= 44.0, "stamina bar is tall enough")
assertions.truthy(hud.exp_bar.custom_minimum_size.y >= 44.0, "experience bar is tall enough")
var top_style := (hud.get_node("TopBar") as PanelContainer).get_theme_stylebox("panel")
assertions.truthy(top_style is StyleBoxFlat, "top status uses a flat readable panel")
if top_style is StyleBoxFlat:
	assertions.truthy(top_style.bg_color.a >= 0.86, "top panel masks busy world backgrounds")
```

Change HUD node contracts in `tests/test_runtime_ui_scenes.gd` to:

```gdscript
"TopBar/StatusRow/StaminaBar",
"TopBar/StatusRow/GoldLabel",
"TopBar/StatusRow/LevelLabel",
"TopBar/StatusRow/ExpBar",
"TopBar/StatusRow/SeasonLabel",
"TopBar/StatusRow/TimeLabel",
```

- [ ] **Step 2: Run the main integration and runtime UI runners and verify RED**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path /Users/huanggui/UnrealEngine/villa/.worktrees/hud-readability \
  --script res://tests/run_main_gameplay_integration_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path /Users/huanggui/UnrealEngine/villa/.worktrees/hud-readability \
  --script res://tests/test_runtime_ui_scenes.gd
```

Expected: failures because `TopBar` is an `HBoxContainer`, has no `StatusRow`, and uses default font metrics.

- [ ] **Step 3: Restructure and style `TopBar`**

In `scenes/ui/hud.tscn`:

1. Change `TopBar` to `PanelContainer`.
2. Add `StatusRow (HBoxContainer)` beneath it.
3. Move the six existing status nodes under `StatusRow`.
4. Add a `StyleBoxFlat` panel resource with:

```gdscript
bg_color = Color(0.105, 0.145, 0.12, 0.90)
border_color = Color(0.82, 0.65, 0.34, 0.92)
border_width_left/right/top/bottom = 2
corner_radius_top_left/top_right/bottom_left/bottom_right = 12
content_margin_left/right = 18
content_margin_top/bottom = 12
```

5. Set the four labels to `font_size=32`, `font_color=#fff1d0`, `font_outline_color=#172019`, `outline_size=4`.
6. Set `StatusRow` separation to `18`.
7. Change `StaminaBar` to `260 × 44` and `ExpBar` to `220 × 44`.

- [ ] **Step 4: Update HUD script paths**

Change only the six top-node paths in `scripts/ui/hud.gd`:

```gdscript
@onready var stamina_bar: ProgressBar = $TopBar/StatusRow/StaminaBar
@onready var gold_label: Label = $TopBar/StatusRow/GoldLabel
@onready var level_label: Label = $TopBar/StatusRow/LevelLabel
@onready var exp_bar: ProgressBar = $TopBar/StatusRow/ExpBar
@onready var season_label: Label = $TopBar/StatusRow/SeasonLabel
@onready var time_label: Label = $TopBar/StatusRow/TimeLabel
```

- [ ] **Step 5: Run both targeted runners and verify GREEN**

Run both commands from Step 2.

Expected: top panel, node path, font, outline, and bar-size checks pass.

- [ ] **Step 6: Commit**

```bash
git add scenes/ui/hud.tscn scripts/ui/hud.gd \
  tests/test_hud_action_bar.gd tests/test_runtime_ui_scenes.gd
git commit -m "feat: improve top status readability"
```

---

### Task 3: Integrate large tiles into the dynamic HUD palette

**Files:**
- Modify: `scenes/ui/hud.tscn`
- Modify: `scripts/ui/hud.gd`
- Modify: `tests/test_hud_action_bar.gd`

- [ ] **Step 1: Replace generic-button expectations with failing tile tests**

Update action-bar assertions in `tests/test_hud_action_bar.gd`:

```gdscript
assertions.equal(quick_bar.get_child_count(), 6, "farming palette has six buttons")
for child in quick_bar.get_children():
	assertions.truthy(child is ActionPaletteButton, "farming uses readable action tiles")
	if child is ActionPaletteButton:
		assertions.equal(child.icon_rect.custom_minimum_size, Vector2(84, 84), "tile icon is large")
assertions.equal(
	(quick_bar.get_child(0) as ActionPaletteButton).name_label.text,
	"锄头",
	"first tile labels the hoe"
)
assertions.equal(
	(quick_bar.get_child(5) as ActionPaletteButton).name_label.text,
	"种子 ×2",
	"seed tile keeps quantity concise and readable"
)
assertions.truthy(hud.mode_button is ActionPaletteButton, "mode switch uses the large tile")
assertions.truthy(hud.tool_label.get_theme_font_size("font_size") >= 28, "selection text is readable")
```

After switching to building mode:

```gdscript
assertions.equal(hud.get_palette_button_count(), 9, "building palette has nine tiles")
assertions.truthy(
	hud.get_node("BottomBar/ActionRow").get_combined_minimum_size().x <= 1280.0,
	"large building palette still fits one row"
)
```

Add an unavailable-resource assertion using an economy double that returns `false`:

```gdscript
assertions.equal(tile.name_label.modulate, Color.WHITE, "resource dimming keeps text opaque")
assertions.truthy(tile.icon_rect.modulate != Color.WHITE, "resource dimming targets icon")
```

- [ ] **Step 2: Run the main integration runner and verify RED**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path /Users/huanggui/UnrealEngine/villa/.worktrees/hud-readability \
  --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: failures because the HUD still creates generic `Button` nodes and uses native icon/text layout.

- [ ] **Step 3: Author the enlarged bottom layout**

In `scenes/ui/hud.tscn`:

- Increase `BottomBar` width to `1280px` using offsets `-640` and `640`.
- Increase its height and top offset so `116px` tiles and `ToolLabel` remain above the bottom edge.
- Set `ToolLabel` to `font_size=28`, cream text, and `outline_size=4`.
- Increase the mode popup to fit `24px` menu labels.
- Replace authored `ModeButton` with an instance of `action_palette_button.tscn`.
- Override `ModeButton.toggle_mode=false` and keep its existing node path.

- [ ] **Step 4: Instantiate and configure `ActionPaletteButton`**

In `scripts/ui/hud.gd`:

```gdscript
const ActionPaletteButtonScene = preload("res://scenes/ui/action_palette_button.tscn")

@onready var mode_button: ActionPaletteButton = $BottomBar/ActionRow/ModeButton
```

In `rebuild_action_palette()`:

```gdscript
mode_button.configure(
	0,
	"建造" if building_mode else "种植",
	_load_palette_icon(
		_building_icon_path("barn")
		if building_mode
		else FARMING_ICON_PATHS[PlayerActionController.SEED_SLOT]
	)
)
mode_button.set_shortcut_visible(false)

for index in range(labels.size()):
	var button := ActionPaletteButtonScene.instantiate() as ActionPaletteButton
	quick_bar.add_child(button)
	var display_name := str(labels[index])
	if not building_mode and index == PlayerActionController.SEED_SLOT:
		var quantity := inventory_ref.get_item_count(PlayerActionController.SEED_ITEM_ID)
		display_name = "种子 ×%d" % quantity
	button.configure(index + 1, display_name, _palette_texture(index, building_mode))
	button.pressed.connect(_on_quick_slot_pressed.bind(index))
```

Extract the existing path logic into:

```gdscript
func _palette_texture(index: int, building_mode: bool) -> Texture2D:
	var path := ""
	if building_mode and index >= 0 and index < PlayerActionController.BUILDING_IDS.size():
		path = _building_icon_path(PlayerActionController.BUILDING_IDS[index])
	elif not building_mode and index >= 0 and index < FARMING_ICON_PATHS.size():
		path = FARMING_ICON_PATHS[index]
	return _load_palette_icon(path)
```

In `refresh_action_bar()`, update the seed tile with `configure()` only when quantity changes, call `button.set_selected(index == selected)`, and call `button.set_available(available)`. Do not modulate the entire button.

- [ ] **Step 5: Preserve click and mode-menu behavior**

Keep these existing signal connections unchanged:

```gdscript
button.pressed.connect(_on_quick_slot_pressed.bind(index))
mode_button.pressed.connect(_on_mode_button_pressed)
mode_button.mouse_entered.connect(_on_mode_menu_mouse_entered)
mode_button.mouse_exited.connect(_on_mode_menu_mouse_exited)
```

Keep Tooltip content on the root tile. If an icon fails to load, `configure()` receives `null`; shortcut and name remain visible.

- [ ] **Step 6: Run the main integration runner and verify GREEN**

Run the command from Step 2.

Expected: large-tile, mode switch, quantity, one-row width, mouse selection, and existing pointer integration checks all pass.

- [ ] **Step 7: Commit**

```bash
git add scenes/ui/hud.tscn scripts/ui/hud.gd tests/test_hud_action_bar.gd
git commit -m "feat: enlarge HUD action palette"
```

---

### Task 4: Documentation and completion verification

**Files:**
- Modify: `docs/detailed-design.md`
- Modify: `docs/superpowers/plans/2026-07-31-hud-readability.md`

- [ ] **Step 1: Update detailed design**

Update sections `5.4 HUD` and `7.1 HUD` to document:

- `TopBar/StatusRow` structure.
- `32px` outlined status text and high-opacity panel.
- `ActionPaletteButton` ownership of icon, shortcut, name, and availability.
- `112 × 116` tile and `84 × 84` icon metrics.
- `1280px` maximum combined action-row width.

- [ ] **Step 2: Mark completed plan checkboxes**

Change executed `- [ ]` steps to `- [x]` only after the corresponding commands have passed.

- [ ] **Step 3: Import and run all test suites**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --editor --path /Users/huanggui/UnrealEngine/villa/.worktrees/hud-readability --quit

for runner in \
  run_tests.gd \
  run_grid_system_tests.gd \
  run_farming_system_tests.gd \
  run_building_system_tests.gd \
  run_main_gameplay_integration_tests.gd
do
  /Applications/Godot.app/Contents/MacOS/Godot \
    --headless --path /Users/huanggui/UnrealEngine/villa/.worktrees/hud-readability \
    --script "res://tests/$runner" || exit 1
done

/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path /Users/huanggui/UnrealEngine/villa/.worktrees/hud-readability \
  --script res://tests/test_runtime_ui_scenes.gd
```

Expected: editor and all six runners exit `0`, with no new parse/runtime error.

- [ ] **Step 4: Run the main scene and static checks**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --path /Users/huanggui/UnrealEngine/villa/.worktrees/hud-readability \
  --quit-after 10
git diff --check
```

Expected: main scene exits `0` with no `SCRIPT ERROR`; `git diff --check` exits `0`.

- [ ] **Step 5: Commit**

```bash
git add docs/detailed-design.md docs/superpowers/plans/2026-07-31-hud-readability.md
git commit -m "docs: document readable HUD metrics"
```
