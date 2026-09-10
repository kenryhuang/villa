"""Convert the supplied CC BY 3.0 Sintel Lite into Yun's game character.

Run Blender --background --disable-autoexec --python this-file.
The original .blend is read only. No legacy rig scripts are executed.
"""
from pathlib import Path
import bpy
import math
import json
import re
from mathutils import Vector, Matrix, Quaternion
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'art/blender/characters/Sintel Lite 2.57b/bendansie_sintel_lite_257b.blend'
OUT = ROOT / 'assets/models/characters'
PREVIEW = ROOT / 'tmp/sintel-yun'
OUT.mkdir(parents=True, exist_ok=True)
PREVIEW.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(SOURCE), use_scripts=False)
bpy.context.preferences.filepaths.save_version = 0
old_rig = bpy.data.objects['rig']
old_rig.data.pose_position = 'REST'
for obj in bpy.data.objects:
    if obj.animation_data:
        for driver in obj.animation_data.drivers: driver.mute = True
    if obj.type == 'MESH':
        if obj.data.shape_keys:
            obj.data.shape_keys.animation_data_clear()
            for key in obj.data.shape_keys.key_blocks: key.value = 0
        for mod in obj.modifiers:
            if mod.type == 'SUBSURF': mod.show_viewport = obj.name == 'GEO-body'; mod.levels = 1
            if mod.type == 'MASK': mod.show_viewport = False
bpy.context.view_layer.update()
deps = bpy.context.evaluated_depsgraph_get()

# Collapse twist/corrective and facial controller bones into a small deform rig.
def bone_name(name):
    name = name.removeprefix('DEF-')
    side = '.L' if '.L' in name else '.R' if '.R' in name else ''
    for part in ['thigh','shin','upper_arm','forearm','shoulder','hand','foot','toe']:
        if name.startswith(part + '.'): return part + side
    for finger in ['finger_index','finger_middle','finger_ring','finger_pinky','thumb']:
        if name.startswith(finger): return finger + '.' + name.split('.')[1] + side
    if name.startswith('palm.'): return 'hand' + side
    if name in ['spine.01','wgt_pelvis']: return 'pelvis'
    if name == 'spine.02': return 'spine'
    if name.startswith(('spine.','pec.','lat.','wgt_torso')): return 'chest'
    if name in ['neck.01','neck.02']: return 'neck'
    if name.startswith('eye.') and not name.startswith('eyelid'): return 'eye' + side
    if name.startswith('jaw'): return 'jaw'
    return 'head' if name.startswith(('neck','eyelid','lip','nose','nostril','brow','cheek')) else None

def point(name, tail=False):
    b = old_rig.data.bones[name]
    return old_rig.matrix_world @ (b.tail_local if tail else b.head_local)

bones = {
    'root': (Vector((0,0,0)), Vector((0,0,.15)), None),
    'pelvis': (point('DEF-spine.01'), point('DEF-spine.01',True), 'root'),
    'spine': (point('DEF-spine.02'), point('DEF-spine.02',True), 'pelvis'),
    'chest': (point('DEF-spine.03'), point('DEF-spine.04',True), 'spine'),
    'neck': (point('DEF-neck.01'), point('DEF-neck.02',True), 'chest'),
    'head': (point('DEF-neck.03'), point('DEF-neck.03',True), 'neck'),
    'jaw': (point('DEF-jaw'), point('DEF-jaw',True), 'head'),
}
for side in ['L','R']:
    for part,parent in [('thigh','pelvis'),('shin','thigh.'+side),('foot','shin.'+side),('toe','foot.'+side),('shoulder','chest'),('upper_arm','shoulder.'+side),('forearm','upper_arm.'+side),('hand','forearm.'+side),('eye','head')]:
        split = part in ['thigh','shin','upper_arm','forearm']
        first = 'DEF-'+part+'.'+side+('.01' if split else '')
        last = 'DEF-'+part+'.'+side+('.02' if split else '')
        bones[part+'.'+side] = (point(first),point(last,True),parent)
    for finger in ['finger_index','finger_middle','finger_ring','finger_pinky','thumb']:
        for digit in ['01','02','03']:
            first = 'DEF-'+finger+'.'+digit+'.'+side+('.01' if digit=='01' else '')
            last = first[:-1]+'2' if digit=='01' else first
            parent = 'hand.'+side if digit=='01' else finger+'.%02d.'%(int(digit)-1)+side
            bones[finger+'.'+digit+'.'+side] = (point(first),point(last,True),parent)

