"""Raised timber henhouse inspired by the original painted chicken_coop art.

Blender Z-up, entrance facing -Y. Exports five construction stages and one hen.
Run with Blender --background --disable-autoexec --python this_file.
"""
from pathlib import Path
import math
import random
import json
import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'assets/models/buildings/chicken_coop'
TEMP = ROOT/'tmp/chicken-coop-paint'
OUT.mkdir(parents=True, exist_ok=True)
TEMP.mkdir(parents=True, exist_ok=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
rng = random.Random(91231)

def material(name, rgb, textured=False):
    mat = bpy.data.materials.new(name); mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*rgb,1)
    shader.inputs['Roughness'].default_value = .91
    shader.inputs['Specular IOR Level'].default_value = .15
    if textured:
        y,x = np.mgrid[0:512,0:512]/512
        # Integer frequencies make each texture tile seamlessly on long boards.
        grain = x+.014*np.sin(y*math.tau*3)+.006*np.sin(y*math.tau*7)
        brush = .03*np.sin(math.tau*(x*11+y*3))+.02*np.sin(math.tau*(y*15+x*4))
        if name == 'Coop timber': brush += .04*np.sin(grain*math.tau*38)+.013*np.sin(grain*math.tau*91)
        else: brush += .05*np.sin(x*math.tau*18)*np.sin(y*math.tau*16)
        pixels = np.clip(np.array(rgb)[None,None,:]*(1+brush[:,:,None]),0,1)
        image = bpy.data.images.new(name,512,512,alpha=False)
        image.pixels.foreach_set(np.concatenate([pixels,np.ones((512,512,1))],axis=2).astype(np.float32).ravel())
        image.filepath_raw = str(TEMP/(name+'.png')); image.file_format='PNG'; image.save(); image.pack()
        texture = mat.node_tree.nodes.new('ShaderNodeTexImage'); texture.image=image
        mat.node_tree.links.new(texture.outputs['Color'],shader.inputs['Base Color'])
    return mat

WOOD=material('Coop timber',(.65,.47,.26),True)
TILE=material('Coop terracotta',(.65,.27,.12),True)
STONE=material('Coop stone',(.46,.49,.40),True)
DARK=material('Dark recesses',(.085,.065,.043))
IRON=material('Forged hinges',(.16,.17,.13))
STRAW=material('Dry straw',(.70,.54,.25))
CREAM=material('Hen cream feathers',(.86,.80,.64))
WING=material('Hen ochre wing feathers',(.55,.29,.12))
RED=material('Hen comb',(.62,.055,.035))
GOLD=material('Hen feet and beak',(.76,.43,.12))
BLACK=material('Hen glossy eyes',(.018,.012,.009))

groups={}
for name in ['Foundation','Frame','Walls','Roof','Details']:
    parent=bpy.data.objects.new(name,None); bpy.context.collection.objects.link(parent); groups[name]=parent

def finish(obj,name,mat,group,bevel=0):
    obj.name=name; obj.parent=groups[group]; obj.data.materials.append(mat)
    if obj.data.uv_layers: obj.data.uv_layers.remove(obj.data.uv_layers.active)
    uv=obj.data.uv_layers.new(name='PaintUV')
    for face in obj.data.polygons:
        major=max(range(3),key=lambda a:abs(face.normal[a]))
        axes=[a for a in range(3) if a!=major]
        axes.sort(key=lambda a:obj.dimensions[a])
        offset=rng.random()
        for loop in face.loop_indices:
            co=obj.data.vertices[obj.data.loops[loop].vertex_index].co
            uv.data[loop].uv=(co[axes[0]]+offset,co[axes[1]])
    if bevel:
        mod=obj.modifiers.new('Soft worn edges','BEVEL'); mod.width=bevel; mod.segments=2
        bpy.context.view_layer.objects.active=obj; bpy.ops.object.modifier_apply(modifier=mod.name)
        mod=obj.modifiers.new('Weighted corner light','WEIGHTED_NORMAL'); bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj

def box(name,p,size,mat=WOOD,group='Frame',bevel=.012):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p); obj=bpy.context.object; obj.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return finish(obj,name,mat,group,bevel)

def beam(name,a,b,width=.06,mat=WOOD,group='Frame'):
    a,b=Vector(a),Vector(b)
    obj=box(name,(a+b)/2,(width,width,(b-a).length),mat,group)
    obj.rotation_mode='QUATERNION'; obj.rotation_quaternion=Vector((0,0,1)).rotation_difference(b-a)
    return obj

def ellipsoid(name,p,size,mat,group='Details'):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12,ring_count=8,location=p)
    obj=bpy.context.object; obj.scale=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    for face in obj.data.polygons: face.use_smooth=True
    return finish(obj,name,mat,group)

# The whole yard fits the existing 3 x 3 cells; no painted or solid ground plane.
for x in [-.71,.71]:
    for y in [-.03,1.07]:
        for row in range(2):
            box('Stone footing',(x,y,.02+row*.14),(.30,.29,.17),STONE,'Foundation',.025)
box('Raised floor',(0,.52,.32),(1.78,1.48,.15),WOOD,'Frame',.02)
for x in [-.78,.78]:
    for y in [-.14,1.18]:
        box('Corner post',(x,y,.98),(.13,.13,1.44),WOOD,'Frame',.018)
for z in [.46,1.60]:
    for y in [-.14,1.18]:box('Horizontal front beam',(0,y,z),(1.76,.12,.11))
    for x in [-.80,.80]:box('Horizontal side beam',(x,.52,z),(.12,1.48,.11))
for i in range(12):
    x=-.73+i*.133
    box('Back wall plank',(x,1.14,1.02),(.126,.075,1.10),WOOD,'Walls',.005)
    if abs(x)>.29:box('Front wall plank',(x,-.12,1.02),(.126,.075,1.10),WOOD,'Walls',.005)
for x in [-.79,.79]:
    for i in range(10):
        y=-.05+i*.125
        box('Side wall plank',(x,y,1.01),(.075,.119,1.10),WOOD,'Walls',.005)
for i in range(13):
    x=-.78+i*.13; height=.53*(1-abs(x)/.86)
    for y in [-.13,1.16]:
        box('Gable board',(x,y,1.63+height/2),(.123,.08,max(.02,height)),WOOD,'Walls',.005)
box('Door opening',(0,-.17,.94),(.60,.035,1.02),DARK,'Walls')
for i in range(4):box('Entrance door board',(-.205+i*.137,-.20,1.00),(.130,.04,.90),WOOD,'Details',.008)
for x in [-.33,.33]:box('Door jamb',(x,-.23,.99),(.085,.09,1.15),WOOD,'Details')
for z in [.61,1.40]:box('Door crossbar',(0,-.24,z),(.62,.06,.075),WOOD,'Details')
for z in [.74,1.24]:box('Iron strap hinge',(.22,-.285,z),(.16,.025,.06),IRON,'Details',.005)
beam('Door handle',(-.20,-.28,.94),(-.20,-.28,1.09),.034,IRON,'Details')
# Small open hen hatch and cleated ramp.
box('Hen hatch',(-.48,-.174,.62),(.27,.025,.32),DARK,'Details',.06)
for i in range(7):
    t=i/6
    plank=box('Ramp plank',(-.36,-.30-t*.66,.36-t*.29),(.53,.12,.055),WOOD,'Details',.008)
    plank.rotation_euler.x=math.atan2(.29,.66)
    if i%2==0:box('Ramp cleat',(-.36,-.30-t*.66,.41-t*.29),(.54,.035,.032),WOOD,'Details',.005)
