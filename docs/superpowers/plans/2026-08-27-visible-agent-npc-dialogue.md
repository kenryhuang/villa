# Visible Agent NPC Dialogue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bind the three headless Agent roles to the three visible NPCs and let the player click either an in-range speech-bubble prompt or the NPC body to start the existing streamed Agent dialogue safely.

**Architecture:** The shared NPC scene owns XZ-distance sensing, prompt visibility/collision, and busy re-entry protection, but emits only an Agent ID. `Main` owns the exact scene-to-Agent mapping and coordinates `AgentRuntime`, `DialogueUI`, and `HudMessageBus`; `DialogueUI` owns request-scoped stream presentation and emits close/cancel lifecycle signals so only the corresponding NPC is unlocked.

**Tech Stack:** Godot 4.7, GDScript, Godot 3D physics ray queries, Sprite3D/SVG UI assets, existing Protocol v2 HTTP/SSE Agent runtime, repository-native headless tests.

---

## File Structure

- Create `assets/ui/dialogue_prompt.svg`: transparent hand-painted speech-bubble texture used by every visible Agent NPC.
- Modify `scenes/actors/npc.tscn`: add the billboard prompt sprite and a layer-64 `Area3D` click target.
- Modify `scripts/actors/npc.gd`: own horizontal range detection, prompt collision state, Agent identity, and dialogue busy state.
- Modify `tests/test_npc_logic.gd`: cover the NPC spatial and prompt contract against the real scene.
- Modify `scripts/actors/player_action_controller.gd`: preserve the shared parent-target resolution and return the NPC's actual interaction result.
- Modify `tests/test_player_action_controller.gd`: prove body and prompt targets use the same `start_dialogue()` entry and rejected clicks remain rejected.
- Modify `scripts/main.gd`: bind the exact three Agent IDs, route dialogue lifecycle by Agent ID, and publish service failures only through `HudMessageBus`.
- Modify `scripts/ui/dialogue_ui.gd`: distinguish active streaming from an open completed dialogue and emit request-scoped close/cancel signals.
- Modify `tests/test_agent_main_integration.gd`: verify the new Dialogue UI lifecycle contract remains available beside Protocol v2 execution.
- Create `tests/test_visible_agent_npc_dialogue.gd`: exercise exact Main mappings and per-NPC success/failure/unlock isolation with fakes.
- Modify `tests/run_tests.gd` and `tests/run_agent_system_tests.gd`: register the new focused checks.
- Modify `docs/validation/role-agent-framework-validation.md`: record the final headless verification commands and results.

### Task 1: Add the NPC proximity and prompt-state contract

**Files:**
- Create: `assets/ui/dialogue_prompt.svg`
- Modify: `scenes/actors/npc.tscn`
- Modify: `scripts/actors/npc.gd`
- Modify: `tests/test_npc_logic.gd`
- Modify: `tests/run_tests.gd`

- [ ] **Step 1: Write failing NPC scene and state tests**

Extend `test_npc_logic.gd` so it instantiates `res://scenes/actors/npc.tscn`, attaches a `Node3D` player, configures an Agent identity, and checks all of these exact cases:

```gdscript
npc.configure_agent(player, "farmer_ahe")
player.global_position = npc.global_position + Vector3(3.0, 20.0, 0.0)
npc.refresh_dialogue_prompt()
assertions.truthy(npc.is_player_in_dialogue_range(), "XZ range ignores height")
assertions.truthy(npc.get_node("DialoguePrompt").visible, "prompt appears at three metres")
assertions.equal(npc.get_node("DialoguePrompt/HitArea").collision_layer, 64, "visible prompt is ray-pickable")

player.global_position.x += 0.01
npc.refresh_dialogue_prompt()
assertions.truthy(not npc.get_node("DialoguePrompt").visible, "prompt hides outside range")
assertions.equal(npc.get_node("DialoguePrompt/HitArea").collision_layer, 0, "hidden prompt cannot intercept rays")

player.global_position = npc.global_position
npc.set_dialogue_busy(true)
npc.refresh_dialogue_prompt()
assertions.truthy(not npc.start_dialogue(), "busy NPC rejects duplicate dialogue")
npc.set_dialogue_busy(false)
assertions.truthy(npc.start_dialogue(), "available NPC emits one dialogue intent")
assertions.equal(spy.last_villager_id, "farmer_ahe", "dialogue intent carries Agent ID")
```

