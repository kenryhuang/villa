# Villa UI and Main Scene Integration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Assemble the completed deterministic systems into the main scene and provide the management HUD, inventory, building, map, dialogue, shop, notifications, and audio shell described by the detailed design.

**Architecture:** UI controllers observe EventBus and call narrow system commands; they never mutate system collections directly. `Main` owns dependency wiring and startup order, while each screen is an independently testable scene that can be hidden until its backing system is ready.

**Tech Stack:** Godot 4.7, GDScript, Control/CanvasLayer, SubViewport, signals.

## Global Constraints

- Preserve `1280×720`, `canvas_items`, and `expand` window behavior.
- UI refreshes on signals or screen open; only the 2D minimap player marker may update every frame.
- Opening a modal screen releases the mouse and blocks world tool input; closing the last modal restores gameplay input.
- UI must not depend on Node absolute paths outside its configured dependencies.
- Main startup order is world, systems, player, villagers, UI bindings, then save load.

---

### Task 1: UI navigation and modal ownership

**Files:** Create `scripts/ui/ui_router.gd`, `tests/test_ui_router.gd`; modify `project.godot`, `tests/run_tests.gd`.

**Interfaces:** `UIRouter.register_screen(id, control)`, `open(id)`, `close(id)`, `close_top()`, `is_modal_open()`, and signal `modal_state_changed(open)`.

- [ ] Write failing tests for single-modal visibility, ESC close order, duplicate open, unknown screen rejection, and mouse/input state.
- [ ] Run the full suite; expect missing router failure.
- [ ] Implement a stack with IDs `inventory`, `build`, `map`, `dialogue`, `shop`; prevent duplicate entries and restore the previous modal after closing the top.
- [ ] Add Input Map actions from Appendix B: `interact`, `sprint`, `inventory`, `map`, `tool_1` through `tool_6`, and `build_mode`.
- [ ] Run tests and commit `feat: add villa UI routing and input actions`.

### Task 2: Management HUD and notifications

**Files:** Modify `scenes/ui/hud.tscn`, `scripts/ui/hud.gd`; create `scenes/ui/notification.tscn`, `scripts/ui/notification.gd`, `tests/test_hud_binding.gd`; modify `tests/run_tests.gd`.

**Interfaces:** `VillaHud.bind(event_bus, inventory, player_state, season, game_state)`, setters for stamina/gold/level/date/time/quick slots, and `show_notification(text, icon_path)`.

- [ ] Write failing tests emitting each documented EventBus signal and asserting exact label/progress values; verify stamina under 30 uses red tint and notifications expire after 3 seconds.
- [ ] Run tests and verify RED.
- [ ] Build the TopBar and BottomBar hierarchy from section 7.1, six 48×48 quick slots, 120×90 minimap container, and pooled notification panel.
- [ ] Bind signals once in `_ready`, disconnect on dependency rebind, and perform no state polling in `_process` except minimap marker position.
- [ ] Run tests and visual capture, then commit `feat: replace combat HUD with management HUD`.

### Task 3: Inventory and building screens

**Files:** Modify `scenes/ui/inventory_ui.tscn`, `scripts/ui/inventory_ui.gd`; create `scenes/ui/build_ui.tscn`, `scripts/ui/build_ui.gd`, `tests/test_inventory_build_ui.gd`; modify `tests/run_tests.gd`.

**Interfaces:** Consume `InventorySystem.swap_slots`, `set_quick_slot`, `BuildingSystem.enter_preview_mode`, `update_preview`, `place_building`, and `exit_preview_mode` from earlier plans.

- [ ] Write failing tests for 20-slot rendering, category filtering, drag/drop, quick assignment, unaffordable building disabled state, preview entry, place confirmation, and cancellation.
- [ ] Run tests and verify RED.
- [ ] Implement screen trees exactly as sections 7.2 and 7.3. Inventory drag/drop calls `swap_slots(from_index, to_index)` and quick assignment calls `set_quick_slot(slot_index, quick_index)`. Selecting a building enters preview; cursor movement calls `update_preview(gx, gz)` and confirmation calls `place_building(selected_building, gx, gz)`. Load item icons only from `GameData`; never trust a UI-provided item or building cost.
- [ ] Route Tab/I and B through UIRouter and suppress player tools while visible.
- [ ] Run tests and commit `feat: add inventory and building interfaces`.

### Task 4: Map, dialogue, and shop screens

**Files:** Modify `scenes/ui/map_ui.tscn`, `scripts/ui/map_ui.gd`, `scenes/ui/dialogue_ui.tscn`, `scripts/ui/dialogue_ui.gd`; create `scenes/ui/shop_ui.tscn`, `scripts/ui/shop_ui.gd`, `tests/test_map_dialogue_shop_ui.gd`; modify `tests/run_tests.gd`.

**Interfaces:** Consume Exploration fog/markers, deterministic DialogueNode choices, and Economy buy/sell/order commands.

- [ ] Write failing tests for hidden fog markers, player marker coordinates, dialogue choice conditions/effects, typewriter skip, unaffordable purchase rejection, sell totals, and shop close.
- [ ] Run tests and verify RED.
- [ ] Implement the map and dialogue trees from sections 7.4–7.5. Shop rows expose item ID and quantity only; EconomySystem calculates all prices.
- [ ] Ensure dialogue choices call the controller by choice ID rather than applying effects in UI.
- [ ] Run tests and commit `feat: add map dialogue and shop interfaces`.

### Task 5: Main scene and audio shell

**Files:** Modify `scenes/main.tscn`, `scenes/world/world.tscn`, `scripts/main.gd`, `scripts/world/world.gd`; create `scripts/core/audio_manager.gd`, `tests/test_main_system_wiring.gd`; modify `project.godot`, `tests/run_tests.gd`.

**Interfaces:** `Main.initialize_new_game()`, `initialize_from_save()`, `collect_save_dependencies()`, and `AudioManager.play_music`, `play_sfx`, `play_ambient`.

- [ ] Write failing structural tests for the complete World/Actors/Systems/UI/AudioManager tree and fake dependency startup order.
- [ ] Run tests and verify RED.
- [ ] Add all containers from section 4, register AudioManager, construct systems in dependency order, bind UI after system initialization, and load a save last. Audio methods safely no-op when streams are absent.
- [ ] Keep unfinished Animals container empty; no animal behavior is invented beyond the documented scene slot.
- [ ] Run the full suite, editor import, and main launch; commit `feat: integrate villa management scene`.

### Task 6: UI journey acceptance

**Files:** Create `tests/ui_acceptance.gd`, modify `tests/capture_scene.gd`.

**Interfaces:** Produces deterministic keyboard/mouse-free calls that open every screen and capture the management HUD.

- [ ] Write the acceptance script to initialize a game, open/close inventory, select a building, open map, complete one dialogue choice, open shop, and assert no world action fires while modal.
- [ ] Capture at `1280×720`; inspect clipping, minimum text readability, quick-slot selection, and modal layering.
- [ ] Run acceptance, full tests, and main launch; expected exit `0` and no leaked controls.
- [ ] Commit `test: verify villa UI integration journey`.
