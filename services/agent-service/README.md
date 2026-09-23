# Villa Agent Service

This local TypeScript service calls a configured real OpenAI-compatible Provider. It has no runtime mock Provider. Godot remains the sole authority for inventories, market state, NPC farms, buildings, activities, and discoveries.

## Code map and execution flow

Read [the loop architecture](docs/loops.md) first. Production entry points:

| Responsibility | Implementation |
| --- | --- |
| NPC event queue, periodic clock producer, bounded execution engine | `../../scripts/ai_agent/agent_event_queue.gd`, `agent_clock_source.gd`, `agent_scheduler.gd` |
| Public event recipients, role/item subscriptions, focus eligibility | `../../scripts/ai_agent/agent_event_router.gd` |
| HTTP routes, SSE envelope, cancellation | `src/app.ts` |
| Action request preparation and persistence | `src/agent/service.ts` |
| Action loop: context → model → ordered tools → results → model | `src/agent/loop.ts` |
| Context blocks: environment, role, resources, goals, memory, dialogue, tools | `src/agent/build_context.ts` |
| Tool discovery, menu and sequential execution | `src/agent/tool_menu.ts`, `execute_tools.ts` |
| Godot action receipt bridge | `src/transport/action_broker.ts` |
| Chat turn and archive | `src/chat/loop.ts` |
| Chat context blocks and five-turn window | `src/chat/build_context.ts`, `context_window.ts` |
| Chat completion client | `src/chat/provider.ts` |
| Latest-turn intent schema and validation | `src/chat/intent_extraction.ts` |
| Durable asynchronous intent outbox | `src/chat/intent_worker.ts` |
| Per-loop, context-size and persistent provider budgets | `src/budget/` |
| Memory extraction, core memory, retrieval and persistence | `src/memory/service.ts`, `src/memory.ts` |

Root `agent_loop.ts`, `chat_provider.ts`, `chat_context.ts`, and `chat_summary.ts` are compatibility exports. The old terminal-batch runner and synchronous chat extraction adapter live in `agent/legacy_loop.ts` and `chat/legacy.ts`; the updated 3D client uses inline execution and asynchronous extraction.

## Separate chat and action models

NPC action loops are event-driven. System events, extracted dialogue intentions and periodic clock events enter a FIFO queue in Godot; completion immediately schedules the next eligible NPC. Configure `max_concurrent_agent_loops` in `config/agent-client.local.json` (repository root): default 3, integer 1–32. Excess events wait, and each NPC runs at most one loop. Queue entries and interrupted active events survive game saves. This bounds whole NPC loops; service `provider.max_concurrency` separately bounds model calls. Foreground chat and the public coordinator retain separate slots.

`POST /v1/agent-events/poll` accepts `{session_id, session_epoch, cursor}` and delivers up to 64 dialogue event notices plus `next_cursor`. The game polls automatically, including while paused; autonomous execution waits until resume. Notices are deduplicated by source ID and never consume intentions. Clock polling and delivery do not call the LLM without a queued event. Model input includes the triggering event in `turn.trigger_events`; the debug summary shows running and waiting counts.

Public facts no longer broadcast decisions to every NPC. Market events select actors with matching inventory/reserves, active supply requests, open offers or typed item goals. Weather selects farmers/explorers; season changes select farmers; environmental events require explicit `affected_actor_ids`. Ordinary day changes update knowledge only. Public events and clocks target the 3D focus pool; demotion removes these incidental queued messages while preserving directed conversation/trade obligations. Waiting public updates coalesce by actor/topic/item, while distinct directed events remain separate. See [routing rules](docs/loops.md) for the full table.

`provider` configures action decisions and action-memory extraction. `chat_provider` optionally selects a different model for chat and intent extraction. If omitted, the server uses the action model configuration for the separate chat loop. The loops and histories remain separate even when the model is the same.

Chat streams natural text without native tools. Context includes the game background, dialogue task, speaking character and tone, participant relationship facts, and the latest five turns (current player turn plus four previous turns). A turn includes a player message and all following NPC replies, including group members. A 6000-character ceiling drops whole older turns while preserving the current player message. Older messages remain archived, but older summaries are neither generated nor injected. The prompt requests only coherent in-character spoken paragraphs, without narration or action descriptions. **Intent extraction never blocks the final reply**.

After a complete reply, `chat/loop.ts` persists a `ChatIntentPending` job containing only this player's message and this NPC's reply. A background worker uses the chat model to extract visits/invitations, activities, trades, information requests, information received, and relationship intentions. It preserves confirmed/proposed/requested/cancelled/stated distinctions and checks quotations against the current pair of messages. Raw quotations do not enter the action model. Names remain names until the action loop resolves them through authoritative tools; extraction needs no live SSE world reads.

