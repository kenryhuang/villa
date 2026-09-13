"""Pruned Godot adaptation of the BlenderKit 'A tree' in t1.blend.

Run Blender with --factory-startup --background --disable-autoexec --python
scripts/tools/build_t1_tree_preview.py. Pass -- --full-detail for the unpruned
conversion; the original source file is never overwritten.
"""
import bpy,json,sys
import numpy as np
from pathlib import Path
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
from prune_t1_tree import prune_tree

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/models/vegetation/t1_tree'
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'art/blender/import/Trees/t1.blend'),use_scripts=False)
asset=bpy.data.objects['A tree']['asset_data']
metadata={k:str(asset.get(k)) for k in ['name','id','assetBaseId','license']}
author=asset.get('author',{})
metadata['author']={k:str(author.get(k)) for k in ['id','firstName','lastName','fullName'] if k in author}
images={}
for kind in ['BaseColor','Normal','Roughness','Displacement']:
    source=bpy.data.images['Moss Bark_'+kind+'.jpg']
    path=OUT/('bark_'+kind.lower()+'.jpg')
    path.write_bytes(bytes(source.packed_file.data))
    images[kind]=bpy.data.images.load(str(path),check_existing=False)
    if kind!='BaseColor':images[kind].colorspace_settings.name='Non-Color'

source_bark=bpy.data.materials['Moss Bark.004']
uv_scale=next(n for n in source_bark.node_tree.nodes if n.type=='MAPPING' and n.inputs['Scale'].default_value.x>2).inputs['Scale'].default_value.copy()
leaf_mix=bpy.data.materials['Material.003'].node_tree.nodes['Mix']
colors=[list(s.default_value) for s in leaf_mix.inputs if s.type=='RGBA']
objects=[]
for source_name,name in [('tree','Trunk'),('leaves.002','Leaves')]:
    source=bpy.data.objects[source_name]
    mesh=bpy.data.meshes.new_from_object(source.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    mesh.transform(source.matrix_world)
    obj=bpy.data.objects.new('T1_'+name,mesh)
    objects.append(obj)
points=[v.co for obj in objects for v in obj.data.vertices]
low=min(p.z for p in points);high=max(p.z for p in points)
base=[v.co for v in objects[0].data.vertices if v.co.z<low+(high-low)*.015]
origin=Vector((sum(p.x for p in base)/len(base),sum(p.y for p in base)/len(base),low))
for obj in objects:
    for v in obj.data.vertices:v.co=(v.co-origin)*6/(high-low)
for obj in list(bpy.context.scene.objects):bpy.data.objects.remove(obj,do_unlink=True)
for obj in objects:
    bpy.context.collection.objects.link(obj)
    obj.select_set(True)
    obj.data.materials.clear()

bark=bpy.data.materials.new('T1 Moss Bark');bark.use_nodes=True
p=bark.node_tree.nodes.get('Principled BSDF')
p.inputs['Specular IOR Level'].default_value=.15
for kind,socket in [('BaseColor','Base Color'),('Roughness','Roughness'),('Normal','Normal')]:
    image=bark.node_tree.nodes.new('ShaderNodeTexImage');image.image=images[kind]
    output=image.outputs['Color']
    if kind=='Normal':
        normal=bark.node_tree.nodes.new('ShaderNodeNormalMap')
        bark.node_tree.links.new(output,normal.inputs['Color']);output=normal.outputs['Normal']
    bark.node_tree.links.new(output,p.inputs[socket])
objects[0].data.materials.append(bark)
for uv in objects[0].data.uv_layers.active.data:
    uv.uv.x*=uv_scale.x;uv.uv.y*=uv_scale.y

leaf_mesh=objects[1].data
leaf=bpy.data.materials.new('T1 Needle Leaves');leaf.use_nodes=True;leaf.use_backface_culling=False
p=leaf.node_tree.nodes.get('Principled BSDF');p.inputs['Roughness'].default_value=.71
p.inputs['Specular IOR Level'].default_value=.15
attribute=leaf.node_tree.nodes.new('ShaderNodeVertexColor');attribute.layer_name='LeafColor'
leaf.node_tree.links.new(attribute.outputs['Color'],p.inputs['Base Color'])
leaf_mesh.materials.append(leaf)
# Each source needle is one disconnected quad; retain per-island variation as
# vertex colours, since glTF cannot export Cycles' Random Per Island shader.
assert all(len(poly.vertices)==4 for poly in leaf_mesh.polygons)
rng=np.random.default_rng(260913)
t=rng.random((len(leaf_mesh.polygons),1))
paint=np.array(colors[0])*(1-t)+np.array(colors[1])*t
values=np.repeat(paint,4,axis=0).astype(np.float32)
layer=leaf_mesh.color_attributes.new(name='LeafColor',type='FLOAT_COLOR',domain='CORNER')
layer.data.foreach_set('color',values.reshape(-1))
report={'source':metadata,'source_height_m':high-low,'preview_height_m':6,'parts':[]}
if '--full-detail' not in sys.argv:
    report['pruning']=prune_tree(objects[0],objects[1])
for obj in objects:
    obj.data.calc_loop_triangles()
    report['parts'].append({'name':obj.name,'triangles':len(obj.data.loop_triangles),'vertices':len(obj.data.vertices)})
report['total_triangles']=sum(part['triangles'] for part in report['parts'])
report['adaptation']='Pruned lower branch families and reduced geometry; original available with --full-detail.' if 'pruning' in report else 'Full geometry.'
report['adaptation']+=' UV scaling baked; source PBR bark maps; deterministic per-needle vertex colour. Translucent shader and procedural displacement are not exported.'
(OUT/'model_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
bpy.context.view_layer.objects.active=objects[0]
bpy.ops.export_scene.gltf(filepath=str(OUT/'tree.glb'),export_format='GLB',use_selection=True,
    export_animations=False,export_cameras=False,export_lights=False,export_materials='EXPORT')
if 'pruning' in report:
    for image in images.values():image.pack()
    credits=bpy.data.texts.new('T1_SOURCE_AND_PRUNING.txt')
    credits.write(json.dumps(report,ensure_ascii=False,indent=2))
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/blender/t1_tree_pruned.blend'))
print('T1 PREVIEW',json.dumps(report))
