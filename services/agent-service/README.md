# Villa Agent Service

This local TypeScript service calls a configured real OpenAI-compatible Provider. It has no runtime mock Provider.

Required environment variables:

- `AGENT_PROVIDER_BASE_URL`
- `AGENT_PROVIDER_API_KEY`
- `AGENT_PROVIDER_MODEL`

Optional variables include `AGENT_SERVICE_HOST`, `AGENT_SERVICE_PORT`, `AGENT_MEMORY_DB`, `AGENT_PROVIDER_TIMEOUT_MS`, `AGENT_PROVIDER_MAX_OUTPUT_TOKENS`, and `AGENT_PROVIDER_TEMPERATURE`.

Godot connects with `AGENT_SERVICE_URL` and optional `AGENT_SERVICE_TOKEN`. The service and game can run on the same machine; Godot remains the sole authority for inventories, market state, NPC farms, buildings, activities, and discoveries.

```powershell
$env:AGENT_PROVIDER_BASE_URL = "https://your-provider.example/v1"
$env:AGENT_PROVIDER_API_KEY = "..."
$env:AGENT_PROVIDER_MODEL = "your-model"
$env:AGENT_SERVICE_URL = "http://127.0.0.1:4317"
npm start
```

Run offline tests with `npm test`. Tests use local fake HTTP endpoints and never use public network or real credentials. The runtime contains no simulated Provider.

HTTP endpoints:

- `GET /health`
- `POST /v1/sessions/sync`
- `POST /v1/agents/:id/decide`
- `POST /v1/agents/:id/outcomes`
- `POST /v1/checkpoints/export`
- `POST /v1/checkpoints/import`

On a successful game save, Godot asynchronously exports the current session memory and writes a `save_N.agent-memory.json` manifest beside the world save. Loading never waits for the service: a missing, corrupt, or unavailable checkpoint produces a HUD warning and continues with empty Agent memory. Deleting a save also deletes its manifest.

Important raw events are scored immediately. Once an Agent accumulates 20 uncompacted high-value events, the configured real Provider condenses them into a factual long-term memory. Provider failure leaves every raw event intact for a later retry. Each decision context includes both recent raw events and that Agent's own long-term memories; session and Agent IDs isolate all reads.

The opt-in connected smoke test is:

```powershell
godot --headless --path . --script res://tests/agent_service_integration.gd
```
