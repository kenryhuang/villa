# Villa Agent Service

This local TypeScript service calls a configured real OpenAI-compatible Provider. It has no runtime mock Provider. Godot remains the sole authority for inventories, market state, NPC farms, buildings, activities, and discoveries.

## Separate chat and action models

The optional top-level `chat_provider` config routes player dialogue (including group replies) to a separate completion model. The example uses `http://127.0.0.1:11434/v1`, `local-ollama`, and `cydonia-24b:latest`. Keep `provider` set to the existing Qwen model for scheduled/event action loops and action-memory summaries. Restart the service after configuration changes, and restart the game after UI/runtime changes. `/health` reports `chat_provider` and `context_channels`.

Chat uses streamed text completions (`stream: true`), without native tool calls, followed by a separate non-streamed JSON extraction call to the same model. Each call has its own `chat_provider.timeout_ms` (default 180 seconds, including chat queue wait), concurrency defaults to one, and output defaults to 800 tokens. A chat failure never falls back to the main provider. The SSE connection forwards each model content delta to the 3D dialogue panel immediately and sends heartbeats while waiting. Partial replies remain visible if streaming fails; incomplete/cancelled replies do not create action handoffs. Extraction JSON is never displayed as dialogue. `chat.first_token` records first visible output latency; `chat.timing` records queue wait, HTTP headers, first token, phase duration and maximum content gap separately for dialogue and extraction. Gaps of at least one second emit `chat.slow_chunk` immediately. Godot also retains server/send versus client/receive gap measurements in `response.content_timing`, even when the player cancels before completion. These are content chunk/character measurements, not tokenizer throughput. Extraction failure keeps the reply and displays an explicit message that the action arrangement was not reliably recorded.

Private rooms and group rooms store messages in separate SQLite namespaces. Each reply sees only a short farm-world background, the current character’s complete persona, current participants (player and other room members, with their names, roles, personas and brief current relationship), and up to the latest 16 room messages bounded to 8,000 characters. Current participant profiles come from the game request, including save overrides. Resources, inventory, activity/schedules, projects, action goals and map/market snapshots are not part of the reply prompt. No world query runs before first output. After the reply, action extraction may resolve game IDs and validate a proposed relationship change through live reads. Participant context is removed from action requests. All messages remain archived and included in memory checkpoints; older chat is currently outside the model's rolling window rather than summarized by Qwen. A newly created group starts its own history; private conversations are not copied into it. Existing legacy dialogue archives remain intact but are not automatically imported into new rooms.

Action context uses `action.v2:<actor>` memory scopes. Legacy chat, mixed old summaries and untrusted old goal descriptions are excluded. Incoming experience, outcomes and live world reads drop chat text/prose fields; action-memory lookup and compaction stay in the action scope. Only service-created `ChatActionAgreed` records may cross the boundary. Handoffs contain bounded enums, known actor/place/item IDs, quantity, price, delay and production parameters; quotation evidence is checked in the chat channel and is never forwarded. Greetings, hypothetical plans, refusals and unaccepted player commands do not create actions. The next fresh action loop queries current conditions before submitting real game tools. Price `0` means no agreed price, not free goods; cancellation takes precedence over an older plan. Existing explicit relationship confirmation/end actions remain in private chat with current dialogue evidence and the game's original relationship checks.

In the dialogue panel, choose another NPC and click **加入群聊**. Up to four NPCs reply in join order, once each per player message. Later speakers see earlier replies from the same room. Membership changes are disabled during a round; adding another NPC between rounds preserves that group's history. Closing the panel cancels the active response and remaining speakers. **回到单聊** restores private history; reopening starts in private mode. Group membership is currently a panel session, while its messages are durably archived.

Without `chat_provider`, legacy single-provider routing remains available for existing tests and installations. With split routing enabled, dialogue requires the v3 streaming endpoint.

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

The initial context contains the brief GameEnv from `data/agents/game_env.json`, identity/soul/current role and goals, the exact owned-resource snapshot, and the latest 15 persisted meaningful events with an older-history summary. Relevant persistent memories and the current trigger/dialogue/short-goal references accompany that header. Long event payloads use a marked excerpt with their source ID; the complete event is still available through a read tool.

World details are discovered on demand. Initially the model receives `discover_tools`, `inspect_self_resources`, `recall_memory`, and basic speech/wait actions. `discover_tools` opens up to three domains and selects up to six permitted action schemas. `query_world` then reads named sections, with ID/search and pagination (default five, maximum ten list entries). The memory domain enables `inspect_event` and `inspect_history_segment`. Public coordination has its own restricted domains and action permissions. Reads query Godot's current authorized state through SSE `read.request` and `POST /v1/reads/result`; they also work while dialogue pauses the simulation.

First discovery advertises only `domains`. Once a domain is open, optional `actions` exposes an enum of its exact permitted action names. A mistaken catalog selection (such as a read-tool name or an intention in prose) returns `invalid_action_selection`, the available names and instructions; it never executes or grants that action. Domain-only discovery retains enabled actions. Actual forbidden command calls still abort, while an authorized command whose schema has not been enabled gets one bounded correction. `loop.validation_failed` records the called and enabled tools for diagnosis.

