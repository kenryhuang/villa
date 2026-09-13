"""Blender regression check: one connected trouser shell, not intersecting tubes."""
import sys
from pathlib import Path
import bpy
import bmesh
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts/tools'))
import build_village_characters as village
from player_garments import trousers

bpy.ops.wm.read_factory_settings(use_empty=True)
village.PARTS=[];village.MAT=village.atlas()
obj=trousers(village)
bm=bmesh.new();bm.from_mesh(obj.data)
remaining=set(bm.faces);components=0
while remaining:
    components+=1;pending=[remaining.pop()]
    while pending:
        face=pending.pop()
        for edge in face.edges:
            for other in edge.link_faces:
                if other in remaining:remaining.remove(other);pending.append(other)
assert components==1, f'Trousers have {components} separate surfaces'
assert all(e.is_boundary or e.is_manifold for e in bm.edges), 'Crotch contains internal or nonmanifold faces'
boundary={v for e in bm.edges if e.is_boundary for v in e.verts};openings=0
while boundary:
    openings+=1;pending=[boundary.pop()]
    while pending:
        vertex=pending.pop()
        for edge in vertex.link_edges:
            if not edge.is_boundary:continue
            other=edge.other_vert(vertex)
            if other in boundary:boundary.remove(other);pending.append(other)
assert openings==3, f'Expected only the waist and two hems; found {openings} openings'
print('Player garments: single connected trouser shell, manifold crotch, waist and two hem openings')
bm.free()
