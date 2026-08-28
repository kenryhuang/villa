# Visible Agent Farmer Work Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Ahe a visible, world-backed 20-plot farm with queued movement/action feedback, and make all crops mature in about 30 real seconds through the authoritative game clock.

**Architecture:** `VisibleNpcFarmSystem` maps Agent plot indices to reserved `GridSystem` cells and owns queued intent records while real soil/crop state stays in `GridSystem` and `FarmingSystem`. `NpcFarmActionController` drives Ahe to each target and completes the authoritative transaction after a short `NpcFarmActionVisual` effect. Crop growth advances continuously from elapsed game minutes without accelerating the world clock.

**Tech Stack:** Godot 4.7, GDScript, Sprite3D/tweens/GPUParticles3D, existing Agent protocol v2, custom Godot test runners.

---

## File Map

- Create `scripts/systems/visible_npc_farm_system.gd`: farm selection, reservations, snapshots, projected batch validation, queue persistence, and authoritative farm commits.
- Create `scripts/actors/npc_farm_action_controller.gd`: sequential work movement, arrival/stall handling, visual timing, and completion signals.
- Create `scripts/visual/npc_farm_action_visual.gd`: lightweight till/plant/harvest feedback.
- Create `assets/ui/action_icons/harvest_basket.svg`: hand-painted-style basket icon.
- Create `tests/test_visible_npc_farm_system.gd`: mapping, ownership, snapshot, queue, and transaction tests.
- Create `tests/test_npc_farm_action_controller.gd`: movement/action sequencing and failure tests.
- Modify `scripts/data/crop_data.gd`: minute-based duration fields.
- Modify `scripts/data/crop_instance.gd`: elapsed-minute growth API.
- Modify `scripts/systems/farming_system.gd`: continuous growth cursor and repeat harvest state.
- Modify `scripts/systems/grid_system.gd`: owner reservations and player-access queries.
- Modify `scripts/systems/building_system.gd`: reject player building footprints on reserved cells.
- Modify `scripts/actors/player_action_controller.gd`: reject player farming/harvest on reserved cells.
- Modify `scripts/actors/npc.gd` and `scenes/actors/npc.tscn`: Agent work movement API and action visual child.
- Modify `scripts/ai_agent/agent_action_executor_router.gd`: queue visible farm actions and finalize asynchronous outcomes.
- Modify `scripts/ai_agent/agent_runtime.gd`: inject the real farm port, expose real snapshots, suppress scheduled work while busy, persist version 3, and report completions.
- Modify `scripts/main.gd`: construct/configure/bind the new systems and register 108-minute crop definitions.
- Modify `scripts/ui/seed_selector_panel.gd`: show seconds instead of days.
- Modify Agent and farming tests/runners for integration and regression coverage.

## Task 1: Continuous 30-Second Crop Growth

**Files:**
- Modify: `scripts/data/crop_data.gd`
- Modify: `scripts/data/crop_instance.gd`
- Modify: `scripts/systems/farming_system.gd`
- Modify: `scripts/main.gd`
- Modify: `scripts/ui/seed_selector_panel.gd`
- Test: `tests/test_farming_system.gd`
- Test: `tests/test_crop_economy.gd`
- Test: `tests/test_seed_selector_panel.gd`

- [ ] **Step 1: Write failing minute-growth tests**

Add tests that create an unwatered crop with `growth_duration_minutes = 108`, advance 107 then 1 game minute, and assert it matures only at 108. Repeat with a watered crop at 71 then 1 minute. Assert no elapsed time leaves progress unchanged and stage/maturity events emit only on transitions.

```gdscript
	var crop := _make_crop("timed", 3, [SeasonSystem.Season.SPRING])
	crop.growth_duration_minutes = 108
	var instance := farming.plant(cell, crop)
	farming.advance_growth_minutes(107)
	assertions.truthy(not instance.is_mature(), "crop waits for all 108 game minutes")
	farming.advance_growth_minutes(1)
	assertions.truthy(instance.is_mature(), "crop matures at 108 game minutes")
```

