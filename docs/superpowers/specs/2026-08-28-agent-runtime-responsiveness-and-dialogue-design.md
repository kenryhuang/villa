# Agent Runtime Responsiveness and Dialogue Design

**Date:** 2026-08-28

## Goal

Remove Agent-related frame spikes, expose per-Agent automatic decision intervals in the runtime debug panel, and make the three visible Agent NPCs support discoverable, multi-turn player dialogue.

## Confirmed user experience

- 阿禾、老李、学者林 always show their configured Agent display names above their heads.
- A dialogue icon appears only while the player is within three horizontal metres and the NPC is available.
- Clicking the icon opens a fixed-size dialogue window without sending an empty model request.
- The window contains scrollable per-NPC history, a multiline input, Send, and Close.
- Enter sends; Shift+Enter inserts a newline.
- Agent replies stream into the history. Input is disabled only while one reply is pending.
- Closing cancels an in-flight reply, preserves in-memory history, and unlocks the NPC. Clicking the icon again reopens the same history.
- Automatic decision intervals are independently configurable for all three Agents in game hours. Zero disables automatic decisions for that Agent without disabling player dialogue.

## Root-cause findings

### Frame spikes are not primarily Agent decision CPU

The TypeScript service and remote model run outside the Godot process. Waiting for the provider does not consume a Godot frame. The scheduler's game-time callback only scans three Agents and is not a meaningful CPU load.

The Godot client currently does three expensive things when streamed data arrives:

1. `AgentSessionTrace` repeatedly concatenates the growing reasoning and content strings for every delta, producing increasingly expensive copies on long responses.
2. `AgentDebugWindow` rebuilds its controls and serializes the full trace for every delta even while the F8 window is hidden.
3. `AgentStreamClient` drains all currently available HTTP chunks and dispatches all parsed SSE events in one `_process()` call, so a burst can monopolize one game frame.

Disabling `store_agent_session` only removes disk writes. It does not disable these in-memory and UI paths, which explains why the symptom remains.

### Dialogue input is not reaching the model

Godot Protocol v2 includes `dialogue_input` in the decision request, but the TypeScript Provider constructs its OpenAI-compatible user message from `AgentContext` alone. `dialogue_input` is therefore omitted from the prompt. The current UI also has no input control and only opens after receiving `stream.started`, so clicking can appear to do nothing while the service is slow or unavailable.

## Performance architecture

### Trace accumulation

`AgentSessionTrace` will store reasoning and content as arrays of delta fragments internally. It will materialize joined strings only when:

- `get_requests()` or `get_request()` supplies data to the visible debug UI;
- a request reaches a terminal state and creates its one aggregated disk record.

The public in-memory record returned to callers keeps the existing `reasoning` and `content` string fields. Internal fragment fields are not exposed or persisted.

### Hidden and coalesced debug rendering

`AgentDebugWindow` will not rebuild controls while hidden. While visible, multiple `trace_updated` signals in the same frame set one pending-refresh flag and result in at most one deferred refresh. Opening the window always performs a fresh render, so no trace information is lost.

### Bounded SSE work per frame

`AgentStreamClient` will keep parsed-but-undispatched events in each stream state and use explicit per-frame budgets:

- at most four response-body chunks read per stream per frame;
- at most 32 SSE events dispatched per stream per frame.

Remaining events stay queued for the next frame. A disconnected response is not classified as incomplete while queued events remain. Terminal events still finish and remove the stream immediately when their turn in the queue is processed. No event is dropped or reordered.

## Automatic interval controls

The runtime debug panel gains an `Agent` tab with one integer SpinBox for each managed Agent, labelled using the profile display name and Agent ID. Values range from 0 to 168 game hours:

- `0`: disable automatic schedule and catch-up dispatch for that Agent;
- `1–168`: minimum game hours between automatic decisions.

The tab has a dedicated `应用 Agent 设置` button and status text. Applying calls a focused Main/AgentRuntime API rather than routing Agent configuration through `DebugStateEditor`, which remains responsible only for player/economy state.

`AgentScheduler` owns a runtime-only override dictionary. Its effective interval is the override when present, otherwise the role's configured minimum interval. Changes affect subsequent game-time ticks, do not cancel an in-flight request, and do not affect `trigger_dialogue()`. Overrides are not included in the formal save and reset when the game restarts.

