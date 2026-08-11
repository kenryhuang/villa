# Production Yard Painted Ground Implementation Plan

> **For Codex:** Use the `executing-plans` skill to implement this plan task-by-task. Follow test-driven development for behavior changes and verify each checkpoint before committing.

**Goal:** Replace every production-yard fence and its collision with one walkable, hand-painted, semi-transparent terrain-following ground patch while preserving output-slot and save compatibility.

**Architecture:** Keep `BuildingProductionYard` and the `ProductionYard` node/API as the compatibility boundary. Internally, replace fence `Sprite3D` segments, construction atlases, transitions, and `StaticBody3D` perimeter collisions with a single subdivided `ArrayMesh`. Its vertices use the same triangle-interpolated surface height as the rendered terrain, which works with the project's `gl_compatibility` renderer and affects no other geometry; building bodies remain the only physical obstruction. Three 1024×1024 RGBA textures cover timber, masonry, and industrial production-yard families.

**Tech Stack:** Godot 4.7 GDScript, `SurfaceTool`, `ArrayMesh`, transparent `StandardMaterial3D`, PNG RGBA assets, the existing headless GDScript test harness, and the built-in image generation tool.

---

### Task 1: Lock the new runtime contract with failing tests

**Files:**
- Modify: `tests/test_building_production_yard.gd`
- Modify: `tests/test_building_instance.gd`
- Modify: `tests/test_terrain_builder.gd`

**Step 1: Rewrite the yard unit test around painted ground**

Replace fence-atlas assertions with these contracts:

- `GROUND_TEXTURES` maps `timber`, `masonry`, and `industrial` to `*_yard_ground.png`.
- Each asset imports as a 1024×1024 `Texture2D` with alpha.
- Transparent corners and feathered perimeter pixels exist.
- The image contains a meaningful semi-transparent painted region, with a majority of painted samples below full opacity and at least some emphasized detail samples above the main-surface opacity.
- Configuring a 3×3 or 4×4 yard creates exactly one Compatibility-renderable `MeshInstance3D`, sized to the footprint plus at most 0.2 world units total overhang per axis.
- The mesh contains enough subdivisions to follow the terrain heightmap and rebuilds after transform changes.
- No `Sprite3D`, `StaticBody3D`, or enabled yard collision remains.
- Output slot counts remain six for 3×3 and eight for 4×4, and every slot remains inside the footprint.
- `set_construction_stage()` stores the requested stage but leaves the same ground mesh and texture in place with no transition visuals.
- Preview state applies green/red tint; maintenance state does not tint the ground.
- `clear_immediately()` removes the mesh and keeps compatibility query methods safe.

Add small recursive helpers for finding the named ground `MeshInstance3D`, unsupported `Decal`, `Sprite3D`, and `StaticBody3D` nodes. Keep assertions focused on observable behavior, not private field names.

**Step 2: Update building integration expectations**

Change production-building assertions from “yard blocks perimeter traversal” to:

```gdscript
assertions.truthy(not yard.has_enabled_collisions(), "%s production ground stays walkable" % id)
assertions.equal(yard.get_collision_layers(), [], "%s production ground owns no physics layer" % id)
```

Update construction, preview, and deactivation messages/assertions to verify the ground persists across construction stages, never creates collision, receives preview tint, and is removed on deactivation.

**Step 3: Add renderer and terrain assertions**

Extend `tests/test_terrain_builder.gd` to build a real `TerrainBuilder`, assert that `TerrainMesh` retains the default visual layer, confirm the configured renderer is `gl_compatibility`, and assert that `TerrainBody` retains collision layer 1.

**Step 4: Run the focused suite and confirm RED**

Run:

```powershell
& $godot --headless --path . --script res://tests/run_building_system_tests.gd
```

Expected: failures for missing `*_yard_ground.png`, missing mesh/query behavior, old fence collisions, and the unsupported Decal runtime.

**Step 5: Commit the failing contract**

```powershell
git add tests/test_building_production_yard.gd tests/test_building_instance.gd tests/test_terrain_builder.gd
git commit -m "test: define painted production ground contract"
```

### Task 2: Create and validate three hand-painted ground assets

**Files:**
- Create: `assets/buildings/yards/timber_yard_ground.png`
- Create: `assets/buildings/yards/masonry_yard_ground.png`
- Create: `assets/buildings/yards/industrial_yard_ground.png`
- Create after Godot import: matching `.png.import` files

