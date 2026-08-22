# Seed Selector Cards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Replace the dense seed table with readable, responsive, whole-card-clickable seed cards while preserving modal and hidden-refresh behavior.

**Architecture:** A reusable SeedCard Control owns card styling and input; SeedSelectorPanel owns authoritative entries, selection and modal lifecycle. The panel changes only presentation and continues using the existing inventory/farming/controller dependencies.

**Tech Stack:** Godot 4.7, GDScript, Control scenes, existing seed selector test runner.

---

### Task 1: Reusable SeedCard component

**Files:**
- Create: scenes/ui/seed_card.tscn
- Create: scripts/ui/seed_card.gd
- Create: tests/test_seed_card.gd
- Modify: tests/run_seed_selector_panel_tests.gd
- Reuse: assets/ui/hud/hud_theme.tres

- [ ] **Step 1: Write the failing card contract**

Instantiate the scene and require configure() to set item metadata, 68-pixel icon, 21-pixel name, 15-pixel metadata/status, gold quantity, green/red status, button enabled state and whole-card mouse activation.

~~~gdscript
var card = preload("res://scenes/ui/seed_card.tscn").instantiate()
tree.root.add_child(card)
var selected: Array[String] = []
card.seed_selected.connect(func(item_id: String) -> void: selected.append(item_id))
card.configure({
    "plant_item_id": "grain_seed",
    "display_name": "谷物种子",
    "quantity": 24,
    "growth_text": "成熟 3 天",
    "season_text": "春 / 秋",
    "environment_text": "露天与温室",
    "status_text": "当前可播种",
    "disabled": false,
    "icon": null,
})
assertions.truthy(card.get_node("Content/Icon").custom_minimum_size.x >= 68.0, "seed icon is readable")
assertions.truthy(card.get_node("Content/Details/NameRow/Name").get_theme_font_size("font_size") >= 21, "seed name uses large text")
var click := InputEventMouseButton.new()
click.button_index = MOUSE_BUTTON_LEFT
click.pressed = true
card.gui_input.emit(click)
assertions.equal(selected, ["grain_seed"], "whole-card click selects seed")
~~~

Repeat with disabled true and require no emission.

- [ ] **Step 2: Run and verify RED**

Expected: seed_card.tscn is missing.

- [ ] **Step 3: Implement SeedCard**

The scene contains Content/Icon, Content/Details/NameRow/Name, Quantity, Metadata, Status and SelectButton. It reuses assets/ui/hud/hud_theme.tres. The script stores plant_item_id and disabled state, connects SelectButton.pressed and root gui_input to one guarded _request_selection(), exposes set_selected(value), and never calls inventory/controller directly.

- [ ] **Step 4: Run and verify GREEN**

Expected: card contract passes with both button and root click paths.

- [ ] **Step 5: Commit**

~~~powershell
git add scenes/ui/seed_card.tscn scripts/ui/seed_card.gd tests/test_seed_card.gd tests/run_seed_selector_panel_tests.gd
git commit -m "feat: add readable seed card component"
~~~

### Task 2: Two-column responsive SeedSelectorPanel

**Files:**
- Modify: scenes/ui/seed_selector_panel.tscn
- Modify: scripts/ui/seed_selector_panel.gd
- Modify: tests/test_seed_selector_panel.gd

- [ ] **Step 1: Write failing panel-layout and click tests**

Replace row-node expectations with card expectations. At 1920×1080 require two GridContainer columns; at 640×960 require one column. Require no ColumnHeader. Require available cards to select from root gui_input and disabled cards to remain open with a red reason. Preserve existing quantity refresh, row identity, re-enter signal and pause tests using card metadata.

- [ ] **Step 2: Run and verify RED**

Expected: ColumnHeader still exists and SeedRows is a VBoxContainer.

- [ ] **Step 3: Re-author the panel scene**

Use the approved dark green 94%-opaque shell with gold border. Replace ColumnHeader and SeedRows VBox with SeedGrid GridContainer inside SeedScroll. Keep Header/CloseButton, EmptyLabel, Footer/SelectionStatus and FooterCloseButton stable. Set title to at least 27 pixels and footer text to at least 15.

- [ ] **Step 4: Replace row creation with card creation**

Preload seed_card.tscn and build this data dictionary from each authoritative entry:

~~~gdscript
var card_data := {
    "plant_item_id": item_id,
    "display_name": str(entry.item_data.get("name", crop.name)),
    "quantity": int(entry.quantity),
    "growth_text": "成熟 %d 天" % crop.growth_days,
    "season_text": _season_text(crop.seasons),
    "environment_text": _environment_text(crop.environment),
    "status_text": REASON_LABELS.get(reason, reason) if not reason.is_empty() else "当前可播种",
    "disabled": not reason.is_empty(),
    "icon": _seed_icon(crop, item_id),
}
~~~

Connect seed_selected to select_seed(), retain plant_item_id and disabled_reason metadata for tests, and update _focus_first_command() to focus the first enabled card button.

- [ ] **Step 5: Implement responsive columns**

In _apply_responsive_layout(), set SeedGrid.columns to 2 when visible viewport width is at least 900, otherwise 1. Clamp shell width to 900 and height to viewport minus 32. Do not rebuild cards on viewport change.

- [ ] **Step 6: Run and verify GREEN**

Run run_seed_selector_panel_tests.gd. Expected: previous hidden/deferred/re-enter/modal checks and new card/layout checks all pass.

- [ ] **Step 7: Commit**

~~~powershell
git add scenes/ui/seed_selector_panel.tscn scripts/ui/seed_selector_panel.gd tests/test_seed_selector_panel.gd
git commit -m "feat: redesign seed selector as responsive cards"
~~~

### Task 3: Main planting integration and visual capture

**Files:**
- Modify: tests/test_main_farming_building_integration.gd
- Create: tests/capture_seed_selector_cards.gd

- [ ] **Step 1: Add a failing real-card planting path**

Open the selector from the real seed slot, send a left mouse event to a non-grain card root, and assert synchronously that the selected plant item changes, the modal closes, the tree unpauses, planting commits and only one seed is removed.

- [ ] **Step 2: Run main gameplay runner and verify RED**

Expected: old direct select_seed path does not prove whole-card input.

- [ ] **Step 3: Update integration helpers without changing production behavior**

Find cards by plant_item_id metadata, emit one InputEventMouseButton through gui_input, and retain the immediate crop/inventory assertions before awaiting the next frame.

- [ ] **Step 4: Capture desktop and narrow layouts**

capture_seed_selector_cards.gd creates owned available and unavailable seed cards, captures 1920×1080 two-column and 640×960 one-column layouts under output/seed-selector/.

- [ ] **Step 5: Verify and commit**

Run seed selector and main gameplay runners; inspect captures for clipping and contrast. Then:

~~~powershell
git add tests/test_main_farming_building_integration.gd tests/capture_seed_selector_cards.gd
git commit -m "test: cover seed card selection integration"
~~~
