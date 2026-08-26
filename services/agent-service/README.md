# Villa Agent Service

This local TypeScript service calls a configured real OpenAI-compatible Provider. It has no runtime mock Provider. Godot remains the sole authority for inventories, market state, NPC farms, buildings, activities, and discoveries.

## Configure and start

From `services/agent-service`, copy the tracked examples to ignored local files:

```powershell
Copy-Item config/agent-service.example.json config/agent-service.local.json
Copy-Item ../../config/agent-client.example.json ../../config/agent-client.local.json
```

Edit `config/agent-service.local.json` and set the Provider `base_url`, `api_key`, and `model`. The default service address is `http://127.0.0.1:8787`. The database and checkpoint paths are resolved relative to `services/agent-service`.

Edit `../../config/agent-client.local.json` if Godot should use a different service address, token, or timeout. Set `enabled` to `false` to keep remote Agent decisions disabled explicitly.

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

Run offline tests with `npm test`. Tests use temporary configuration files and local fake HTTP endpoints; they never use public network or real credentials. The runtime contains no simulated Provider.

HTTP endpoints:

- `GET /health`
- `POST /v1/sessions/sync`
- `POST /v1/agents/:id/decide`
- `POST /v1/agents/:id/outcomes`
- `POST /v1/checkpoints/export`
- `POST /v1/checkpoints/import`

On a successful game save, Godot asynchronously exports the current session memory and writes a `save_N.agent-memory.json` manifest beside the world save. Loading never waits for the service: a missing, corrupt, or unavailable checkpoint produces a HUD warning and continues with empty Agent memory. Deleting a save also deletes its manifest.

Important raw events are scored immediately. Once an Agent accumulates 20 uncompacted high-value events, the configured real Provider condenses them into a factual long-term memory. Provider failure leaves every raw event intact for a later retry. Each decision context includes both recent raw events and that Agent's own long-term memories; session and Agent IDs isolate all reads.

With both local configuration files present, the opt-in connected smoke test is:

```powershell
godot --headless --path ../.. --script res://tests/agent_service_integration.gd
```
