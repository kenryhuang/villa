# Agent Runtime Responsiveness and Dialogue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate streamed-Agent frame spikes, add per-Agent automatic interval controls, and deliver fixed-size multi-turn dialogue for all three visible Agent NPCs.

**Architecture:** Keep remote inference asynchronous and bound Godot main-thread work with fragment-based trace accumulation, coalesced hidden-aware rendering, and an SSE event queue with per-frame budgets. Add runtime-only scheduler overrides behind a focused debug-panel API. Separate opening an NPC conversation from submitting a model request, then pass the actual player text through Godot Protocol v2 into the Provider and recent Agent memory.

**Tech Stack:** Godot 4.7/GDScript, TypeScript on Node 24, OpenAI-compatible streamed chat completions, SQLite Agent memory, existing headless Godot and Node test runners.

---

### Task 1: Remove per-delta trace and hidden-window rendering costs

**Files:**
- Modify: `tests/test_agent_streaming.gd`
- Modify: `tests/test_agent_debug_window.gd`
- Modify: `scripts/ai_agent/agent_session_trace.gd`
- Modify: `scripts/ui/agent_debug_window.gd`

- [x] **Step 1: Add failing trace-fragment and hidden-render tests**

Extend the streaming test to feed multiple reasoning/content fragments and assert that `get_request()` still exposes joined `reasoning` and `content` strings and that the schema-v2 terminal record is unchanged. Change the debug-window test so trace events received while the window is hidden leave `ItemList.item_count == 0`; after `open()` the request appears. While visible, feed several deltas in one frame and assert the text view changes only after the deferred frame refresh.

- [x] **Step 2: Run the Agent suite and confirm RED**

```powershell
godot_console --headless --path . --script res://tests/run_agent_system_tests.gd
```

Expected: the hidden window renders immediately and visible updates are not coalesced.

- [x] **Step 3: Store fragments and materialize public records**

Replace per-delta string concatenation with internal arrays:

```gdscript
"reasoning_parts": [],
"content_parts": [],
```

Append delta strings in `accept_event()`. Add `_materialize_record(record)` that joins parts into the existing public `reasoning` and `content` fields and erases the internal arrays. Use it in `get_requests()`, `get_request()`, and `_disk_record()`.

- [x] **Step 4: Make debug rendering hidden-aware and frame-coalesced**

Add `_refresh_pending`. `_on_trace_updated()` records selection but returns without rendering when hidden; otherwise it schedules exactly one deferred `_flush_trace_refresh()`. `open()` cancels the pending flag and refreshes synchronously. The deferred method refreshes only if still visible.

- [x] **Step 5: Run the Agent suite and commit**

Run the Agent suite, expect PASS, then commit the focused performance change.

### Task 2: Bound streamed HTTP work per Godot frame

**Files:**
- Create: `scripts/ai_agent/agent_stream_event_queue.gd`
- Create: `tests/test_agent_stream_event_queue.gd`
- Modify: `tests/run_agent_system_tests.gd`
- Modify: `scripts/ai_agent/agent_stream_client.gd`

- [x] **Step 1: Write failing queue behavior tests**

Specify this API:

```gdscript
func push_many(events: Array) -> bool
func drain(limit: int) -> Array[Dictionary]
func is_empty() -> bool
func size() -> int
```

Assert that `drain(32)` returns the first 32 of 40 events in order, leaves eight queued, rejects non-dictionary events, and never drains when the limit is non-positive. Register the test in `run_agent_system_tests.gd`.

- [x] **Step 2: Run the Agent suite and confirm RED**

Expected: preload fails because `agent_stream_event_queue.gd` does not exist.

- [x] **Step 3: Implement the FIFO queue and integrate frame budgets**

Add constants to `AgentStreamClient`:

```gdscript
const MAX_CHUNKS_PER_STREAM_FRAME := 4
const MAX_EVENTS_PER_STREAM_FRAME := 32
```

Each stream state owns an event queue. `_poll_stream()` first dispatches queued events up to the event budget, reads at most four chunks, pushes parsed events, then spends the remaining event budget. It must defer incomplete-response detection until the queue is empty. Terminal event handling remains ordered and calls `_finish()` exactly once.

