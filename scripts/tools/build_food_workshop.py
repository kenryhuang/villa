"""Native food workshop inspired by assets/buildings/painted/food_workshop/food_workshop_back.png.
Blender Z-up, front -Y; exports an editable source and five construction groups.
Run in Blender --background --python scripts/tools/build_food_workshop.py.
"""
from pathlib import Path
import math
import random
import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/models/buildings/food_workshop'
PAINT = ROOT / 'tmp/food_workshop_paint'
OUT.mkdir(parents=True, exist_ok=True)
PAINT.mkdir(parents=True, exist_ok=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
random.seed(260907)

def paint(kind, color):
    n = 512
    y, x = np.mgrid[0:n, 0:n] / n
    rng = np.random.default_rng(47)
    brush = .045*np.sin(x*39 + np.sin(y*17))*np.cos(y*48) + .035*np.sin(x*107+y*23)
    if kind == 'timber':
        grain = x + .016*np.sin(y*13) + .008*np.sin(y*37)
        brush += .04*np.sin(grain*290) + .015*np.sin(grain*610)
    elif kind == 'slate':
        brush += .07*np.sin(y*125 + np.sin(x*45))
    else:
        brush += .055*np.sin(x*76)*np.sin(y*65)
    rgb = np.clip(np.array(color)[None,None,:]*(1+brush[:,:,None])+rng.normal(0,.009,(n,n,1)),0,1)
    image = bpy.data.images.new('Food workshop '+kind+' paint',n,n)
    image.pixels.foreach_set(np.concatenate([rgb,np.ones((n,n,1))],axis=2).astype(np.float32).ravel())
    image.filepath_raw = str(PAINT/(kind+'.png'))
    image.file_format='PNG'
    image.save()
    material=bpy.data.materials.new('Painted '+kind)
    material.use_nodes=True
    shader=material.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Roughness'].default_value=.9
    tex=material.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image=image
    material.node_tree.links.new(tex.outputs['Color'],shader.inputs['Base Color'])
    return material

WOOD=paint('timber',(.63,.43,.22))
STONE=paint('limestone',(.67,.65,.48))
SLATE=paint('slate',(.34,.40,.36))
def plain(name,color):
    mat=bpy.data.materials.new(name)
    mat.diffuse_color=(*color,1)
    mat.use_nodes=True
    mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(*color,1)
    return mat
DARK=plain('Recesses',(.07,.065,.045))
IRON=plain('Forged iron',(.12,.13,.10))
MOSS=plain('Quiet moss',(.29,.34,.14))
MORTAR=plain('Recessed mortar',(.39,.40,.31))
groups={}
for name in ['Foundation','Frame','Walls','Roof','Details','Rotor']:
    parent=bpy.data.objects.new(name,None)
    bpy.context.collection.objects.link(parent)
    groups[name]=parent

def finish(obj,name,mat,stage,bevel=0):
    obj.name=name
    obj.parent=groups[stage]
    obj.data.materials.append(mat)
    for old in list(obj.data.uv_layers):obj.data.uv_layers.remove(old)
    uv=obj.data.uv_layers.new(name='PaintUV')
    for face in obj.data.polygons:
        major=max(range(3),key=lambda a:abs(face.normal[a]))
        axes=[a for a in range(3) if a!=major]
        offset=random.random()
        for loop in face.loop_indices:
            co=obj.data.vertices[obj.data.loops[loop].vertex_index].co
            uv.data[loop].uv=(co[axes[0]]+offset,co[axes[1]])
    if bevel:
        mod=obj.modifiers.new('Worn soft edges','BEVEL');mod.width=bevel;mod.segments=2
        bpy.context.view_layer.objects.active=obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
        mod=obj.modifiers.new('Weighted light','WEIGHTED_NORMAL')
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj

def box(name,p,size,mat=WOOD,stage='Frame',bevel=.012):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p)
    obj=bpy.context.object;obj.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return finish(obj,name,mat,stage,bevel)

def beam(name,a,b,width=.07,depth=None,stage='Frame',mat=WOOD):
    a,b=Vector(a),Vector(b)
    obj=box(name,(a+b)/2,(width,depth or width,(b-a).length),mat,stage)
    obj.rotation_mode='QUATERNION'
    obj.rotation_quaternion=Vector((0,0,1)).rotation_difference(b-a)
    return obj

def cone(name,p,r1,r2,depth,mat,stage,vertices=32):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=r1,radius2=r2,depth=depth,location=p)
    return finish(bpy.context.object,name,mat,stage,.009)

