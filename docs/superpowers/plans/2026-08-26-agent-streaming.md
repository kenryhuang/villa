# Agent Streaming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an end-to-end SSE path that streams Provider input, reasoning, dialogue content, and final tool output into Godot without allowing partial output to mutate the world.

**Architecture:** The TypeScript service converts OpenAI-compatible SSE chunks into a stable project-owned SSE envelope and retains the synchronous endpoint as a collector over the same Provider logic. Godot uses a dedicated incremental `HTTPClient`, stores bounded trace records in memory or optional NDJSON, streams dialogue content into the existing dialogue panel, and submits only the final validated ActionIntent to the existing executor.

**Tech Stack:** Node.js 24 built-in fetch/streams/http, TypeScript 5, OpenAI-compatible Chat Completions SSE, Godot 4.7 `HTTPClient`, GDScript SceneTree tests.

---

## File map

TypeScript service:

- `services/agent-service/src/provider_stream.ts`: byte-safe Provider SSE decoder, delta assembler, and stream event types.
- `services/agent-service/src/provider.ts`: build one Provider request and expose streaming and collected decision APIs.
- `services/agent-service/src/app.ts`: `/decide/stream`, project SSE envelopes, heartbeat, disconnect abort, final commit.
- `services/agent-service/tests/provider_stream.test.ts`: fragmented UTF-8/SSE and tool-call assembly tests.
- `services/agent-service/tests/provider.test.ts`: real adapter request and collected-result compatibility tests.
- `services/agent-service/tests/app.test.ts`: local SSE route ordering, errors, cancellation, and synchronous compatibility.

Godot transport and trace:

- `scripts/ai_agent/agent_sse_parser.gd`: pure incremental project-SSE parser with sequence validation.
- `scripts/ai_agent/agent_stream_client.gd`: one `HTTPClient` stream per Agent, per-frame polling, timeout, and cancellation.
- `scripts/ai_agent/agent_session_trace.gd`: 100-request in-memory trace and optional 20-file NDJSON retention.
- `scripts/ai_agent/agent_client_config.gd`: optional `store_agent_session` setting, default false.
- `scripts/ai_agent/agent_gateway.gd`: delegate decisions to stream client while retaining outcome/checkpoint HTTP helpers.
- `tests/test_agent_streaming.gd`: parser, trace, cancellation, and fake-client runtime tests.
- `tests/test_agent_client_config.gd`: new configuration compatibility tests.

Runtime and UI:

- `scripts/ai_agent/agent_scheduler.gd`: forward stream events and replace an older request for the same Agent.
- `scripts/ai_agent/agent_runtime.gd`: route trace/reasoning/content/final events and enforce epoch/final-only execution.
- `scripts/ui/dialogue_ui.gd`: begin, append, finish, fail, and cancel one Agent dialogue stream.
- `scripts/ui/agent_debug_window.gd`: request list plus Input/Reasoning/Output live views.
- `scenes/ui/agent_debug_window.tscn`: independent debug-only window.
- `scripts/ui/debug_panel.gd` and `scenes/ui/debug_panel.tscn`: emit an Agent-debug-window request from a new button.
- `scripts/main.gd`: create/wire the window, F8 toggle, dialogue cancellation, and incremental dialogue signals.
- `tests/test_agent_debug_window.gd`: trace rendering, F8-facing toggle API, and dialogue streaming UI tests.
- `tests/run_agent_system_tests.gd`: include new Agent streaming/UI suites.

Configuration and evidence:

- `config/agent-client.example.json`: document `store_agent_session: false`.
- `config/agent-client.local.json`: add the same local default without tracking it.
- `tests/agent_service_integration.gd`: consume the new SSE route and verify real reasoning/content/final ordering.
- `services/agent-service/README.md`: streaming endpoint, config, debug trace, and manual PowerShell usage.
- `docs/validation/role-agent-framework-validation.md`: fresh automated and real-Provider evidence.

### Task 0: Preserve the verified Provider compatibility baseline