**Step 1: Inspect representative building references**

Use the front/back painted building art as visual references:

- Timber: `assets/buildings/painted/lumberyard/lumberyard_front.png` and `_back.png`
- Masonry: `assets/buildings/painted/stone_kiln/stone_kiln_front.png`, `_back.png`, and quarry art
- Industrial: `assets/buildings/painted/mine/mine_front.png`, `_back.png`, and furnace art

Confirm their brushwork, outline softness, palette, and 2.5D lighting before generation.

**Step 2: Generate the three texture families**

Generate one square texture per family, without buildings, fences, UI, text, or shadows from absent objects. Use a flat chroma background so it can be removed reliably. Composition requirements:

- Timber: compacted warm earth, sawdust, wood chips, a few short worn planks.
- Masonry: aged irregular stone slabs, brick chips, loose stones, sparse moss/soil seams.
- Industrial: dark gravel, coal dust, slag, sparse rust-colored fragments.
- Keep the center relatively quiet for the building body and preserve a readable front collection zone.
- Paint an irregular organic edge but keep the content inside the allowed footprint overhang.
- Match the existing hand-painted 2.5D building style, with top-down/isometric surface detail and no perspective object silhouette.

**Step 3: Convert to production-ready RGBA**

Remove chroma without eroding colored details, resize to exactly 1024×1024, and shape alpha so:

- the main interior sits around 70–80% opacity;
- selected chips/stones/planks reach 85–95%;
- the irregular outer edge feathers smoothly to 0%;
- all four corners are fully transparent.

Use a deterministic local post-processing helper for chroma removal/alpha shaping, then delete any temporary intermediates outside the final three PNGs.

**Step 4: Visually inspect all final PNGs**

Open each final asset and verify no chroma fringe, no hard square boundary, no fence fragments, no text, enough negative space under the building, and clear family differentiation. Regenerate or revise any failed family before continuing.

**Step 5: Import and run the asset-contract test**

Launch Godot headlessly once to generate imports, then run the focused building suite. Expected: image-format and alpha assertions pass; runtime assertions may remain red until Task 3.

**Step 6: Commit the assets**

```powershell
git add assets/buildings/yards/*_yard_ground.png assets/buildings/yards/*_yard_ground.png.import
git commit -m "art: add painted production ground textures"
```

### Task 3: Replace fence runtime with a Compatibility-safe terrain mesh

**Files:**
- Modify: `scripts/buildings/building_production_yard.gd`
- Modify: `scripts/world/terrain_builder.gd`

**Step 1: Preserve the Compatibility renderer contract**

Do not switch the renderer or introduce `Decal`; the project targets `gl_compatibility`. Keep `TerrainMesh.layers == 1` and add `TerrainBuilder.sample_surface_height()` to reproduce the rendered mesh's two-triangle interpolation from its sampled vertices.

**Step 2: Simplify `BuildingProductionYard` state**

Replace atlas/fence constants and state with:

- `GROUND_TEXTURE_SIZE := Vector2(1024.0, 1024.0)`
- `GROUND_OVERHANG := 0.1` per side
- a small surface lift and three subdivisions per occupied cell
- `GROUND_TEXTURES` pointing to the three new PNGs
- one `_ground_mesh: MeshInstance3D` and transparent `StandardMaterial3D`
- preserved `_yard_size`, `_style`, `_structure_offset`, `_construction_stage`, preview state, output slots, and warn-once tracking

Remove segment arrays, fence layers, collision body, transition sprites, and processing state.

**Step 3: Build one terrain-following ground mesh**

During `configure()`:

1. Validate the same supported yard sizes/styles.
2. Clear prior derived state.
3. Load and validate the 1024×1024 ground texture.
4. Create one named `GroundMesh` if the texture is valid.
5. Generate UV-mapped triangles through `SurfaceTool`, sampling `TerrainBuilder.sample_surface_height()` for each world-space vertex.
6. Use smooth alpha blending, unshaded hand-painted color, double-sided culling, no shadow, and no collision. Rebuild after entering the tree and global transform changes.
7. Rebuild the existing output slots unchanged.

If a texture is missing or malformed, warn once and omit only the ground visual; still return valid output slots and successful configuration.

