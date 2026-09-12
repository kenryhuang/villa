"""Build closed, lightweight stones and recover existing farm rock placements.
Run with Blender --background --disable-autoexec --python this_file.py.
The source scan and existing farm GLB are read only.
"""
from pathlib import Path
from mathutils import Vector
import bpy
import bmesh
import json
import hashlib

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/models/environment/scanned_stones'
OUT.mkdir(parents=True, exist_ok=True)
SOURCE = ROOT / 'art/blender/import/Stone Pack 1 photoscanned/stone_pack_01.blend'
ENV = ROOT / 'assets/models/farm3d/farm_environment.glb'
hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [SOURCE, ENV]}
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(ENV))
rock_mesh = next(o for o in bpy.data.objects if o.type == 'MESH')
bm = bmesh.new(); bm.from_mesh(rock_mesh.data)
rock_slots = {i for i, mat in enumerate(rock_mesh.data.materials) if mat.name == 'River stone'}
bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index not in rock_slots], context='FACES')
bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=.00001)
unseen = {v for v in bm.verts if v.link_faces}; placements = []
while unseen:
    stack = [unseen.pop()]; points = []
    while stack:
        v = stack.pop(); points.append(rock_mesh.matrix_world @ v.co)
        for edge in v.link_edges:
            other = edge.other_vert(v)
            if other in unseen: unseen.remove(other); stack.append(other)
    lo = Vector([min(p[a] for p in points) for a in range(3)])
    hi = Vector([max(p[a] for p in points) for a in range(3)])
    center = (lo + hi) / 2
    placements.append({'position': [round(center.x, 5), 0, round(-center.y, 5)],
                       'width': round(max(hi.x-lo.x, hi.y-lo.y), 5),
                       'large': max(hi.x-lo.x, hi.y-lo.y) > .7})
bm.free()
placements.sort(key=lambda r: (r['position'][0], r['position'][2]))
assert len(placements) == 58 and sum(p['large'] for p in placements) == 3, placements
(OUT/'placements.tres').write_text('[gd_resource type="Resource" format=3]\n\n[resource]\nmetadata/placements = '+json.dumps(placements, indent=2)+'\n', encoding='utf-8')

bpy.ops.wm.open_mainfile(filepath=str(SOURCE), use_scripts=False)
bpy.context.preferences.filepaths.save_version = 0
stones = [bpy.data.objects[f'stone_{i:02d}'] for i in range(1, 5)]
for obj in list(bpy.data.objects):
    if obj not in stones: bpy.data.objects.remove(obj, do_unlink=True)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'; scene.cycles.samples = 8
scene.render.bake.margin = 12
report = []

def select(obj):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True); bpy.context.view_layer.objects.active = obj