**Files:**
- Modify: `services/agent-service/src/provider.ts`
- Modify: `services/agent-service/tests/provider.test.ts`
- Modify: `tests/agent_service_integration.gd`

- [ ] **Step 1: Re-run the focused regression evidence**

Run:

```powershell
npm --prefix services/agent-service test -- tests/provider.test.ts
godot --headless --path . --script res://tests/agent_service_integration.gd
```

Expected: Provider tests pass with `tool_choice == "auto"`; the connected script passes and does not attempt synchronous `free()` from its completion signal.

- [ ] **Step 2: Commit only the existing compatibility changes**

```powershell
git add services/agent-service/src/provider.ts services/agent-service/tests/provider.test.ts tests/agent_service_integration.gd
git commit -m "fix: support thinking Agent providers"
```

### Task 1: Decode and assemble OpenAI-compatible Provider streams

**Files:**
- Create: `services/agent-service/src/provider_stream.ts`
- Create: `services/agent-service/tests/provider_stream.test.ts`
- Modify: `services/agent-service/src/provider.ts`
- Modify: `services/agent-service/tests/provider.test.ts`

- [ ] **Step 1: Write failing fragmented-stream tests**

Cover a Chinese UTF-8 character split between byte chunks, multiple SSE records in one chunk, comment heartbeat, `[DONE]`, interleaved `reasoning_content`/`content`, and tool arguments split across three deltas. The central assertion is:

```ts
assert.deepEqual(result.rawMessage, {
  content: "我来整理土地。",
  reasoning_content: "地块未开垦。",
  tool_calls: [{id: "call-1", type: "function", function: {name: "till", arguments: '{"plot_index":0}'}}],
});
assert.equal(result.intent.tool_name, "till");
assert.deepEqual(result.intent.arguments, {plot_index: 0});
```

- [ ] **Step 2: Run RED**

Run: `node --experimental-strip-types --test services/agent-service/tests/provider_stream.test.ts`  
Expected: FAIL because `provider_stream.ts` does not exist.

- [ ] **Step 3: Implement the byte-safe decoder and assembler**

Export these focused interfaces:

```ts
export type ProviderDelta =
  | {type: "reasoning"; delta: string}
  | {type: "content"; delta: string}
  | {type: "tool_call"; index: number; id?: string; name?: string; arguments?: string};

export async function* decodeProviderSse(body: ReadableStream<Uint8Array>): AsyncGenerator<Record<string, unknown>>;
export class AgentStreamAssembler {
  accept(chunk: Record<string, unknown>): readonly ProviderDelta[];
  finish(request: DecisionRequest, allowedTools: readonly string[]): ProviderStreamResult;
}
```

Use `TextDecoder.decode(bytes, {stream: true})`, retain incomplete lines, ignore comment lines, reject malformed JSON, and require exactly one final tool call.

- [ ] **Step 4: Make Provider streaming the source of truth**

Add:

```ts
async streamDecision(
  request: DecisionRequest,
  context: AgentContext,
  emit: (event: ProviderTraceEvent) => void,
  externalSignal?: AbortSignal,
): Promise<ActionIntent>
```

Build the exact outgoing body once with `stream: true` and `tool_choice: "auto"`. Emit `input`, each delta, and reconstructed `output`. Keep `decide()` by calling `streamDecision()` with a no-op emitter.

- [ ] **Step 5: Run GREEN and the complete Node suite**

Run:

```powershell
npm --prefix services/agent-service test
```

Expected: all tests pass; captured request includes `stream: true`, the API key appears only in Authorization, and synchronous callers still receive one ActionIntent.

- [ ] **Step 6: Commit**

```powershell
git add services/agent-service/src/provider_stream.ts services/agent-service/src/provider.ts services/agent-service/tests/provider_stream.test.ts services/agent-service/tests/provider.test.ts
git commit -m "feat: stream OpenAI-compatible Agent decisions"
```

### Task 2: Expose the project-owned SSE decision route

**Files:**
- Modify: `services/agent-service/src/app.ts`
- Modify: `services/agent-service/tests/app.test.ts`

- [ ] **Step 1: Write failing route tests**

