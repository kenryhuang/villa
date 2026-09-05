# Agent Farm Context Implementation Plan

> Execute in the existing `feature/painted-production-buildings` worktree. The user's requested behavior is the approved design; preserve prior uncommitted edits.

**Goal:** Clear withered crops through harvest without rewards and provide reliable calendar and planting context.

**Architecture:** Reuse the real farming system for mutation and previews. Build crop options at the visible farm port and attach them to runtime actor context. Keep current protocol fields and add human-readable calendar fields.

**Tech Stack:** Godot GDScript, Node.js native test runner.

- [x] Add failing regressions to visible farmer tests for cleanup/replant/replay, ordinary harvest/rejection, and crop options with winter/greenhouse restrictions. Run `godot_console --headless --path . --script res://tests/run_visible_farmer_tests.gd`.
- [x] Implement visible farm cleanup using `clear_withered`, return an empty resource delta, and generate per-crop planting previews from registered definitions and owned cells.
- [x] Add request-context assertions for all four named seasons, formatted time, and crop options in `tests/test_agent_main_integration.gd`; run `tests/run_agent_system_tests.gd` to demonstrate failures, then update `agent_runtime.gd`.
- [x] Add service tests for harvest semantics and crop-option transport; run `npm test` in `services/agent-service`, then update tool descriptions.
- [x] Run focused farmer, Agent system, service, and aggregate regression tests. Review the diff against the approved scope and existing uncommitted changes. Record any pre-existing failures separately.

## Validation

- Initial farmer regressions: 6 expected failures, then pass after implementation.
- Calendar and tool-description regressions failed on missing fields/semantics before implementation.
- Review regressions demonstrated seedless planting, unauthorized seed advertising, and cleanup incorrectly satisfying a productive-harvest milestone; all fixed.
- Final Agent system suite: 1703 checks passed. Service suite: 44 tests passed.
- Aggregate suite: 2 of 3167 failed, matching the two failures already observed before this task (`stored crop initially enables contract delivery`; `all villagers are registered: expected 5, got 6`).
- Existing uncommitted dialogue/input changes preserved; this work does not alter service memory ordering or complete the pending main merge.
