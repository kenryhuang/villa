# Agent Read Budget and Debug Scroll Design

## Evidence

The latest session trace contains three merchant decisions. Two fail with `provider_too_many_read_calls`: the first Provider round requests four market reads, then the second round requests three more reads. The current six-call counter advertises every read tool while only two calls remain, so a valid Provider batch can be rejected after the service itself offered those tools.

The Agent debug window also calls `_scroll_views_to_end` after every trace refresh. Streaming reasoning and tool-call deltas therefore overwrite a user's scrollbar position on the next frame.

## Provider read budget

A decision may execute at most two local read-tool rounds. Every tool call in an accepted read round is executed, regardless of the number of parallel reads in that batch. After two read rounds, subsequent Provider requests expose command tools only. Mixed read and command batches remain invalid because execution order would be ambiguous.

This replaces `provider_too_many_read_calls`; ordinary model-selected read batches no longer fail because of an invisible remaining-call count. The limit still bounds remote round trips and context growth: at most two read rounds can precede the final command-only round.

## Debug window scrolling and errors

Each Input, Reasoning, and Output `TextEdit` independently follows the bottom only while its scrollbar is already at the bottom. A user scroll or thumb drag above the bottom disables following for that view. Streaming refreshes preserve its current vertical position. Returning the thumb to the bottom resumes following.

Opening the window or selecting another request resets all three views to follow the latest content. Programmatic scrolling is guarded so its own scrollbar signal cannot disable following.

Error records append their stable error code to both the request-list row and the status label. The Output tab continues to show the full raw error object.

## Verification

Provider regression tests reproduce the merchant's four-read then three-read sequence and prove it reaches a final command on a third command-only round. Godot UI tests build overflowing text, scroll upward, append a streamed delta, and prove the position remains unchanged; they also prove the error code is visible without opening raw JSON. The complete TypeScript and Godot Agent suites must remain green.
