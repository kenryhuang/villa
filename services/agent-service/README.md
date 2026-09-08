# Villa Agent Service

This local TypeScript service calls a configured real OpenAI-compatible Provider. It has no runtime mock Provider. Godot remains the sole authority for inventories, market state, NPC farms, buildings, activities, and discoveries.

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

If the Godot client configuration is missing or invalid, the game reports a warning and continues with remote Agent decisions disabled. A configuration with `enabled: false` disables the service without warning.

## Tests and API

The formal 3D farm reuses this service and the existing Godot runtime directly. Use `./tools/run_farm3d.ps1 -ServiceOnly` to leave the service running in the background and launch Godot manually, or `-Agents` to launch both. Existing local configs in Git worktrees are read in place, including manual editor launches. The 3D bottom HUD has a debug-only **调试** button for actor state, schedule controls, environment/rental schedules, and the original request trace. NPC dialogue pauses the game and disables gameplay shortcuts while retaining text editing and network streaming; closing clears held movement actions and restores the previous pause state.

Dialogue uses a compact prompt with identity, current resources/activity/project, active terms and recent summaries, instead of full public event histories and historical production receipts. Inspection tools still query the original complete immutable context. Greetings and activity questions are answered directly when these facts suffice. The current project and trade/cooperation terms remain intact. See [dialogue latency validation](../../docs/validation/agent-dialogue-latency.md).

`inspect_map`, `inspect_characters`, `inspect_buildings`, and `inspect_building` read the current immutable world snapshot. Existing market tools remain available. `rent_production` requires the real building instance ID, recipe, batch count and a total fee cap. Godot validates and transfers tenant inputs/gold, shares the original production queue, and delivers goods to the tenant. The 3D save includes Agent state and paid jobs; asynchronous memory manifests live beside `data/farm_3d_save.json` and are matched using its SHA-256 before import.

Run offline tests with `npm test`. Tests use temporary configuration files and local fake HTTP endpoints; they never use public network or real credentials. The runtime contains no simulated Provider.

Decisions have two batched read rounds. Each round advertises its remaining reads consistently in both the prompt and tool list. A mixed read/command batch performs only the authorized reads and asks the model to reissue commands; exhausted reads or invalid read arguments also receive explicit feedback. There is at most one tool-correction attempt per decision. Unknown tools remain unauthorized. An autonomous Provider timeout gets one retry with extended thinking disabled; a second timeout remains an error. Dialogue and external cancellation do not use this timeout retry.

The 3D region reader resolves `world_map.regions`, and market depth contains authoritative total buy/sell quotes including slippage and separate stock availability. Project submission checks current commission status, deadline, quota and claim slots before escrow. If its commission becomes invalid during execution, the project stops new spending, waits for already committed production to settle, then returns unused funds and goods and releases its claims. Moving to the market center resolves to a reachable south counter. Game close, session change and client reconfiguration are recorded as cancellations with distinct reasons, not decision errors. See [trace recovery validation](../../docs/validation/agent-trace-recovery.md).

HTTP endpoints:

- `GET /health`
- `POST /v1/sessions/sync`
- `POST /v1/agents/:id/decide`
- `POST /v1/agents/:id/decide/stream` (`text/event-stream`)
- `POST /v1/agents/:id/outcomes`
- `POST /v1/checkpoints/export`
- `POST /v1/checkpoints/import`

The streaming route emits project-owned `provider.input`, `reasoning.delta`, `content.delta`, `tool_call.delta`, `provider.output`, and final decision events. Partial or failed streams never commit a decision. In debug builds, press `F8` or use “Agent 调试” in the runtime debug panel to inspect the live Input/Reasoning/Output trace. Reasoning is never shown in normal dialogue or the HUD.

To inspect raw SSE manually from Windows PowerShell while the service is running:

```powershell
curl.exe -N -H "Accept: text/event-stream" -H "Content-Type: application/json" --data-binary "@../../shared/agent_protocol/v2/decision-request.json" http://127.0.0.1:8787/v1/agents/farmer_ahe/decide/stream
```

On a successful game save, Godot asynchronously exports the current session memory and writes a `save_N.agent-memory.json` manifest beside the world save. Loading never waits for the service: a missing, corrupt, or unavailable checkpoint produces a HUD warning and continues with empty Agent memory. Deleting a save also deletes its manifest.

Important raw events are scored immediately. Once an Agent accumulates 20 uncompacted high-value events, the configured real Provider condenses them into a factual long-term memory. Provider failure leaves every raw event intact for a later retry. Each decision context includes both recent raw events and that Agent's own long-term memories; session and Agent IDs isolate all reads.

The model projection carries shared public events once in `global_public_events`; matching event IDs are removed from the model-facing `own_event_delta` while private, regional, and older events remain. The complete frozen inbox batch is still acknowledged only after a valid decision. Authored automatic schedule defaults are two game hours for the farmer, two to four for the merchant, and four to eight for the explorer; debug-panel overrides remain literal.

With both local configuration files present, the opt-in connected streaming smoke test is:

```powershell
godot --headless --path ../.. --script res://tests/agent_service_integration.gd
```