Change `NpcLogicTest.run(assertions)` to `run(assertions, tree)` and pass the runner's `SceneTree`, so the real scene's `@onready` prompt references initialize.

- [ ] **Step 2: Run the core suite and confirm the new checks fail**

Run: `godot_console --headless --path . --script res://tests/run_tests.gd`

Expected: the new NPC checks fail because `configure_agent`, `refresh_dialogue_prompt`, busy state, and `DialoguePrompt` do not exist. Preserve the four already-recorded unrelated baseline failures separately.

- [ ] **Step 3: Author the prompt asset and scene branch**

Create a 96×96 transparent SVG with an irregular cream speech bubble, warm-brown two-pass outline, and three dark-brown hand-painted dots. Add this scene branch:

```text
DialoguePrompt (Node3D, position 0,1.45,0; initially hidden)
├── Icon (Sprite3D; texture dialogue_prompt.svg; billboard enabled; shaded false)
└── HitArea (Area3D; layer 0 until visible; mask 0; ray-pickable false)
    └── CollisionShape3D (SphereShape3D radius 0.42)
```

The sprite and hit area share the same local origin. The body remains on layer `4`; the prompt uses the existing interaction layer `64` only while visible.

- [ ] **Step 4: Implement the minimal NPC state machine**

Add the focused interface below to `npc.gd` and call `refresh_dialogue_prompt()` from `_physics_process()` after movement:

```gdscript
const INTERACTION_DISTANCE := 3.0
const PROMPT_INTERACTION_LAYER := 64

var _agent_dialogue_enabled := false
var _dialogue_busy := false

func configure_agent(player: Node3D, agent_id: String) -> bool:
	configure(player)
	if agent_id.is_empty():
		return false
	villager_id = agent_id
	_agent_dialogue_enabled = true
	refresh_dialogue_prompt()
	return true

func is_player_in_dialogue_range() -> bool:
	if _player_ref == null or not is_instance_valid(_player_ref):
		return false
	return Vector2(global_position.x, global_position.z).distance_to(
		Vector2(_player_ref.global_position.x, _player_ref.global_position.z)
	) <= INTERACTION_DISTANCE

func set_dialogue_busy(value: bool) -> void:
	_dialogue_busy = value
	refresh_dialogue_prompt()

func is_dialogue_busy() -> bool:
	return _dialogue_busy

func refresh_dialogue_prompt() -> void:
	var visible_now := _agent_dialogue_enabled and not _dialogue_busy and is_player_in_dialogue_range()
	_set_dialogue_prompt_visible(visible_now)

func start_dialogue() -> bool:
	if not _agent_dialogue_enabled or _dialogue_busy or not is_player_in_dialogue_range():
		return false
	_dialogue_busy = true
	refresh_dialogue_prompt()
	dialogue_started.emit(villager_id)
	return true
```

`_set_dialogue_prompt_visible()` must update `DialoguePrompt.visible`, `HitArea.collision_layer`, and `HitArea.input_ray_pickable` together. Hiding is immediate; showing sets the icon alpha to zero and starts only a short alpha tween without delaying collision availability.

- [ ] **Step 5: Run focused/core checks and commit**

Run: `godot_console --headless --path . --script res://tests/run_tests.gd`

Expected: every new NPC check passes; only the four pre-existing baseline failures may remain.

Commit:

```powershell
git add assets/ui/dialogue_prompt.svg scenes/actors/npc.tscn scripts/actors/npc.gd tests/test_npc_logic.gd tests/run_tests.gd
git commit -m "feat: add Agent NPC dialogue prompts"
```