- [ ] **Step 2: Run the focused farming suite and verify RED**

Run:

```powershell
godot_console --headless --path . --script res://tests/run_tests.gd
```

Expected: new assertions fail because `growth_duration_minutes` and `advance_growth_minutes` do not exist.

- [ ] **Step 3: Add duration fields and elapsed-minute growth**

Add to `CropData`:

```gdscript
@export_range(1, 100000, 1) var growth_duration_minutes := 108
@export_range(1, 100000, 1) var regrow_duration_minutes := 108
```

Add a bounded proportional method to `CropInstance`:

```gdscript
func advance_game_minutes(minutes: int, watered_multiplier: float = 1.0) -> bool:
	if crop_data == null or lifecycle_state != LifecycleState.GROWING or minutes <= 0:
		return false
	var duration := maxi(1, int(crop_data.growth_duration_minutes))
	var advance := float(crop_data.growth_days) * float(minutes) * watered_multiplier / float(duration)
	var next_progress := minf(growth_progress + advance, float(crop_data.growth_days))
	var next_state := LifecycleState.MATURE if is_equal_approx(next_progress, float(crop_data.growth_days)) else LifecycleState.GROWING
	return set_growth_state(next_progress, next_state)
```

Add `FarmingSystem.advance_growth_minutes(minutes)` and a synchronized absolute-minute cursor. Connect `EventBus.time_changed`, calculate elapsed minutes from `SeasonSystem`, and call the method. Remove the growth increment from `on_day_changed` while keeping environment and water reset behavior.

- [ ] **Step 4: Restore repeat-crop harvest semantics with tests first**

Change the harvest preview expectations so annual crops produce `post_crop = null`, while `annual_regrow`, `bush`, `tree`, and `vine` preserve a crop dictionary with progress zero, `GROWING`, incremented harvest count, and farmland state `PLANTED`. Verify transaction rollback restores the mature state exactly.

- [ ] **Step 5: Update default data and UI**

Set both duration fields to `108` for every row created by `Main.default_crop_definitions()`. Replace the seed panel day text with:

```gdscript
"growth_text": "成熟约 30 秒 · 浇水约 20 秒",
```

- [ ] **Step 6: Run relevant tests and commit**

Run the aggregate tests, confirm only the recorded four baseline failures remain, then commit:

```powershell
git add -- scripts/data/crop_data.gd scripts/data/crop_instance.gd scripts/systems/farming_system.gd scripts/main.gd scripts/ui/seed_selector_panel.gd tests
git commit -m "feat: grow crops on a thirty-second clock"
```

## Task 2: Grid Reservations and the 20-Plot Real Farm

**Files:**
- Create: `scripts/systems/visible_npc_farm_system.gd`
- Create: `tests/test_visible_npc_farm_system.gd`
- Modify: `scripts/systems/grid_system.gd`
- Modify: `scripts/systems/building_system.gd`
- Modify: `scripts/actors/player_action_controller.gd`
- Modify: `tests/run_agent_system_tests.gd`

- [ ] **Step 1: Write failing reservation and mapping tests**

Test a wished-for API:

```gdscript
	assertions.truthy(farm.configure(grid, farming, economy, game_data, "farmer_ahe", Vector3(-3, 0, -2)))
	assertions.equal(farm.get_plot_count("farmer_ahe"), 20, "Ahe owns twenty plots")
	assertions.equal(farm.get_plot("farmer_ahe", 0).plot_index, 0, "plot mapping starts at zero")
	var cell := farm.get_plot_cell("farmer_ahe", 0)
	assertions.truthy(grid.is_reserved_for(cell.gx, cell.gz, "farmer_ahe"), "plot is reserved for Ahe")
	assertions.truthy(not grid.can_actor_use_cell(cell.gx, cell.gz, "player"), "player cannot use Ahe plot")
```