# Individual overlapping red roof tiles and timber ridge.
for side in [-1,1]:
    for row in range(5):
        x=side*(.08+row*.20); z=2.21-abs(x)*.68
        for col in range(7):
            tile=box('Rounded clay shingle',(x,-.29+col*.25,z+rng.uniform(-.004,.004)),(.29,.245,.055),TILE,'Roof',.025)
            tile.rotation_euler.y=side*math.atan(.68)
for y in [-.40,1.33]:
    for side in [-1,1]:beam('Gable fascia',(0,y,2.25),(side*1.02,y,1.56),.115,WOOD,'Roof')
box('Ridge cap',(0,.47,2.27),(.14,1.95,.12),WOOD,'Roof',.025)
# Mesh-covered side window, sill and little tiled rain cover.
box('Side window dark opening',(-.835,.53,1.12),(.025,.55,.37),DARK,'Details')
for y in [.22,.84]:box('Window upright',(-.86,y,1.12),(.08,.065,.48),WOOD,'Details')
for z in [.90,1.35]:box('Window sill',(-.87,.53,z),(.12,.67,.07),WOOD,'Details')
for j in range(8):beam('Window wire',(-.88,.28+j*.073,.94),(-.88,.28+j*.073,1.30),.009,IRON,'Details')
for j in range(5):beam('Window cross wire',(-.89,.28,.96+j*.078),(-.89,.79,.96+j*.078),.009,IRON,'Details')
awning=box('Window tiled awning',(-.94,.53,1.40),(.32,.76,.065),TILE,'Details',.025); awning.rotation_euler.y=-.26
# Nest box on the opposite wall.
box('Nesting box',(.95,.58,.68),(.43,.66,.44),WOOD,'Details',.025)
lid=box('Nest box lid',(1.00,.58,.94),(.55,.76,.08),TILE,'Details',.022); lid.rotation_euler.y=.14
box('Nest inspection latch',(1.18,.56,.77),(.026,.08,.10),IRON,'Details')
for i in range(12):
    a=rng.random()*math.tau
    beam('Nest straw',(.86+.11*math.cos(a),.5+.13*math.sin(a),.47),(.97+.12*math.cos(a),.57+.16*math.sin(a),.47),.008,STRAW,'Details')
# Low timber run, with a clear entrance facing the player.
for x in [-1.37,1.37]:
    for y in [-1.35,-.48,.43,1.33]:
        box('Run fence post',(x,y,.33),(.095,.095,.76),WOOD,'Frame',.02)
    for y in [-.91,-.02,.88]:
        for z in [.22,.51]:box('Run side rail',(x,y,z),(.065,.88,.055),WOOD,'Details')
for x in [-.89,.89]:
    for z in [.22,.51]:box('Front fence rail',(x,-1.35,z),(.90,.06,.065),WOOD,'Details')
for x in [-.44,.44]:box('Gatepost',(x,-1.35,.33),(.10,.10,.74),WOOD,'Frame',.02)
for z in [.22,.51]:box('Rear fence rail',(0,1.33,z),(2.73,.06,.065),WOOD,'Details')
# Feed trough: rim remains visible when grain is depleted (runtime GrainFill).
box('Feed trough base',(.56,-.70,.095),(.44,.35,.10),WOOD,'Details')
for x in [.33,.79]:box('Feed trough rim',(x,-.70,.17),(.04,.40,.12),WOOD,'Details',.005)
for y in [-.89,-.51]:box('Feed trough end',(.56,y,.17),(.48,.04,.12),WOOD,'Details',.005)

def join_group(parent):
    pieces=[o for o in parent.children if o.type=='MESH']
    if not pieces:return
    bpy.ops.object.select_all(action='DESELECT')
    for obj in pieces:obj.select_set(True)
    bpy.context.view_layer.objects.active=pieces[0]
    bpy.ops.object.join();bpy.context.object.name=parent.name+'Mesh'

