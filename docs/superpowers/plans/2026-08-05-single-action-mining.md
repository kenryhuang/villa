# Single-Action Mining Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make one three-second mining action atomically collect all remaining ore, add green/red ore hover feedback, and suppress the farming cell highlight while the pickaxe is selected.

**Architecture:** Keep quantity and duration owned by `ResourceNode`, so `ToolSystem` and `GatheringController` continue using their existing preview/commit and target-duration contracts. Generalize the existing tree hover channel in `PlayerActionController` and reuse `GatheringFeedback.TreeHoverRing`; no mining-specific controller or duplicate UI is introduced.

**Tech Stack:** Godot 4.7.1, GDScript, existing headless assertion runners, deterministic Windows OpenGL screenshot capture.

---

### Task 1: Atomic three-second mining

**Files:**
- Modify: `tests/test_resource_gathering.gd`
- Modify: `tests/test_tool_action_transaction.gd`
- Modify: `tests/test_gathering_controller.gd`
- Modify: `scripts/world/resource_node.gd`

- [ ] **Step 1: Write failing resource and transaction tests**

Add assertions that a full ore node previews all remaining units, `get_gather_duration()` returns `3.0`, one commit empties the node, and a partial saved node returns only its remaining quantity:

```gdscript
assertions.equal(node.preview_reward("pickaxe"), {"copper_ore": 3}, "ore previews its full remaining yield")
assertions.near(node.get_gather_duration(), 3.0, 0.001, "ore exposes a three-second action")
var reward := node.commit_gather("pickaxe", 4)
assertions.equal(reward, {"copper_ore": 3}, "one mining commit returns the whole vein")
assertions.equal(node.remaining_units, 0, "one mining commit depletes the whole vein")
```

Extend the real `ToolSystem` transaction test so a partial ore vein adds the complete remaining amount while spending stamina and durability once. Add an inventory-capacity case where insufficient room for the whole batch rejects before mutation.

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```powershell
godot --headless --path . --script res://tests/run_resource_gathering_tests.gd
godot --headless --path . --script res://tests/run_economy_system_tests.gd
```

Expected: failures show ore still previews/commits one unit and exposes the old 1.2-second fallback.

- [ ] **Step 3: Implement the minimal target-owned behavior**

In `ResourceNode`, return all remaining ore in preview, subtract the previewed amount atomically, and expose the duration:

```gdscript
func preview_reward(tool_id: String) -> Dictionary:
	return {item_id: remaining_units} if can_gather(tool_id) else {}


func commit_gather(tool_id: String, total_day: int = 0) -> Dictionary:
	if total_day < 0:
		return {}
	var reward := preview_reward(tool_id)
	if reward.is_empty():
		return {}
	remaining_units -= int(reward[item_id])
	if remaining_units == 0:
		_respawn_day = total_day + respawn_days
	_update_visual_stage()
	_set_gather_active(gathering_enabled and remaining_units > 0)
	return reward


func get_gather_duration() -> float:
	return 3.0
```

`ToolSystem` remains unchanged: its current preview, whole-batch capacity check, atomic rollback, stamina cost and durability cost consume the larger target reward once.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the same two commands. Expected: resource gathering and economy suites pass with updated assertion counts.

- [ ] **Step 5: Commit atomic mining**

```powershell
git add scripts/world/resource_node.gd tests/test_resource_gathering.gd tests/test_tool_action_transaction.gd tests/test_gathering_controller.gd
git commit -m "feat: mine resource nodes in one action"
```

### Task 2: Ore eligibility ring and pickaxe highlight suppression

**Files:**
- Modify: `tests/test_player_action_controller.gd`
- Modify: `tests/test_gathering_visuals.gd`
- Modify: `scripts/actors/player_action_controller.gd`
- Modify: `scripts/ui/gathering_feedback.gd`

- [ ] **Step 1: Write failing action-controller tests**

Assert that slots 2 and 3 both suppress cell highlights, axe hover still accepts tree eligibility, and pickaxe hover accepts only pickaxe resources and emits green/red state from `can_gather("pickaxe")`:

```gdscript
controller._selected_slot = 3
assertions.truthy(not controller.should_show_cell_highlight(), "pickaxe suppresses the farming cell highlight")
controller.gather_hover_changed.connect(func(target: Node, allowed: bool): hover_events.append([target, allowed]))
controller._update_gather_hover(mineable_ore)
assertions.equal(hover_events[-1], [mineable_ore, true], "mineable ore emits a green hover state")
controller._update_gather_hover(blocked_ore)
assertions.equal(hover_events[-1], [blocked_ore, false], "blocked ore emits a red hover state")
```

