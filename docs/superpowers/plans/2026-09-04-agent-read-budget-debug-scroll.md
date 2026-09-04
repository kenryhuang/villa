# Agent Read Budget and Debug Scroll Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent normal batched read-tool choices from failing merchant decisions and let users inspect earlier Agent trace content while streaming continues.

**Architecture:** `OpenAICompatibleProvider` counts completed read rounds, exposes read tools for at most two rounds, and then sends a command-only Provider request. `AgentDebugWindow` tracks bottom-follow state per `TextEdit`, preserves manual positions across rerenders, and surfaces terminal error codes in summary labels.

**Tech Stack:** TypeScript/Node test runner, Godot 4/GDScript scene tests.

---

### Task 1: Replace read-call budget with read-round budget

**Files:**
- Modify: `services/agent-service/tests/provider.test.ts`
- Modify: `services/agent-service/src/provider.ts`

- [x] Add a regression server that returns four read calls, then three read calls, then one `speak` command. Assert three Provider bodies, no read tools in the third body, and a successful action.
- [x] Run `node --experimental-strip-types --test --test-name-pattern="two batched read rounds" tests/provider.test.ts` and confirm it fails with `provider_too_many_read_calls`.
- [x] Replace `readCount` with `readRounds`; expose reads while `readRounds < 2`, increment once per accepted read batch, and remove the six-call rejection.
- [x] Re-run the focused Provider test and require it to pass.

### Task 2: Preserve manual debug scrolling

**Files:**
- Modify: `tests/test_agent_debug_window.gd`
- Modify: `scripts/ui/agent_debug_window.gd`

- [x] Extend the scene test with long multiline output, wait for layout, move the Output scrollbar to the top, stream another delta, and assert the scrollbar remains at the top.
- [x] Assert an errored request's list row and status label contain the stable error code.
- [x] Run `godot_console --headless --path . --script res://tests/run_agent_system_tests.gd` and confirm the scroll-preservation and error-summary assertions fail against unconditional bottom scrolling.
- [x] Capture each view's bottom-follow state before rerendering, preserve its previous position when not following, and reset following on open/request selection.
- [x] Include the terminal error code in `_request_label` and `_status_text`, leaving raw JSON unchanged.
- [x] Re-run the Godot Agent suite and require it to pass.

### Task 3: Full verification and service restart

**Files:**
- Modify: `docs/superpowers/plans/2026-09-04-agent-read-budget-debug-scroll.md`

- [x] Run `npm test` in `services/agent-service` and require zero failures.
- [x] Run `godot_console --headless --path . --script res://tests/run_agent_system_tests.gd` and require zero failures.
- [x] Run `git diff --check` and inspect `git status --short`, preserving all earlier uncommitted Provider timeout/concurrency/context work.
- [x] Restart only the Node process listening on `127.0.0.1:8787`, verify `/health`, and require an empty stderr log.
