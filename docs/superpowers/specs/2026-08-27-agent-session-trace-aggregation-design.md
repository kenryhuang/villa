# Agent Session Trace Aggregation Design

**Date:** 2026-08-27

## Goal

When `store_agent_session` is enabled, persist one NDJSON record for each completed Agent request instead of one record for every streamed SSE delta. Keep the F8 Agent debug window incremental and unchanged.

## Current problem

`AgentSessionTrace.accept_event()` already aggregates streamed input, reasoning, content, tool-call fragments, provider output, and the final decision in memory. However, it also immediately writes every accepted SSE event to disk. Long reasoning streams therefore generate thousands of records for a small number of Agent requests, making the saved trace expensive to write and difficult to inspect.

## Persistence boundary

Streaming events continue to update the in-memory request record and emit `trace_updated` so the F8 debug window can display live input, reasoning, and output.

Disk persistence happens only when a request reaches one of these terminal states:

- `stream.completed`: write one aggregated record with status `completed`.
- `stream.error`: write one aggregated record with status `error`.
- A local transport failure, timeout, or cancellation reported by the scheduler: finish the in-memory request as `error` and write one aggregated record.

Terminal persistence is idempotent by `request_id`. An SSE `stream.error` followed by the transport completion callback must still create only one line. If the game exits while a request has no terminal event, the partial request remains memory-only and is not written.

## Record schema

Each line is an independent JSON object using schema version 2:

```json
{
  "schema_version": 2,
  "request_id": "farmer_ahe-1",
  "stream_id": "farmer_ahe-1:stream",
  "agent_id": "farmer_ahe",
  "trigger": "schedule",
  "status": "completed",
  "started_msec": 1001,
  "updated_msec": 1012,
  "input": {},
  "response": {
    "reasoning_content": "...",
    "content": "...",
    "tool_call_deltas": [],
    "provider_output": {},
    "decision": {},
    "error": {}
  }
}
```

The in-memory record keeps its existing field names because the F8 window consumes them directly. Serialization maps those fields into the stable disk schema at the terminal boundary.

## Cancellation handling

Replacing an in-flight autonomous request with player dialogue currently cancels the gateway request after removing the scheduler's in-flight marker. That deliberately suppresses the stale gateway callback, but it also hides the cancellation from `AgentRuntime`.

The scheduler will explicitly report the replaced request to its failure callback with `dialogue_replaced` before dispatching the new dialogue request. `AgentRuntime` then finalizes the old trace. The later stale gateway callback remains ignored, preventing duplicate UI signals and duplicate disk records.

## Compatibility and retention

This change affects only new trace lines. Existing event-per-line NDJSON files are not migrated. The configured directory, sanitized filenames, maximum of 20 session files, maximum of 100 in-memory request records, Protocol v2 request/response contract, and F8 live display remain unchanged.

## Verification

Automated coverage must prove that:

- streamed deltas update memory but do not write to disk;
- completion writes exactly one aggregated line;
- stream errors and local failures/cancellations write exactly one error line;
- duplicate terminal notifications do not append another line;
- closing an unfinished trace does not persist it;
- live F8 aggregation behavior still passes its existing tests;
- session-file retention still keeps at most 20 files.
