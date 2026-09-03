# Agent Timeout Backpressure Design

## Evidence

The latest persisted session contains 32 autonomous decisions: 10 completed and 22 timed out. Eighteen timeouts occurred in the first Provider round at the configured 30-second boundary. Farmer and merchant requests each retained 90 unacknowledged events; the raw delta alone occupied about 51 KB. `public_world_state.market_summary` also duplicated roughly 14 KB of market state already represented by the role-specific compact market summary.

## Provider timeout

The configured per-round Provider timeout becomes 60 seconds in the tracked example, the parser default, and the local development configuration. The per-round timer behavior remains unchanged: every `/chat/completions` round gets its own budget and reports `provider_timeout` if that round exceeds it.

## Request projection

`AgentContextProjection` removes `market_summary` from its copy of `public_world_state`. The authoritative projector retains the complete market projection for checkpoints and local reads. The request continues to carry the new top-level role-specific `market_summary` and the separate full `market_view` used only by local TypeScript read tools.

An Agent request carries at most 16 `own_event_delta` records. If the frozen unconsumed batch contains more than 16 events, the projection contains:

1. one synthetic `EventDeltaSummary` record for the omitted prefix; and
2. the most recent 15 original events in global-sequence order.

The summary contains schema version, omitted count, first and last omitted global sequence, latest omitted game minute, and sorted counts by event type and aggregate type. It contains no omitted payload bodies.

The inbox still freezes the complete batch. A successful decision acknowledges the complete frozen batch and advances the cursor through every represented event. A failed decision releases the complete batch unchanged. Thus projection size is bounded without truncating the immutable event store or losing delivery semantics.

## Scheduler backpressure

When any request reaches a terminal success or failure callback, the scheduler updates that Agent's automatic scheduling baseline to the scheduler's current game minute. The next time-based decision therefore waits a complete configured interval instead of immediately issuing `catch_up` for game time elapsed while the Provider was running.

Explicit pending dialogue and priority event work remains eligible for immediate dispatch after the current request finishes. This change suppresses only automatic catch-up storms.

## Verification

Regression tests prove the 60-second default, absence of the nested market projection, deterministic 16-record event projection with full-batch acknowledgement/release, and a full post-response scheduling interval after both success and failure. Existing Provider, Agent protocol, Godot Agent, and connected service tests must remain green.