Also assert deterministic row-major coordinates, all 20 cells are valid wasteland on initialization, failure is atomic when no full rectangle exists, and snapshots reflect real farmland/crop state.

- [ ] **Step 2: Run the Agent suite and verify RED**

Run the Agent test runner. Expected: missing script/API failures only.

- [ ] **Step 3: Add owner reservations to GridSystem**

Implement:

```gdscript
var _cell_reservations: Dictionary = {}

func reserve_cells(owner_id: String, cells: Array[Vector2i]) -> bool
func release_cells(owner_id: String) -> void
func get_cell_owner(gx: int, gz: int) -> String
func is_reserved_for(gx: int, gz: int, owner_id: String) -> bool
func can_actor_use_cell(gx: int, gz: int, actor_id: String) -> bool
```

Reservation must prevalidate the complete list before changing `_cell_reservations`.

- [ ] **Step 4: Implement deterministic real-farm selection**

Create `VisibleNpcFarmSystem` with `FARM_WIDTH = 5`, `FARM_HEIGHT = 4`, `PLOT_COUNT = 20`. Search anchors by distance from the spawn grid coordinate and coordinate tie-breaker; accept only a full rectangle of in-bounds wasteland cells below the slope threshold and not already reserved. Reserve all 20 cells atomically and expose row-major mapping.

- [ ] **Step 5: Enforce player restrictions**

Make player previews pass actor ID `player` and return `reserved_plot` when a cell has another owner. Add the same ownership check for every building footprint in `BuildingSystem.diagnose_placement`. Internal load/rollback methods continue to bypass player ownership.

- [ ] **Step 6: Derive snapshots from real cells**

Implement `get_snapshot(agent_id, absolute_game_minute)` returning 20 records with coordinate, world position, state, crop, normalized progress, remaining minutes, season validity, and queue reservation.

- [ ] **Step 7: Run tests and commit**

Run Agent and targeted farming/building tests, then commit:

```powershell
git add -- scripts/systems/visible_npc_farm_system.gd scripts/systems/grid_system.gd scripts/systems/building_system.gd scripts/actors/player_action_controller.gd tests/test_visible_npc_farm_system.gd tests/run_agent_system_tests.gd
git commit -m "feat: reserve Ahe's visible farm"
```

## Task 3: Asynchronous Agent Farm Queue and Transactions

**Files:**
- Modify: `scripts/systems/visible_npc_farm_system.gd`
- Modify: `scripts/ai_agent/agent_action_executor_router.gd`
- Modify: `scripts/ai_agent/agent_runtime.gd`
- Modify: `scripts/ai_agent/agent_action_validator.gd`
- Test: `tests/test_visible_npc_farm_system.gd`
- Test: `tests/test_agent_action_execution.gd`
- Test: `tests/test_agent_runtime.gd`

- [ ] **Step 1: Write failing projected-batch and completion tests**

Assert zero actions is legal, one-to-three farm actions queue in order, `till` then `plant` on the same plot validates against projected state, plot indices above 19 reject, and a queued result is `in_progress` without mutating grid or inventory.

```gdscript
	var outcomes := executor.execute_batch(_intent([
		_action("till", {"plot": 2}),
		_action("plant", {"plot": 2, "seed_item_id": "carrot_seed"}),
	]), 10)
	assertions.equal(outcomes.size(), 2, "farm batch queues both dependent actions")
	assertions.equal(outcomes[0].status, "in_progress", "queued till is not committed")
	assertions.equal(cell.state, GridCell.State.WASTELAND, "queue does not mutate soil")
```

- [ ] **Step 2: Run Agent tests and verify RED**

Expected: existing executor commits immediately and stops after the first in-progress result.

- [ ] **Step 3: Add queue APIs and projected validation**

Implement on `VisibleNpcFarmSystem`:

```gdscript
signal work_available
signal work_finished(intent: Dictionary, result: Dictionary)

func queue_batch(intent: Dictionary, game_minute: int) -> Array[Dictionary]
func peek_work() -> Dictionary
func mark_work_started(idempotency_key: String) -> bool
func complete_work(idempotency_key: String) -> Dictionary
func fail_work(idempotency_key: String, code: String) -> Dictionary
func has_pending_work(agent_id: String) -> bool
```

Projected validation simulates plot state and reserved seed counts across the batch without mutating authority.

- [ ] **Step 4: Commit through existing authoritative systems**

At completion, till through the grid transition, plant through `FarmingSystem.preview_plant/commit_plant` plus an NPC economy snapshot rollback, and harvest through `FarmingSystem` prepared-publication APIs plus NPC inventory receipt. Never deduct or produce inventory at queue time.

- [ ] **Step 5: Route asynchronous outcomes through Executor and Runtime**

The executor delegates farmer tools to `queue_batch`, stores initial `in_progress` outcomes, and adds:

```gdscript
func finalize_queued_action(intent: Dictionary, result: Dictionary, game_minute: int) -> Dictionary
```

`AgentRuntime` handles `work_finished`, reports the completed/rejected outcome, publishes final HUD text, and suppresses only Ahe's scheduled automatic requests while `has_pending_work` is true. Dialogue triggers bypass suppression.

- [ ] **Step 6: Restrict validator plots to 0–19**

Update farm-tool argument validation to use `0, 19`, leaving other integer ranges unchanged.

- [ ] **Step 7: Run Agent tests and commit**

```powershell
git add -- scripts/systems/visible_npc_farm_system.gd scripts/ai_agent/agent_action_executor_router.gd scripts/ai_agent/agent_runtime.gd scripts/ai_agent/agent_action_validator.gd tests
git commit -m "feat: queue real Agent farm actions"
```

## Task 4: Ahe Movement and Action Feedback

**Files:**
- Create: `scripts/actors/npc_farm_action_controller.gd`
- Create: `scripts/visual/npc_farm_action_visual.gd`
- Create: `assets/ui/action_icons/harvest_basket.svg`
- Create: `tests/test_npc_farm_action_controller.gd`
- Modify: `scripts/actors/npc.gd`
- Modify: `scenes/actors/npc.tscn`
- Modify: `tests/run_agent_system_tests.gd`

- [ ] **Step 1: Write failing NPC work movement tests**

Assert the NPC exposes `begin_agent_work`, reaches a nearby target without changing farm state, reports arrival, can stop independently of dialogue busy state, and emits a blocked result after no distance progress. Test the controller state order `moving → animating → completion` and that completion happens after the configured feedback duration.

- [ ] **Step 2: Run Agent tests and verify RED**

Expected: missing controller, movement, and visual methods.

- [ ] **Step 3: Add dedicated Agent-work movement to Npc**

Add an `AGENT_WORK` state and APIs:

```gdscript
func begin_agent_work(target: Vector3) -> bool
func has_agent_work_target() -> bool
func is_agent_work_arrived() -> bool
func stop_agent_work() -> void
func face_world_point(target: Vector3) -> void
```

Reuse the existing velocity path and four-direction visual synchronization. Do not alter dialogue range or dialogue busy state.

- [ ] **Step 4: Build the focused action controller**

The controller receives the farm port and actor, consumes `peek_work`, chooses an adjacent reachable interaction point, drives movement, tracks distance progress, starts the action visual at arrival, and calls `complete_work` only after feedback finishes. Use a short stall timeout and return `path_blocked` without retry.

- [ ] **Step 5: Build lightweight visual feedback**

Create a Node3D child with a Sprite3D action icon and procedural particles. Reuse the hoe PNG, use the selected seed texture for planting, and add the basket SVG for harvest. Expose:

```gdscript
signal finished
func play(action_name: String, item_texture: Texture2D = null) -> bool
func cancel() -> void
func is_playing() -> bool
```

Use tweens for the icon arc/body dip and approximately one second duration. Asset fallback keeps the tween and never blocks completion.

