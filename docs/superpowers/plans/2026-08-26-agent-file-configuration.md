# Agent File Configuration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every Agent environment-variable setting with ignored JSON configuration files for the TypeScript service and Godot client.

**Architecture:** The TypeScript service validates one service-local JSON file before startup and resolves data paths from the service root. Godot uses a focused `AgentClientConfig` parser and degrades to disabled remote decisions when its local JSON is absent or invalid; Provider credentials never cross into Godot.

**Tech Stack:** Node.js 24 native TypeScript stripping, built-in `fs/path`, Godot 4.7 GDScript, repository Node and SceneTree test harnesses.

---

## File map

- `services/agent-service/src/config.ts`: strict JSON parsing, defaults, path resolution, and CLI `--config` selection.
- `services/agent-service/src/server.ts`: load the selected file and inject configured memory/checkpoint paths.
- `services/agent-service/config/agent-service.example.json`: committed service template without a real key.
- `services/agent-service/config/agent-service.local.json`: ignored operator-owned secret file.
- `scripts/ai_agent/agent_client_config.gd`: focused Godot client JSON parser.
- `config/agent-client.example.json`: committed Godot template.
- `config/agent-client.local.json`: ignored local Godot connection file.
- `scripts/ai_agent/agent_runtime.gd`: consume parsed client configuration instead of environment variables.
- `tests/test_agent_client_config.gd`: parser and graceful-degradation tests.
- `tests/agent_service_integration.gd`: discover the service from the Godot JSON file.

### Task 1: TypeScript service configuration file

**Files:**
- Create: `services/agent-service/tests/config.test.ts`
- Create: `services/agent-service/config/agent-service.example.json`
- Modify: `services/agent-service/src/config.ts`
- Modify: `services/agent-service/src/server.ts`
- Modify: `services/agent-service/tests/provider.test.ts`
- Modify: `.gitignore`

- [ ] **Step 1: Write failing file-loading tests**

Create temporary JSON files and assert this API:

```ts
const config = loadConfigFile(configPath, serviceRoot);
assert.equal(config.provider.baseUrl, "http://127.0.0.1:9000/v1");
assert.equal(config.databasePath, resolve(serviceRoot, "data/test.sqlite"));
assert.equal(config.checkpointRoot, resolve(serviceRoot, "data/checkpoints"));
assert.equal(selectConfigPath(["node", "server.ts", "--config", "custom.json"], serviceRoot), resolve(serviceRoot, "custom.json"));
```

Cover missing files, malformed JSON, missing `provider.api_key`, invalid URL, invalid numeric ranges, unknown top-level shapes, and proof that `process.env.AGENT_PROVIDER_API_KEY` is never consulted.

- [ ] **Step 2: Run RED**

Run: `npm --prefix services/agent-service test`

Expected: FAIL because `loadConfigFile` and `selectConfigPath` do not exist.

- [ ] **Step 3: Implement strict JSON configuration**

Replace `loadConfig(env)` with:

```ts
export function selectConfigPath(argv: string[], serviceRoot: string): string;
export function loadConfigFile(configPath: string, serviceRoot: string): ServiceConfig;
```

Use exact sections `service`, `provider`, and `memory`. Require `base_url`, `api_key`, and `model`; default optional fields to host `127.0.0.1`, port `8787`, timeout `10000`, max output tokens `1200`, and temperature `0.4`. Add `checkpointRoot` to `ServiceConfig`. Resolve database/checkpoint paths against `serviceRoot`.

Update `server.ts` to derive its root from `import.meta.url`, select `--config` or `config/agent-service.local.json`, and pass `config.checkpointRoot` into `createApp`.

- [ ] **Step 4: Add templates and ignore secrets**

Commit a complete `agent-service.example.json` with `api_key: "replace-with-your-key"`. Ignore only `services/agent-service/config/agent-service.local.json`, while keeping the example tracked.

- [ ] **Step 5: Run GREEN**

Run: `npm --prefix services/agent-service test`

Expected: every Node test passes using temporary JSON configuration files; no test depends on Provider environment variables.

- [ ] **Step 6: Commit**

