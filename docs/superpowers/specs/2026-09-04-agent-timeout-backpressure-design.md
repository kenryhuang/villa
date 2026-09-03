# Agent Timeout Backpressure Design

## Evidence

The latest persisted session contains 32 autonomous decisions: 10 completed and 22 timed out. Eighteen timeouts occurred in the first Provider round at the configured 30-second boundary. Farmer and merchant requests each retained 90 unacknowledged events; the raw delta alone occupied about 51 KB. `public_world_state.market_summary` also duplicated roughly 14 KB of market state already represented by the role-specific compact market summary.

## Provider timeout

The configured per-round Provider timeout becomes 180 seconds in the tracked example, the parser default, and the local development configuration. The per-round timer behavior remains unchanged: every `/chat/completions` round gets its own budget and reports `provider_timeout` if that round exceeds it.

The Agent Service owns one fair FIFO concurrency gate shared by decision rounds and memory-compaction calls. `provider.max_concurrency` is configurable and defaults to `2`. A remote call first waits for a gate permit and only then starts its per-round timeout, so queue delay cannot consume the Provider execution budget. Caller cancellation removes a queued call without consuming a permit. A permit is always released after success, Provider error, timeout, or caller cancellation.

## Request projection

`AgentContextProjection` removes `market_summary` from its copy of `public_world_state`. The authoritative projector retains the complete market projection for checkpoints and local reads. The request continues to carry the new top-level role-specific `market_summary` and the separate full `market_view` used only by local TypeScript read tools.

An Agent request carries at most 16 `own_event_delta` records. If the frozen unconsumed batch contains more than 16 events, the projection contains:

1. one synthetic `EventDeltaSummary` record for the omitted prefix; and
2. the most recent 15 original events in global-sequence order.

The summary contains schema version, omitted count, first and last omitted global sequence, latest omitted game minute, and sorted counts by event type and aggregate type. It contains no omitted payload bodies.

The inbox still freezes the complete batch. A successful decision acknowledges the complete frozen batch and advances the cursor through every represented event. A failed decision releases the complete batch unchanged. Thus projection size is bounded without truncating the immutable event store or losing delivery semantics.

Before compacting the model-facing delta, `AgentContextProjection` removes any `own_event_delta` event whose non-empty `event_id` already appears in the same request's `global_public_events`. Private, regional, older public, and identifier-less events remain in the private delta. This merge changes only the model projection: acknowledgement and failure release continue to operate on the complete frozen inbox batch.

## Scheduler backpressure

When any request reaches a terminal success or failure callback, the scheduler updates that Agent's automatic scheduling baseline to the scheduler's current game minute. The next time-based decision therefore waits a complete configured interval instead of immediately issuing `catch_up` for game time elapsed while the Provider was running.

Every role's authored default scheduling range doubles: farmer `[2, 2]`, merchant `[2, 4]`, and explorer `[4, 8]` game hours. Explicit debug-panel overrides keep their literal values and are not multiplied again.

Explicit pending dialogue and priority event work remains eligible for immediate dispatch after the current request finishes. This change suppresses only automatic catch-up storms.

## Verification

Regression tests prove the 180-second default, configurable two-call FIFO Provider gate whose queue wait is outside the timeout, doubled role defaults, absence of the nested market projection, event-ID de-duplication between public history and the private delta, deterministic 16-record event projection with full-batch acknowledgement/release, and a full post-response scheduling interval after both success and failure. Existing Provider, Agent protocol, Godot Agent, and connected service tests must remain green.