def evaluated_mesh(obj):
    return bpy.data.meshes.new_from_object(obj.evaluated_get(deps), preserve_all_data_layers=True, depsgraph=deps)

# Most torso and limb motion in Sintel is carried by the mesh-deformation cage,
# not direct body vertex groups. Transfer its weights before removing that cage.
cage=bpy.data.objects['GEO-deformation_cage']; cage_mesh=evaluated_mesh(cage)
cage_mesh.calc_loop_triangles()
cage_points=[cage.matrix_world@v.co for v in cage_mesh.vertices]
cage_tris=[tuple(t.vertices) for t in cage_mesh.loop_triangles]
cage_tree=BVHTree.FromPolygons(cage_points,cage_tris,all_triangles=True)
cage_groups={g.index:g.name for g in cage.vertex_groups}
cage_weights=[]
for v in cage_mesh.vertices:
    w={}
    for g in v.groups:
        name=bone_name(cage_groups.get(g.group,''))
        if name in bones and g.weight>0:w[name]=w.get(name,0)+g.weight
    if not w:w={'pelvis':1}
    total=sum(w.values());cage_weights.append({k:n/total for k,n in w.items()})
def cage_weight(position):
    loc,_,index,_=cage_tree.find_nearest(position);ids=cage_tris[index]
    factors=barycentric_transform(loc,*[cage_points[i] for i in ids],Vector((1,0,0)),Vector((0,1,0)),Vector((0,0,1)))
    result={}
    for i,f in zip(ids,factors):
        for k,w in cage_weights[i].items():result[k]=result.get(k,0)+max(0,f)*w
    return result

reference = bpy.data.objects['GEO-body']
reference_mesh = evaluated_mesh(reference)
ref_points = [reference.matrix_world @ v.co for v in reference_mesh.vertices]
reference_mesh.calc_loop_triangles()
triangles = [tuple(t.vertices) for t in reference_mesh.loop_triangles]
bvh = BVHTree.FromPolygons(ref_points, triangles, all_triangles=True)
group_names = {g.index:g.name for g in reference.vertex_groups}
ref_weights = []
for v in reference_mesh.vertices:
    weights = {}
    for g in v.groups:
        source = group_names.get(g.group,'')
        if not source.startswith('DEF-'): continue
        name = bone_name(source)
        if name in bones: weights[name] = weights.get(name,0)+g.weight
    remaining=max(0,1-sum(weights.values()))
    if remaining>1e-6:
        for k,w in cage_weight(reference.matrix_world@v.co).items():weights[k]=weights.get(k,0)+remaining*w
    total=sum(weights.values()); ref_weights.append({k:w/total for k,w in weights.items()})

def closest_weights(position):
    loc, normal, index, distance = bvh.find_nearest(position)
    ids=triangles[index]; a,b,c=[ref_points[i] for i in ids]
    factors=barycentric_transform(loc,a,b,c,Vector((1,0,0)),Vector((0,1,0)),Vector((0,0,1)))
    weights={}
    for i,factor in zip(ids,factors):
        for key,value in ref_weights[i].items(): weights[key]=weights.get(key,0)+max(0,factor)*value
    return weights

