# Agent Dialogue Latency and Player Input Rearm Design

## Goal

Reduce NPC dialogue latency by disabling Provider thinking only for dialogue requests, and prevent text-entry keys from becoming continuous player movement after the dialogue closes.

## Provider request behavior

`OpenAICompatibleProvider.streamDecision` remains the only place that constructs remote `/chat/completions` request bodies. Every Provider round belonging to a request with `trigger == "dialogue"` includes the top-level field `enable_thinking: false`. Schedule, event, and catch-up requests omit the field and retain the Provider's configured/default reasoning behavior.

The rule applies to the initial dialogue request and to any follow-up round after a local read tool. This keeps a single dialogue turn internally consistent and prevents thinking from being re-enabled after the first read.

## Player input rearm behavior

Opening the Agent dialogue keeps using the existing movement block and immediately cancels auto-movement. Closing it removes the logical dialogue block but does not immediately accept the current movement vector.

`PlayerController` enters a rearm state when movement becomes unblocked. While rearming, it returns zero movement and ignores jump/sprint. It leaves this state only after all movement actions (`move_left`, `move_right`, `move_forward`, `move_back`, `jump`, and `sprint`) have been observed neutral together. Movement then requires a subsequent new press. This applies equally to WASD, arrow-key mappings, and any future input mapped to those actions.

The existing `Input.action_release` loop is removed because mutating the global action state does not establish a fresh-input boundary and can be overwritten by later physical or repeated key events.

## Failure and lifecycle behavior

The rearm state is entered for every transition from blocked to unblocked, including successful dialogue, Provider failure, and cancellation. Other movement-block reasons remain authoritative: removing the dialogue reason cannot rearm movement while another modal reason is still active.

No timers are used. A key held intentionally while closing the dialogue must be released once before it can move the player.

## Tests

- Provider regression: a dialogue request body contains `enable_thinking: false`; every follow-up read round does too; an autonomous request omits it.
- Player regression: unblocking while a non-zero movement vector is present still returns zero, observing a neutral vector rearms control, and only a later non-zero vector moves.
- Existing Agent Service and Godot Agent suites must remain green.