# Food workshop geometry, using the same painted materials as the 3D farm.
TILE = paint('terracotta',(.73,.34,.13))
GREEN = plain('Sage awning',(.39,.49,.25))
CREAM = plain('Canvas cream',(.87,.81,.61))
COPPER = plain('Hammered copper',(.68,.32,.10))
GLASS = plain('Sea green glass',(.47,.66,.57))
BREAD = plain('Golden crust',(.82,.49,.17))
RED = plain('Berry preserves',(.62,.16,.08))

def ellipsoid(name,p,size,mat,stage='Details'):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=8,radius=1,location=p)
    obj=bpy.context.object;obj.scale=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    for face in obj.data.polygons:face.use_smooth=True
    return finish(obj,name,mat,stage)

def ring(name,p,r,thickness,mat,rotation=(0,0,0)):
    bpy.ops.mesh.primitive_torus_add(major_segments=24,minor_segments=8,major_radius=r,minor_radius=thickness,location=p,rotation=rotation)
    return finish(bpy.context.object,name,mat,'Details')

# Front is Blender -Y / Godot +Z. The model occupies a 4 m square yard.
box('Stone footing',(0,.1,.03),(3.25,2.5,.24),STONE,'Foundation',.04)
for row in range(3):
    for side in [-1,1]:
        for k in range(7):
            box('Foundation masonry',(side*1.49,-.94+k*.34,.17+row*.16),(.23,.32,.145),STONE,'Walls',.025)
    for k in range(9):
        box('Rear masonry',(-1.36+k*.34,1.19,.17+row*.16),(.32,.22,.145),STONE,'Walls',.025)
for x in [-1.45,1.45]:
    for y in [-1.04,1.18]:
        beam('Oak corner post',(x,y,.2),(x,y,2.32),.15)
    beam('Oak eave',(x,-1.25,2.25),(x,1.35,2.25),.16)
    for y in [-.92,.45]:
        beam('Diagonal knee brace',(x,y,1.82),(x,y+.45,2.26),.10)
for y in [-1.05,1.19]:
    beam('Gable tie',(-1.48,y,2.24),(1.48,y,2.24),.15)
    beam('Gable left',(-1.48,y,2.24),(0,y,3.18),.14)
    beam('Gable right',(0,y,3.18),(1.48,y,2.24),.14)
    beam('King post',(0,y,2.24),(0,y,3.16),.12)
beam('Ridge cap',(0,-1.32,3.22),(0,1.4,3.22),.17)
for y in [-1.01,1.16]:
    for col in range(15):
        x=-1.33+col*.19
        top=3.15-abs(x)*.63
        box('Gable timber infill',(x,y,(2.24+top)/2),(.183,.08,top-2.24),WOOD,'Walls',.008)

# Closed back, half timber side walls, large mullioned windows.
for k in range(16):
    box('Rear planks',(-1.37+k*.182,1.16,1.38),(.173,.10,1.6),WOOD,'Walls',.009)
for side in [-1,1]:
    box('Window recess',(side*1.44,.18,1.37),(.085,1.72,1.28),DARK,'Walls')
    for y in [-.4,.21,.82]:
        for z in [1.09,1.63]:
            box('Glass pane',(side*1.496,y,z),(.025,.53,.47),GLASS,'Details',.008)
    for y in [-.7,-.1,.51,1.11]:
        beam('Window upright',(side*1.53,y,.79),(side*1.53,y,1.94),.065)
    for z in [.78,1.37,1.96]:
        beam('Window rail',(side*1.53,-.72,z),(side*1.53,1.13,z),.075)

# Individually rounded ceramic tiles on both pitched roof planes.
for side in [-1,1]:
    for row in range(6):
        x=side*(.14+row*.273);z=3.14-abs(x)*.61
        for col in range(10):
            tile=box('Clay roof tile',(x,-1.25+col*.278,z),(.335,.265,.063),TILE,'Roof',.016)
            tile.rotation_euler.y=side*math.atan(.61)
    for y in [-1.39,1.4]:
        beam('Roof verge',(0,y,3.25),(side*1.74,y,2.18),.14,stage='Roof')
    beam('Roof lower trim',(side*1.72,-1.4,2.18),(side*1.72,1.4,2.18),.12,stage='Roof')

# Open service front with sage-and-cream canvas and wooden worktop.
for col in range(12):
    awning=box('Canvas stripe',(-1.485+col*.27,-1.33,2.07),(.266,.63,.05),GREEN if col%2==0 else CREAM,'Details',.014)
    awning.rotation_euler.x=.17
    box('Scalloped valance',(-1.485+col*.27,-1.65,1.98),(.26,.055,.15),GREEN if col%2==0 else CREAM,'Details',.03)