# Choose UVTexAll explicitly: legacy active_render flags were lost by 2.57 import.
materials={}
def material(name, color, image_name=None, uv='UVMap', roughness=.82):
    mat=bpy.data.materials.new(name); mat.diffuse_color=(*color,1); mat.use_nodes=True
    nodes=mat.node_tree.nodes; nodes.clear(); out=nodes.new('ShaderNodeOutputMaterial'); p=nodes.new('ShaderNodeBsdfPrincipled')
    p.inputs['Roughness'].default_value=roughness; p.inputs['Base Color'].default_value=(*color,1)
    mat.node_tree.links.new(p.outputs['BSDF'],out.inputs['Surface'])
    if image_name:
        tex=nodes.new('ShaderNodeTexImage'); tex.image=bpy.data.images[image_name]
        coord=nodes.new('ShaderNodeUVMap'); coord.uv_map=uv; mat.node_tree.links.new(coord.outputs['UV'],tex.inputs['Vector'])
        tint=nodes.new('ShaderNodeMixRGB'); tint.blend_type='MULTIPLY'; tint.inputs[0].default_value=1; tint.inputs[2].default_value=(*color,1)
        mat.node_tree.links.new(tex.outputs['Color'],tint.inputs[1]); mat.node_tree.links.new(tint.outputs[0],p.inputs['Base Color'])
    materials[name]=mat
    return mat

# Texture tint is baked into exported base-color using an emission pass below.
skin=material('Yun • original painted skin',(1,1,1),'sintel_skin_diff.jpg')
shirt=material('Yun • sage woven cotton',(.49,.66,.34),'sintel_sweater_painte')
pants=material('Yun • warm work trousers',(.48,.30,.17),'sintel_pants.jpg')
boots=material('Yun • leather boots',(.52,.32,.19),'sintel_boots.jpg')
gloves=material('Yun • soft work gloves',(.50,.31,.18),'leather_06_diff.jpg')
eyes=material('Yun • eyes',(1,1,1),'sintel_eyeball_diff.j',roughness=.38)
mouth=material('Yun • mouth',(1,1,1),'sintel_teeth_diff.jpg')
hair=material('Yun • chestnut hair',(.20,.069,.026))
dark=material('Yun • brows and lashes',(.035,.015,.009))
apron=material('Yun • linen apron',(.78,.65,.42))
metal=material('Yun • brass clasp',(.55,.32,.095),roughness=.48)

mapping={'GEO-body':skin,'GEO-body_mouth':mouth,'GEO-boots':boots,'GEO-eyeballs':eyes,'GEO-gloves':gloves,'GEO-pants':pants,'GEO-shirt':shirt,'GEO-shirt_hooks':metal,'GEO-hair_proxy':hair,'GEO-emit_brows':dark,'GEO-emit_lash_btm':dark,'GEO-emit_lash_top':dark}
scene=bpy.data.scenes.new('Yun game character')
parts=[]
for name,mat in mapping.items():
    src=bpy.data.objects[name]
    mesh=evaluated_mesh(src)
    mesh.transform(src.matrix_world)
    mesh.name='Yun '+name.removeprefix('GEO-')
    obj=bpy.data.objects.new(mesh.name,mesh); scene.collection.objects.link(obj); parts.append(obj)
    chosen='UVTexAll' if name=='GEO-body' else mesh.uv_layers[0].name if mesh.uv_layers else None
    if chosen:
        for layer in list(mesh.uv_layers):
            if layer.name!=chosen: mesh.uv_layers.remove(layer)
        mesh.uv_layers[0].name='UVMap'; mesh.uv_layers.active_index=0; mesh.uv_layers[0].active_render=True
    mesh.materials.clear(); mesh.materials.append(mat)
    for poly in mesh.polygons: poly.material_index=0; poly.use_smooth=True
    weights=[closest_weights(v.co) for v in mesh.vertices]
    if name in ['GEO-hair_proxy','GEO-emit_brows','GEO-emit_lash_btm','GEO-emit_lash_top']: weights=[{'head':1} for v in mesh.vertices]
    for key in bones: obj.vertex_groups.new(name=key)
    for v,w in zip(mesh.vertices,weights):
        ranked=sorted(w.items(),key=lambda kv:kv[1],reverse=True)[:4]; total=sum(n for _,n in ranked)
        for key,n in ranked:
            if n>0: obj.vertex_groups[key].add([v.index],n/total,'REPLACE')
    if name=='GEO-body':
        obj.shape_key_add(name='Basis')
        # Preserve selected authored expressions with topology and subdivision intact.
        for src_name,dst_name in [('MOUTH-smile.L','Smile.L'),('MOUTH-smile.R','Smile.R'),('BROW-surp.L','BrowUp.L'),('BROW-surp.R','BrowUp.R'),('EYE-squint.L','Squint.L'),('EYE-squint.R','Squint.R')]:
            key=src.data.shape_keys.key_blocks[src_name]; key.value=1; deps.update()
            expression=evaluated_mesh(src)
            shape=obj.shape_key_add(name=dst_name)
            assert len(expression.vertices)==len(mesh.vertices)
            for a,b in zip(shape.data,expression.vertices): a.co=src.matrix_world@b.co
            bpy.data.meshes.remove(expression); key.value=0; deps.update()