- [x] **Step 4: Run the Agent suite and commit**

Expect all Agent checks to pass and commit the bounded-stream change.

### Task 3: Add per-Agent automatic interval controls

**Files:**
- Modify: `tests/test_agent_runtime.gd`
- Modify: `tests/test_debug_panel.gd`
- Modify: `tests/test_visible_agent_npc_dialogue.gd`
- Modify: `scripts/ai_agent/agent_scheduler.gd`
- Modify: `scripts/ai_agent/agent_runtime.gd`
- Modify: `scripts/ui/debug_panel.gd`
- Modify: `scenes/ui/debug_panel.tscn`
- Modify: `scripts/main.gd`

- [x] **Step 1: Write failing scheduler override tests**

Require:

```gdscript
func set_decision_interval_hours(agent_id: String, hours: int) -> bool
func get_decision_interval_hours(agent_id: String) -> int
```

Assert unknown IDs and values outside `0..168` reject, zero prevents `advance_to()` dispatch, a positive override changes the next automatic eligibility, and `trigger_dialogue()` still dispatches when the override is zero.

- [x] **Step 2: Run the Agent suite and confirm RED**

Expected: scheduler interval methods are missing.

- [x] **Step 3: Implement scheduler and runtime APIs**

Store overrides in `_decision_interval_overrides`. Automatic scheduling uses the override when present and skips zero. Runtime exposes:

```gdscript
func get_agent_debug_settings() -> Array[Dictionary]
func apply_agent_debug_intervals(intervals: Dictionary) -> bool
```

Each settings record contains `agent_id`, `display_name`, and `decision_interval_hours`.

- [x] **Step 4: Write failing debug-panel UI tests**

Add an Agent tab with `IntervalRows`, `AgentStatus`, and `ApplyAgentSettingsButton`. Configure it with the three runtime records, edit one SpinBox to zero, press Apply, and assert one `agent_settings_apply_requested` signal containing all three integer values.

- [x] **Step 5: Implement the Agent tab and Main wiring**

Add:

```gdscript
signal agent_settings_apply_requested(intervals: Dictionary)
func configure_agent_settings(settings: Array[Dictionary]) -> bool
func show_agent_settings_result(ok: bool) -> void
```

Main refreshes settings whenever the panel opens and routes the dedicated signal to `AgentRuntime.apply_agent_debug_intervals()`. It displays success/failure in the Agent tab without applying or saving player-state drafts.

- [x] **Step 6: Run Agent and debug-panel suites, then commit**

```powershell
godot_console --headless --path . --script res://tests/run_agent_system_tests.gd
godot_console --headless --path . --script res://tests/run_debug_panel_tests.gd
```

Expected: both suites pass.

### Task 4: Send dialogue text to the Provider and remember exchanges

**Files:**
- Modify: `services/agent-service/tests/provider.test.ts`
- Modify: `services/agent-service/tests/app.test.ts`
- Modify: `services/agent-service/src/provider.ts`
- Modify: `services/agent-service/src/app.ts`

- [x] **Step 1: Write a failing Provider prompt test**

Send a dialogue-triggered request with `dialogue_input: "今天胡萝卜价格怎么样？"`, capture the OpenAI-compatible request body, and assert its user message parses to an object containing the exact dialogue input. Assert the system prompt asks for an in-character conversational response.

- [x] **Step 2: Write a failing dialogue-memory route test**

Return an intent with `speech: "今天价格稳定。"`, complete the streamed request, then assert `memory.recent(session, agent, 8)` contains exactly one `dialogue` event whose payload has both `player_text` and `agent_speech`. Replay the cached request and assert no duplicate event is added.

- [x] **Step 3: Run Node tests and confirm RED**

```powershell
npm test
```

Run from `services/agent-service`. Expected: Provider input omits dialogue text and no dialogue memory event exists.

- [x] **Step 4: Implement Provider input and idempotent dialogue memory**

For dialogue triggers, include `{context, dialogue_input: request.dialogue_input}` in the JSON user message and add a dialogue-specific system instruction. In `storeDecision()`, append:

```ts
{
  event_id: `dialogue:${intent.decision_id}`,
  kind: "dialogue",
  game_minute: request.game_minute,
  payload: {player_text: request.dialogue_input, agent_speech: intent.speech ?? intent.decision_summary},
}
```

only when the trigger is dialogue and input is non-empty. `appendEvent()` supplies idempotency.

- [x] **Step 5: Run Node tests and commit**

Expect the complete Agent Service suite to pass.

### Task 5: Build discoverable fixed-size multi-turn NPC dialogue

**Files:**
- Modify: `tests/test_npc_logic.gd`
- Modify: `tests/test_agent_main_integration.gd`
- Modify: `tests/test_visible_agent_npc_dialogue.gd`
- Modify: `tests/test_agent_debug_window.gd`
- Modify: `scenes/actors/npc.tscn`
- Modify: `scripts/actors/npc.gd`
- Modify: `scenes/ui/dialogue_ui.tscn`
- Modify: `scripts/ui/dialogue_ui.gd`
- Modify: `scripts/ai_agent/agent_runtime.gd`
- Modify: `scripts/main.gd`

- [x] **Step 1: Write failing NPC nameplate tests**

Require a billboarded `Nameplate` Label3D. Configure the NPC with `configure_agent(player, "farmer_ahe", "阿禾")` and assert the name remains visible both inside and outside dialogue range while the dialogue icon remains range-gated.

- [x] **Step 2: Write failing dialogue composer tests**

Require `open_agent_dialogue(agent_id, display_name)`, a fixed-size panel, scrollable History, multiline MessageInput, SendButton, and CloseButton. Assert opening does not emit a request; empty input rejects; Enter/send emits `agent_message_submitted` with exact text; input disables while pending; streaming builds one Agent history entry; completion re-enables input; close/reopen preserves history; and close during a request emits cancellation.

- [x] **Step 3: Write failing Main lifecycle tests**

Change the runtime double to retain submitted text. Assert NPC click opens the composer without calling `trigger_dialogue`, submitting calls it once with exact text, start/delta/complete update the same request, synchronous failure leaves the window open, and close unlocks only the matching NPC.

- [x] **Step 4: Run the Agent suite and confirm RED**

Expected: nameplate, composer APIs, input controls, and submit routing are absent.

- [x] **Step 5: Implement NPC nameplates and dialogue UI state**

Pass profile display names from Main through `configure_agent()`. Add per-Agent history records with `role` and `text`, one pending request ID, stale-request guards, automatic bottom scrolling, and focused multiline input. Keep history on close but clear current view/request state.

- [x] **Step 6: Rewire Main and make dialogue speech validation-independent**

NPC click calls `open_agent_dialogue()` only. Connect `agent_message_submitted` to a handler that calls `AgentRuntime.trigger_dialogue(agent_id, text)`. Stream callbacks update the open conversation. Runtime emits final dialogue speech before action validation, using `speech`, then `decision_summary`, then `……`, so invalid world actions cannot swallow valid conversation text.

- [x] **Step 7: Run Agent and gameplay integration suites, then commit**

```powershell
godot_console --headless --path . --script res://tests/run_agent_system_tests.gd
godot_console --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
```

Expected: both suites pass without script errors or leaked dialogue nodes.

### Task 6: Final verification and documentation

**Files:**
- Modify: `docs/validation/role-agent-framework-validation.md`
- Modify: `docs/superpowers/plans/2026-08-28-agent-runtime-responsiveness-and-dialogue.md`

- [x] **Step 1: Document the verified behavior and root cause**

Record the trace/render/SSE budgets, interval semantics, dialogue flow, Provider input propagation, and exact test results.

- [x] **Step 2: Run all relevant tests from clean processes**

```powershell
godot_console --headless --path . --script res://tests/run_agent_system_tests.gd
godot_console --headless --path . --script res://tests/run_debug_panel_tests.gd
godot_console --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
Push-Location services/agent-service; npm test; Pop-Location
git diff --check
```

Expected: every suite exits zero and the diff check reports no whitespace errors.

- [x] **Step 3: Review the final diff and commit**

Confirm only the planned Agent runtime, UI, service, tests, and documentation changed. Commit any final validation documentation, then verify the worktree is clean.
