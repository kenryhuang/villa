# Agent Provider Per-Round Timeout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give each remote Provider round its own timeout budget and report internal timeout aborts as `provider_timeout`.

**Architecture:** Extract one Provider streaming round into a private method that owns its timeout controller and bridges the decision-scoped external cancellation signal. The existing read-tool loop invokes this method once per round, so completed rounds release their timer before the next begins.

**Tech Stack:** Node.js 24, TypeScript, Fetch API, Node test runner.

---

### Task 1: Specify per-round timeout behavior

**Files:**
- Modify: `services/agent-service/tests/provider.test.ts`

- [x] **Step 1: Add a failing multi-round timeout test**

Create a local streaming Provider that delays each of two rounds by less than the configured timeout, while their combined duration exceeds it. The first response calls an allowed read tool and the second returns a command. Assert the decision completes and the endpoint receives two requests.

- [x] **Step 2: Add a failing stable timeout-code test**

Create a local Provider that delays one response beyond a short configured timeout. Assert `streamDecision` rejects with `provider_timeout` rather than the platform-specific AbortError message.

- [x] **Step 3: Run the focused tests and verify RED**

Run:

```powershell
node --experimental-strip-types --test tests/provider.test.ts
```

Expected: the multi-round test fails under the shared decision timer and the timeout-code test receives `This operation was aborted`.

### Task 2: Move timeout ownership into one Provider round

**Files:**
- Modify: `services/agent-service/src/provider.ts`
- Modify: `services/agent-service/tests/provider.test.ts`

- [x] **Step 1: Implement a per-round streaming helper**

Create a fresh `AbortController` and timeout for each fetch/SSE round. Track whether the internal timer fired; normalize only that case to `provider_timeout`. Forward external aborts without changing their semantics, and always remove listeners and clear the timer.

- [x] **Step 2: Use the helper in the read-tool loop**

Replace the loop's direct fetch and SSE consumption with the helper. Keep message accumulation, local read execution, output events, and command parsing unchanged.

- [x] **Step 3: Stabilize memory-compaction timeout errors**

Track the compaction timer independently and translate its own abort to `provider_timeout`, while retaining the existing one-request timeout budget.

- [x] **Step 4: Run focused and full tests**

Run:

```powershell
node --experimental-strip-types --test tests/provider.test.ts
npm test
```

Expected: all tests pass with no failures.

- [x] **Step 5: Restart and validate the configured service**

Restart only the verified process listening on `127.0.0.1:8787`, run both connected Godot tests, and confirm the service error log is empty.
