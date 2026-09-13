# 3D village characters

The player, Ahe, Lao Li and Scholar Lin use the same continuous facial topology,
eyes, mouth, hands and 55-bone deform rig as Yun. Their proportions, hair,
clothing and accessories are authored individually from the original 2D sheets.

The player and Ahe use independent body proportions. The player's current
revision lowers the hip joint to 0.90 m and the waist to 1.052 m within a
1.96 m silhouette, giving the torso more length and shortening both leg segments.
The body, garments, expression shapes and rest skeleton use the same remapping.
Ahe's proportions and facial geometry are preserved. The player's cheeks,
jaw, mouth corners, hair color and collar were revised with the proportions.

| Character | Appearance | Runtime asset |
| --- | --- | --- |
| Player | Approved concept: curved straw hat, rolled linen sleeves, blue overalls with turned hems, ankle boots, seed pouch | `../farm3d/player_farmer.glb` |
| 阿禾 | Olive kerchief and apron, wheat pocket, seed bag | `farmer_ahe.glb` |
| 老李 | Broader build and face, moustache, graying topknot, brown waistcoat, wine sash, ledger and coins | `lao_li.glb` |
| 学者林 | Slimmer build, brass spectacles, teal coat, field backpack, map and compass | `xuezhe_lin.glb` |
| 云姐 | Existing Sintel-derived cook, unchanged | `resident_yun.glb` |

Editable source files are in `art/blender/characters/`. The four rebuilt files
contain named meshes, painted materials, six facial expression shapes, the game
skeleton and Idle / Walk / Run / Work clips. Two exported mesh nodes per actor
keep the expressive face separate from joined clothing and accessories.

