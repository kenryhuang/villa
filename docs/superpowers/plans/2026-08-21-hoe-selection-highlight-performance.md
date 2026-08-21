# Hoe Selection and Highlight Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make hoe selection immediate and restore a stable green/red single-cell ground highlight without unrelated inventory UI refreshes or per-frame render-resource allocation.

**Architecture:** Correct tool event semantics in `ToolSystem` so selection and automatic equipment do not publish zero-quantity inventory mutations. Make `GridSystem.highlight_cell()` idempotent by rebuilding geometry only when the target cell changes and reusing one material across color updates. Preserve the existing controller and HUD APIs.

**Tech Stack:** Godot 4.7, GDScript, repository `TestAssert` SceneTree runners, Git.

---

## File Map

- Modify `scripts/systems/tool_system.gd`: remove fake inventory events from tool selection and automatic equipment.
- Modify `tests/test_tool_action_transaction.gd`: prove selection and gathering publish only real inventory mutations.
- Modify `scripts/systems/grid_system.gd`: reuse highlight Mesh and material when inputs are unchanged.
- Modify `tests/test_grid_system_complete.gd`: verify Mesh/material identity, color updates, movement and hide/show behavior.
- Modify `tests/test_main_item_container_wiring.gd`: verify a real Main scene shows the hoe highlight on the pointed cell.
- Create `tests/run_hoe_highlight_performance_tests.gd`: focused runner for the tool, grid and real-Main regression checks.

### Task 1: Stop Tool Selection from Publishing Inventory Mutations

**Files:**
- Modify: `tests/test_tool_action_transaction.gd:54-157`
- Modify: `scripts/systems/tool_system.gd:62-65, 190-196`
- Create: `tests/run_hoe_highlight_performance_tests.gd`

- [ ] **Step 1: Create the focused runner**

Create `tests/run_hoe_highlight_performance_tests.gd`:

```gdscript
extends SceneTree

const TestAssertScript = preload("res://tests/test_assert.gd")
const ToolTest = preload("res://tests/test_tool_action_transaction.gd")
const GridTest = preload("res://tests/test_grid_system_complete.gd")
const MainTest = preload("res://tests/test_main_item_container_wiring.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions := TestAssertScript.new()
	ToolTest.new().run(assertions, self)
	GridTest.new().run(assertions)
	await MainTest.new().run(assertions, self)
	if assertions.failures.is_empty():
		print("PASS: %d hoe/highlight performance checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print(
		"FAIL: %d of %d hoe/highlight performance checks failed"
		% [assertions.failures.size(), assertions.checks]
	)
	quit(1)
```

- [ ] **Step 2: Add failing tool event assertions**

In `tests/test_tool_action_transaction.gd`, immediately after the real tool node enters the tree, connect a short-lived recorder and prove a selection is not an inventory mutation:

```gdscript
	var event_bus := tree.root.get_node_or_null("EventBus")
	assertions.truthy(event_bus != null, "tool transaction test has EventBus")
	var selection_item_events: Array[Dictionary] = []
	var selection_callback := func(item_id: String, quantity: int) -> void:
		selection_item_events.append({"item_id": item_id, "quantity": quantity})
	event_bus.item_added.connect(selection_callback)
	tool.switch_tool(ToolSystem.ToolType.HOE)
	event_bus.item_added.disconnect(selection_callback)
	assertions.equal(
		selection_item_events,
		[],
		"selecting the hoe does not publish a fake inventory addition"
	)
```

Around the existing successful copper commit, record item additions and require only the real reward publication:

```gdscript
	var gather_item_events: Array[Dictionary] = []
	var gather_callback := func(item_id: String, quantity: int) -> void:
		gather_item_events.append({"item_id": item_id, "quantity": quantity})
	event_bus.item_added.connect(gather_callback)
	var committed: Dictionary = tool.commit_gather_unit(copper)
	event_bus.item_added.disconnect(gather_callback)
	assertions.equal(
		gather_item_events,
		[{"item_id": "copper_ore", "quantity": 3}],
		"automatic equipment publishes the reward but no zero-quantity tool event"
	)
```

- [ ] **Step 3: Run the focused runner and verify RED**

Run:

```powershell
godot_console.exe --headless --path . --script res://tests/run_hoe_highlight_performance_tests.gd
```

Expected: FAIL because selecting the hoe emits a zero-quantity hoe event and the copper commit additionally emits a zero-quantity pickaxe event.

- [ ] **Step 4: Remove the fake inventory publications**

Change `ToolSystem.switch_tool()` to:

```gdscript
func switch_tool(tool_type: ToolType) -> void:
	current_tool = tool_type
```

In `commit_gather_unit()`, retain stamina and durability publication but remove the zero-quantity item event:

```gdscript
	if _event_bus != null:
		_event_bus.stamina_changed.emit(int(game_state.player_state.stamina))
		_emit_durability_changed(str(preview.tool_id))
```

