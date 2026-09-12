"""Render the original Baum3 trees for art review; never saves the source blend.
Blender --background --disable-autoexec --python scripts/tools/render_baum3_previews.py
"""
from pathlib import Path
from mathutils import Vector
import bpy
import json
import math
import sys
from collections import Counter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/validation/baum3-previews'
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ROOT / 'art/blender/import/Trees/Baum3.blend'), use_scripts=False)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 32
scene.cycles.use_denoising = True
try:
    prefs = bpy.context.preferences.addons['cycles'].preferences
    prefs.compute_device_type = 'OPTIX'
    prefs.get_devices()
    for device in prefs.devices: device.use = device.type == 'OPTIX'
    scene.cycles.device = 'GPU'
except Exception:
    scene.cycles.device = 'CPU'
scene.render.resolution_x = 1600
scene.render.resolution_y = 1100
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.film_transparent = False
scene.view_settings.view_transform = 'AgX'
scene.view_settings.look = 'AgX - Medium High Contrast'
scene.world = bpy.data.worlds.new('Review daylight')
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (.72, .80, .87, 1)
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value = .45

# Legacy Blender Internal materials cannot be reproduced exactly in Cycles.
# Rebuild opaque matte materials from stored original diffuse colors only.
for mat in bpy.data.materials:
    color = tuple(mat.diffuse_color)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    output = nodes.new('ShaderNodeOutputMaterial')
    shader = nodes.new('ShaderNodeBsdfPrincipled')
    shader.inputs['Base Color'].default_value = color
    shader.inputs['Roughness'].default_value = .88
    shader.inputs['Specular IOR Level'].default_value = .18
    mat.node_tree.links.new(shader.outputs['BSDF'], output.inputs['Surface'])

groups = [('A', ['tree', 'tree.001']), ('B', ['tree.002', 'tree.003'])]
trees = {name: bpy.data.objects[name] for _, names in groups for name in names}
for obj in list(bpy.data.objects):
    if obj.type in {'CAMERA', 'LIGHT'} or obj.name == 'Plane':
        bpy.data.objects.remove(obj, do_unlink=True)

def bounds(objects):
    coords = [obj.matrix_world @ Vector(v) for obj in objects for v in obj.bound_box]
    return (Vector([min(v[a] for v in coords) for a in range(3)]),
            Vector([max(v[a] for v in coords) for a in range(3)]))

report = []
for label, names in groups:
    objects = [trees[name] for name in names]
    lo, hi = bounds(objects)
    report.append({'label': label, 'objects': names, 'bounds': [list(lo), list(hi)],
                   'particle_settings': [{'object': obj.name, 'count': p.settings.count,
                       'render_children': p.settings.rendered_child_count,
                       'leaf_object': p.settings.instance_object.name} for obj in objects for p in obj.particle_systems]})

for obj in trees.values():
    for p in obj.particle_systems:
        # Original render density, never the reduced viewport preview density.
        p.settings.child_percent = p.settings.rendered_child_count

bpy.ops.object.light_add(type='SUN', location=(0, -10, 25))
sun = bpy.context.object
sun.rotation_euler = (math.radians(28), math.radians(-25), math.radians(-25))
sun.data.energy = 2.0
sun.data.angle = math.radians(8)
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.035))
ground = bpy.context.object
ground.name = 'Review floor'
mat = bpy.data.materials.new('Neutral sage ground')
mat.diffuse_color = (.29, .36, .29, 1)
ground.data.materials.append(mat)
bpy.ops.object.camera_add()
camera = bpy.context.object
scene.camera = camera
camera.data.type = 'ORTHO'
camera.data.lens = 50
camera.data.clip_end = 500

def render(name, target, span, angle=0, pitch=12):
    target = Vector(target)
    angle, pitch = math.radians(angle), math.radians(pitch)
    camera.location = target + Vector((math.sin(angle)*math.cos(pitch), -math.cos(angle)*math.cos(pitch), math.sin(pitch))) * 65
    camera.rotation_euler = (target-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.ortho_scale = span
    scene.render.filepath = str(OUT / (name+'.png'))
    print('RENDER_START', name, flush=True)
    bpy.ops.render.render(write_still=True)
    print('RENDER_DONE', name, flush=True)

def select_group(names):
    for name, obj in trees.items(): obj.hide_render = name not in names

# Original relative dimensions are kept in overview and individual views.
select_group(list(trees))
lo, hi = bounds(list(trees.values()))
if '--comparison-only' not in sys.argv:
    render('01-original-pair', (lo+hi)*.5, max((hi.x-lo.x)*1.2, (hi.z-lo.z)*1.7), 0)
    for label, names in groups:
        select_group(names)
        lo, hi = bounds([trees[name] for name in names])
        center = (lo+hi)*.5
        render('02-tree-a' if label=='A' else '03-tree-b', center, (hi.z-lo.z)*1.65, -25 if label=='A' else 25)
        render('04-a-branch-detail' if label=='A' else '05-b-branch-detail', center+Vector((0,0,(hi.z-lo.z)*.15)), (hi.z-lo.z)*.70, 30)

select_group(list(trees))
bpy.context.scene.frame_set(1)
dg = bpy.context.evaluated_depsgraph_get()
instances = Counter(i.parent.name for i in dg.object_instances if i.is_instance and i.parent)
for record in report:
    record['evaluated_leaf_instances'] = sum(instances.get(name, 0) for name in record['objects'])

def normalize_group(objects, x):
    lo, hi = bounds([o for o in objects if o.type=='MESH'])
    base = Vector(((lo.x+hi.x)*.5, (lo.y+hi.y)*.5, lo.z))
    scale = 6 / (hi.z-lo.z)
    root = bpy.data.objects.new('Comparison placement', None)
    scene.collection.objects.link(root)
    collection = bpy.data.collections.new('Full original tree instance')
    for obj in objects:
        for old_collection in list(obj.users_collection): old_collection.objects.unlink(obj)
        collection.objects.link(obj)
    # Transform the entire evaluated collection including particle instances;
    # scaling the emitters themselves changes the apparent leaf distribution.
    root.instance_type = 'COLLECTION'
    root.instance_collection = collection
    root.scale = (scale,)*3
    root.location = Vector((x,0,0))-base*scale
    bpy.context.view_layer.update()

for index, (_, names) in enumerate(groups):
    normalize_group([trees[name] for name in names], -6 if index==0 else 0)
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=str(ROOT/'assets/models/vegetation/painted_oak.glb'))
oak = list(set(bpy.data.objects)-before)
normalize_group(oak, 6)
scene.render.resolution_x = 2100
scene.render.resolution_y = 1050
ground.scale = (10,10,10)
for x, title in [(-6,'A - Baum3 broadleaf'), (0,'B - Baum3 conifer'), (6,'Current painted oak')]:
    font = bpy.data.curves.new(title, 'FONT')
    font.body = title
    font.align_x = 'CENTER'
    font.size = .32
    text = bpy.data.objects.new(title, font)
    scene.collection.objects.link(text)
    text.location = (x,-2.5,.15)
    text.rotation_euler = (math.radians(78),0,0)
    material = bpy.data.materials.new(title)
    material.diffuse_color = (.055,.075,.06,1)
    material.use_nodes = True
    material.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (.055,.075,.06,1)
    text.data.materials.append(material)
render('06-same-light-oak-comparison', (0,0,2.8), 21, 0)

(OUT/'inspection.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf8')
print('BAUM3_PREVIEWS_COMPLETE', flush=True)
