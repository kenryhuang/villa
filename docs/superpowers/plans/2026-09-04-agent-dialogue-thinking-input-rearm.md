# Agent Dialogue Thinking and Input Rearm Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make NPC dialogue requests fast by disabling Provider thinking and prevent dialogue text keystrokes from becoming continuous player movement after close.

**Architecture:** `OpenAICompatibleProvider` adds a dialogue-only request option to every remote round. `PlayerController` clears gameplay actions at the input boundary while dialogue owns the keyboard and requires a fresh, non-echo action press after close. Expected request preemption is recorded as `cancelled`, not `error`.

**Tech Stack:** TypeScript/Node test runner, Godot 4/GDScript scene tests.

---

### Task 1: Disable Provider thinking for dialogue only

**Files:**
- Modify: `services/agent-service/tests/provider.test.ts`
- Modify: `services/agent-service/src/provider.ts`

- [x] **Step 1: Write failing Provider request assertions**

Extend the dialogue test to inspect every captured request body and require:

```ts
assert.equal(dialogueBodies.length, 2);
assert.ok(dialogueBodies.every((body) => body.enable_thinking === false));
assert.ok(autonomousBodies.every((body) => !("enable_thinking" in body)));
```

The fake dialogue Provider first returns one allowed read call and then a final textual response, proving the option survives the follow-up round.

- [x] **Step 2: Run the focused test and verify RED**

Run:

```powershell
node --experimental-strip-types --test --test-name-pattern="dialogue.*thinking" tests/provider.test.ts
```

Expected: FAIL because dialogue bodies do not contain `enable_thinking`.

- [x] **Step 3: Add the dialogue-only request option**

In `OpenAICompatibleProvider.streamDecision`, add the option while constructing each `providerBody` inside the round loop:

```ts
const providerBody: Record<string, unknown> = {
  model: this.#config.model,
  ...(isDialogue ? {enable_thinking: false} : {}),
  temperature: this.#config.temperature,
  // existing fields remain unchanged
};
```

Do not add the field for schedule, event, catch-up, or memory-compaction calls.

- [x] **Step 4: Re-run the focused test and verify GREEN**

Run the same focused command. Expected: PASS.

### Task 2: Require a fresh input event after dialogue

**Files:**
- Create: `tests/run_player_logic_tests.gd`
- Modify: `tests/test_player_logic.gd`
- Modify: `scripts/actors/player.gd`

- [x] **Step 1: Add a focused Player logic runner**

Create `tests/run_player_logic_tests.gd`:

```gdscript
extends SceneTree

const PlayerLogicTest = preload("res://tests/test_player_logic.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")

func _init() -> void:
	var assertions = TestAssertScript.new()
	PlayerLogicTest.new().run(assertions)
	if assertions.failures.is_empty():
		print("PASS: %d player logic checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print("FAIL: %d of %d player logic checks failed" % [assertions.failures.size(), assertions.checks])
	quit(1)
```

- [x] **Step 2: Add real Godot input-event regression coverage**

Drive `InputEventKey` through `Input.parse_input_event` and verify that D typed while dialogue is open never remains in `move_right`, a held-key echo after close cannot rearm movement, and only a new non-echo press restores movement.

```gdscript
player.set_movement_input_blocked(true)
Input.parse_input_event(d_pressed)
assertions.truthy(not Input.is_action_pressed("move_right"))
player.set_movement_input_blocked(false)
Input.parse_input_event(d_echo)
assertions.equal(player.filter_movement_input(Input.get_vector(...)), Vector2.ZERO)
Input.parse_input_event(d_released)
Input.parse_input_event(d_fresh_press)
assertions.equal(player.filter_movement_input(Input.get_vector(...)), Vector2.RIGHT)
```

- [x] **Step 3: Run the Player test and verify RED**

Run:

```powershell
godot_console --headless --path . --script res://tests/run_player_logic_tests.gd
```

Expected: FAIL because current unlock immediately passes `Vector2.RIGHT`.

- [x] **Step 4: Implement event-gated rearming**

Add `_movement_input_rearm_pending`. While blocked, every mapped movement/jump/sprint event immediately releases its gameplay action state without consuming the UI event. On unblock, clear all mapped actions and keep the latch closed. Only a fresh non-echo mapped press clears the latch; neutral polling and key echo cannot do so.

Use the combined blocked/pending state for jump and sprint checks in `_physics_process`, so those actions cannot escape the latch before movement filtering runs.

### Task 3: Classify dialogue preemption as cancellation

**Files:**
- Modify: `scripts/ai_agent/agent_runtime.gd`
- Modify: `scripts/ai_agent/agent_session_trace.gd`
- Modify: `scripts/ui/agent_debug_window.gd`
- Modify: `tests/test_agent_runtime.gd`
- Modify: `tests/test_agent_streaming.gd`

- [x] Add a `cancelled` trace terminal state with a separate cancellation reason.
- [x] Route `dialogue_replaced` and `dialogue_closed` through cancellation finalization.
- [x] Keep expected cancellations out of dialogue failure signals and error payloads.
- [x] Display cancellation diagnostics separately in the Agent debug window.

- [x] **Step 5: Re-run the Player test and verify GREEN**

Run the same Player command. Expected: PASS with zero failures.

### Task 4: Full verification and runtime reload

**Files:**
- Modify: `docs/superpowers/plans/2026-09-04-agent-dialogue-thinking-input-rearm.md`

- [x] **Step 1: Run the complete Agent Service suite**

Run `npm test` in `services/agent-service`. Expected: all tests pass.

- [x] **Step 2: Run the complete Godot Agent suite**

Run `godot_console --headless --path . --script res://tests/run_agent_system_tests.gd`. Expected: all checks pass.

- [x] **Step 3: Check the patch**

Run `git diff --check` and inspect `git status --short`. Expected: no whitespace errors and only the planned implementation/plan files are uncommitted.

- [x] **Step 4: Restart Agent Service**

Verify the exact Node process listening on `127.0.0.1:8787`, stop only that PID, restart it hidden from `services/agent-service` with `config/agent-service.local.json`, then verify `/health` returns protocol v2 and the new stderr log is empty.
