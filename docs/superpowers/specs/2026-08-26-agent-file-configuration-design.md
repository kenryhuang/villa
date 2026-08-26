# Agent File Configuration Design

## Goal

Replace all environment-variable configuration for the local TypeScript Agent Service and its Godot client with explicit JSON files. Provider credentials remain outside Godot and outside version control.

## Configuration files

The TypeScript service reads this ignored local file by default:

```text
services/agent-service/config/agent-service.local.json
```

The repository provides a safe template:

```text
services/agent-service/config/agent-service.example.json
```

Schema:

```json
{
  "service": {"host": "127.0.0.1", "port": 8787},
  "provider": {
    "base_url": "https://provider.example/v1",
    "api_key": "replace-me",
    "model": "provider-model",
    "timeout_ms": 30000,
    "max_output_tokens": 1200,
    "temperature": 0.4
  },
  "memory": {
    "database_path": "data/agent-memory.sqlite",
    "checkpoint_root": "data/checkpoints"
  }
}
```

`npm start` loads the default file. `npm start -- --config <path>` loads an explicitly selected file. Relative database and checkpoint paths resolve from the Agent Service root, not the caller's current directory.

Godot reads this ignored local file:

```text
config/agent-client.local.json
```

The repository provides:

```text
config/agent-client.example.json
```

Schema:

```json
{
  "enabled": true,
  "service_url": "http://127.0.0.1:8787",
  "token": "",
  "timeout_seconds": 10
}
```

The Provider API key is never present in the Godot configuration.

## Runtime behavior

The TypeScript service validates every field before opening SQLite or listening on a port. A missing file, malformed JSON, unsupported property type, incomplete Provider configuration, invalid URL, or out-of-range number stops startup with a field-specific error. Environment variables are not consulted.

Godot loads and validates its client configuration during `AgentRuntime.configure`. A missing or invalid local file, `enabled: false`, or an empty service URL disables remote Agent decisions without blocking the main scene. Existing local NPC dialogue remains the fallback. Godot publishes a warning for invalid configuration but treats deliberate disablement as normal.

`session_id`, memory checkpoint manifests, Provider request behavior, world validation, and authoritative action execution remain unchanged.

## Security and version control

Both `*.local.json` files are ignored. Only example files are committed. Provider secrets are held only by the TypeScript process and are never serialized into Godot saves, HUD messages, traces, or example files.

The optional Godot `token` continues to be sent to the local service for future authentication support. It is not presented as an effective security boundary until server-side verification exists; the service remains bound to `127.0.0.1` by default.

## Testing

TypeScript tests use temporary real JSON files and cover valid loading, explicit `--config` selection, missing files, malformed JSON, incomplete Provider fields, invalid ranges, and proof that environment variables are ignored.

Godot tests cover valid client configuration, deliberate disablement, missing/malformed files, invalid URL/timeout, and graceful fallback with `service_enabled == false`. Existing Provider HTTP tests continue using local fake endpoints after loading their Provider settings through temporary files.

## Documentation and migration

The service README documents copying each example to its local filename, editing it, starting the service, and launching Godot. Existing environment-variable instructions are removed. This is a deliberate configuration migration with no environment-variable compatibility fallback.
