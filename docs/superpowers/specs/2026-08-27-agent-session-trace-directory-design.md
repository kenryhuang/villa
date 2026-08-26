# Agent Session Trace Directory Configuration

## Goal

Move locally persisted Godot Agent session trace files out of the operating-system user-data directory and into a configurable directory. The current development configuration will write traces directly under `D:/UnityProject/villa/tmp`.

## Configuration Contract

`config/agent-client.local.json` gains an optional string field:

```json
"agent_session_directory": "D:/UnityProject/villa/tmp"
```

The field must be a non-empty string after trimming whitespace. When it is absent, the client retains the existing `user://agent_sessions` default so older configuration files remain valid.

`config/agent-client.example.json` documents the field with the portable value `user://agent_sessions`. Only the local development configuration contains the machine-specific absolute path.

Godot accepts forward slashes in the configured Windows path. The configuration must not contain credentials, and the trace records remain credential-free.

## Runtime Data Flow

`AgentClientConfig` parses and validates `agent_session_directory`, returning the resolved configuration value together with `store_agent_session`.

`AgentRuntime` stores that directory and passes it to `AgentSessionTrace.configure()`:

1. during initial runtime configuration;
2. after switching save slots and reopening the trace file;
3. when retrying configuration after a file-open failure, while disabling disk persistence.

This prevents a save-slot change from silently restoring the old `user://agent_sessions` directory.

`AgentSessionTrace` continues to create the configured directory recursively, name files by session and timestamp, flush every accepted non-heartbeat SSE event, and retain at most 20 NDJSON files. With the local configuration, files are created directly as:

```text
D:/UnityProject/villa/tmp/<session-id>-<timestamp>.ndjson
```

No migration or deletion of existing files under the Godot `user://agent_sessions` directory is included.

## Failure Behavior

If the configured directory cannot be created or a trace file cannot be opened, Agent execution remains enabled. The runtime publishes the existing warning and reconfigures the trace collector for memory-only operation. It must not fall back to writing under the administrator profile.

An invalid `agent_session_directory` makes the Agent client configuration invalid using the existing configuration-error path. This is preferable to silently writing to an unexpected directory.

## Tests

Automated coverage will verify:

- a missing field resolves to `user://agent_sessions`;
- a valid absolute Windows-style path is returned unchanged;
- an empty or non-string field is rejected;
- initial runtime configuration passes the configured directory to the trace collector;
- changing save slots keeps using the configured directory;
- trace retention and immediate NDJSON flushing continue to work in a temporary test directory.

The implementation will also run the existing Agent-focused Godot test suite to detect configuration or lifecycle regressions.

## Out of Scope

- moving or deleting historical trace files;
- changing the NDJSON event schema;
- changing the in-memory request limit or the 20-file retention limit;
- changing Agent scheduling, Provider calls, or stale-world-revision handling.