**Step 4: Preserve API compatibility without fence behavior**

- `set_construction_stage(stage)` only clamps/stores the stage.
- `set_interaction_enabled(enabled)` is a no-op because ground is always walkable.
- `has_enabled_collisions()` always returns `false`.
- `get_collision_layers()` always returns `[]`.
- Keep `get_fence_segment_count()` returning `0` temporarily for callers/tests that use the legacy cleanup query.
- Keep `get_transition_sprite_count()` returning `0` and `advance_transition_for_test()` as a no-op until all callers are migrated.
- Add `get_ground_visual_count()` and `get_ground_size()` for observable testing/debugging.
- `clear_immediately()` removes the ground mesh immediately and clears output slots.

**Step 5: Apply preview tint only**

`get_visual_tint()` returns green/red RGB with alpha `1.0` for active preview and white otherwise. `set_maintenance_state()` retains the state for compatibility but does not modify the ground. Apply tint through the material albedo color so the texture's authored alpha is not multiplied down a second time.

**Step 6: Run focused tests and confirm GREEN**

Run the building suite and the core world suite:

```powershell
& $godot --headless --path . --script res://tests/run_building_system_tests.gd
& $godot --headless --path . --script res://tests/run_tests.gd
```

Expected: all production-yard, building integration, and terrain assertions pass.

**Step 7: Commit runtime implementation**

```powershell
git add scripts/buildings/building_production_yard.gd scripts/world/terrain_builder.gd
git commit -m "feat: project painted ground beneath production buildings"
```

### Task 4: Remove obsolete fence assets and language

**Files:**
- Delete: `assets/buildings/yards/timber_yard_fence.png`
- Delete: `assets/buildings/yards/timber_yard_fence.png.import`
- Delete: `assets/buildings/yards/masonry_yard_fence.png`
- Delete: `assets/buildings/yards/masonry_yard_fence.png.import`
- Delete: `assets/buildings/yards/industrial_yard_fence.png`
- Delete: `assets/buildings/yards/industrial_yard_fence.png.import`
- Modify as discovered: fence-specific test messages or comments in production-yard consumers

**Step 1: Prove old assets are no longer referenced**

Run:

```powershell
rg -n "yard_fence|FenceCollisions|BackFenceLayer|SideFenceLayer|FrontFenceLayer|fence segment|fence atlas" scripts tests docs
```

Update current code/test wording that still describes the production ground as a fence. Historical design/plan documents may retain history, but executable code and active tests must not.

**Step 2: Delete the obsolete PNGs and imports**

Remove exactly the six listed fence files. Do not touch unrelated yard or building art.

**Step 3: Reimport and verify no missing-resource errors**

Launch the project headlessly, rerun the building suite, and inspect stderr for missing `yard_fence` resource messages.

**Step 4: Commit cleanup**

```powershell
git add -A assets/buildings/yards scripts tests
git commit -m "chore: remove obsolete production yard fences"
```

### Task 5: Final verification and branch handoff

**Files:**
- Verify only; no planned source changes

**Step 1: Run all relevant test entry points**

At minimum:

```powershell
& $godot --headless --path . --script res://tests/run_tests.gd
& $godot --headless --path . --script res://tests/run_building_system_tests.gd
& $godot --headless --path . --script res://tests/run_building_economy_ui_tests.gd
```

If the repository exposes additional `tests/run_*tests.gd` entry points touched by building/economy integration, run those too.

**Step 2: Run a full project parse/import check**

```powershell
& $godot --headless --path . --editor --quit
```

Expected: exit 0, no parser errors, no missing ground resources, and no `Class hides a global script class` errors.

**Step 3: Inspect the final diff and asset set**

Confirm:

- only the three new ground PNGs/imports remain under `assets/buildings/yards`;
- no fence or perimeter collision creation remains;
- the terrain retains its standard visual layer and the ground uses no unsupported Decal;
- output slots/save-facing APIs are unchanged;
- unrelated pre-existing untracked `.uid` files remain untouched.

**Step 4: Commit any verification-only corrections**

If verification required fixes, make a narrowly scoped final commit. Otherwise do not create an empty commit.

**Step 5: Report outcome**

Report changed runtime behavior, asset families, test counts/commands, commits created, current branch, and any remaining known warning that predates this work.
