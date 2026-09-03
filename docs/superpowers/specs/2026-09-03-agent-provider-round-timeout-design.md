# Agent Provider Per-Round Timeout Design

## Problem

`OpenAICompatibleProvider.streamDecision` currently creates one timeout before its read-tool loop. A decision that needs several `/chat/completions` rounds shares the same 30-second budget, so a later round is aborted even when every individual Provider request is making progress. Node exposes that timeout as the unstable message `This operation was aborted`.

## Design

Each Provider `/chat/completions` round owns a fresh timeout controller. The controller covers both `fetch` and consumption of that response's SSE body. It is cleared as soon as that round finishes, before local read-tool results are appended and the next round starts.

The caller's cancellation signal remains decision-scoped. It is forwarded into every active round and must retain its existing cancellation behavior. A Provider round whose own timer fires throws the stable error `provider_timeout`; an external cancellation is not relabeled as a timeout.

Memory compaction keeps its existing single-request timeout behavior, but uses the same stable `provider_timeout` error when its own timer fires.

## Error and retry semantics

The Agent Service emits `stream.error` with `code` and `message` equal to `provider_timeout`. The existing retry classification recognizes the word `timeout`, so the error is marked retryable. No automatic retry is added in this change; the scheduler may try again on a later cycle.

## Verification

Provider tests use a delayed local HTTP endpoint and a short timeout to prove:

- two read-tool Provider rounds each receive a fresh timeout budget and complete successfully;
- a single slow round fails specifically with `provider_timeout`;
- external cancellation still aborts promptly without being mislabeled.