```powershell
git add .gitignore services/agent-service/config services/agent-service/src services/agent-service/tests
git commit -m "feat: load Agent service configuration from JSON"
```

### Task 2: Godot client configuration file

**Files:**
- Create: `scripts/ai_agent/agent_client_config.gd`
- Create: `tests/test_agent_client_config.gd`
- Create: `config/agent-client.example.json`
- Modify: `scripts/ai_agent/agent_runtime.gd`
- Modify: `tests/run_agent_system_tests.gd`
- Modify: `tests/test_agent_main_integration.gd`
- Modify: `.gitignore`

- [ ] **Step 1: Write failing Godot parser tests**

Write temporary files under `user://` and assert:

```gdscript
var loaded := AgentClientConfigScript.load_file(valid_path)
assertions.truthy(loaded.ok, "valid Agent client configuration loads")
assertions.equal(loaded.value.service_url, "http://127.0.0.1:8787", "service URL normalizes")
assertions.truthy(not AgentClientConfigScript.load_file(missing_path).ok, "missing configuration rejects")
assertions.truthy(AgentClientConfigScript.load_file(disabled_path).value.enabled == false, "explicit disablement loads")
```

Cover malformed JSON, invalid URL schemes, empty enabled URL, timeout outside `0.1..120`, and unexpected field types.

- [ ] **Step 2: Run RED**

Run: `godot --headless --path . --script res://tests/run_agent_system_tests.gd`

Expected: preload failure because `agent_client_config.gd` does not exist.

- [ ] **Step 3: Implement the focused parser and runtime wiring**

Create `AgentClientConfig.load_file(path)` returning `{ok, value}` or `{ok:false,error}`. Accept only HTTP/HTTPS service URLs and normalize trailing slashes.

Change `AgentRuntime.configure` to accept an optional final argument:

```gdscript
func configure(..., client_config_path: String = "res://config/agent-client.local.json") -> bool:
```

Remove all `OS.get_environment` calls. Missing/invalid/disabled client configuration leaves `service_enabled = false`, publishes a warning only for invalid/missing files, and still returns `true`. A valid enabled file configures `AgentGateway` with URL, token, and timeout.

- [ ] **Step 4: Add template and ignore local client config**

Commit `config/agent-client.example.json` with localhost defaults and ignore `config/agent-client.local.json`.

- [ ] **Step 5: Run GREEN**

Run: `godot --headless --path . --script res://tests/run_agent_system_tests.gd`

Expected: all Agent checks pass, including explicit configuration parsing and runtime fallback.

- [ ] **Step 6: Commit**

```powershell
git add .gitignore config scripts/ai_agent tests
git commit -m "feat: load Godot Agent connection from JSON"
```

### Task 3: Connected test, documentation, and final verification

**Files:**
- Modify: `tests/agent_service_integration.gd`
- Modify: `services/agent-service/README.md`
- Modify: `docs/validation/role-agent-framework-validation.md`

- [ ] **Step 1: Update the connected acceptance script**

Load `res://config/agent-client.local.json`; explicitly skip when it is missing or disabled. Remove every Provider and service environment-variable check. Use the configured URL/token for health, session, decision, outcome, and checkpoint requests.

- [ ] **Step 2: Rewrite setup documentation**

Document:

```powershell
Copy-Item config/agent-service.example.json config/agent-service.local.json
Copy-Item ../../config/agent-client.example.json ../../config/agent-client.local.json
npm start
```

Explain `npm start -- --config <path>`, the default port, ignored secret files, Godot fallback behavior, and the absence of environment-variable compatibility.

- [ ] **Step 3: Run final verification**

Run serially:

```powershell
npm --prefix services/agent-service test
godot --headless --path . --script res://tests/run_agent_system_tests.gd
godot --headless --path . --script res://tests/agent_service_integration.gd
godot --headless --path . --quit-after 2
git diff --check
```

Expected: Node and Godot suites pass, connected smoke explicitly skips when no local files exist, main initializes, and diff checking is clean.

- [ ] **Step 4: Commit**

```powershell
git add services/agent-service/README.md tests/agent_service_integration.gd docs/validation/role-agent-framework-validation.md
git commit -m "docs: configure role agents with local JSON"
```