Extracted records accumulate in the actor's action memory. The next action loop includes them in `turn.confirmed_dialogue`, with source IDs, times and explicit status. A proposal is not consent; stated information is not an authoritative world fact. On successful loop completion only the records actually supplied (or explicitly retrieved) are acknowledged. Records arriving during that loop remain pending. A loop interrupted by an error does not consume them. Multi-step commitments must become durable goals.

The worker retries transient failures after 30 seconds, with at most three failed attempts. Validation errors and exhausted provider budgets stop automatic retry and retain the failed job and diagnostics. Pending jobs resume after restart. Save epoch, room reset generation and source existence are checked before committing results. The queue, results and diagnostic events travel with memory checkpoints.

The debug window polls `POST /v1/chat/intent-trace` every two seconds while visible, scoped to its selected chat request. Its action-intention tab shows original messages, prepared prompt, actual model request, raw response, validation details and retry failures even after the chat stream has ended. The call picker includes asynchronous extraction calls. Missing historical traces are explicitly identified; queued work is never labelled as an empty extraction. See the [exact extraction prompt](docs/intent-extraction-prompt.md).

Private and group rooms remain isolated. **重新开始** changes only the selected room's generation; completed game plans, actor core memories and other rooms remain intact. Incomplete/cancelled chat replies do not enqueue intent extraction. A completed reply is preserved if later extraction fails; failures are archived as `ChatIntentError` for diagnosis.

## Configure and start

From `services/agent-service`, copy the tracked examples to ignored local files:

```powershell
Copy-Item config/agent-service.example.json config/agent-service.local.json
Copy-Item ../../config/agent-client.example.json ../../config/agent-client.local.json
```

Edit `config/agent-service.local.json` and set the Provider `base_url`, `api_key`, and `model`. `timeout_ms` defaults to `180000` per remote Provider round, and `max_concurrency` defaults to `2` across decision and memory-compaction calls. Dialogue takes priority; waiting background calls retain FIFO order. If all slots are occupied, an unfinished background Provider round yields to dialogue and resumes through a fresh round afterward, without committing partial commands or exceeding the configured concurrency. Queue time does not consume the per-round timeout. The default service address is `http://127.0.0.1:8787`. The database and checkpoint paths are resolved relative to `services/agent-service`.

Edit `../../config/agent-client.local.json` if Godot should use a different service address, token, or timeout. Set `enabled` to `false` to keep remote Agent decisions disabled explicitly. `store_agent_session` defaults to `false`; when enabled, Godot appends one credential-free aggregate input/response record per completed or failed request to `user://agent_sessions` and retains the newest 20 session files.

Start the service:

```powershell
npm start
```

To load a service configuration from another location, pass `--config`. Relative paths are resolved from `services/agent-service`; absolute paths are also accepted.

```powershell
npm start -- --config D:\configs\villa-agent.json
```

Both `*.local.json` files are ignored by Git. Never commit the Provider API key. The key belongs only in the TypeScript service configuration and is never sent to Godot, saves, logs, traces, or SQLite. There is no environment-variable compatibility fallback.

For v3, `provider.stream_idle_timeout_ms` defaults to 45,000 ms without meaningful model deltas, including waiting for the first output. Heartbeats do not extend it. `provider.loop_timeout_ms` defaults to 180,000 ms for the entire loop, including queue wait, all model rounds and world reads. Exceeding these limits aborts the request and releases its slot with `provider_stream_idle_timeout` or `agent_loop_timeout`. The existing `timeout_ms` still bounds each acquired Provider call. Memory extraction disables thinking, runs at lower priority, and occupies at most one slot; foreground decisions can preempt it. Debug loop events distinguish queue wait, first-output wait, receiving output and completed rounds; `provider.input` now means the request has acquired a slot and is being sent.

If the Godot client configuration is missing or invalid, the game reports a warning and continues with remote Agent decisions disabled. A configuration with `enabled: false` disables the service without warning.

## Tests and API

The formal 3D farm reuses this service and the existing Godot runtime directly. Use `./tools/run_farm3d.ps1 -ServiceOnly` to leave the service running in the background and launch Godot manually, or `-Agents` to launch both. Existing local configs in Git worktrees are read in place, including manual editor launches. The 3D bottom HUD has a debug-only **调试** button for actor state, schedule controls, environment/rental schedules, and the original request trace. NPC dialogue pauses the game and disables gameplay shortcuts while retaining text editing and network streaming; closing clears held movement actions and restores the previous pause state.