- [ ] **Step 5: Run the focused runner and verify the tool assertions are GREEN**

Run the command from Step 3. Expected: the new tool event assertions pass.

- [ ] **Step 6: Commit the tool event slice**

```powershell
git add scripts/systems/tool_system.gd tests/test_tool_action_transaction.gd tests/run_hoe_highlight_performance_tests.gd
git commit -m "fix: keep tool selection out of inventory events"
```

### Task 2: Reuse Ground Highlight Render Resources

**Files:**
- Modify: `tests/test_grid_system_complete.gd:54-65`
- Modify: `scripts/systems/grid_system.gd:583-615`

- [ ] **Step 1: Add failing resource reuse assertions**

Extend the existing valid-cell highlight section in `tests/test_grid_system_complete.gd`:

```gdscript
	var first_highlight_mesh := highlight.mesh
	var first_highlight_material := highlight.material_override
	assertions.truthy(grid.highlight_cell(18, 14, Color.YELLOW), "same cell highlights repeatedly")
	assertions.truthy(highlight.mesh == first_highlight_mesh, "same-cell highlight reuses its mesh")
	assertions.truthy(highlight.material_override == first_highlight_material, "same-cell highlight reuses its material")
	assertions.truthy(grid.highlight_cell(18, 14, Color.RED), "same cell accepts a changed color")
	assertions.truthy(highlight.mesh == first_highlight_mesh, "color changes do not rebuild geometry")
	assertions.truthy(highlight.material_override == first_highlight_material, "color changes reuse material")
	assertions.equal(
		(highlight.material_override as StandardMaterial3D).albedo_color,
		Color(1.0, 0.0, 0.0, 0.58),
		"changed color reaches the reused material"
	)
	assertions.truthy(grid.highlight_cell(19, 14, Color.RED), "highlight moves to a neighboring cell")
	assertions.truthy(highlight.mesh != first_highlight_mesh, "moving cells rebuilds geometry once")
	assertions.equal(int(highlight.get_meta("gx", -1)), 19, "moved highlight stores x")
	assertions.equal(int(highlight.get_meta("gz", -1)), 14, "moved highlight stores z")
```

After moving to `(19, 14)`, verify hide/show reuse:

```gdscript
	var hidden_mesh := highlight.mesh
	var hidden_material := highlight.material_override
	grid.clear_highlights()
	assertions.truthy(not highlight.visible, "clear hides the highlight")
	assertions.truthy(grid.highlight_cell(19, 14, Color.RED), "hidden highlight restores")
	assertions.truthy(highlight.visible, "restored highlight is visible")
	assertions.truthy(highlight.mesh == hidden_mesh, "hide/show reuses mesh")
	assertions.truthy(highlight.material_override == hidden_material, "hide/show reuses material")
```

- [ ] **Step 2: Run the grid runner and verify RED**

```powershell
godot_console.exe --headless --path . --script res://tests/run_grid_system_tests.gd
```

Expected: FAIL because repeated calls currently replace both Mesh and material.

- [ ] **Step 3: Implement idempotent highlight updates**

After validation in `GridSystem.highlight_cell()`, replace unconditional resource construction with:

```gdscript
	var same_cell := (
		highlight.mesh != null
		and int(highlight.get_meta("gx", -1)) == gx
		and int(highlight.get_meta("gz", -1)) == gz
	)
	if not same_cell:
		var x0 := WORLD_ORIGIN_X + float(gx) * CELL_SIZE
		var z0 := WORLD_ORIGIN_Z + float(gz) * CELL_SIZE
		var x1 := x0 + CELL_SIZE
		var z1 := z0 + CELL_SIZE
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var points := [
			Vector3(x0, terrain.get_height_at(x0, z0) + HIGHLIGHT_LIFT, z0),
			Vector3(x1, terrain.get_height_at(x1, z0) + HIGHLIGHT_LIFT, z0),
			Vector3(x1, terrain.get_height_at(x1, z1) + HIGHLIGHT_LIFT, z1),
			Vector3(x0, terrain.get_height_at(x0, z1) + HIGHLIGHT_LIFT, z1),
		]
		for point in points:
			surface.add_vertex(point)
		for index in [0, 2, 1, 0, 3, 2]:
			surface.add_index(index)
		highlight.mesh = surface.commit()
	var material := highlight.material_override as StandardMaterial3D
	if material == null:
		material = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.no_depth_test = true
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		highlight.material_override = material
	var display_color := Color(color.r, color.g, color.b, minf(color.a, 0.58))
	if material.albedo_color != display_color:
		material.albedo_color = display_color
	highlight.set_meta("gx", gx)
	highlight.set_meta("gz", gz)
	highlight.visible = true
	return true
```

- [ ] **Step 4: Run the grid and focused runners and verify GREEN**

