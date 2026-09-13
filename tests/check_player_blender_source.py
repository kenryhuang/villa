"""Run in Blender: validate the editable player face through a bmesh round trip."""
from pathlib import Path
import bpy
import bmesh

ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'art/blender/characters/player.blend'),use_scripts=False)
body=bpy.data.objects['player body']
copy=body.data.copy()
before=[v.co.copy() for v in copy.shape_keys.key_blocks[0].data]
bm=bmesh.new();bm.from_mesh(copy);bm.to_mesh(copy);bm.free()
error=max((v.co-before[i]).length for i,v in enumerate(copy.shape_keys.key_blocks[0].data))
assert error<1e-6, f'A later topology edit discards the neutral facial sculpt: {error:.6f} m'
assert len(copy.shape_keys.key_blocks)==7, 'Keep Basis and six facial expressions'
uv=body.data.uv_layers.active
def landmark(u,v):
    loop=min(body.data.loops,key=lambda l:(uv.data[l.index].uv.x-u)**2+(uv.data[l.index].uv.y-v)**2)
    return body.data.shape_keys.key_blocks[0].data[loop.vertex_index].co
mouth=landmark(.750,.420)
corners=[landmark(.769,.429),landmark(.731,.429)]
for corner in corners:
    assert corner.z>mouth.z+.004, 'The neutral smile must survive the final clothing cut and export'
print('Player source: facial sculpt survives topology editing; six expressions and lifted smile corners retained')