box('Counter stone base',(0,-1.14,.41),(2.95,.40,.65),STONE,'Walls',.03)
for col in range(9):
    box('Counter front boards',(-1.31+col*.328,-1.37,.52),(.315,.065,.62),WOOD,'Details',.015)
box('Bread preparation counter',(0,-1.34,.88),(3.26,.68,.14),WOOD,'Details',.035)
for x in [-1.32,1.32]:
    box('Counter brackets',(x,-1.48,.73),(.16,.38,.17),WOOD,'Details',.02)

# Built-in stone oven: dark open mouth framed by individual voussoirs.
box('Oven body',(-.9,.54,1.04),(.97,.83,1.35),STONE,'Walls',.06)
box('Oven opening',(-.9,.10,1.1),(.63,.035,.68),DARK,'Details',.09)
for i in range(9):
    a=i*math.pi/8
    block=box('Oven arch stone',(-.9+.39*math.cos(a),.045,1.21+.39*math.sin(a)),(.18,.16,.19),STONE,'Details',.025)
    block.rotation_euler.y=math.pi/2-a
for x in [-1.29,-.51]:box('Oven jamb',(x,.045,.98),(.18,.16,.46),STONE,'Details',.02)
for k in range(5):box('Chimney stone',(-.96,.83,2.20+k*.20),(.44,.44,.19),STONE,'Roof',.025)
cone('Copper chimney collar',(-.96,.83,3.16),.27,.27,.10,COPPER,'Details')
cone('Copper chimney hood',(-.96,.83,3.34),.31,.06,.23,COPPER,'Details')

# Copper preserving kettle with open lip, soup surface and curved handles.
ellipsoid('Copper kettle',(-.83,-.62,1.1),(.30,.25,.24),COPPER)
cone('Kettle dark opening',(-.83,-.62,1.275),.21,.21,.018,DARK,'Details')
ring('Rolled copper rim',(-.83,-.62,1.29),.226,.021,COPPER)
for x in [-1.16,-.50]:ring('Kettle handle',(x,-.62,1.19),.075,.013,COPPER,(math.pi/2,0,0))
for y in [.48,.84]:box('Pantry shelf',(.57,y,1.24 if y==.48 else 1.78),(1.45,.24,.065),WOOD,'Details')
for row in range(2):
    for col in range(6):
        x=-.03+col*.235;y=.45 if row==0 else .82;z=1.40 if row==0 else 1.95
        cone('Preserve jar',(x,y,z),.080,.073,.24,[RED,GREEN,COPPER][col%3],'Details',16)
        cone('Jar lid',(x,y,z+.14),.085,.085,.042,WOOD,'Details',16)
for x in [.35,.66,.96]:
    ellipsoid('Fresh bread',(x,-1.45,1.035),(.21,.105,.085),BREAD)
    for k in [-1,0,1]:
        slash=box('Bread scoring',(x+k*.075,-1.465,1.108),(.014,.13,.007),CREAM,'Details',.003)
        slash.rotation_euler.z=.3
cone('Flour bowl',(-.12,-1.34,1.05),.14,.21,.21,WOOD,'Details')
ellipsoid('Flour in bowl',(-.12,-1.34,1.15),(.18,.18,.05),CREAM)
box('Chopping board',(-.75,-1.4,.985),(.52,.28,.035),WOOD,'Details')
for k in range(4):
    ellipsoid('Tomatoes',(-1.28+k*.075,-1.35,1.03),(.064,.059,.062),RED)
for x in [-1.7,1.7]:
    box('Produce crate',(x,.62,.28),(.35,.60,.39),WOOD,'Details',.015)
    for k in range(4):ellipsoid('Stored produce',(x,.42+k*.13,.50),(.12,.10,.12),GREEN if x<0 else BREAD)

# Join by construction stage to keep runtime draw calls bounded.
for stage,parent in list(groups.items()):
    pieces=list(parent.children)
    if not pieces:
        bpy.data.objects.remove(parent,do_unlink=True)
        continue
    bpy.ops.object.select_all(action='DESELECT')
    for obj in pieces:obj.select_set(True)
    bpy.context.view_layer.objects.active=pieces[0]
    bpy.ops.object.join();bpy.context.object.name=stage+'Mesh'
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=str(OUT/'food_workshop.glb'),export_format='GLB',use_selection=True,export_yup=True,export_animations=False)
for image in bpy.data.images:
    if image.filepath:image.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/blender/food_workshop.blend'))
print('FOOD WORKSHOP EXPORT COMPLETE')