### Formal 3D Agent Loop (decision v3)

Every new action context also includes up to five actor core memories and pending extracted dialogue intentions. The initial context contains the brief GameEnv from `data/agents/game_env.json`, identity/soul/current role and goals, the exact owned-resource snapshot, and the latest 15 persisted meaningful events with an older-history summary. Relevant persistent memories and the current trigger/dialogue/short-goal references accompany that header. Long event payloads use a marked excerpt with their source ID; the complete event is still available through a read tool.

World details are discovered on demand. Initially the model receives `discover_tools`, `inspect_self_resources`, `recall_memory`, and basic speech/wait actions. `discover_tools` opens up to three domains and selects up to six permitted action schemas. `query_world` then reads named sections, with ID/search and pagination (default five, maximum ten list entries). The memory domain enables `inspect_event` and `inspect_history_segment`. Public coordination has its own restricted domains and action permissions. Reads query Godot's current authorized state through SSE `read.request` and `POST /v1/reads/result`; they also work while dialogue pauses the simulation.

First discovery advertises only `domains`. Once a domain is open, optional `actions` exposes an enum of its exact permitted action names. A mistaken catalog selection (such as a read-tool name or an intention in prose) returns `invalid_action_selection`, the available names and instructions; it never executes or grants that action. Domain-only discovery retains enabled actions. Actual forbidden command calls still abort, while an authorized command whose schema has not been enabled gets one bounded correction. `loop.validation_failed` records the called and enabled tools for diagnosis.

Each scheduled/event trigger creates an action loop. The updated 3D client advertises `tool_execution: "inline"`. A loop has six read rounds / twelve read calls and three action attempts by default (one for the public coordinator). Tool calls in a response run sequentially; reads and enabled actions may be mixed. Each action emits `action.request`, waits for a terminal Godot outcome, then refreshes owned resources. `in_progress` does not release the next action. The provider sees `assistant.tool_calls`, matching `tool` result messages and an assistant execution-results record before its next round. Tool errors are returned as observations for reflection; failed attempts consume budget. Invalid response batches allow one correction, and unauthorized tools abort. Final decisions contain no already-executed actions. Cancellation cannot roll back game effects; Godot retains pending receipts and blocks another background decision while execution remains active. Older clients without inline support retain final-batch compatibility.

Short goals are persisted in the game save with version, source event IDs, expiry and review time. At most three can be active; `adopt_short_term_goal`, `revise_short_term_goal` and `abandon_short_term_goal` change them. Optional typed completion conditions check actual inventory, completed projects or known discoveries. A model statement cannot mark a goal complete. Failed actions and useful progress on an active goal can schedule a follow-up, with a three-link feedback limit and a 60-game-minute cooldown.

Resources remain authoritative in Godot. Snapshots have a revision and observation time; changes are captured before decisions and after action results. A sync every 60 game minutes persists resources and pending events independently of model decisions. Pending events survive saves and are removed only after service acknowledgement. The memory database keeps immutable source events, important memories and rolling older-history summaries. Relevant retrieval supports Chinese text and is scoped to the save and actor. Important-memory/history extraction runs in the background; failure preserves raw sources for later retrieval and retry. Schema upgrades create a `.pre-v3.sqlite` backup and preserve existing history and checkpoints.

Optional top-level `loop` configuration is illustrated in `config/agent-service.example.json`. Existing local configs work with defaults. Before every model round, automatic compaction checks messages **and tool schemas**. Defaults are `compact_at_tokens=48000`, `compact_target_tokens=32000`, `max_input_tokens=64000`, and `max_compactions=6`. Currently these use a conservative **UTF-8 byte upper bound**, labelled `utf8_bytes_upper_bound` in traces, not exact model token counts. Tune them for the configured model window, including its output allowance. Compaction preserves the fixed header and replaces complete old tool-call/result pairs with bounded observations carrying source/time/version and a refresh requirement. The effective target accounts for the protected header/tool floor plus observation space, capped below the hard limit. Crossing the hard limit triggers emergency compaction even after the normal count is exhausted. Traces expose `configured_target`, `target`, `protected_input`, `target_met`, and the trigger reason. If the result still exceeds the hard limit, `context.capacity_exceeded` reports whether protected content or working context caused the failure. Read, action and time budgets never reset during compaction.