for index, obj in enumerate(stones):
    name = f'stone_{index+1:02d}'
    obj.modifiers.clear()
    obj.data.transform(obj.matrix_world); obj.matrix_world.identity()
    bm = bmesh.new(); bm.from_mesh(obj.data)
    # Trim the ragged scan skirt, including the photographed grass on stone 02.
    low = min(v.co.z for v in bm.verts); high = max(v.co.z for v in bm.verts)
    cut = low + (high-low) * (.18 if index == 1 else .11)
    cut = max(cut, max(v.co.z for e in bm.edges if e.is_boundary for v in e.verts) + .001)
    bmesh.ops.bisect_plane(bm, geom=list(bm.verts)+list(bm.edges)+list(bm.faces),
                          dist=.000001, plane_co=(0,0,cut), plane_no=(0,0,1), clear_inner=True)
    bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=0)
    bmesh.ops.delete(bm, geom=[e for e in bm.edges if not e.link_faces], context='EDGES')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data); bm.free()
    select(obj)
    obj.data.calc_loop_triangles()
    mod = obj.modifiers.new('Game mesh budget', 'DECIMATE')
    mod.ratio = min(1, 3000 / len(obj.data.loop_triangles)); mod.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=mod.name)
    points = [v.co for v in obj.data.vertices]
    lo = Vector([min(p[a] for p in points) for a in range(3)])
    hi = Vector([max(p[a] for p in points) for a in range(3)])
    origin = Vector(((lo.x+hi.x)/2, (lo.y+hi.y)/2, lo.z))
    for v in obj.data.vertices: v.co = (v.co-origin) * (2/max(hi.x-lo.x, hi.y-lo.y))
    for face in obj.data.polygons: face.use_smooth = True
    original_uv = obj.data.uv_layers.active.name
    obj.data.uv_layers.new(name='GameUV')
    obj.data.uv_layers.active_index = len(obj.data.uv_layers)-1
    obj.data.uv_layers.active.active_render = True
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(island_margin=.025)
    bpy.ops.object.mode_set(mode='OBJECT')
    mat = bpy.data.materials.new(name+' baked matte'); mat.use_nodes = True
    obj.data.materials.clear(); obj.data.materials.append(mat)
    nodes = mat.node_tree.nodes; links = mat.node_tree.links
    shader = nodes.get('Principled BSDF'); output = nodes.get('Material Output')
    uv = nodes.new('ShaderNodeUVMap'); uv.uv_map = original_uv
    tex = nodes.new('ShaderNodeTexImage'); tex.image = bpy.data.images[name+'_tex']
    links.new(uv.outputs['UV'], tex.inputs['Vector'])
    hue = nodes.new('ShaderNodeHueSaturation'); hue.inputs['Saturation'].default_value = .78
    links.new(tex.outputs['Color'], hue.inputs['Color'])
    mix = nodes.new('ShaderNodeMixRGB'); mix.inputs[0].default_value = .12
    mix.inputs[2].default_value = (.42,.38,.29,1); links.new(hue.outputs['Color'],mix.inputs[1])
    emission = nodes.new('ShaderNodeEmission'); links.new(mix.outputs[0],emission.inputs[0])
    links.new(emission.outputs[0],output.inputs['Surface'])
    color = bpy.data.images.new(name+'_albedo', width=1024, height=1024)
    target = nodes.new('ShaderNodeTexImage'); target.image = color; nodes.active = target
    bpy.ops.object.bake(type='EMIT')
    color.pack()
    links.new(shader.outputs[0],output.inputs['Surface'])
    height = nodes.new('ShaderNodeTexImage'); height.image = bpy.data.images[name+'_disp']
    height.image.colorspace_settings.name = 'Non-Color'; links.new(uv.outputs['UV'],height.inputs['Vector'])
    bump = nodes.new('ShaderNodeBump'); bump.inputs['Strength'].default_value = .16
    bump.inputs['Distance'].default_value = .015
    links.new(height.outputs['Color'],bump.inputs['Height']); links.new(bump.outputs['Normal'],shader.inputs['Normal'])
    normal = bpy.data.images.new(name+'_normal', width=1024, height=1024)
    normal.colorspace_settings.name = 'Non-Color'; target.image = normal; nodes.active = target
    bpy.ops.object.bake(type='NORMAL')
    normal.pack()
    nodes.clear(); shader=nodes.new('ShaderNodeBsdfPrincipled'); output=nodes.new('ShaderNodeOutputMaterial')
    shader.inputs['Roughness'].default_value=.94
    shader.inputs['Specular IOR Level'].default_value=.18
    links.new(shader.outputs['BSDF'],output.inputs['Surface'])
    tex=nodes.new('ShaderNodeTexImage'); tex.image=color; links.new(tex.outputs['Color'],shader.inputs['Base Color'])
    tex=nodes.new('ShaderNodeTexImage'); tex.image=normal
    mapping=nodes.new('ShaderNodeNormalMap'); links.new(tex.outputs['Color'],mapping.inputs['Color'])
    links.new(mapping.outputs['Normal'],shader.inputs['Normal'])
    obj.data.uv_layers.remove(obj.data.uv_layers[original_uv])
    obj.name='Rock'; obj.data.calc_loop_triangles()
    large_count=len(obj.data.loop_triangles)
    pebble=obj.copy(); pebble.data=obj.data.copy(); scene.collection.objects.link(pebble); pebble.name='Pebble'
    select(pebble)
    mod=pebble.modifiers.new('Pebble budget','DECIMATE'); mod.ratio=140/large_count; mod.use_collapse_triangulate=True
    bpy.ops.object.modifier_apply(modifier=mod.name)
    pebble.data.calc_loop_triangles()
    for variant in [obj,pebble]:
        bm=bmesh.new(); bm.from_mesh(variant.data)
        assert all(e.is_manifold for e in bm.edges), name+' '+variant.name+' has non-manifold edges: '+str([(len(e.link_faces)) for e in bm.edges if not e.is_manifold])
        bm.free()
    record={'id':name,'triangles':large_count,'pebble_triangles':len(pebble.data.loop_triangles), 'closed':True}
    select(obj); pebble.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')), export_format='GLB', use_selection=True,
                             export_animations=False,export_cameras=False,export_lights=False)
    record['bytes']=(OUT/(name+'.glb')).stat().st_size; report.append(record)
    # Side-by-side editable source; export variants overlap only inside each GLB.
    obj.location.x=index*3; pebble.location=(index*3,3,0)

bpy.data.orphans_purge(do_recursive=True)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/blender/scanned_stones.blend'))
for path, before in hashes.items(): assert hashlib.sha256(Path(path).read_bytes()).hexdigest()==before
(OUT/'model_report.json').write_text(json.dumps({'models':report,'placements':len(placements),'source_hashes':hashes},indent=2)+'\n',encoding='utf-8')
print('SCANNED STONES COMPLETE',json.dumps(report),flush=True)
