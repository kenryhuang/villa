# 3D Farming Integration Implementation Plan

> **For agentic workers:** Use subagent-driven-development to implement independent asset and rules tasks, with root integrating controls and reviewing the result.

**Goal:** Play the original farming lifecycle in the current 3D farm with painted meadow detail.
**Architecture:** Shared original simulation systems + 3D visual adapters + small session and interaction/HUD controllers. No second crop growth algorithm.
**Tech Stack:** Godot 4.7 GDScript, Blender Python, glTF, original painted textures.

- [x] Commit verified oak integration (6ee6943).
- [x] Meadow task: modify scripts/tools/build_3d_farm_assets.py to remove baked fields/crops/grass; rebuild environment and Blender source. Create scripts/farm3d/painted_meadow.gd and shader/material assets using original grass texture and curved mesh clumps. API configure(grid), refresh_cell(gx,gz), no scene edits. Keep paths and trees clear. Inspect rendered scene.
- [x] Session task: create scripts/farm3d/farm_session.gd, flat_grid.gd, crop_visual_system.gd. Reuse original rules and action transactions; API configure(player), grid/farming/season/inventory/tools, act(cell,mode)->Dictionary, rest(), save_game(), load_game(); modes hoe/seed/water/harvest. Reject beyond 2.6m before spending. Share original crop definitions. Headless tests first for lifecycle, invalid actions and save roundtrip, then implement and rerun.
- [x] Root task: integrate session and meadow in farm_3d_preview.gd, replace old field colliders with generated fields. Implement scripts/farm3d/farm_interaction.gd and farm_hud.gd, cursor projection, near/front actions, tool mesh/swing and feedback. Keep camera controls compatible. Add end-to-end tests using real scene and inputs.
- [x] Run godot_console.exe --headless --editor --path . --quit, then tests/run_3d_farming_tests.gd, tests/run_farm_3d_preview_tests.gd, tests/run_painted_oak_tests.gd and relevant original farming tests. Fix failures attributable to integration.
- [x] Capture default follow and overview plus planted/mature/harvested states on GPU; inspect screenshots and verify no static duplicate crops. Review changed files, document controls and persistence, commit working integration on existing branch.
