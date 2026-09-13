"""Convert mawais' legacy Blender tree into a standalone Godot preview.

Blender --background --disable-autoexec --python scripts/tools/build_mawais_tree_preview.py
The original source is preserved. This is a full-detail material/import probe,
not a replacement for the game's instanced, wind-enabled LOD trees.
"""
import bpy,json
from pathlib import Path
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/models/vegetation/mawais_tree'
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'art/blender/import/Tree/tree.blend'),use_scripts=False)
source=bpy.data.objects['trunk']
mesh=bpy.data.meshes.new_from_object(source.evaluated_get(bpy.context.evaluated_depsgraph_get()))
points=[source.matrix_world@v.co for v in mesh.vertices]
low=min(p.z for p in points);high=max(p.z for p in points)
base=[p for p in points if p.z<low+(high-low)*.015]
origin=Vector((sum(p.x for p in base)/len(base),sum(p.y for p in base)/len(base),low))
for vertex,point in zip(mesh.vertices,points):vertex.co=(point-origin)*6/(high-low)
for obj in list(bpy.data.objects):bpy.data.objects.remove(obj,do_unlink=True)
tree=bpy.data.objects.new('MawaisTree',mesh);bpy.context.collection.objects.link(tree)
bpy.context.view_layer.objects.active=tree;tree.select_set(True)
# Legacy texture slots have no glTF equivalent; provide explicit UVs and PBR nodes.
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.cube_project(cube_size=1.4,correct_aspect=False)
bpy.ops.object.mode_set(mode='OBJECT')
bark=bpy.data.images['brown_bumpy.jpg']
(OUT/'bark.jpg').write_bytes(bytes(bark.packed_file.data))
bark=bpy.data.images.load(str(OUT/'bark.jpg'),check_existing=False)
material_indices=[p.material_index for p in mesh.polygons]
mesh.materials.clear()
for name,color in [('Bark',(1,1,1,1)),('Leaves',(.059,.1424,.0084,1))]:
    material=bpy.data.materials.new(name);material.use_nodes=True
    material.diffuse_color=color;material.use_backface_culling=False
    p=material.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=color
    p.inputs['Roughness'].default_value=.9
    if name=='Bark':
        image=material.node_tree.nodes.new('ShaderNodeTexImage');image.image=bark
        material.node_tree.links.new(image.outputs['Color'],p.inputs['Base Color'])
    mesh.materials.append(material)
for polygon,index in zip(mesh.polygons,material_indices):polygon.material_index=index
mesh.calc_loop_triangles()
report={'source':'Tree by mawais / Blend Swap 72376','license':'CC BY 3.0',
        'triangles':len(mesh.loop_triangles),'vertices':len(mesh.vertices),
        'height_m':6,'materials':2,'texture':'bark.jpg',
        'note':'Full-detail standalone preview; generated box UVs replace legacy texture mapping. No wind, collision or manual LODs yet.'}
(OUT/'model_report.json').write_text(json.dumps(report,indent=2)+'\n')
bpy.ops.export_scene.gltf(filepath=str(OUT/'tree.glb'),export_format='GLB',use_selection=True,
    export_animations=False,export_cameras=False,export_lights=False,export_materials='EXPORT')
print('TREE PREVIEW',json.dumps(report))