### Task 2: Preserve one mouse-interaction path for body and prompt

**Files:**
- Modify: `scripts/actors/player_action_controller.gd`
- Modify: `tests/test_player_action_controller.gd`

- [ ] **Step 1: Write failing shared-target tests**

Add a fake dialogue target with `start_dialogue() -> bool` and an `Area3D` child. Verify `_find_interaction_target(area)` returns the same parent target as a body collider and that `perform_target_interaction()` returns the target's boolean result:

```gdscript
assertions.equal(controller.call("_find_interaction_target", prompt_area), npc_target, "prompt resolves to NPC parent")
assertions.equal(controller.call("_find_interaction_target", npc_target), npc_target, "body resolves to same NPC")
npc_target.allow_dialogue = false
assertions.truthy(not controller.perform_target_interaction(npc_target), "rejected NPC click remains rejected")
npc_target.allow_dialogue = true
assertions.truthy(controller.perform_target_interaction(npc_target), "accepted NPC click uses shared entry")
```

- [ ] **Step 2: Run the controller suite and confirm RED**

Run: `godot_console --headless --path . --script res://tests/run_player_action_controller_tests.gd`

Expected: rejected `start_dialogue()` currently reports `true` unconditionally.

- [ ] **Step 3: Return the target's interaction result without adding a second ray**

Keep `INTERACTION_MASK := 4 | 64`, `collide_with_areas = true`, and `_find_interaction_target()`'s parent walk. Change only the dialogue call branch:

```gdscript
if target.has_method("start_dialogue"):
	var dialogue_result: Variant = target.call("start_dialogue")
	return bool(dialogue_result) if dialogue_result is bool else true
```

Do not add an Agent-specific raycast or change building/resource interaction masks.

- [ ] **Step 4: Run the controller suite and commit**

Run: `godot_console --headless --path . --script res://tests/run_player_action_controller_tests.gd`

Expected: PASS with zero failures.

Commit:

```powershell
git add scripts/actors/player_action_controller.gd tests/test_player_action_controller.gd
git commit -m "fix: share NPC body and prompt interaction"
```

### Task 3: Bind the three scene NPCs and enforce the no-fallback boundary

**Files:**
- Modify: `scripts/main.gd`
- Create: `tests/test_visible_agent_npc_dialogue.gd`
- Modify: `tests/run_agent_system_tests.gd`

- [ ] **Step 1: Write failing Main routing tests**

Create fake `AgentRuntime`, `DialogueUI`, and `HudMessageBus` nodes, then exercise Main's public callbacks without starting HTTP. Assert this exact constant mapping and per-Agent isolation:

```gdscript
assertions.equal(str(MainScript.AGENT_NPC_BINDINGS.NpcNorthwest.agent_id), "farmer_ahe", "northwest NPC is farmer")
assertions.equal(str(MainScript.AGENT_NPC_BINDINGS.NpcSouth.agent_id), "lao_li", "south NPC is merchant")
assertions.equal(str(MainScript.AGENT_NPC_BINDINGS.NpcEast.agent_id), "xuezhe_lin", "east NPC is explorer")
main.call("_on_dialogue_started", "farmer_ahe")
assertions.equal(runtime.triggered, ["farmer_ahe"], "NPC intent starts the Agent runtime")
assertions.truthy(farmer.is_dialogue_busy(), "accepted request keeps only farmer busy")
assertions.truthy(not merchant.is_dialogue_busy(), "merchant stays independently available")

runtime.trigger_result = false
main.call("_on_dialogue_started", "lao_li")
assertions.truthy(not merchant.is_dialogue_busy(), "failed start immediately unlocks merchant")
assertions.equal(dialogue.fixed_dialogue_calls, 0, "managed Agent never uses authored fallback")
assertions.equal(hud.last_text, "Agent 服务不可用，请稍后再试。", "failure enters message stream")
```

Also assert that a stream failure unlocks only its Agent and invokes Dialogue UI failure cleanup with the original request ID.

