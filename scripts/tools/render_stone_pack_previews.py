"""Inspect and render packed stone assets without saving/modifying the source blend.

Blender --background --disable-autoexec --python scripts/tools/render_stone_pack_previews.py
Previews use original base meshes/albedo plus approximate height-map bump,
not the legacy Cycles microdisplacement shader or exported Godot materials.
"""
from pathlib import Path
from mathutils import Vector
import bpy
import bmesh
import hashlib
import json
import math

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'art/blender/import/Stone Pack 1 photoscanned/stone_pack_01.blend'
OUT = ROOT / 'docs/validation/stone-pack-previews'
OUT.mkdir(parents=True, exist_ok=True)
source_hash = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(SOURCE), use_scripts=False)
scene = bpy.context.scene
stones = [bpy.data.objects[f'stone_{index:02d}'] for index in range(1, 5)]
report = {'source': str(SOURCE.relative_to(ROOT)), 'source_version': list(bpy.data.version),
          'source_sha256': source_hash, 'unit_system': scene.unit_settings.system,
          'unit_scale': scene.unit_settings.scale_length, 'stones': [],
          'preview_material': 'Original albedo + roughness 0.90 + approximate height bump; no subdivision/displacement.'}

for obj in stones:
    obj.data.calc_loop_triangles()
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    boundary = [edge for edge in bm.edges if edge.is_boundary]
    modifiers = [{'type': mod.type, 'levels': getattr(mod, 'levels', None),
                  'render_levels': getattr(mod, 'render_levels', None),
                  'viewport': mod.show_viewport, 'render': mod.show_render}
                 for mod in obj.modifiers]
    row = {'name': obj.name, 'base_triangles': len(obj.data.loop_triangles),
           'dimensions': list(obj.dimensions), 'modifiers': modifiers,
           'boundary_edges': len(boundary),
           'boundary_z_range': [min(vertex.co.z for edge in boundary for vertex in edge.verts),
                                max(vertex.co.z for edge in boundary for vertex in edge.verts)] if boundary else [],
           'nonmanifold_edges_excluding_boundary': sum(not edge.is_manifold and not edge.is_boundary for edge in bm.edges),
           'loose_vertices': sum(not vertex.link_edges for vertex in bm.verts),
           'degenerate_faces': sum(face.calc_area() < 1e-12 for face in bm.faces),
           'uv_layers': [uv.name for uv in obj.data.uv_layers],
           'adaptive_subdivision': getattr(obj.cycles, 'use_adaptive_subdivision', None)}
    bm.free()
    report['stones'].append(row)
    obj.modifiers.clear()
    mat = bpy.data.materials.new(obj.name + ' review PBR')
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Roughness'].default_value = .90
    shader.inputs['Specular IOR Level'].default_value = .20
    color = mat.node_tree.nodes.new('ShaderNodeTexImage')
    color.image = bpy.data.images[obj.name + '_tex']
    mat.node_tree.links.new(color.outputs['Color'], shader.inputs['Base Color'])
    height = mat.node_tree.nodes.new('ShaderNodeTexImage')
    height.image = bpy.data.images[obj.name + '_disp']
    height.image.colorspace_settings.name = 'Non-Color'
    bump = mat.node_tree.nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = .25
    bump.inputs['Distance'].default_value = .012
    mat.node_tree.links.new(height.outputs['Color'], bump.inputs['Height'])
    mat.node_tree.links.new(bump.outputs['Normal'], shader.inputs['Normal'])
    obj.data.materials.clear()
    obj.data.materials.append(mat)

for obj in list(bpy.data.objects):
    if obj not in stones:
        bpy.data.objects.remove(obj, do_unlink=True)

scene.render.engine = 'CYCLES'
scene.cycles.samples = 32
scene.cycles.use_denoising = True
try:
    prefs = bpy.context.preferences.addons['cycles'].preferences
    prefs.compute_device_type = 'OPTIX'
    prefs.get_devices()
    enabled = False
    for device in prefs.devices:
        device.use = device.type == 'OPTIX'
        enabled = enabled or device.use
    scene.cycles.device = 'GPU' if enabled else 'CPU'
except Exception:
    scene.cycles.device = 'CPU'
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.film_transparent = False
scene.render.use_compositing = False
scene.view_settings.view_transform = 'AgX'
scene.view_settings.look = 'AgX - Medium High Contrast'
scene.view_settings.exposure = 0
scene.world = bpy.data.worlds.new('Stone review world')
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (.72, .78, .84, 1)
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value = .5

bpy.ops.object.light_add(type='AREA', location=(-3, -4, 6))
light = bpy.context.object
light.data.energy = 650
light.data.shape = 'DISK'
light.data.size = 5
light.rotation_euler = (-light.location).to_track_quat('-Z', 'Y').to_euler()
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.002))
floor = bpy.context.object
floor.name = 'Review floor (not part of assets)'
floor_mat = bpy.data.materials.new('Review floor matte')
floor_mat.diffuse_color = (.30, .34, .29, 1)
floor.data.materials.append(floor_mat)
bpy.ops.object.camera_add()
camera = bpy.context.object
camera.data.type = 'ORTHO'
scene.camera = camera


def place(obj, x, y):
    bpy.context.view_layer.update()
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    lo = Vector([min(point[axis] for point in points) for axis in range(3)])
    hi = Vector([max(point[axis] for point in points) for axis in range(3)])
    obj.location += Vector((x - (lo.x + hi.x) / 2, y - (lo.y + hi.y) / 2, -lo.z))
    bpy.context.view_layer.update()


def render(name, location, target, scale, width, height):
    camera.location = location
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat('-Z', 'Y').to_euler()
    camera.data.ortho_scale = scale
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.filepath = str(OUT / name)
    bpy.ops.render.render(write_still=True)


for obj in stones:
    place(obj, 0, 0)
    for other in stones:
        other.hide_render = other != obj
    size = max(obj.dimensions.x, obj.dimensions.y)
    render(obj.name + '.png', (2, -3, 2.3), (0, 0, obj.dimensions.z * .35), size * 1.6, 1100, 900)

labels = []
label_mat = bpy.data.materials.new('Readable labels')
label_mat.use_nodes = True
label_mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (.025, .035, .025, 1)
for obj, (x, y) in zip(stones, [(-.85, .9), (.85, .9), (-.85, -.9), (.85, -.9)]):
    obj.hide_render = False
    place(obj, x, y)
    bpy.ops.object.text_add(location=(x, y - .72, .008))
    label = bpy.context.object
    label.data.body = obj.name
    label.data.align_x = 'CENTER'
    label.data.size = .13
    label.data.materials.append(label_mat)
    labels.append(label)
render('overview.png', (0, -5, 7), (0, 0, .05), 4.0, 1500, 1500)
for obj, (x, y) in zip(stones, [(-.85, .9), (.85, .9), (-.85, -.9), (.85, -.9)]):
    obj.rotation_euler.x += math.pi
    place(obj, x, y)
render('undersides.png', (0, -5, 7), (0, 0, .05), 4.0, 1500, 1500)

report['source_unchanged'] = hashlib.sha256(SOURCE.read_bytes()).hexdigest() == source_hash
assert report['source_unchanged'], 'Source blend unexpectedly changed'
(OUT / 'review.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('STONE_REVIEW ' + json.dumps(report), flush=True)