Each timer/event/dialogue trigger creates a loop. A loop may read for six rounds / twelve calls by default, then submit at most three ordered actions (one during dialogue or public coordination). Each round exposes the remaining read budget, including the maximum batch size. Mixed read/action batches are rejected before execution. Invalid arguments get at most one correction; permission failures abort. Godot validates and executes the final batch, preserving existing movement, production queues, project escrow and idempotency. An asynchronous action completes before its batch continuation; a failure stops the remainder. Another background loop for the same actor waits for execution to finish. Physical dialogue actions are deferred until the game resumes and are validated again.

Short goals are persisted in the game save with version, source event IDs, expiry and review time. At most three can be active; `adopt_short_term_goal`, `revise_short_term_goal` and `abandon_short_term_goal` change them. Optional typed completion conditions check actual inventory, completed projects or known discoveries. A model statement cannot mark a goal complete. Failed actions and useful progress on an active goal can schedule a follow-up, with a three-link feedback limit and a 60-game-minute cooldown.

Resources remain authoritative in Godot. Snapshots have a revision and observation time; changes are captured before decisions and after action results. A sync every 60 game minutes persists resources and pending events independently of model decisions. Pending events survive saves and are removed only after service acknowledgement. The memory database keeps immutable source events, important memories and rolling older-history summaries. Relevant retrieval supports Chinese text and is scoped to the save and actor. Important-memory/history extraction runs in the background; failure preserves raw sources for later retrieval and retry. Schema upgrades create a `.pre-v3.sqlite` backup and preserve existing history and checkpoints.

Optional top-level `loop` configuration is illustrated in `config/agent-service.example.json`. Existing local configs work with defaults. Before every model round, automatic compaction checks messages **and tool schemas**. Defaults are `compact_at_tokens=48000`, `compact_target_tokens=32000`, `max_input_tokens=64000`, and `max_compactions=6`. Currently these use a conservative **UTF-8 byte upper bound**, labelled `utf8_bytes_upper_bound` in traces, not exact model token counts. Tune them for the configured model window, including its output allowance. Compaction preserves the fixed header and replaces complete old tool-call/result pairs with bounded observations carrying source/time/version and a refresh requirement. The effective target accounts for the protected header/tool floor plus observation space, capped below the hard limit. Crossing the hard limit triggers emergency compaction even after the normal count is exhausted. Traces expose `configured_target`, `target`, `protected_input`, `target_met`, and the trigger reason. If the result still exceeds the hard limit, `context.capacity_exceeded` reports whether protected content or working context caused the failure. Read, action and time budgets never reset during compaction.

In formal 3D, discover `buildings` and query its `sites` section for legal plots, material costs and exact `build_action` arguments. The `build` tool accepts `building_type` (`windmill` or `food_workshop`), `gx` and `gz`. It submits a persistent project that escrows the actor's materials, reserves the plot, walks to the site and completes real construction. The initial receipt is `in_progress`; only actual completion releases subsequent ordered actions. Failed construction reports a project ID for inspection/retry/cancellation. New buildings are privately owned and closed until their service policy is configured. The legacy 2D build contract is unchanged.

The 3D `survey(region_id)` action includes walking to the field site; no preceding `travel` or `move` is required. At arrival it checks that day's evidence and consumes one bread, then performs 20 game minutes of on-site work. Travel time cannot produce evidence. Only completion creates a report and releases later ordered actions. `travel` remains relocation only. Survey progress persists across saves; old prepaid surveys resume without another charge. For trips crossing a day boundary, report identity uses the day the on-site survey starts.

The standalone legacy 2D path still accepts decision v2 with its original frozen projection, two read rounds and recovery rules. Formal 3D uses decision v3 only, with no eager-context fallback; action/outcome/SSE envelopes retain the existing v2 executor contract. Run the matching updated service with the client. No local Provider credentials or live save files are changed by this refactor.

Run offline service tests with `npm test`; they use temporary databases and local fake HTTP endpoints. The runtime has no simulated Provider. To exercise real Godot + service + a local scripted upstream (no external model call), run from this directory:

```powershell
$env:RUN_GODOT_LOOP_TEST = '1'
node --experimental-strip-types --test tests/agent_loop_godot.test.ts
Remove-Item Env:RUN_GODOT_LOOP_TEST
godot_console.exe --headless --path ../.. --script tests/run_agent_loop_tests.gd -- --farm-test
```

Dialogue model rounds disable thinking; autonomous rounds enable it. Corrective rounds disable thinking. All rounds share the existing Provider queue and concurrency limit with memory work. Per-round timeouts and client cancellation abort unfinished inference without submitting partial actions.

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

The streaming route emits project-owned `provider.input`, `reasoning.delta`, `content.delta`, `tool_call.delta`, `provider.output`, `read.request`, `context.ack`, `loop.trace`, and final decision events. Partial or failed streams never commit a decision. In debug builds, press `F8` or use “Agent 调试” in the runtime debug panel to inspect the live Input/Reasoning/Output trace. Reasoning is never shown in normal dialogue or the HUD.

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