bpy.context.window.scene=scene
for action in list(bpy.data.actions): bpy.data.actions.remove(action)

# Bake each original texture/tint through its actual UVs. Material-space baking
# avoids losing the legacy UV setup or unsupported color-mix nodes in glTF.
scene.render.engine='CYCLES'; scene.cycles.samples=1
for obj in parts:
    mat=obj.data.materials[0]
    if not any(n.type=='TEX_IMAGE' for n in mat.node_tree.nodes): continue
    bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True); bpy.context.view_layer.objects.active=obj
    nodes=mat.node_tree.nodes; p=next(n for n in nodes if n.type=='BSDF_PRINCIPLED'); out=next(n for n in nodes if n.type=='OUTPUT_MATERIAL')
    color_link=p.inputs['Base Color'].links[0].from_socket
    emit=nodes.new('ShaderNodeEmission'); mat.node_tree.links.new(color_link,emit.inputs['Color']); mat.node_tree.links.new(emit.outputs[0],out.inputs['Surface'])
    size=2048 if obj.name=='Yun body' else 1024 if obj.name in ['Yun shirt','Yun pants'] else 512
    image=bpy.data.images.new(obj.name+' albedo',width=size,height=size,alpha=False)
    target=nodes.new('ShaderNodeTexImage'); target.image=image; nodes.active=target
    bpy.ops.object.bake(type='EMIT',margin=8)
    image.pack()
    nodes.clear(); out=nodes.new('ShaderNodeOutputMaterial'); p=nodes.new('ShaderNodeBsdfPrincipled'); p.inputs['Roughness'].default_value=.8
    tex=nodes.new('ShaderNodeTexImage'); tex.image=image
    mat.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color']); mat.node_tree.links.new(p.outputs['BSDF'],out.inputs['Surface'])

# A shaped waist apron and pocket distinguish the village cook from the source.
def cloth(name,rows,width,mat):
    verts=[]; faces=[]; segments=16
    for y,z in rows:
        for j in range(segments+1):
            u=j/segments*2-1
            verts.append((u*width, y+.035*u*u-.002*math.cos(u*math.pi*6), z-.012*u*u))
    for r in range(len(rows)-1):
        for j in range(segments):
            i=r*(segments+1)+j; faces.append((i,i+1,i+segments+2,i+segments+1))
    mesh=bpy.data.meshes.new(name); mesh.from_pydata(verts,[],faces); mesh.materials.append(mat)
    obj=bpy.data.objects.new(name,mesh); scene.collection.objects.link(obj)
    for p in mesh.polygons:p.use_smooth=True
    pelvis=obj.vertex_groups.new(name='pelvis')
    left=obj.vertex_groups.new(name='thigh.L');right=obj.vertex_groups.new(name='thigh.R')
    for i,(x,y,z) in enumerate(verts):
        leg_weight=max(0,min(.88,(.98-z)/.22))
        side=max(0,min(1,(x+.055)/.11))
        pelvis.add([i],1-leg_weight,'REPLACE');left.add([i],leg_weight*side,'REPLACE');right.add([i],leg_weight*(1-side),'REPLACE')
    solid=obj.modifiers.new('Fabric thickness','SOLIDIFY'); solid.thickness=.002
    bpy.context.view_layer.objects.active=obj; obj.select_set(True); bpy.ops.object.modifier_apply(modifier=solid.name); obj.select_set(False)
    parts.append(obj); return obj