Use a programmable Provider port that emits input, reasoning, content, tool deltas, output, and a final intent. Assert event names and envelope sequences are exactly:

```ts
assert.deepEqual(events.map((event) => event.name), [
  "stream.started", "provider.input", "reasoning.delta", "content.delta",
  "tool_call.delta", "provider.output", "decision.final", "stream.completed",
]);
assert.deepEqual(events.map((event) => event.data.sequence), [1, 2, 3, 4, 5, 6, 7, 8]);
```

Also assert cached requests replay only final/completed, a mid-stream error emits `stream.error` without memory mutation, and client disconnect aborts the Provider signal.

- [ ] **Step 2: Run RED**

Run: `node --experimental-strip-types --test services/agent-service/tests/app.test.ts`  
Expected: FAIL because `/decide/stream` returns 404.

- [ ] **Step 3: Implement SSE envelopes and lifecycle**

Add a `ProviderPort.streamDecision` method, `writeSseEvent()`, monotonic sequence closure, immediate headers, five-second heartbeat comments, and an AbortController tied to response close. On successful final result, store idempotency/memory before emitting `decision.final`. On error after headers, emit one `stream.error` and close.

- [ ] **Step 4: Run GREEN and Node suite**

Run: `npm --prefix services/agent-service test`  
Expected: all service tests pass, including legacy synchronous routes.

- [ ] **Step 5: Commit**

```powershell
git add services/agent-service/src/app.ts services/agent-service/tests/app.test.ts
git commit -m "feat: expose Agent decision SSE endpoint"
```

### Task 3: Add Godot stream parsing, client configuration, and trace storage

**Files:**
- Create: `scripts/ai_agent/agent_sse_parser.gd`
- Create: `scripts/ai_agent/agent_stream_client.gd`
- Create: `scripts/ai_agent/agent_session_trace.gd`
- Create: `tests/test_agent_streaming.gd`
- Modify: `scripts/ai_agent/agent_client_config.gd`
- Modify: `scripts/ai_agent/agent_gateway.gd`
- Modify: `tests/test_agent_client_config.gd`
- Modify: `tests/run_agent_system_tests.gd`
- Modify: `config/agent-client.example.json`
- Modify ignored local file: `config/agent-client.local.json`

- [ ] **Step 1: Write failing parser, config, and trace tests**

Feed SSE bytes at every possible boundary around a Chinese character and `\n\n`. Assert comments are ignored, events wait for a complete delimiter, sequence must increase, duplicate final fails, and `stream.completed` seals the parser. Extend config fixtures so missing `store_agent_session` defaults false and explicit non-bool rejects.

For trace, assert:

```gdscript
trace.begin_request(started_event)
trace.accept_event(input_event)
trace.accept_event(reasoning_event)
trace.accept_event(output_event)
assertions.equal(trace.get_requests()[0].reasoning, "地块未开垦。", "reasoning accumulates verbatim")
```

Use a temporary `user://agent-session-test-*` directory to verify NDJSON append and 20-file retention.

- [ ] **Step 2: Run RED**

Run: `godot --headless --path . --script res://tests/run_agent_system_tests.gd`  
Expected: FAIL because the three streaming scripts and new configuration field do not exist.

- [ ] **Step 3: Implement the pure SSE parser**

`AgentSseParser.feed(bytes: PackedByteArray) -> Dictionary` returns `{ok, events, error}`. Keep a byte buffer until `\n\n` or `\r\n\r\n`, decode only complete records, parse `event:` and `data:`, validate the common envelope, and enforce sequence/final/completed state.

- [ ] **Step 4: Implement bounded trace and configuration**

Allow `store_agent_session` as an optional bool defaulting false. `AgentSessionTrace.configure(store, sessionId, directory = "user://agent_sessions")` keeps 100 requests, appends every non-heartbeat event as one JSON line when enabled, flushes immediately, and deletes all but the newest 20 files by modification time.

- [ ] **Step 5: Implement the incremental HTTP client and Gateway delegation**