for parent in groups.values():join_group(parent)
building_objects=list(bpy.context.scene.objects)
bpy.ops.object.select_all(action='DESELECT')
for obj in building_objects:obj.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(OUT/'chicken_coop.glb'),export_format='GLB',use_selection=True,export_yup=True,export_animations=False)

# Articulated hen: head and feet remain separate transform nodes for light animation.
hen_root=bpy.data.objects.new('Hen',None);bpy.context.collection.objects.link(hen_root)
groups={}
for name in ['Body','Head','LeftFoot','RightFoot']:
    parent=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(parent);parent.parent=hen_root;groups[name]=parent
ellipsoid('Hen body',(0,0,.27),(.17,.23,.20),CREAM,'Body')
for x in [-.145,.145]:ellipsoid('Layered wing',(x,.015,.29),(.05,.16,.12),WING,'Body')
for i in range(3):
    tail=ellipsoid('Tail feather',((i-1)*.054,.20,.41),(.045,.15,.075),WING,'Body');tail.rotation_euler.x=.6
ellipsoid('Hen head',(0,-.18,.49),(.105,.10,.115),CREAM,'Head')
ellipsoid('Neck',(0,-.13,.37),(.095,.10,.12),CREAM,'Head')
for y in [-.24,-.18,-.12]:ellipsoid('Red comb',(0,y,.61),(.025,.039,.047),RED,'Head')
for x in [-.031,.031]:ellipsoid('Wattle',(x,-.245,.42),(.027,.025,.041),RED,'Head')
for x in [-.096,.096]:ellipsoid('Bright eye',(x,-.218,.515),(.014,.012,.015),BLACK,'Head')
bpy.ops.mesh.primitive_cone_add(vertices=8,radius1=.037,radius2=0,depth=.10,location=(0,-.30,.49))
beak=bpy.context.object;beak.rotation_euler.x=math.pi/2;finish(beak,'Beak',GOLD,'Head')
for group,x in [('LeftFoot',-.068),('RightFoot',.068)]:
    beam('Leg',(x,0,.03),(x,0,.19),.025,GOLD,group)
    for dx in [-.04,0,.04]:beam('Toe',(x,0,.025),(x+dx,-.10,.025),.014,GOLD,group)
for parent in groups.values():join_group(parent)
for group,pivot in [('Head',Vector((0,-.13,.37))),('LeftFoot',Vector((-.068,0,.14))),('RightFoot',Vector((.068,0,.14)))]:
    parent=groups[group]
    for child in parent.children:child.location-=pivot
    parent.location=pivot
bpy.ops.object.select_all(action='DESELECT')
hen_root.select_set(True)
for parent in groups.values():
    parent.select_set(True)
    for child in parent.children:child.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(OUT/'hen.glb'),export_format='GLB',use_selection=True,export_yup=True,export_animations=False)
hen_root.location=(-.86,-.95,0)
report={'building_triangles':sum(len(p.vertices)-2 for o in building_objects if o.type=='MESH' for p in o.data.polygons),
        'hen_triangles':sum(len(p.vertices)-2 for parent in groups.values() for o in parent.children for p in o.data.polygons)}
# An editable studio camera, excluded from both exports.
bpy.context.scene.world.color=(.55,.55,.55)
bpy.ops.object.light_add(type='AREA',location=(-3,-4,6));bpy.context.object.data.energy=450;bpy.context.object.data.shape='DISK';bpy.context.object.data.size=5
bpy.context.object.rotation_euler=(Vector((0,0,1))-bpy.context.object.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(4,-6,3.7));bpy.context.object.rotation_euler=(Vector((0,0,1))-bpy.context.object.location).to_track_quat('-Z','Y').to_euler()
bpy.context.scene.camera=bpy.context.object;bpy.context.object.data.type='ORTHO';bpy.context.object.data.ortho_scale=4.7
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/blender/chicken_coop.blend'))
(OUT/'model_report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print('CHICKEN_COOP_READY',report,flush=True)