Add feedback assertions that the generalized signal binds to the existing ring and that green/red colors remain unchanged.

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```powershell
godot --headless --path . --script res://tests/run_tests.gd
godot --headless --path . --script res://tests/run_gathering_visual_tests.gd
```

Expected: failures show slot 3 still enables grid highlighting and no ore hover signal/path exists.

- [ ] **Step 3: Generalize the hover channel**

Add `gather_hover_changed(target, allowed)` while retaining `tree_hover_changed` as a compatibility signal. Replace tree-only pointer filtering with tool-aware qualification:

```gdscript
func _hover_allowed(target: Node) -> Variant:
	if _selected_slot == 2 and target.has_method("is_chop_eligible"):
		return bool(target.call("is_chop_eligible"))
	if (
		_selected_slot == 3
		and _target_required_tool(target) == "pickaxe"
		and target.has_method("can_gather")
	):
		return bool(target.call("can_gather", "pickaxe"))
	return null


func _target_required_tool(target: Object) -> String:
	for property in target.get_property_list():
		if str(property.get("name", "")) == "required_tool":
			return str(target.get("required_tool"))
	return ""
```

Emit the generalized signal for both resources, mirror tree events for axe compatibility, clear it on UI hover/tool changes/action start, and update `should_show_cell_highlight()` to exclude both slots:

```gdscript
and _selected_slot not in [2, 3]
```

Bind `GatheringFeedback.show_tree_hover()` to `gather_hover_changed` when available; fall back to `tree_hover_changed` only for older controller fixtures.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the same two commands. Expected: core and gathering visual suites pass.

- [ ] **Step 5: Commit hover feedback**

```powershell
git add scripts/actors/player_action_controller.gd scripts/ui/gathering_feedback.gd tests/test_player_action_controller.gd tests/test_gathering_visuals.gd
git commit -m "feat: show mining eligibility hover ring"
```

### Task 3: Main-scene behavior, deterministic captures, and documentation

**Files:**
- Modify: `tests/test_main_gathering_integration.gd`
- Modify: `tests/capture_manual_gathering.gd`
- Modify: `docs/superpowers/specs/2026-08-04-manual-gathering-design.md`
- Modify: `docs/validation/manual-gathering-validation.md`

- [ ] **Step 1: Write failing main-scene tests**

Change the real mining scenario to keep a multi-unit stone target, advance 2.9 seconds without mutation, then finish at 3.0 seconds and assert the whole remaining amount, one stamina cost, one durability cost, and one 10-minute time advance. Select the pickaxe and assert the grid highlight is absent.

- [ ] **Step 2: Run integration tests and verify RED**

Run:

```powershell
godot --headless --path . --script res://tests/run_main_gathering_integration_tests.gd
```

Expected: failures show the old duration/one-unit expectations or the missing pickaxe-hover behavior.

- [ ] **Step 3: Extend deterministic capture states**

Add `ore_hover_green` and `ore_hover_red` states. Green uses a live pickaxe resource; red temporarily disables a resource while keeping its authored visual visible and calls the same hover feedback path. Ensure `ore_action` has no cell highlight and captures the action before 3 seconds completes.

- [ ] **Step 4: Run targeted and full verification**

Run the editor parse plus all ten existing test entry points. Expected: all exit zero and every runner prints `PASS`. Capture the two new states and the changed ore action at 1280×720, 1920×1080 and 3000×2000, then verify every expected PNG exists with the requested dimensions.

- [ ] **Step 5: Update design and validation records**

Replace old `1.2 秒/1 单位` mining statements with `3 秒/当前全部剩余量`, document single stamina/durability cost, generalized green/red ore ring, hidden pickaxe cell highlight, updated test counts and updated screenshot totals.

- [ ] **Step 6: Run static checks and commit**

```powershell
git diff --check
rg -n "TODO|FIXME|HACK" scripts tests docs/superpowers/specs/2026-08-04-manual-gathering-design.md docs/validation/manual-gathering-validation.md
git add tests/test_main_gathering_integration.gd tests/capture_manual_gathering.gd docs/superpowers/specs/2026-08-04-manual-gathering-design.md docs/validation/manual-gathering-validation.md
git commit -m "test: validate single-action mining flow"
```

Expected: no whitespace errors, no new unfinished markers, clean worktree, and `main` contains all three implementation commits.
