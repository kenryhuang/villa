# Building Construction Process Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace instant finished-building placement with a saved, testable four-stage construction process using dedicated art for all nine buildings.

**Architecture:** Each placed `BuildingInstance` owns a `FOUNDATION → FRAME → HALF_BUILT → COMPLETE` state machine and progresses itself in real time. `BuildingSystem` keeps atomic placement, forwards construction signals, and restores saved stage data without re-spending resources. The visual verifier keeps its nine-building completed gallery and uses a separate interactive construction site controlled by `P`, `N`, and `X`.

**Tech Stack:** Godot 4.7.1, typed GDScript, Sprite3D, CPUParticles3D, PNG assets, existing headless SceneTree test runners.

## Global Constraints

- New 1×1, 2×2, and 3×3 construction durations are exactly 3.0, 4.0, and 5.0 seconds.
- Construction occupies grid cells and blocks movement from `FOUNDATION`.
- `InteractionArea` remains disabled until `COMPLETE`.
- `CameraOccluder` is disabled only during `FOUNDATION`.
- Cancelling construction restores grid snapshots and never refunds resources.
- Each of nine buildings has three dedicated 1024×1024 transparent PNG stages.
- Old save records without construction fields restore as `COMPLETE`.
- Preview instances never enter construction or enable physics.
- Preserve existing compatibility signal signatures.

---

### Task 1: Deterministic Construction State Machine

**Files:**
- Create: `tests/test_building_construction_state.gd`
- Modify: `tests/run_building_system_tests.gd`
- Modify: `scripts/buildings/building_instance.gd`

**Interfaces:**
- Consumes: `BuildingData.footprint`, existing `BuildingInstance.configure()`.
- Produces: `ConstructionStage`, `construction_duration_for()`, `start_construction()`, `restore_construction()`, `advance_construction()`, `advance_construction_stage()`, `complete_construction()`, `is_construction_complete()`, `get_construction_progress()`.

- [ ] **Step 1: Write the failing state-machine test**

Add `test_building_construction_state.gd` with an instance configured from the `barn` catalog and assertions equivalent to:

```gdscript
assertions.equal(BuildingInstance.construction_duration_for(Vector2i(1, 1)), 3.0, "1x1 duration")
assertions.equal(BuildingInstance.construction_duration_for(Vector2i(2, 2)), 4.0, "2x2 duration")
assertions.equal(BuildingInstance.construction_duration_for(Vector2i(3, 3)), 5.0, "3x3 duration")
instance.start_construction()
assertions.equal(instance.construction_stage, BuildingInstance.ConstructionStage.FOUNDATION, "starts at foundation")
instance.advance_construction(instance.construction_duration / 3.0)
assertions.equal(instance.construction_stage, BuildingInstance.ConstructionStage.FRAME, "advances to frame")
instance.advance_construction_stage()
assertions.equal(instance.construction_stage, BuildingInstance.ConstructionStage.HALF_BUILT, "manual step advances once")
instance.complete_construction()
assertions.truthy(instance.is_construction_complete(), "completion is observable")
```

Register the test in `run_building_system_tests.gd`.

- [ ] **Step 2: Run the suite and verify RED**

Run:

```bash
godot --headless --path . --script res://tests/run_building_system_tests.gd
```

Expected: parse or assertion failure because construction APIs do not exist.

- [ ] **Step 3: Implement the minimal deterministic state machine**

Add:

```gdscript
enum ConstructionStage { FOUNDATION, FRAME, HALF_BUILT, COMPLETE }
signal construction_stage_changed(building: BuildingInstance, stage: ConstructionStage)
signal construction_completed(building: BuildingInstance)

var construction_stage := ConstructionStage.COMPLETE
var construction_elapsed := 0.0
var construction_duration := 0.0
var _completion_emitted := false

static func construction_duration_for(footprint: Vector2i) -> float:
    var largest_side := maxi(footprint.x, footprint.y)
    if largest_side <= 1:
        return 3.0
    if largest_side == 2:
        return 4.0
    return 5.0
```

