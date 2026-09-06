"""Native windmill inspired by assets/buildings/painted/windmill/windmill_back.png.
Blender Z-up, front -Y; exports an editable source and five stages plus a rotor.
Run in Blender --background --python scripts/tools/build_windmill.py.
"""
from pathlib import Path
import math
import random
import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/models/buildings/windmill'
PAINT = ROOT / 'tmp/windmill_paint'
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
        brush += .095*np.sin(grain*290) + .03*np.sin(grain*610)
    elif kind == 'slate':
        brush += .07*np.sin(y*125 + np.sin(x*45))
    else:
        brush += .055*np.sin(x*76)*np.sin(y*65)
    rgb = np.clip(np.array(color)[None,None,:]*(1+brush[:,:,None])+rng.normal(0,.009,(n,n,1)),0,1)
    image = bpy.data.images.new('Windmill '+kind+' paint',n,n)
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

cone('Deep stone footing',(0,0,.045),.96,.93,.35,STONE,'Foundation')
cone('Tapered mortar tower',(0,0,1.04),.90,.67,1.8,MORTAR,'Walls')
for row in range(10):
    z=.22+row*.175
    radius=.915-row*.023
    count=18
    for i in range(count):
        angle=math.tau*(i+(row%2)*.5)/count
        # Stone courses wrap all the way round; door and windows mask their recesses.
        p=(radius*math.sin(angle),radius*math.cos(angle),z)
        obj=box('Dressed limestone block',p,(radius*math.tau/count*.95,.14,.158),STONE,'Walls',.023)
        obj.rotation_euler.z=-angle+random.uniform(-.012,.012)
        if row<2 and i%5==0:
            moss=box('Moss in stone joint',(p[0]*1.045,p[1]*1.045,z-.055),(.15,.045,.026),MOSS,'Details',.009)
            moss.rotation_euler.z=-angle

# Eight posts and a wood-clad upper machinery floor.
for i in range(8):
    a=math.tau*i/8
    x,y=.75*math.sin(a),.75*math.cos(a)
    beam('Upper floor post',(x,y,1.81),(x,y,2.83),.105)
    beam('Support knee',(x*.82,y*.82,1.65),(x*1.13,y*1.13,1.98),.085)
for z in [1.94,2.72]:
    for i in range(8):
        a,b=math.tau*i/8,math.tau*(i+1)/8
        beam('Octagonal timber belt',(.80*math.sin(a),.80*math.cos(a),z),(.80*math.sin(b),.80*math.cos(b),z),.11)
cone('Upper plank backing',(0,0,2.33),.74,.74,.78,DARK,'Walls',8)
for side in range(8):
    angle=math.tau*(side+.5)/8
    for board in range(5):
        local=(board-2)*.108
        p=(.704*math.sin(angle)+local*math.cos(angle),.704*math.cos(angle)-local*math.sin(angle),2.33)
        obj=box('Upper timber boards',p,(.102,.065,.69),WOOD,'Walls',.008)
        obj.rotation_euler.z=-angle

# Conical cap with actual overlapping shingles, matching the green-grey roof.
cone('Roof underboarding',(0,0,3.19),1.02,.10,1.04,DARK,'Roof')
for row in range(8):
    t=row/8
    radius=.985*(1-t)+.08*t
    z=2.70+t*1.03
    count=max(8,round(30*(1-t)))
    for i in range(count):
        angle=math.tau*(i+(row%2)*.5)/count
        tile=box('Individual slate shingle',(radius*math.sin(angle),radius*math.cos(angle),z),(.23,.25,.035),SLATE,'Roof',.008)
        tile.rotation_euler=(math.radians(-47),0,-angle)
cone('Roof finial base',(0,0,3.82),.13,.06,.25,WOOD,'Roof',12)
cone('Carved finial',(0,0,4.01),.065,0,.24,WOOD,'Roof',12)

# Front door: planks, peaked lintel, jambs and a real iron ring.
box('Door dark reveal',(0,-.931,.68),(.62,.03,1.16),DARK,'Details')
for i in range(6):
    box('Door plank',(-.235+i*.094,-.963,.68),(.089,.055,1.09),WOOD,'Details',.009)