`AgentStreamClient.request_decision(agentId, body, eventCallback, finalCallback)` creates one HTTPClient state per Agent, POSTs `/decide/stream`, polls in `_process`, feeds response chunks to the parser, and calls final only for `decision.final` or terminal error. `cancel_agent`, `cancel_all`, and epoch bump close sockets and return `cancelled` exactly once. `AgentGateway.request_decision` delegates to this client while its outcome/checkpoint methods remain unchanged.

- [ ] **Step 6: Run GREEN**

Run: `godot --headless --path . --script res://tests/run_agent_system_tests.gd`  
Expected: all Agent checks pass with parser/config/trace coverage.

- [ ] **Step 7: Commit tracked files**

```powershell
git add config/agent-client.example.json scripts/ai_agent tests/test_agent_streaming.gd tests/test_agent_client_config.gd tests/run_agent_system_tests.gd
git commit -m "feat: consume and trace Agent SSE streams"
```

Do not add `config/agent-client.local.json`; verify it remains ignored.

### Task 4: Route streaming events through scheduling and dialogue

**Files:**
- Modify: `scripts/ai_agent/agent_scheduler.gd`
- Modify: `scripts/ai_agent/agent_runtime.gd`
- Modify: `scripts/ui/dialogue_ui.gd`
- Modify: `tests/test_agent_runtime.gd`
- Modify: `tests/test_agent_main_integration.gd`

- [ ] **Step 1: Write failing runtime/dialogue tests**

Extend the fake Gateway to capture event callbacks. Assert input/reasoning/output go to trace, dialogue content emits incrementally, autonomous content does not open dialogue, close cancels dialogue, same-Agent new request cancels the old one, stale epoch final is ignored, and only one final response reaches the executor.

- [ ] **Step 2: Run RED**

Run: `godot --headless --path . --script res://tests/run_agent_system_tests.gd`  
Expected: FAIL because scheduler/runtime do not expose stream events and DialogueUI lacks incremental methods.

- [ ] **Step 3: Add scheduler and runtime stream routing**

Configure scheduler with a stream-event callback. Track each in-flight request ID and trigger. Dialogue replaces an in-flight request for the same Agent; lower-priority schedule/event requests retain current queuing behavior. Runtime sends every event to `AgentSessionTrace`, emits dedicated `dialogue_stream_started`, `dialogue_stream_delta`, `dialogue_stream_failed`, and final `dialogue_ready` signals, and calls `_handle_response` only from final success.

- [ ] **Step 4: Add DialogueUI incremental lifecycle**

Implement:

```gdscript
begin_agent_dialogue(villager_id: String, request_id: String) -> void
append_agent_dialogue(request_id: String, delta: String) -> void
finish_agent_dialogue(request_id: String, speech: String) -> void
fail_agent_dialogue(request_id: String, fallback: String) -> void
signal agent_dialogue_cancelled(villager_id: String, request_id: String)
```

Opening displays `正在思考……`; first delta replaces it; close emits cancellation; failure replaces partial content with the stable fallback.

- [ ] **Step 5: Run GREEN and commit**

Run: `godot --headless --path . --script res://tests/run_agent_system_tests.gd`  
Expected: all Agent checks pass and world execution remains final-only.

```powershell
git add scripts/ai_agent/agent_scheduler.gd scripts/ai_agent/agent_runtime.gd scripts/ui/dialogue_ui.gd tests/test_agent_runtime.gd tests/test_agent_main_integration.gd
git commit -m "feat: stream Agent dialogue into Godot"
```

### Task 5: Build and wire the Agent debug window

**Files:**
- Create: `scripts/ui/agent_debug_window.gd`
- Create: `scenes/ui/agent_debug_window.tscn`
- Create: `tests/test_agent_debug_window.gd`
- Modify: `scripts/ui/debug_panel.gd`
- Modify: `scenes/ui/debug_panel.tscn`
- Modify: `scripts/main.gd`
- Modify: `tests/run_agent_system_tests.gd`
- Modify: `tests/test_agent_main_integration.gd`

- [ ] **Step 1: Write failing UI and main wiring tests**