Implement stage thresholds at duration/3 and 2×duration/3. Clamp elapsed to `0.0..duration`; emit every crossed stage once and completion once. `_process(delta)` calls `advance_construction(delta)` only while incomplete.

- [ ] **Step 4: Run and verify GREEN**

Run the Building suite. Expected: all checks pass with the new duration and transition assertions.

- [ ] **Step 5: Commit**

```bash
git add scripts/buildings/building_instance.gd tests/test_building_construction_state.gd tests/run_building_system_tests.gd
git commit -m "feat: add building construction state machine"
```

---

### Task 2: Stage Visuals, Collision, Interaction, and Effects

**Files:**
- Modify: `scripts/buildings/building_instance.gd`
- Modify: `tests/test_building_instance.gd`
- Modify: `tests/test_building_construction_state.gd`

**Interfaces:**
- Consumes: construction state from Task 1.
- Produces: `ConstructionLayer`, `ConstructionEffects`, `get_construction_texture_path()`, stage-aware physics and interaction.

- [ ] **Step 1: Write failing visual and physics assertions**

Assert:

```gdscript
instance.start_construction()
assertions.truthy(instance.has_node("VisualRoot/ConstructionLayer"), "construction sprite exists")
assertions.truthy(instance.has_node("VisualRoot/ConstructionEffects"), "effects root exists")
assertions.equal(instance.get_node("Collision").collision_layer, 16 | 64, "foundation blocks movement")
assertions.equal(instance.get_node("InteractionArea").collision_layer, 0, "foundation interaction disabled")
assertions.equal(instance.get_node("CameraOccluder").collision_layer, 0, "foundation does not occlude")
instance.advance_construction_stage()
assertions.equal(instance.get_node("CameraOccluder").collision_layer, 32, "frame occludes camera")
instance.complete_construction()
assertions.equal(instance.get_node("InteractionArea").collision_layer, 64 | 256, "complete interaction enabled")
assertions.truthy(instance.get_node("VisualRoot/BackLayer").visible, "complete back art visible")
```

Connect `interacted`; call `interact()` before and after completion; assert it emits only after completion.

- [ ] **Step 2: Run the Building suite and verify RED**

Expected: missing construction nodes and current physics remaining enabled during construction.

- [ ] **Step 3: Implement stage-aware visuals and physics**

Create nodes in `_ensure_nodes()`:

```gdscript
ConstructionLayer (Sprite3D)
ConstructionEffects (Node3D)
```

Map stage to exact paths:

```gdscript
"res://assets/buildings/construction/%s/%s_foundation.png"
"res://assets/buildings/construction/%s/%s_frame.png"
"res://assets/buildings/construction/%s/%s_half_built.png"
```

Use one construction sprite at the same pixel scale, footprint center, and bottom anchor as finished art. Stage application hides finished layers until `COMPLETE`, assigns the stage texture, and applies the physics table from the spec. `interact()` returns immediately unless complete.

Create low-count one-shot `CPUParticles3D` emitters with runtime `QuadMesh` particles: tan dust for `FOUNDATION` and completion; small ochre wood chips for `FRAME` and `HALF_BUILT`.

- [ ] **Step 4: Run and verify GREEN**

Run Building tests. Expected: state, physics, interaction, and finished visual assertions pass without warnings.

- [ ] **Step 5: Commit**

```bash
git add scripts/buildings/building_instance.gd tests/test_building_instance.gd tests/test_building_construction_state.gd
git commit -m "feat: render staged building construction"
```

---

### Task 3: BuildingSystem Construction Integration and Signals

**Files:**
- Modify: `scripts/systems/building_system.gd`
- Modify: `scripts/core/event_bus.gd`
- Modify: `tests/test_building_system_complete.gd`

**Interfaces:**
- Consumes: `BuildingInstance.start_construction()` and instance construction signals.
- Produces: `building_construction_started`, `building_construction_stage_changed`, `building_construction_completed`.