- [ ] **Step 6: Run tests and commit**

```powershell
git add -- scripts/actors/npc.gd scripts/actors/npc_farm_action_controller.gd scripts/visual/npc_farm_action_visual.gd scenes/actors/npc.tscn assets/ui/action_icons/harvest_basket.svg tests/test_npc_farm_action_controller.gd tests/run_agent_system_tests.gd
git commit -m "feat: animate Ahe's farm work"
```

## Task 5: Main Wiring, Persistence, and Migration

**Files:**
- Modify: `scripts/main.gd`
- Modify: `scripts/ai_agent/agent_runtime.gd`
- Modify: `scripts/core/save_manager.gd`
- Modify: `tests/test_agent_main_integration.gd`
- Modify: `tests/test_agent_world_state.gd`
- Modify: `tests/test_visible_agent_npc_dialogue.gd`

- [ ] **Step 1: Write failing Main and save/load tests**

Assert Main creates/configures the farm after the world grid, binds Ahe after `_setup_npcs`, injects the farm into `AgentRuntime`, and resumes a persisted uncommitted action without duplicating resources. Add a version-2 migration fixture whose detached farm is discarded while inventory and other Agent state survive.

- [ ] **Step 2: Run Agent tests and verify RED**

Expected: Main has no visible farm/controller and Agent save version is still 2.

- [ ] **Step 3: Wire creation and binding order**

Create the farm system and action controller in `_initialize_systems`, configure the farm after Grid/Farming/NPC economy, inject it into AgentRuntime, and bind the `farmer_ahe` visible NPC after `_setup_npcs`. Publish `farm_unavailable` without disabling dialogue if no rectangle is found.

- [ ] **Step 4: Persist version 3 Agent farm state**

Store farm anchor/mapping and queued uncommitted records under `agent_world.farm`. Restore grid and NPC economy first, synchronize the farming clock, restore the Agent farm, then resume the visible controller. A version-2 record is accepted by discarding its detached farm section and creating a fresh visible mapping.

- [ ] **Step 5: Add debug lifecycle records**

Record `queued`, `moving`, `arrived`, `animating`, `committed`, `rejected`, and `cancelled` metadata in the in-memory Agent trace. Player messages remain limited to concise start and final outcomes.

- [ ] **Step 6: Run integration tests and commit**

```powershell
git add -- scripts/main.gd scripts/ai_agent/agent_runtime.gd scripts/core/save_manager.gd tests
git commit -m "feat: persist Ahe's visible farm work"
```

## Task 6: Verification and Rendered Acceptance

**Files:**
- Modify: `docs/superpowers/plans/2026-08-28-visible-agent-farmer-work.md`

- [ ] **Step 1: Run fresh Agent tests**

```powershell
godot_console --headless --path . --script res://tests/run_agent_system_tests.gd
```

Expected: all Agent checks pass.

- [ ] **Step 2: Run the full suite**

```powershell
godot_console --headless --path . --script res://tests/run_tests.gd
```

Expected: no failures beyond the recorded baseline of three economy/order-contract checks and one villager-count check.

- [ ] **Step 3: Perform real-time growth acceptance**

Run a non-headless probe in `main.tscn`, plant an unwatered and watered crop, capture at start, around 20 seconds, and around 30 seconds, and verify their mature transitions and displayed models.

- [ ] **Step 4: Perform visible work acceptance**

Queue till, plant, and harvest actions for Ahe in the real main scene. Capture movement and each action effect, confirm no mutation before arrival, and confirm the final grid/crop/NPC inventory state afterward. Delete temporary probes.

- [ ] **Step 5: Verify repository state and update this plan**

Mark completed checkboxes, then run:

```powershell
git diff --check
git status --short
```

- [ ] **Step 6: Commit the completed plan record**

```powershell
git add -- docs/superpowers/plans/2026-08-28-visible-agent-farmer-work.md
git commit -m "docs: record visible Agent farmer implementation"
```