Rebuild from the repository root:

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --disable-autoexec --python scripts/tools/build_village_characters.py
```

Use `-- --character=lao_li` to rebuild one actor, or `-- --no-render` to skip
studio renders. The generator reads `resident_yun.blend` without executing
embedded scripts and never modifies Yun or the original licensed source.
Temporary exports and studio renders go to ignored `tmp/character-rebuild/`.

The player now follows [the approved concept sheet](../../../art/concepts/player/player-farmer-design.png).
Both the full-cast command and `-- --character=player` delegate to
`scripts/tools/build_player_concept.py`. That script can also run directly in
Blender with the same `--background --disable-autoexec --python` flags.
Its render goes to `tmp/player-concept/player.png`. The editable
`art/blender/characters/player.blend` embeds the concept as a viewport reference.
The player has 119,702 triangles, 55 bones, two skinned mesh nodes, seven material
surfaces and the four existing animation clips. Dedicated `player_concept_fabric.png`
`player_face_skin.png` and `player_hands_skin.png` avoid recoloring the NPC assets. The bare hand surface
retains the original finger weights; sleeves have a continuous shoulder surface.
The silhouette and clothing follow the concept, while the face retains the
existing Sintel-derived topology with a new neutral sculpt and freshly painted skin; it is not an exact reproduction
of the illustration's face or lighting.

`village_fabric.png` supplies brushed linen, denim, leather trim, hair and straw.
The five `resident_yun_Yun ... albedo.png` maps referenced by the rebuilt GLBs
are shared directly with Yun. Keep the external PNGs and their `.import`
settings with the GLBs. `model_report.json` records actual geometry and texture
dependencies. The previous face atlas is obsolete and removed.

Formal gameplay still loads the same model paths and character IDs. Existing
saves, NPC assets and decisions are unchanged. Tool poses use imported limb
lengths, wrist bones and curled fingers; walking, running and work use authored
animation clips. Ordinary movement is fixed at 3 m/s and Shift running at 6 m/s
(2×). Ordinary movement now uses a restrained light jog, keeping the clip name
Walk for runtime compatibility. `scripts/tools/player_locomotion.py` retargets
Quaternius Universal Animation Library motions onto the existing farmer rig,
then adapts foot contact, forward knee poles and rigid boot pivots to its proportions.
Walk is 1.2 seconds; Run is 0.8 seconds. Runtime playback uses measured contact
speeds of 1.73 / 4.34 m/s, independently of the fixed gameplay speeds.
The sampled source motions, CC0 license and rebuild instructions are in
[art/animations/player](../../../art/animations/player/README.md).
Root displacement is converted from world Z to the rig's local axes. The boot
sole is weighted to the foot, while only its shaft blends toward the shin.
Opening the shirt neck is restricted to the neck region so it cannot cut the
tops off the sleeves.

`player_face.py` synchronizes the sculpted Basis and mesh vertices before garment
cut-outs; otherwise bmesh silently overwrites the neutral sculpt. Front-face
morphs fade into the neck continuously, preventing a jagged jaw seam.
`scripts/tools/import_player.gd` gives the player's skin wrapped diffuse lighting
without hard received facial shadows. A separate denim material avoids broad
self-shadow bands from the Compatibility renderer; the character still casts
shadows onto the ground.

The abdomen is tapered in depth, with the same remap applied to the shirt, bib,
belt and straps. Shoulder caps have a round neckline and a wider weight transition
through the clavicles. `player_garments.py` builds one connected trouser surface
with a curved crotch seam, a rounded seat and waist-to-thigh weight blending.
Rear pockets project onto that final surface and inherit its deformation weights.
The garment topology check verifies one connected manifold shell with exactly
three openings: the waist and both trouser hems.

Locomotion couples restrained pelvis roll/yaw with forward pelvis/spine pitch
and shoulder counter-rotation. Source vertical travel is reduced without adding
a push-off bounce pulse. Waist-level shirt,
bib and strap vertices blend between pelvis and spine, keeping the two halves
connected. The foot solver runs after the body pose and limits vertical lift
only where a planted leg would otherwise exceed its reach.

Current validation: 449 player proportion/gait/sole-weight/physical-movement
checks and 271 character/tool checks pass. Support-knee flexion at loaded midstance
is about 21.3 degrees for the light jog, and pelvis vertical travel is 27 mm per cycle.
The tests
check actual deformed sole vertices for heel/sole/toe contact, not constant ankle
height. They also verify alternating support-hip elevation, pelvis rotation,
forward chest movement and continuous pelvis/torso animation loops.
`tests/check_player_blender_source.py` verifies the neutral facial sculpt
survives a topology round trip, with six expressions and raised mouth corners.
Visual captures show
[four views](../../../art/concepts/player/player-turnaround.png),
[eight walk frames](../../../art/concepts/player/player-walk-frames.png) and
[eight run frames](../../../art/concepts/player/player-run-frames.png).
The [walk](../../../art/concepts/player/player-walk.gif) and
[run](../../../art/concepts/player/player-run.gif) GIFs show continuous cycles
at gameplay speed, with stationary ground marks to expose foot sliding.
The [before/after comparison](../../../art/concepts/player/player-locomotion-compare.gif)
renders both versions at the same 3 m/s. After capturing, run
`python scripts/tools/encode_player_motion.py`; it reads the frame manifests so
old frames from longer captures cannot enter the current GIFs.

Validation:

```powershell
godot_console.exe --headless --path . --script tests/run_3d_character_tests.gd -- --farm-test
godot_console.exe --path . --script tests/run_3d_character_tests.gd -- --farm-test --capture-characters
godot_console.exe --headless --path . --script tests/run_player_gait_tests.gd
godot_console.exe --path . --script tests/capture_player_revision.gd -- --motion
blender.exe --background --disable-autoexec --python-exit-code 1 --python tests/check_player_blender_source.py
blender.exe --background --disable-autoexec --python-exit-code 1 --python tests/check_player_garments.py
```

The second command captures gameplay views in ignored
`docs/validation/character-rebuild/`, including both golf stances and fishing.
See [SINTEL_LICENSE.md](SINTEL_LICENSE.md) for the required original attribution.