- [ ] **Step 1: Write failing placement and signal tests**

Connect signal counters, place a `well`, then assert:

```gdscript
assertions.equal(placed.construction_stage, BuildingInstance.ConstructionStage.FOUNDATION, "placement starts construction")
assertions.equal(started_events.size(), 1, "system emits one construction start")
placed.advance_construction_stage()
assertions.equal(stage_events.size(), 1, "system forwards stage change")
placed.complete_construction()
assertions.equal(completed_events.size(), 1, "system forwards completion")
```

Also assert preview instances remain `_preview_mode`, have collision layer `0`, and do not start construction.

- [ ] **Step 2: Run the suite and verify RED**

Expected: placed building is currently complete and construction signals are absent.

- [ ] **Step 3: Integrate construction into atomic placement**

Add typed signals to `BuildingSystem` and `EventBus`. After `add_child` and tracking, connect instance signals, call `start_construction()`, then emit `building_construction_started`. Forward stage and completion to both BuildingSystem and EventBus.

Keep rollback ordering unchanged; no construction signal may fire before resource spending succeeds.

Gallery and tests needing a completed building call `complete_construction()` explicitly after normal placement.

- [ ] **Step 4: Run and verify GREEN**

Run Building tests. Expected: placement, rollback, compatibility signals, and new construction signals pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/building_system.gd scripts/core/event_bus.gd tests/test_building_system_complete.gd
git commit -m "feat: integrate construction with building placement"
```

---

### Task 4: Construction Save and Restore

**Files:**
- Modify: `scripts/buildings/building_instance.gd`
- Modify: `scripts/systems/building_system.gd`
- Modify: `tests/test_building_save_integration.gd`

**Interfaces:**
- Consumes: `restore_construction(stage, elapsed)`.
- Produces: construction fields in `to_dict()` and backward-compatible `restore_buildings()`.

- [ ] **Step 1: Write failing save assertions**

Place a fence, advance to `FRAME`, serialize, and assert:

```gdscript
assertions.equal(record.construction_stage, BuildingInstance.ConstructionStage.FRAME, "save stores stage")
assertions.truthy(record.construction_elapsed > 0.0, "save stores elapsed")
system.restore_buildings([record])
var restored := system.get_building_at(6, 6)
assertions.equal(restored.construction_stage, BuildingInstance.ConstructionStage.FRAME, "load restores stage")
```

Remove construction keys from a duplicate legacy record and assert it restores as `COMPLETE`.

- [ ] **Step 2: Run and verify RED**

Expected: records lack construction fields and restored instances use their default state.

- [ ] **Step 3: Implement serialization and compatible restore**

Add exact fields to `to_dict()`:

```gdscript
"construction_stage": int(construction_stage),
"construction_elapsed": construction_elapsed,
"construction_duration": construction_duration,
```

In `restore_buildings()`, after configure and before tracking completion, call `restore_construction()` with saved values when keys exist; otherwise call `restore_construction(ConstructionStage.COMPLETE, construction_duration)`. Restoration changes visuals and physics without emitting construction signals.

- [ ] **Step 4: Run and verify GREEN**

Run Building tests. Expected: staged and legacy save cases pass; spending call count remains unchanged during restore.

- [ ] **Step 5: Commit**

```bash
git add scripts/buildings/building_instance.gd scripts/systems/building_system.gd tests/test_building_save_integration.gd
git commit -m "feat: persist building construction progress"
```

---

### Task 5: Generate and Validate 27 Dedicated Construction Images

**Files:**
- Create: `assets/buildings/construction/barn/barn_foundation.png`
- Create: `assets/buildings/construction/barn/barn_frame.png`
- Create: `assets/buildings/construction/barn/barn_half_built.png`
- Create: `assets/buildings/construction/greenhouse/greenhouse_foundation.png`
- Create: `assets/buildings/construction/greenhouse/greenhouse_frame.png`
- Create: `assets/buildings/construction/greenhouse/greenhouse_half_built.png`
- Create: `assets/buildings/construction/windmill/windmill_foundation.png`
- Create: `assets/buildings/construction/windmill/windmill_frame.png`
- Create: `assets/buildings/construction/windmill/windmill_half_built.png`
- Create: `assets/buildings/construction/chicken_coop/chicken_coop_foundation.png`
- Create: `assets/buildings/construction/chicken_coop/chicken_coop_frame.png`
- Create: `assets/buildings/construction/chicken_coop/chicken_coop_half_built.png`
- Create: `assets/buildings/construction/beehive/beehive_foundation.png`
- Create: `assets/buildings/construction/beehive/beehive_frame.png`
- Create: `assets/buildings/construction/beehive/beehive_half_built.png`
- Create: `assets/buildings/construction/well/well_foundation.png`
- Create: `assets/buildings/construction/well/well_frame.png`
- Create: `assets/buildings/construction/well/well_half_built.png`
- Create: `assets/buildings/construction/workbench/workbench_foundation.png`
- Create: `assets/buildings/construction/workbench/workbench_frame.png`
- Create: `assets/buildings/construction/workbench/workbench_half_built.png`
- Create: `assets/buildings/construction/lamp/lamp_foundation.png`
- Create: `assets/buildings/construction/lamp/lamp_frame.png`
- Create: `assets/buildings/construction/lamp/lamp_half_built.png`
- Create: `assets/buildings/construction/fence/fence_foundation.png`
- Create: `assets/buildings/construction/fence/fence_frame.png`
- Create: `assets/buildings/construction/fence/fence_half_built.png`
- Modify: `tests/test_building_art_assets.gd`

**Interfaces:**
- Consumes: the existing back/front references under `assets/buildings/painted/` for barn, greenhouse, windmill, chicken_coop, beehive, well, workbench, lamp, and fence.
- Produces: all construction texture paths consumed by Task 2.

- [ ] **Step 1: Extend the art contract and verify RED**

For every catalog ID and each suffix `foundation`, `frame`, `half_built`, assert:

```gdscript
ResourceLoader.exists(path)
texture.get_width() == 1024
texture.get_height() == 1024
image.detect_alpha() != Image.ALPHA_NONE
```

Run Building tests. Expected: failures list all 27 missing paths.

- [ ] **Step 2: Generate three coherent stages per building**

For each ID, use its finished back/front images as references with this exact prompt:

```text
Create a coherent three-stage construction sequence for the same building
shown in the references. Hand-painted semi-realistic rural fantasy style, fixed
isometric three-quarter view, warm light from upper left, identical footprint,
orientation, palette, ground contact and camera scale across all stages.
Panel 1: building-specific foundation with stones, posts or base.
Panel 2: recognizable structural frame, beams and supports.
Panel 3: mostly built structure missing final roof/doors/windows/machinery/front props.
Transparent background, centered, generous clean margins, no text, no watermark,
no square terrain tile, no unrelated fragments. Output three separate square images.
```

Required name mapping:

```text
barn=谷仓, greenhouse=温室, windmill=风车, chicken_coop=鸡舍,
beehive=蜂箱, well=水井, workbench=工作台, lamp=路灯, fence=围栏
```

Save the three outputs to the exact paths above. Inspect every image at original resolution for opaque background, clipping, debris, mismatched orientation, and unstable root anchor; regenerate any failed image.

- [ ] **Step 3: Import and verify GREEN**

Run:

```bash
godot --headless --editor --path . --quit
godot --headless --path . --script res://tests/run_building_system_tests.gd
```

Expected: all 27 paths import and all art checks pass.

- [ ] **Step 4: Commit**

```bash
git add assets/buildings/construction tests/test_building_art_assets.gd
git commit -m "art: add dedicated building construction stages"
```

---

### Task 6: Interactive Visual Verification

**Files:**
- Modify: `tests/visual/building_system_verification.gd`
- Modify: `tests/visual/building_system_verification.tscn`
- Modify: `tests/test_building_visual_scene.gd`
- Modify: `tests/capture_building_visual.gd`

**Interfaces:**
- Consumes: instance stage APIs and BuildingSystem construction signals.
- Produces: `P` construction start, `N` stage step, `X` cancellation, construction status panel and screenshot contract.

- [ ] **Step 1: Write failing visual-scene contract assertions**

Instantiate the scene and assert it exposes:

```gdscript
has_method("_advance_active_construction")
has_method("_construction_contract_passes")
```

After ready, assert one interactive construction exists at `FRAME`, collision is enabled, interaction is disabled, gallery count remains nine completed buildings, and `verification_contract_passes()` is true.

- [ ] **Step 2: Run and verify RED**

Run:

```bash
godot --headless --path . --script res://tests/test_building_visual_scene.gd
```

Expected: missing construction helpers and no active staged construction.

- [ ] **Step 3: Implement verifier construction controls**

Keep gallery placements but call `complete_construction()` on each. Track `_active_construction`.

`P / Enter` places and begins construction. `N` calls `_active_construction.advance_construction_stage()`. `X` first removes a building under the preview; otherwise removes the active incomplete construction. Add state, percent, duration, collision, interaction and cancellation checks to the status panel.

During reset, create a barn in the interaction zone, call `advance_construction_stage()` once, and leave it at `FRAME` for the default screenshot.

Update the instruction label to:

```text
1–9 选择建筑   方向键移动   P/Enter 开工   N 推进阶段   X 取消/拆除   B 阻塞   M 材料   R 重置   Esc 退出
```

- [ ] **Step 4: Run scene contract and capture**

Run:

```bash
godot --headless --path . --script res://tests/test_building_visual_scene.gd
godot --path . --script res://tests/capture_building_visual.gd
```

Expected: contract passes and `/tmp/villa-building-system-verification.png` is 1600×1000 with a visible frame-stage construction site.

- [ ] **Step 5: Commit**

```bash
git add tests/visual/building_system_verification.gd tests/visual/building_system_verification.tscn tests/test_building_visual_scene.gd tests/capture_building_visual.gd
git commit -m "test: visualize staged building construction"
```

---

### Task 7: Full Regression and Integration Review

**Files:**
- Modify only if a verified regression requires a scoped fix.

**Interfaces:**
- Consumes: all prior tasks.
- Produces: fresh completion evidence.

- [ ] **Step 1: Parse the complete project**

```bash
godot --headless --editor --path . --quit
```

Expected: exit `0`, no parse errors.

- [ ] **Step 2: Run subsystem suites**

```bash
godot --headless --path . --script res://tests/run_building_system_tests.gd
godot --headless --path . --script res://tests/run_farming_system_tests.gd
godot --headless --path . --script res://tests/run_grid_system_tests.gd
godot --headless --path . --script res://tests/test_player_grid_binding.gd
```

Expected: all supported checks pass with no script errors.

- [ ] **Step 3: Run visual contracts and runtimes**

```bash
godot --headless --path . --script res://tests/test_building_visual_scene.gd
godot --headless --path . --script res://tests/test_farming_visual_scene.gd
godot --headless --path . --script res://tests/test_grid_visual_scene.gd
godot --headless --path . res://tests/visual/building_system_verification.tscn --quit-after 6
godot --headless --path . --quit-after 6
```

Expected: all commands exit `0` and contain no `SCRIPT ERROR`.

- [ ] **Step 4: Inspect final image and Git diff**

Open `/tmp/villa-building-system-verification.png` at original resolution. Confirm the `FRAME` construction differs visibly from the completed gallery, aligns to the grid, has no opaque background or clipped debris, and the status panel is readable.

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; only intentional plan execution changes before the final commit.

- [ ] **Step 5: Commit any final scoped corrections**

If Step 1–4 required a correction:

```bash
git add -u
git diff --cached --name-only
git commit -m "fix: finalize staged building construction"
```

If no correction was required, do not create an empty commit.