- [ ] **Step 2: Run the Agent suite and confirm RED**

Run: `godot_console --headless --path . --script res://tests/run_agent_system_tests.gd`

Expected: compilation/assertion failures because the binding table, NPC route map, and no-fallback failure path do not exist.

- [ ] **Step 3: Implement exact scene binding and per-Agent routing**

Add this immutable mapping and a runtime route map to `main.gd`:

```gdscript
const AGENT_NPC_BINDINGS := {
	"NpcNorthwest": {"agent_id": "farmer_ahe", "spawn": Vector2(-3.0, -2.0)},
	"NpcSouth": {"agent_id": "lao_li", "spawn": Vector2(3.0, -3.0)},
	"NpcEast": {"agent_id": "xuezhe_lin", "spawn": Vector2(4.0, 2.0)},
}
const AGENT_SERVICE_UNAVAILABLE_MESSAGE := "Agent 服务不可用，请稍后再试。"
var _agent_npcs: Dictionary = {}
```

Make `_setup_npcs()` resolve each named child explicitly, place it, call `configure_agent(player, agent_id)`, connect `dialogue_started`, and store `_agent_npcs[agent_id] = npc`. Remove the positional legacy villager array.

Add focused helpers:

```gdscript
func _set_agent_npc_busy(agent_id: String, busy: bool) -> void:
	var npc: Variant = _agent_npcs.get(agent_id)
	if npc != null and is_instance_valid(npc) and npc.has_method("set_dialogue_busy"):
		npc.call("set_dialogue_busy", busy)

func _publish_agent_service_unavailable(agent_id: String) -> void:
	_publish_hud_message("agent", "warning", AGENT_SERVICE_UNAVAILABLE_MESSAGE, {"agent_id": agent_id})
```

In `_on_dialogue_started()`, Agent-managed IDs must either successfully call `trigger_dialogue()` or publish the warning and unlock the same NPC. They must never reach `dialogue_ui.start_dialogue()`. Keep authored dialogue only for IDs not managed by `AgentRuntime`.

- [ ] **Step 4: Route stream failures and close events by ID**

Change `_on_agent_dialogue_stream_failed(agent_id, request_id, error)` to ask Dialogue UI to discard the matching incomplete request, publish the standard warning, and unlock only `agent_id`. Connect the new `agent_dialogue_closed(agent_id, request_id)` signal in `_setup_ui()`; cancellation still calls `AgentRuntime.cancel_dialogue(agent_id, request_id)`, while close always unlocks that Agent's NPC.

- [ ] **Step 5: Run the Agent suite and commit**

Run: `godot_console --headless --path . --script res://tests/run_agent_system_tests.gd`

Expected: the mapping, failure, and per-NPC isolation checks pass together with all existing 813 Agent checks.

Commit:

```powershell
git add scripts/main.gd tests/test_visible_agent_npc_dialogue.gd tests/run_agent_system_tests.gd
git commit -m "feat: bind visible NPCs to Agent roles"
```

### Task 4: Make streamed dialogue close and failure request-scoped

**Files:**
- Modify: `scripts/ui/dialogue_ui.gd`
- Modify: `tests/test_agent_main_integration.gd`
- Modify: `tests/test_visible_agent_npc_dialogue.gd`
- Modify: `docs/validation/role-agent-framework-validation.md`

- [ ] **Step 1: Write failing Dialogue UI lifecycle tests**

Extend the Agent integration test to instantiate `dialogue_ui.tscn` in the tree and verify these lifecycle rules:

```gdscript
dialogue.begin_agent_dialogue("farmer_ahe", "request-a")
dialogue.append_agent_dialogue("request-a", "你好")
dialogue.finish_agent_dialogue("request-a", "你好，今天适合播种。")
dialogue.close()
assertions.equal(spy.closed, [["farmer_ahe", "request-a"]], "completed dialogue closes with original identity")
assertions.equal(spy.cancelled.size(), 0, "completed dialogue is not cancelled")

dialogue.begin_agent_dialogue("lao_li", "request-b")
dialogue.close()
assertions.equal(spy.cancelled, [["lao_li", "request-b"]], "in-flight close cancels original request")

dialogue.begin_agent_dialogue("xuezhe_lin", "request-c")
assertions.truthy(dialogue.fail_agent_dialogue("request-c"), "matching failure closes incomplete dialogue")
dialogue.append_agent_dialogue("request-c", "迟到文本")
assertions.truthy(not dialogue.visible, "late delta cannot reopen failed dialogue")
```

- [ ] **Step 2: Run the Agent suite and confirm RED**

Run: `godot_console --headless --path . --script res://tests/run_agent_system_tests.gd`

Expected: `agent_dialogue_closed` and request-scoped failure cleanup are missing, and completed requests lose their ID before close.

- [ ] **Step 3: Separate open-dialogue identity from stream-pending state**

Add `signal agent_dialogue_closed(villager_id, request_id)`, retain `_agent_dialogue_request_id` until the panel closes, and track `_agent_stream_pending` separately. `finish_agent_dialogue()` marks pending false but keeps the original request identity. `close()` must:

```gdscript
var villager_id := _current_villager_id
var request_id := _agent_dialogue_request_id
var should_cancel := _agent_stream_pending and not request_id.is_empty()
_clear_agent_dialogue_state()
if should_cancel:
	agent_dialogue_cancelled.emit(villager_id, request_id)
if not request_id.is_empty():
	agent_dialogue_closed.emit(villager_id, request_id)
```

Replace the fixed-text `fail_agent_dialogue(request_id, fallback)` behavior with `fail_agent_dialogue(request_id) -> bool`: only a matching pending request is cleared and hidden, then `agent_dialogue_closed` is emitted. It must not inject local NPC speech. Append/final calls with any stale request ID remain no-ops.

- [ ] **Step 4: Run fresh focused and regression verification**

Run all of:

```powershell
godot_console --headless --path . --script res://tests/run_player_action_controller_tests.gd
godot_console --headless --path . --script res://tests/run_agent_system_tests.gd
godot_console --headless --path . --editor --quit
godot_console --headless --path . --quit-after 3
git diff --check
```

Expected: focused suites pass with zero failures; project import and headless startup exit `0` without parse errors. Run `tests/run_tests.gd` once more and document the already-known unrelated baseline failures separately from this feature.

- [ ] **Step 5: Record validation and commit**

Add the exact commands, check counts, and any unchanged baseline failures to `docs/validation/role-agent-framework-validation.md`. Confirm the record states that Protocol v2 batching, autonomous decisions, real world-state mutations, F8 reasoning traces, and stream cancellation remain covered.

Commit:

```powershell
git add scripts/ui/dialogue_ui.gd tests/test_agent_main_integration.gd tests/test_visible_agent_npc_dialogue.gd docs/validation/role-agent-framework-validation.md
git commit -m "feat: complete streamed Agent NPC dialogue"
```

## Manual Acceptance

- [ ] Start the configured local Agent Service and the game.
- [ ] Approach each named NPC and verify the bubble appears at XZ distance `<= 3.0` even across a terrain height difference, then disappears outside range.
- [ ] Click both the body and bubble for different NPCs and verify both open the same streamed Agent dialogue path.
- [ ] Repeatedly click during generation and while the dialogue remains open; verify no duplicate request is issued.
- [ ] Open F8 and verify input, reasoning, and output raw events still appear only in the Agent debug window.
- [ ] Close a completed and an in-progress dialogue; verify only the corresponding nearby NPC bubble returns and the in-progress request is cancelled.
- [ ] Stop Agent Service, click an NPC, and verify no fixed line appears; only `Agent 服务不可用，请稍后再试。` enters the right-side message panel.
- [ ] Advance game time and verify all three Agents still take autonomous actions that mutate their inventories, farms, market state, activities, buildings, or knowledge.