## Visible NPC presentation

The NPC scene gains an always-billboarded `Label3D` nameplate above the character body. `Main` obtains `display_name` through `AgentRuntime`/`AgentRegistry` and passes it to `configure_agent()`. The dialogue icon remains above the nameplate and retains its existing range, health, busy-state, collision-layer, and click-routing rules.

The nameplate remains visible whenever the bound NPC is alive. Dialogue availability does not control the nameplate.

## Dialogue state machine

### Opening

`Npc.start_dialogue()` continues to validate range and mark the NPC busy, but its signal now means “open this Agent conversation.” `Main._on_dialogue_started()` opens the dialogue UI immediately and does not call the gateway.

The dialogue UI keeps an in-memory history dictionary keyed by Agent ID. Opening selects that history, renders it, enables input, and focuses the editor.

### Sending

The UI rejects empty or whitespace-only messages and messages over the existing 1000-character protocol limit. A valid send:

1. appends a player history entry;
2. appends one pending Agent entry;
3. disables input and Send;
4. emits `agent_message_submitted(agent_id, text)`.

Main calls `AgentRuntime.trigger_dialogue(agent_id, text)`. A synchronous start failure converts the pending entry to a visible service-error message and re-enables input without closing the window.

### Streaming and completion

`stream.started` binds the request ID to the pending Agent entry. Content deltas replace the thinking placeholder and append to that entry. Completion replaces it with the final `speech` and re-enables input.

Dialogue speech is delivered even when a returned tool action is rejected: conversational output and world-action validation are separate concerns. If a dialogue decision contains no `speech`, `decision_summary` is used as the visible fallback, followed by `……` only when both are empty.

A stream or transport failure turns the pending entry into an error message and re-enables input. The conversation stays open. Closing while a request is active emits the existing request-scoped cancellation before unlocking the NPC.

### Closing and reopening

Close hides the window and clears only active-view/request state. It does not delete the per-Agent history. The NPC becomes available again; if the player remains in range, its icon reappears. Reopening renders the prior history and scrolls to the bottom.

## Provider and memory behavior

For a dialogue-triggered decision, `OpenAICompatibleProvider` includes the current `dialogue_input` alongside the Agent context in the Provider user message and adds a dialogue-specific instruction to answer in character. The existing zero-to-three tool contract remains available, so a conversational reply may also produce valid world actions.

After a successful dialogue decision, the Agent Service appends one `dialogue` memory event containing the player text and Agent speech. Subsequent decisions already include recent events in `AgentContext`, so later turns receive recent conversation history without changing Protocol v2 or sending the full UI transcript on every request. Idempotency uses the decision ID and prevents duplicate memory events.

## Failure behavior

- A disabled or unavailable service leaves the dialogue window open with a readable error entry.
- Empty input never starts a request.
- Only one request per Agent can be pending; the UI prevents duplicate sends.
- Player dialogue may replace an in-flight autonomous request using the existing scheduler priority rule.
- Closing an in-flight dialogue cancels it; stale deltas and terminal callbacks cannot modify a reopened or newer request.
- Setting an automatic interval to zero does not cancel work already in flight.

## Testing

Godot coverage will verify:

- hidden F8 windows do not render per delta and visible updates coalesce;
- trace fragments materialize to the same public strings and terminal disk schema;
- SSE processing respects chunk/event budgets without loss, reordering, or premature incomplete errors;
- per-Agent interval defaults, overrides, zero-disable behavior, and dialogue independence;
- debug panel Agent controls emit validated settings;
- all three NPCs show configured names and range-gated dialogue icons;
- click opens the fixed dialogue UI without calling the gateway;
- send passes the exact player text, streams a reply, preserves history, and supports close/reopen;
- failures re-enable input and stale callbacks are ignored.

TypeScript coverage will verify:

- Provider input contains `dialogue_input` for dialogue requests;
- non-dialogue prompts do not invent a dialogue input;
- completed dialogue decisions append one idempotent dialogue memory event containing both sides of the exchange.

## Out of scope

- persisting debug interval overrides or UI chat history into the formal game save;
- moving HTTP parsing to a worker thread;
- changing Protocol v2 fields or the zero-to-three action-array contract;
- new NPC models, voice, portraits, or relationship mechanics;
- changing the three-metre interaction range.