In formal 3D, discover `buildings` and query its `sites` section for legal plots, material costs and exact `build_action` arguments. The `build` tool accepts `building_type` (`windmill` or `food_workshop`), `gx` and `gz`. It submits a persistent project that escrows the actor's materials, reserves the plot, walks to the site and completes real construction. The initial receipt is `in_progress`; only actual completion releases subsequent ordered actions. Failed construction reports a project ID for inspection/retry/cancellation. New buildings are privately owned and closed until their service policy is configured. The legacy 2D build contract is unchanged.

The 3D `survey(region_id)` action includes walking to the field site; no preceding `travel` or `move` is required. At arrival it checks that day's evidence and consumes one bread, then performs 20 game minutes of on-site work. Travel time cannot produce evidence. Only completion creates a report and releases later ordered actions. `travel` remains relocation only. Survey progress persists across saves; old prepaid surveys resume without another charge. For trips crossing a day boundary, report identity uses the day the on-site survey starts.

The standalone legacy 2D path still accepts decision v2 with its original frozen projection, two read rounds and recovery rules. Formal 3D uses decision v3 only, with no eager-context fallback; action/outcome/SSE envelopes retain the existing v2 executor contract. Run the matching updated service with the client. No local Provider credentials or live save files are changed by this refactor.

Run `npm run typecheck` for production TypeScript and offline service tests with `npm test`; they use temporary databases and local fake HTTP endpoints. The runtime has no simulated Provider. To exercise real Godot + service + a local scripted upstream (no external model call), run from this directory:

```powershell
$env:RUN_GODOT_LOOP_TEST = '1'
node --experimental-strip-types --test tests/agent_loop_godot.test.ts
Remove-Item Env:RUN_GODOT_LOOP_TEST
godot_console.exe --headless --path ../.. --script tests/run_agent_loop_tests.gd -- --farm-test
```

Action model rounds enable thinking; corrective rounds disable it. Action-memory work shares the action provider gate. Chat replies and JSON extraction share their own provider gate; replies can preempt background extraction. Both providers reserve input/output budgets before every actual network call, including retries. Per-round timeouts and client cancellation abort unfinished inference without submitting partial actions.

HTTP endpoints:

- `GET /health`
- `POST /v1/sessions/sync`
- `POST /v1/experience/sync`
- `POST /v1/reads/result`
- `POST /v1/agents/:id/decide`
- `POST /v1/agents/:id/decide/stream` (`text/event-stream`)
- `POST /v1/agents/:id/outcomes`
- `POST /v1/checkpoints/export`
- `POST /v1/checkpoints/import`

The streaming route emits project-owned `provider.input`, `reasoning.delta`, `content.delta`, `tool_call.delta`, `provider.output`, `read.request`, `context.ack`, `loop.trace`, `action.request`, and final decision events. Partial or failed streams never commit a decision. In debug builds, press `F8` or use “Agent 调试” in the runtime debug panel to inspect the live Input/Reasoning/Output trace. Reasoning is never shown in normal dialogue or the HUD.

Godot NDJSON traces append late action receipts as separate `record_type: "action_event"` rows linked by `request_id`, with `action_event.event`, `timestamp_msec`, and `metadata`. Group these with the original request when investigating movement or settlement; a completed Provider stream does not mean its physical actions have completed. See [dialogue and action diagnosis](../../docs/design/2026-09-14-agent-dialogue-action-fix.md).

To inspect raw SSE manually from Windows PowerShell while the service is running:

```powershell
curl.exe -N -H "Accept: text/event-stream" -H "Content-Type: application/json" --data-binary "@../../shared/agent_protocol/v2/decision-request.json" http://127.0.0.1:8787/v1/agents/farmer_ahe/decide/stream
```

On a successful game save, Godot asynchronously exports the current session memory and writes a `save_N.agent-memory.json` manifest beside the world save. Loading never waits for the service: a missing, corrupt, or unavailable checkpoint produces a HUD warning and continues with empty Agent memory. Deleting a save also deletes its manifest.

With both local configuration files present, the opt-in connected streaming smoke test is:

```powershell
godot --headless --path ../.. --script res://tests/agent_service_integration.gd
```


Tool-only dialogue trade calls (`propose_trade`, `counter_trade`, `accept_trade`, `reject_trade`, `cancel_trade`) receive a short pending-request reply after all normal permission, schema and action-budget validation. Missing provider prose alone no longer aborts a valid trade or consumes a correction round. The synthesized reply lives in decision `speech`; raw provider output is preserved and `dialogue.reply_fallback` identifies the source in traces. It never asserts settlement or bypasses recipient confirmation. Godot appends actual execution facts only for successful/pending receipts, never a success caption for rejected trades.
