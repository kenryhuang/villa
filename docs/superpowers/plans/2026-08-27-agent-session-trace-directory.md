# Agent Session Trace Directory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Godot Agent trace directory configurable and write the active local configuration's NDJSON files directly under `D:/UnityProject/villa/tmp`.

**Architecture:** Extend the existing Agent client configuration contract with one optional validated path, retaining `user://agent_sessions` as the compatibility default. `AgentRuntime` owns the selected path and supplies it to `AgentSessionTrace` during startup and save-slot changes; the trace writer keeps responsibility for directory creation, flushing, and retention.

**Tech Stack:** Godot 4.7, GDScript, JSON, `FileAccess`, `DirAccess`, repository headless tests.

---

## File Structure

- `scripts/ai_agent/agent_client_config.gd`: validate and return the directory field.
- `scripts/ai_agent/agent_runtime.gd`: retain the path and pass it through the trace lifecycle.
- `config/agent-client.example.json`: document the portable default.
- `config/agent-client.local.json`: select `D:/UnityProject/villa/tmp` locally.
- `tests/test_agent_client_config.gd`: cover configuration validation and compatibility.
- `tests/test_agent_main_integration.gd`: cover startup and save-slot trace paths.

### Task 1: Extend the client configuration contract

**Files:**
- Modify: `tests/test_agent_client_config.gd`
- Modify: `scripts/ai_agent/agent_client_config.gd`
- Modify: `config/agent-client.example.json`
- Modify: `config/agent-client.local.json`

- [ ] **Step 1: Write failing configuration tests**

Add this field to the valid fixture:

```gdscript
"agent_session_directory": "D:/UnityProject/villa/tmp",
```

Assert exact preservation:

```gdscript
assertions.equal(
	loaded.value.agent_session_directory,
	"D:/UnityProject/villa/tmp",
	"Agent session directory loads",
)
```

For the existing disabled fixture that omits the field, assert:

```gdscript
assertions.equal(
	disabled.value.agent_session_directory,
	"user://agent_sessions",
	"missing Agent session directory keeps compatibility default",
)
```

Add invalid fixtures:

```gdscript
{"enabled": false, "service_url": "", "token": "", "timeout_seconds": 10, "agent_session_directory": ""},
{"enabled": false, "service_url": "", "token": "", "timeout_seconds": 10, "agent_session_directory": 42},
```

- [ ] **Step 2: Run tests and verify failure**

```powershell
& 'C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Links\godot_console.exe' --headless --path . --script res://tests/run_agent_system_tests.gd
```

Expected: non-zero exit because the new field is unknown or absent from the returned value.

- [ ] **Step 3: Implement minimal parsing and validation**

In `agent_client_config.gd`, add:

```gdscript
const DEFAULT_SESSION_DIRECTORY := "user://agent_sessions"
```

Append `"agent_session_directory"` to `ALLOWED_FIELDS`. Before constructing the successful result, add:

```gdscript
if data.has("agent_session_directory") and (
	typeof(data.agent_session_directory) != TYPE_STRING
	or str(data.agent_session_directory).strip_edges().is_empty()
):
	return _failure("invalid_agent_session_directory")
```

Return the selected value:

```gdscript
"agent_session_directory": str(
	data.get("agent_session_directory", DEFAULT_SESSION_DIRECTORY)
).strip_edges(),
```

- [ ] **Step 4: Update JSON files**

Add to `agent-client.example.json`:

```json
"agent_session_directory": "user://agent_sessions"
```

Add to `agent-client.local.json`:

```json
"agent_session_directory": "D:/UnityProject/villa/tmp"
```

- [ ] **Step 5: Run tests and verify success**

```powershell
& 'C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Links\godot_console.exe' --headless --path . --script res://tests/run_agent_system_tests.gd
```

Expected: exit code 0 and a `PASS` summary.

- [ ] **Step 6: Commit**

```powershell
git add -- scripts/ai_agent/agent_client_config.gd config/agent-client.example.json config/agent-client.local.json tests/test_agent_client_config.gd
git commit -m "feat: configure Agent trace directory"
```

### Task 2: Preserve the directory through the runtime lifecycle

