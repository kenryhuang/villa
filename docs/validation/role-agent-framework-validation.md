# Role-Based NPC Agent Framework Validation

Validated through 2026-08-28 with Godot 4.7.1 stable and Node.js 24.19 on branch `feature/painted-production-buildings`.

## Passing evidence

| Check | Result |
|---|---|
| `npm --prefix services/agent-service test` | Exit 0; 27/27 tests passed |
| `godot_console --headless --path . --script res://tests/run_agent_system_tests.gd` | Exit 0; 957/957 checks passed |
| `godot_console --headless --path . --script res://tests/run_debug_panel_tests.gd` | Exit 0; 253/253 checks passed |
| `godot_console --headless --path . --script res://tests/run_player_action_controller_tests.gd` | Exit 0; 226/226 checks passed |
| `godot_console --headless --path . --editor --quit` | Exit 0; new prompt SVG imported and all changed scripts compiled |
| `godot_console --headless --path . --quit-after 3` | Exit 0; main scene initialized without script errors |
| `godot_console --headless --path . --script res://tests/agent_service_integration.gd` | Exit 0; real Provider returned a valid protocol v2 decision with one action, then v2 outcome and checkpoint passed |

The passing suites cover role-isolated Soul/goals/tools, exact Provider JSON Schemas, protocol v2 rejection of v1 traffic, zero-to-three ordered tool calls, empty decisions, per-action idempotency, fail-stop and in-progress-stop batch execution, current-state domain validation without global revision rejection or model retry, fragmented UTF-8 Provider SSE, streaming dialogue routing, bounded debug traces, per-Agent runtime scheduling controls, fixed-size multi-turn conversations, world save round trips, session-isolated SQLite memory, Provider-backed long-term memory compaction, checkpoint safety, and asynchronous memory sidecar coordination.

## Runtime responsiveness and scheduling

Disabling `store_agent_session` removes file writes but does not remove Provider work, SSE parsing, debug tracing, or UI rendering. The observed stalls came from three main-thread amplification paths rather than autonomous Agent simulation itself:

- trace deltas repeatedly rebuilt ever-growing reasoning/content strings;
- the hidden F8 window still serialized and rendered the full trace after every delta;
- each `AgentStreamClient._process()` drained all currently available chunks and decoded events in one frame.

Trace sessions now retain fragments internally and materialize complete records only when read or persisted. The debug window skips rendering while hidden and coalesces visible updates to one deferred refresh. Stream clients process at most four network chunks and 32 decoded events per Agent per frame, preserving FIFO order across later frames.

The F8 Agent tab now exposes one runtime-only decision interval per managed Agent in game hours. Values are clamped to `0..168`; `0` disables that Agent's automatic scheduler trigger without disabling player-initiated dialogue. Applying the controls updates the scheduler immediately and does not modify configuration files or save data.

## Visible Agent NPC dialogue

The visible-NPC and multi-turn-dialogue validation proves:

- `Actors/Npcs/NpcNorthwest`, `NpcSouth`, and `NpcEast` bind by node name to `farmer_ahe`, `lao_li`, and `xuezhe_lin`; child ordering is not used.
- The real NPC scene enables its hand-painted billboard prompt at XZ distance `<= 3.0`, ignores Y-axis height, and disables prompt visibility, layer-64 collision, and ray picking together when out of range or busy.
- NPC body and prompt-area hits resolve through the existing `PlayerActionController` parent walk to the same `start_dialogue()` method; a rejected interaction is no longer reported as successful.
- Every managed NPC has an always-visible billboarded Agent display name. Its dialogue icon remains range-gated and clickable through the existing interaction routing.
- Clicking the icon opens a fixed `760 x 420` conversation window without starting a Provider request. The window has scrollable per-NPC history, multiline input, Enter-to-send, Shift+Enter newline, a send button, and a close button. Closing and reopening the same NPC preserves history for the current runtime.
- Submitting non-empty text starts exactly one Agent dialogue request with the exact player message and disables the composer while pending. Streaming deltas update one pending Agent history entry; completion or failure re-enables input so the player can continue the conversation.
- A managed NPC never falls back to `VillagerSystem` text. Request-start and stream failures keep the conversation available for retry, publish `Agent 服务不可用，请稍后再试。` through `HudMessageBus`, and retain the matching NPC lock until the player closes the window.
- Completed dialogue close does not cancel; in-flight close cancels with the exact Agent/request identity and then unlocks. Main rejects stale request deltas, completions, closes, and cancels, so old events cannot update or unlock another conversation.
- Dialogue speech is emitted before world-action validation, using `speech`, then `decision_summary`, then `……`. A valid reply therefore remains visible even when one accompanying world action fails its current-state constraints.
- Existing autonomous scheduling, Protocol v2 validation/execution, authoritative world mutations, outcome reporting, and F8 raw trace coverage remain in the same passing Agent suite.