```powershell
godot_console.exe --headless --path . --script res://tests/run_grid_system_tests.gd
godot_console.exe --headless --path . --script res://tests/run_hoe_highlight_performance_tests.gd
```

Expected: both commands exit 0 and the reuse assertions pass.

- [ ] **Step 5: Commit the highlight resource slice**

```powershell
git add scripts/systems/grid_system.gd tests/test_grid_system_complete.gd
git commit -m "fix: reuse farming cell highlight resources"
```

### Task 3: Prove the Hoe Shadow in the Real Main Scene

**Files:**
- Modify: `tests/test_main_item_container_wiring.gd:7-70`

- [ ] **Step 1: Add a real-scene hoe pointer assertion**

After startup assertions, enter farming mode, select the hoe and exercise the real pointer path:

```gdscript
	assertions.truthy(main.action_controller.switch_mode(PlayerActionController.ActionMode.FARMING), "real Main enters farming mode")
	assertions.truthy(main.action_controller.select_mode_slot(0), "real Main selects the hoe")
	var camera: Camera3D = tree.root.get_camera_3d()
	var target_cell := _visible_reachable_farm_cell(main, camera)
	assertions.truthy(target_cell != null, "real Main has a visible reachable farm cell")
	if target_cell != null:
		var motion := InputEventMouseMotion.new()
		motion.position = camera.unproject_position(target_cell.world_position_3d())
		motion.global_position = motion.position
		main.action_controller._input(motion)
		main.action_controller._process(0.0)
		var highlight := main.grid_system.get_node_or_null("GridCells/CellHighlight") as MeshInstance3D
		assertions.truthy(highlight != null and highlight.visible, "hoe shows a cell shadow")
		assertions.equal(int(highlight.get_meta("gx", -1)), target_cell.gx, "hoe shadow aligns on x")
		assertions.equal(int(highlight.get_meta("gz", -1)), target_cell.gz, "hoe shadow aligns on z")
```

Add the helper:

```gdscript
func _visible_reachable_farm_cell(main: Node, camera: Camera3D) -> GridCell:
	if camera == null:
		return null
	for cell_value in main.grid_system._cells.values():
		var cell := cell_value as GridCell
		if not main.grid_system.can_farm_at(cell.gx, cell.gz):
			continue
		var point := cell.world_position_3d()
		if camera.is_position_behind(point):
			continue
		var distance := Vector2(
			main.player.global_position.x - point.x,
			main.player.global_position.z - point.z
		).length()
		if distance <= main.player.interaction_range:
			return cell
	return null
```

- [ ] **Step 2: Run the focused runner**

```powershell
godot_console.exe --headless --path . --script res://tests/run_hoe_highlight_performance_tests.gd
```

Expected: PASS with the real Main hoe shadow visible and aligned. If the chosen projected cell is occluded, refine the helper to require that `_raycast_to_ground()` resolves back to that cell; do not bypass the production pointer path.

- [ ] **Step 3: Run scoped regressions**

```powershell
godot_console.exe --headless --path . --script res://tests/run_player_action_controller_tests.gd
godot_console.exe --headless --path . --script res://tests/run_action_mode_debug_day_regression_tests.gd
godot_console.exe --headless --path . --script res://tests/run_grid_system_tests.gd
```

Expected: all runners exit 0. Existing resource-leak warnings may remain, but there must be no assertion failures or script errors.

- [ ] **Step 4: Commit the real-scene regression**

```powershell
git add tests/test_main_item_container_wiring.gd
git commit -m "test: cover real hoe ground highlight"
```

### Task 4: Final Verification and Review

**Files:**
- Verify all files changed by Tasks 1–3.

- [ ] **Step 1: Run fresh focused verification**

```powershell
godot_console.exe --headless --path . --script res://tests/run_hoe_highlight_performance_tests.gd
godot_console.exe --headless --path . --script res://tests/run_action_mode_debug_day_regression_tests.gd
godot_console.exe --headless --path . --script res://tests/run_seed_selector_panel_tests.gd
git diff --check
```

Expected: all focused runners exit 0 and `git diff --check` prints no errors.

- [ ] **Step 2: Run the broad suite and record baseline status**

```powershell
godot_console.exe --headless --path . --script res://tests/run_tests.gd
```

Expected baseline: 3 existing economy/save assertions fail. Confirm there are no new tool, grid, pointer, farming-mode or seed-selector failures.

- [ ] **Step 3: Request code review**

Review commits after `a758c04` against `docs/superpowers/specs/2026-08-21-hoe-selection-highlight-performance-design.md`. Resolve every Critical and Important finding, rerun Step 1, and commit review fixes separately.

- [ ] **Step 4: Inspect final repository state**

```powershell
git status --short --branch
git log -8 --oneline
```

Expected: branch `feature/painted-production-buildings`, clean worktree, and the plan commits present. Do not merge or push without user authorization.