for x in [-.33,.33]:box('Door jamb',(x,-.977,.70),(.085,.12,1.26),WOOD,'Details')
beam('Peaked door lintel',(-.40,-.99,1.28),(0,-.99,1.40),.10,.11,'Details')
beam('Peaked door lintel',(0,-.99,1.40),(.40,-.99,1.28),.10,.11,'Details')
for z in [.39,.93]:box('Iron hinge',(-.21,-1.001,z),(.13,.018,.031),IRON,'Details',.007)
bpy.ops.mesh.primitive_torus_add(major_segments=16,minor_segments=6,major_radius=.036,minor_radius=.008,location=(.16,-1.013,.67),rotation=(math.pi/2,0,0))
finish(bpy.context.object,'Iron door ring',IRON,'Details')
for i in range(2):box('Stone step',(0,-1.06-i*.13,.065-i*.04),(.83,.28,.15),STONE,'Foundation',.025)

for side in range(4):
    angle=side*math.pi/2
    # Lower narrow windows and small upper timber shutters on side/rear faces.
    if side==0:continue
    for z,r,w,h in [(1.36,.84,.24,.42),(2.37,.77,.30,.36)]:
        x,y=r*math.sin(angle),r*math.cos(angle)
        pane=box('Inset window',(x,y,z),(w,.035,h),DARK,'Details',.015);pane.rotation_euler.z=-angle
        for offset in [-w*.56,w*.56]:
            post=box('Window frame',(x+offset*math.cos(angle),y-offset*math.sin(angle),z),(.038,.068,h+.08),WOOD,'Details');post.rotation_euler.z=-angle
        for height in [z-h*.54,z,z+h*.54]:
            rail=box('Window mullion',(x*1.025,y*1.025,height),(w+.08,.068,.038),WOOD,'Details');rail.rotation_euler.z=-angle

# Rotor geometry is authored around its own axis; Godot rotates this node only.
pivot=Vector((0,-1.095,2.64))
for blade in range(4):
    a=math.pi/4+blade*math.pi/2
    radial=Vector((math.sin(a),0,math.cos(a)))
    tangent=Vector((math.cos(a),0,-math.sin(a)))
    beam('Sail spar',pivot+radial*.08,pivot+radial*1.48,.063,.085,'Rotor')
    for offset in [0,.17,.34]:
        beam('Sail lattice rail',pivot+radial*.58+tangent*offset,pivot+radial*1.48+tangent*offset,.027,.033,'Rotor')
    for row in range(7):
        center=pivot+radial*(.58+row*.15)
        beam('Sail cross lattice',center,center+tangent*.34,.026,.031,'Rotor')
bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=.16,depth=.17,location=pivot,rotation=(math.pi/2,0,0))
finish(bpy.context.object,'Carved rotor hub',WOOD,'Rotor',.012)
bpy.ops.mesh.primitive_torus_add(major_segments=24,minor_segments=6,major_radius=.11,minor_radius=.013,location=pivot+Vector((0,-.095,0)),rotation=(math.pi/2,0,0))
finish(bpy.context.object,'Hub iron ring',IRON,'Rotor')

# Stage meshes retain true geometry while keeping runtime draw calls low.
for stage,parent in groups.items():
    pieces=list(parent.children)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in pieces:obj.select_set(True)
    bpy.context.view_layer.objects.active=pieces[0]
    bpy.ops.object.join()
    obj=bpy.context.object;obj.name=stage+'Mesh'
    if stage=='Rotor':
        world=obj.matrix_world.copy()
        parent.location=pivot
        bpy.context.view_layer.update()
        # Explicit local transform keeps the pivot at the shaft in glTF.
        obj.matrix_world=world

bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=str(OUT/'windmill.glb'),export_format='GLB',use_selection=True,export_yup=True,export_animations=False)
for image in bpy.data.images:
    if image.filepath:image.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/blender/windmill.blend'))
print('WINDMILL EXPORT COMPLETE')