The TypeScript Provider prompt now includes `dialogue_input` verbatim for dialogue triggers and explicitly requests an in-character response. After a successful response, the service stores one idempotent memory event containing the complete `player_text` and `agent_speech`; it does not persist one database row per stream delta.

The short headless main-scene startup was intentionally network-passive: it verified scene wiring and parse/runtime startup without initiating player dialogue, changing the configured Agent database, or claiming a real Provider conversation.

## Protocol v2 destructive migration

Before the updated local service accepted any request, validation observed `PRAGMA user_version=2` and zero rows in `sessions`, `events`, `long_term_memories`, and `idempotency`. Six pre-v2 checkpoint SQLite files under the configured checkpoint root were removed. A non-SQLite preservation test proves checkpoint cleanup does not delete unrelated files, and a second v2 repository open proves the migration does not clear new data again.

## Existing repository baselines

`godot_console --headless --path . --script res://tests/run_tests.gd` still reports the same four pre-existing failures out of 3089 checks: three order/contract persistence assertions and one shared `VillagerSystem` count assertion (`expected 5, got 6`). The updated NPC prompt/name checks in that aggregate pass; these unrelated failures were present before this implementation and were not changed.

`godot_console --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd` reports two existing fixture failures out of 1786 checks: the automatic seed-map inventory assertion and the initial contract-delivery availability assertion. No Agent/NPC dialogue assertion fails in that suite.

Two broader suites fail identically on `main` and this feature branch when run with the same console binary:

| Suite | `main` | Feature branch | Assessment |
|---|---:|---:|---|
| `tests/run_task2_trade_tests.gd` | 13 of 1386 failed | 13 of 1386 failed | Existing Market settlement/history baseline |
| `tests/run_economy_save_integration_tests.gd` | 45 of 1507 failed | 45 of 1507 failed | Existing building/save fixture cascade |

These failures are recorded rather than changed because they are outside the Agent framework and the counts/messages are unchanged from `main`. Save-mutating Godot suites must be run serially because they share `user://villa_saves`.

## Real Provider smoke

The connected test requires all of:

- `services/agent-service/config/agent-service.local.json` with a real Provider base URL, API key, and model;
- `config/agent-client.local.json` with `enabled` set to `true` and the running service URL;
- a running Agent Service.

An ignored local credential configuration was used for the connected validation. No secret value was printed or persisted in trace output. The script verified protocol v2 health, session sync, `stream.started`, sanitized Provider input, optional reasoning/content/tool deltas, one Provider output, one final farmer batch accepted by `AgentActionValidator`, stream completion, per-action outcome persistence when non-empty, and checkpoint export. The observed real decision contained one valid action. Both local files are ignored by Git, and no environment-variable fallback exists.

## Intentional non-goals

NPC actions mutate authoritative inventories, market state, farms, buildings, activities, and discoveries, and publish their committed results to the HUD. NPC-specific planting, harvesting, building, and travel visuals are intentionally deferred; the current framework represents these actions through world data and message-panel output.