**Files:**
- Modify: `tests/test_agent_main_integration.gd`
- Modify: `scripts/ai_agent/agent_runtime.gd`

- [ ] **Step 1: Write the failing lifecycle test**

Create a temporary directory name in `test_agent_main_integration.gd` and enable disk persistence in the generated test configuration:

```gdscript
var trace_directory := "user://agent-main-trace-%d" % Time.get_ticks_usec()
disabled_config.store_string(JSON.stringify({
	"enabled": false,
	"service_url": "",
	"token": "",
	"timeout_seconds": 10,
	"store_agent_session": true,
	"agent_session_directory": trace_directory,
}))
```

After `runtime.configure(...)`, assert:

```gdscript
assertions.truthy(
	str(runtime.get_session_trace().get_log_path()).begins_with(trace_directory + "/"),
	"runtime opens Agent trace in configured directory",
)
```

Then switch slots and assert the replacement file stays there:

```gdscript
runtime.set_save_slot(3)
assertions.truthy(
	str(runtime.get_session_trace().get_log_path()).begins_with(trace_directory + "/"),
	"save-slot change preserves configured Agent trace directory",
)
```

After freeing both runtime nodes, remove the temporary files and directory:

```gdscript
for file_name in DirAccess.get_files_at(trace_directory):
	DirAccess.remove_absolute(ProjectSettings.globalize_path(trace_directory.path_join(file_name)))
DirAccess.remove_absolute(ProjectSettings.globalize_path(trace_directory))
```

- [ ] **Step 2: Run tests and verify failure**

```powershell
& 'C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Links\godot_console.exe' --headless --path . --script res://tests/run_agent_system_tests.gd
```

Expected: non-zero exit because runtime still calls the trace collector without the configured directory.

- [ ] **Step 3: Implement runtime path propagation**

Add this field to `agent_runtime.gd`:

```gdscript
var _agent_session_directory := AgentClientConfigScript.DEFAULT_SESSION_DIRECTORY
```

After loading a valid client configuration, store:

```gdscript
_agent_session_directory = str(client_config.value.agent_session_directory)
```

Change both disk-capable configuration calls—startup and `set_save_slot()`—to:

```gdscript
if not session_trace.configure(
	_store_agent_session,
	session_id,
	_agent_session_directory
):
```

Leave the memory-only fallback as `session_trace.configure(false, session_id)` because it opens no file.

- [ ] **Step 4: Run focused tests and startup validation**

```powershell
& 'C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Links\godot_console.exe' --headless --path . --script res://tests/run_agent_system_tests.gd
& 'C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Links\godot_console.exe' --headless --path . --quit-after 2
```

Expected: both commands exit 0; no GDScript parse or runtime configuration errors occur.

- [ ] **Step 5: Verify the actual local output path**

```powershell
Get-ChildItem -LiteralPath 'D:\UnityProject\villa\tmp' -Filter '*.ndjson' | Sort-Object LastWriteTime -Descending | Select-Object -First 3 FullName,Length,LastWriteTime
```

Expected: at least one current NDJSON file is directly under `D:\UnityProject\villa\tmp`.

- [ ] **Step 6: Check formatting and commit**

```powershell
git diff --check
git add -- scripts/ai_agent/agent_runtime.gd tests/test_agent_main_integration.gd
git commit -m "fix: preserve Agent trace directory"
```

Expected: `git diff --check` emits no output and the commit succeeds.

### Task 3: Final verification

**Files:**
- Verify: `config/agent-client.local.json`
- Verify: `D:/UnityProject/villa/tmp`

- [ ] **Step 1: Run the complete Agent regression suite**

```powershell
& 'C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Links\godot_console.exe' --headless --path . --script res://tests/run_agent_system_tests.gd
```

Expected: exit code 0 and all Agent checks pass.

- [ ] **Step 2: Verify repository state and latest trace**

```powershell
git status --short --branch
Get-ChildItem -LiteralPath 'D:\UnityProject\villa\tmp' -Filter '*.ndjson' | Sort-Object LastWriteTime -Descending | Select-Object -First 1 FullName,Length,LastWriteTime
```

Expected: no uncommitted implementation files remain and the latest trace path is under the requested directory.