Instantiate the scene with a real trace, append stream events, and assert the request list and Input/Reasoning/Output views update without recreating the window. Assert the debug-panel button emits `agent_debug_requested`, `toggle()` works, and Main connects trace, F8-facing toggle, incremental dialogue, and cancellation.

- [ ] **Step 2: Run RED**

Run: `godot --headless --path . --script res://tests/run_agent_system_tests.gd`  
Expected: FAIL because the debug scene and signal do not exist.

- [ ] **Step 3: Implement the independent debug window**

Create a debug-only CanvasLayer with a request `ItemList`, status metadata, and three read-only code-style text views. Configure it with `AgentSessionTrace`, update the selected request incrementally, preserve scroll-at-bottom behavior, and expose `open`, `close`, `toggle`, and `clear`.

- [ ] **Step 4: Wire both entry points and dialogue signals**

Add “Agent 调试” to RuntimeDebugPanel and connect its signal in Main. Instantiate the independent window only in debug builds, connect runtime trace and dialogue stream signals, handle `KEY_F8` in `_unhandled_input`, and forward DialogueUI cancellation to `AgentRuntime.cancel_dialogue`.

- [ ] **Step 5: Run GREEN, main startup, and commit**

Run:

```powershell
godot --headless --path . --script res://tests/run_agent_system_tests.gd
godot --headless --path . --quit-after 2
```

Expected: all Agent/UI checks pass; main initializes without script errors.

```powershell
git add scripts/ui/agent_debug_window.gd scenes/ui/agent_debug_window.tscn scripts/ui/debug_panel.gd scenes/ui/debug_panel.tscn scripts/main.gd tests/test_agent_debug_window.gd tests/test_agent_main_integration.gd tests/run_agent_system_tests.gd
git commit -m "feat: add Agent streaming debug window"
```

### Task 6: Connected streaming acceptance and documentation

**Files:**
- Modify: `tests/agent_service_integration.gd`
- Modify: `services/agent-service/README.md`
- Modify: `docs/validation/role-agent-framework-validation.md`

- [ ] **Step 1: Convert connected acceptance to the stream endpoint**

Use the same Godot stream parser/client as runtime. Require `stream.started`, `provider.input`, zero or more reasoning/content/tool deltas, exactly one `provider.output`, exactly one `decision.final`, and `stream.completed`. Validate and report the returned ActionIntent, then retain outcome and checkpoint checks.

- [ ] **Step 2: Run all offline verification**

```powershell
npm --prefix services/agent-service test
godot --headless --path . --script res://tests/run_agent_system_tests.gd
godot --headless --path . --quit-after 2
git diff --check
```

Expected: every command exits 0 with no test failures or script errors.

- [ ] **Step 3: Run real Provider streaming acceptance**

Start the configured local service and run:

```powershell
godot --headless --path . --script res://tests/agent_service_integration.gd
```

Expected: PASS after observing the complete project SSE event order. Reasoning may be empty for Providers that do not expose it; final intent, outcome, and checkpoint must succeed.

- [ ] **Step 4: Update operator documentation and evidence**

Document both endpoints, `store_agent_session`, `user://agent_sessions`, F8/debug-panel entry points, local PowerShell streaming example, test counts, and the real Provider result. Never include local configuration contents or credentials.

- [ ] **Step 5: Commit and inspect final branch state**

```powershell
git add tests/agent_service_integration.gd services/agent-service/README.md docs/validation/role-agent-framework-validation.md
git commit -m "test: validate Agent streaming workflow"
git status --short
```

Expected: tracked worktree is clean; ignored local JSON and generated Agent session traces are not staged.

## Completion gate

- `/decide` remains compatible and `/decide/stream` emits versioned SSE.
- Godot displays reasoning only in the independent debug window and dialogue content incrementally in DialogueUI.
- Partial, invalid, cancelled, timed-out, or stale streams never mutate world assets.
- `store_agent_session` defaults false; enabled NDJSON is credential-free and capped at 20 files.
- F8 and the existing debug panel both open the Agent debug window.
- Node, Godot Agent, main startup, and one real Provider streaming acceptance all pass.
