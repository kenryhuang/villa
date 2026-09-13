# Tree — mawais

Source: `art/blender/import/Tree/tree.blend`, Blend Swap asset 72376.
Author: **mawais**. License: **Creative Commons Attribution 3.0**.
Original listing: http://www.blendswap.com/blends/view/72376
License: https://creativecommons.org/licenses/by/3.0/
Original bundled license: `art/blender/import/Tree/72376 - Tree - License.html`.

Villa adaptation: isolate the tree from its presentation scene, evaluate the
displacement/subdivision modifiers, normalize its base and height to 6 metres,
replace legacy materials with PBR materials, extract the packed bark image and
generate box-projected UVs. This is a material conversion, not an exact recreation
of the old Blender render. Leaves retain their mesh geometry and source colour.

Rebuild using Blender with `--background --disable-autoexec --python
scripts/tools/build_mawais_tree_preview.py`. See `model_report.json` for counts.
The GLB embeds its bark texture; `bark.jpg` is also retained for editing.

Open `scenes/preview/mawais_tree_preview.tscn` and press F6. Existing orbit,
zoom and turntable controls are shared with the tree preview. The farmer shows
scale. This standalone preview displays the static model.

## Three trees in the farm

`scenes/vegetation/mawais_tree.tscn` wraps the model with material-preserving wind,
player/trunk collision (layer 1) and camera/golf crown collision (layer 4).
Three existing core sites in `scenes/farm3d/main.tscn` now use it:

| Site | World X/Z | Scale | Height |
| --- | --- | --- | --- |
| OakA, west | -8 / -5 | 0.92 | 5.52 m |
| OakD, east | 10 / 5 | 0.86 | 5.16 m |
| OakF, north | 5 / -14 | 0.94 | 5.64 m |

Positions, rotations, scales, grid reservations and total tree count (34) are
preserved. The other 31 trees keep their existing models. The three instances
share meshes and wind materials; Godot's imported mesh LODs remain enabled,
with a 150 m visual cutoff. No custom manual LOD meshes are authored yet.

Validation: 37 trial-tree checks pass, including physics ray hits, navigation,
land reservations, shared meshes and textured wind materials. The full world
suite reports 862 checks / 29 failures in existing tree-root slope checks;
the unmodified baseline also reports the same 29 root failures (877 checks).
GPU captures of all three sites have no shader errors, under `docs/validation/mawais-tree/`.
