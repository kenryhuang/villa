# Agent Session Trace Aggregation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist exactly one aggregated Agent session trace record per terminal request while retaining live per-delta debug updates in memory.

**Architecture:** `AgentSessionTrace` remains the sole stream accumulator and adds an idempotent terminal serializer plus a public local-failure finalizer. `AgentRuntime` forwards scheduler failures to that finalizer, and `AgentScheduler` explicitly reports dialogue-replacement cancellation before it suppresses the stale gateway callback.

**Tech Stack:** Godot 4, GDScript, NDJSON, existing headless Agent system test runner.

---

### Task 1: Lock the terminal persistence contract with tests

**Files:**
- Modify: `tests/test_agent_streaming.gd`
- Modify: `tests/test_agent_runtime.gd`

- [x] **Step 1: Replace the per-event disk assertion with completion aggregation assertions**

Feed `stream.started`, `provider.input`, reasoning/content/tool deltas, `provider.output`, and `decision.final`; assert that the file remains empty until `stream.completed`. Parse the single resulting line and assert `schema_version`, identifiers, status, input, accumulated response text, tool fragments, provider output, decision, and empty error.

- [x] **Step 2: Add error, idempotency, and unfinished-request cases**

Create separate request IDs for an SSE error, a locally finalized cancellation, and an unfinished stream. Assert one aggregated error line per terminal request, no duplicate line after repeated finalization, and no line after closing an unfinished stream.

- [x] **Step 3: Require dialogue replacement to report the cancelled request**

Change the scheduler assertion from zero failures to one failure containing the replaced request ID and `dialogue_replaced`, while retaining the assertions that a new dialogue request starts and stale callbacks are ignored.

- [x] **Step 4: Run the Agent suite and confirm the tests fail for the intended reasons**

Run:

```powershell
godot_console --headless --path . --script res://tests/run_agent_system_tests.gd
```

Expected: failures show per-event disk writes, missing `finish_error`, and missing explicit replacement cancellation reporting.

### Task 2: Implement one-record terminal trace persistence

**Files:**
- Modify: `scripts/ai_agent/agent_session_trace.gd`

- [x] **Step 1: Add terminal state and disk schema helpers**

Add schema version 2, an idempotency dictionary keyed by `request_id`, a shared request-record constructor, and a serializer that maps the live fields to `input` plus a normalized `response` object.

- [x] **Step 2: Stop writing non-terminal events**

Keep all existing in-memory aggregation and `trace_updated` emissions, but call the serializer only for `stream.completed` and `stream.error`. Preserve stream-error payload under `response.error` rather than overwriting provider output.

- [x] **Step 3: Add local error finalization**

Implement:

```gdscript
func finish_error(
	agent_id: String,
	request_id: String,
	error: String,
	trigger: String = "",
	timestamp_msec: int = -1
) -> bool
```

It must complete an existing record or create a minimal one, emit one live update, and persist at most one disk line. It must not make `close()` persist unfinished requests.

- [x] **Step 4: Run the focused Agent suite**

Run the headless Agent suite and expect the trace persistence tests to pass except for the still-unimplemented runtime/scheduler cancellation path.

### Task 3: Wire transport failures and replacement cancellation

**Files:**
- Modify: `scripts/ai_agent/agent_runtime.gd`
- Modify: `scripts/ai_agent/agent_scheduler.gd`

- [x] **Step 1: Finalize failed requests in `AgentRuntime`**

Capture the request trigger, call `session_trace.finish_error(agent_id, request_id, error, trigger)`, preserve dialogue failure signaling, then remove the trigger mapping. The call is safe after an SSE error because persistence is idempotent.

- [x] **Step 2: Report dialogue replacement explicitly**

Before dispatching the replacement, capture the old request ID, remove it from scheduler state, cancel it at the gateway, and invoke `_handle_failure(agent_id, old_request_id, "dialogue_replaced")`. Continue ignoring the later stale gateway callback.

- [x] **Step 3: Run the complete Agent system suite**

Run:

```powershell
godot_console --headless --path . --script res://tests/run_agent_system_tests.gd
```

Expected: `PASS` with no Agent system failures.

### Task 4: Verify and document the result

**Files:**
- Modify: `docs/superpowers/specs/2026-08-27-agent-session-trace-aggregation-design.md` only if implementation details differ from the approved design

- [x] **Step 1: Run formatting and diff checks**

Run:

```powershell
git diff --check
git status --short
```

Expected: no whitespace errors and only the intended trace, runtime, scheduler, test, spec, and plan files changed.

- [x] **Step 2: Re-run the Agent suite from a clean process**

Run the headless Agent system test command once more and record its passing assertion count.

- [x] **Step 3: Commit the implementation**

Stage only the intended files and create a focused commit describing aggregated Agent session trace persistence.