cloth('Yun waist apron',[(-.115,.99),(-.147,.94),(-.180,.87),(-.205,.80),(-.218,.74)],.148,apron)
cloth('Yun apron pocket',[(-.191,.87),(-.208,.83),(-.220,.79)],.058,apron)

data=bpy.data.armatures.new('YunSkeleton'); rig=bpy.data.objects.new('YunRig',data); scene.collection.objects.link(rig)
bpy.ops.object.select_all(action='DESELECT'); rig.select_set(True); bpy.context.view_layer.objects.active=rig
bpy.ops.object.mode_set(mode='EDIT')
for name,(head,tail,parent) in bones.items():
    bone=data.edit_bones.new(name); bone.head=head; bone.tail=tail
for name,(_,_,parent) in bones.items():
    if parent:data.edit_bones[name].parent=data.edit_bones[parent]
bpy.ops.object.mode_set(mode='OBJECT')
for obj in parts:
    obj.parent=rig; mod=obj.modifiers.new('Game skin','ARMATURE'); mod.object=rig
rig.animation_data_create()

def rotate(name,axis,angle):
    bone=rig.pose.bones[name]
    def pose_matrix(b):
        rest=b.bone.matrix_local.to_3x3()
        if b.parent: rest=pose_matrix(b.parent) @ b.parent.bone.matrix_local.to_3x3().inverted() @ rest
        return rest @ b.rotation_quaternion.to_matrix()
    basis=bone.bone.matrix_local.to_3x3()
    if bone.parent:basis=pose_matrix(bone.parent) @ bone.parent.bone.matrix_local.to_3x3().inverted() @ basis
    local_axis=basis.inverted()@Vector(axis)
    bone.rotation_quaternion=Quaternion(local_axis,angle) @ bone.rotation_quaternion

for name,duration in [('Idle',90),('Walk',30),('Run',24),('Work',48)]:
    action=bpy.data.actions.new(name); action.use_fake_user=True; rig.animation_data.action=action
    for frame in range(duration+1):
        phase=frame/duration*math.tau
        for bone in rig.pose.bones:bone.rotation_mode='QUATERNION';bone.rotation_quaternion=(1,0,0,0);bone.location=(0,0,0)
        for sign,side in [(1,'L'),(-1,'R')]:
            rotate('upper_arm.'+side,(0,1,0),sign*math.radians(78))
            for finger in ['finger_index','finger_middle','finger_ring','finger_pinky']:
                for digit in ['02','03']:rotate(finger+'.'+digit+'.'+side,(1,0,0),-.22)
        if name in ['Walk','Run']:
            fast=name=='Run'; amplitude=.60 if fast else .36
            for sign,side in [(1,'L'),(-1,'R')]:
                swing=math.sin(phase)*sign
                rotate('thigh.'+side,(1,0,0),amplitude*swing)
                rotate('shin.'+side,(1,0,0),-(.8 if fast else .52)*max(0,-swing))
                rotate('foot.'+side,(1,0,0),.17*max(0,-swing))
                rotate('upper_arm.'+side,(1,0,0),-.36*swing)
                rotate('forearm.'+side,(1,0,0),-.55 if fast else -.10-.14*max(0,swing))
            rig.pose.bones['root'].location.z=(.026 if fast else .012)*(1-math.cos(2*phase))
            rotate('spine',(0,0,1),.04*math.sin(phase)); rotate('chest',(1,0,0),.13 if fast else .025)
        elif name=='Work':
            wave=.5-.5*math.cos(phase)
            rotate('spine',(1,0,0),.12*wave)
            for sign,side in [(1,'L'),(-1,'R')]:
                rotate('upper_arm.'+side,(1,0,0),-.45-.16*wave)
                rotate('forearm.'+side,(1,0,0),-.65-.22*math.sin(phase+sign*.6))
                rotate('hand.'+side,(0,0,1),.10*math.sin(phase+sign))
        else:
            rotate('chest',(1,0,0),.012*math.sin(phase)); rotate('head',(0,0,1),.018*math.sin(phase))
        for bone in rig.pose.bones:
            bone.keyframe_insert('rotation_quaternion',frame=frame,group=bone.name)
            if bone.name=='root':bone.keyframe_insert('location',frame=frame,group=bone.name)
