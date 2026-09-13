# T1 pine tree import assessment

Source: `art/blender/import/Trees/t1.blend`, containing BlenderKit **A tree**
by **Toby Noby**. The embedded metadata declares `royalty_free` (asset base ID
`b7c9b16a-4be0-429f-8716-072153107219`, asset version ID
`8b4d3452-acae-4828-9281-0831c264547f`). This is a separate asset from Baum3 and
the mawais tree; their Blend Swap license files do not describe this model.

The original source is preserved. The current derivative removes the bottom three
branch whorls and one further mid/lower primary branch, including their smaller
branch families and attached needles. Three instances now replace existing core
tree sites in the formal farm scene, alongside the standalone preview.

| Farm site (x, z) | Scale | Height |
| --- | ---: | ---: |
| West (-10, 2) | 0.90 | 5.4 m |
| Northeast (12, -9) | 1.00 | 6.0 m |
| North (-5, -12) | 0.95 | 5.7 m |

`scenes/vegetation/t1_tree.tscn` retains the imported materials and shared meshes.
The trunk blocks players on layer 1; the crown uses camera/golf layer 4.
Existing core-site grid reservations continue to block NPC paths through trunks.
The total world tree count stays 34: 28 established trees, three mawais trials,
and three T1 pines. Trial integration checks pass (71 checks); world captures are
`docs/validation/t1-tree/world-west.png`, `world-east.png`, and `world-north.png`.

| Part | Original triangles | Pruned triangles |
| --- | ---: | ---: |
| Trunk and branches | 205,568 | 43,678 |
| Needle leaves | 425,560 | 121,064 |
| Total | 631,128 | 164,742 |

The reduction is 73.9%. Eleven of 35 primary branches are removed; branches of all
orders fall from 2,351 to 1,277. The lowest remaining primary attachment is 2.25 m
above the base. Needles fall from 212,780 to 60,532, with surviving needle widths
increased 18% while preserving their length. Upper-crown retention is higher
than lower-crown retention. Branch tube geometry is decimated after pruning.

Original world-space height is about 5.56 m; the preview is normalized to 6 m
with its origin at the trunk base. Four packed 2048×2048 bark images are complete.
Albedo, normal and roughness maps are exported, with the authored UV scale baked
into the UV coordinates. The disconnected needle quads receive deterministic
vertex colours between the source shader's two colours. Original translucent
shading and procedural displacement are not exported.

`scripts/tools/import_t1_tree.gd` supplies a two-sided wrapped-diffuse needle
shader and explicitly handles glTF's linear vertex colours for Compatibility.
Godot's default imported material had not enabled vertex colours; using those
linear values directly in Compatibility also produced an excessively dark result.
The shader checks `OUTPUT_IS_SRGB` when choosing the encoding.

Rebuild with Blender:

```powershell
blender.exe --factory-startup --background --disable-autoexec --python scripts/tools/build_t1_tree_preview.py
```

The pruning logic is in `scripts/tools/prune_t1_tree.py`. The editable derivative
is `art/blender/t1_tree_pruned.blend`, with packed working textures and source
metadata. Append `-- --full-detail` to regenerate the original full-detail
conversion instead. The previous GLB and preview are backed up locally under
`tmp/t1-before-pruning/`.

Open `scenes/preview/t1_tree_preview.tscn` and press F6. Right drag orbits, the
wheel zooms, and Space toggles the turntable. GPU capture:

```powershell
godot_console.exe --path . scenes/preview/t1_tree_preview.tscn -- --capture-preview=res://docs/validation/t1-tree/front.png --view=front
```

Godot import and GPU rendering were verified without errors. Pruned front/side
captures and a comparison under identical lighting are in
`docs/validation/t1-tree/`. The exported GLB retains needle colours and the bark's
three PBR maps. Dense map placement still needs LOD evaluation; wind has not been
added to this model. No frame-rate claim is made from a static
capture; the fine needle silhouette still needs motion/LOD evaluation.