rig.animation_data.action=bpy.data.actions['Idle']; scene.render.fps=30; scene.frame_set(0)

# Export only the selected character; no original controllers, scripts or stage.
bpy.ops.object.select_all(action='DESELECT'); rig.select_set(True)
for obj in parts:obj.select_set(True)
bpy.context.view_layer.objects.active=rig
filename=OUT/'resident_yun.glb'
bpy.ops.export_scene.gltf(filepath=str(filename),export_format='GLB',use_selection=True,export_yup=True,export_animations=True,export_animation_mode='ACTIONS',export_materials='EXPORT',export_cameras=False,export_lights=False,export_extras=True)
report={'source':str(SOURCE.relative_to(ROOT)),'actor':'resident_yun','bones':len(data.bones),'meshes':len(parts),'triangles':0,'materials':len({o.data.materials[0].name for o in parts}),'clips':['Idle','Walk','Run','Work'],'bytes':filename.stat().st_size}
for obj in parts:obj.data.calc_loop_triangles();report['triangles']+=len(obj.data.loop_triangles)

# Remove legacy data from the editable derived file, retaining the original separately.
for obj in list(bpy.data.objects):
    if obj not in parts and obj!=rig:bpy.data.objects.remove(obj,do_unlink=True)
for old_scene in list(bpy.data.scenes):
    if old_scene!=scene:bpy.data.scenes.remove(old_scene)
for text in list(bpy.data.texts):bpy.data.texts.remove(text)
bpy.data.orphans_purge(do_recursive=True)
credits=bpy.data.texts.new('CREDITS.txt')
credits.write('Yun game adaptation of Sintel Lite 2.57b by BenDansie.\nSource: http://www.blendswap.com/blends/view/7093\nLicense: https://creativecommons.org/licenses/by/3.0/\nChanges: game deform rig and weights; selected expressions; converted/tinted materials; waist apron; new Idle/Walk/Run/Work animations.\n')
scene.world=bpy.data.worlds.new('Warm studio'); scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.38,.43,.38,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.6
scene.cycles.samples=32;scene.cycles.use_denoising=True
scene.render.resolution_x=900;scene.render.resolution_y=1050;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG'
for loc,power,size in [((-3,-4,5),400,4),((3,-1,3),200,3),((0,3,4),450,3)]:
    bpy.ops.object.light_add(type='AREA',location=loc);light=bpy.context.object;light.data.energy=power;light.data.shape='DISK';light.data.size=size;light.rotation_euler=(Vector((0,0,1))-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(2,-5,2));camera=bpy.context.object;camera.rotation_euler=(Vector((0,0,.88))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=1.98;scene.camera=camera
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/blender/characters/resident_yun.blend'))
for clip,frame in [('Idle',0),('Walk',7),('Work',12)]:
    rig.animation_data.action=bpy.data.actions[clip];scene.frame_set(frame);scene.render.filepath=str(PREVIEW/(clip.lower()+'.png'));bpy.ops.render.render(write_still=True)
(OUT/'resident_yun_report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')
print('YUN BUILD COMPLETE',report,flush=True)
