"""Five illustrated trees with fuller crowns and readable trunks.

Blender --background --python scripts/tools/build_illustrated_trees.py -- --render
Editable branch construction, fused game meshes, three deliberately authored LODs.
Only generated illustrated_trees assets are overwritten; original pictures are read-only.
"""
from pathlib import Path
import bpy
import math
import random
import json
import sys
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/models/vegetation/illustrated_trees'
PREV = ROOT / 'docs/validation/illustrated-trees'
for p in [OUT, PREV]: p.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.save_version = 0
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 32
scene.cycles.use_denoising = True
scene.render.image_settings.file_format = 'PNG'
scene.view_settings.view_transform = 'Standard'
scene.view_settings.look = 'None'
scene.view_settings.exposure = -.35
studio = bpy.data.collections.new('STUDIO - excluded from exports'); scene.collection.children.link(studio)

def move_to(obj, col):
    for c in list(obj.users_collection): c.objects.unlink(obj)
    col.objects.link(obj)
    return obj

def mesh_obj(name, vertices, faces, col):
    m = bpy.data.meshes.new(name); m.from_pydata(vertices, [], faces); m.update()
    obj = bpy.data.objects.new(name, m); col.objects.link(obj)
    return obj

def curve(points, steps=5):
    result = []
    for i in range(len(points)-1):
        a,b,c,d = [np.array(points[max(0,min(len(points)-1,k))],dtype=float) for k in [i-1,i,i+1,i+2]]
        for j in range(steps):
            t=j/steps
            p=.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t)
            p[3]=max(.008,p[3]); result.append(p)
    return result+[np.array(points[-1],dtype=float)]

def tube(name, points, col, sides=14):
    ps=curve(points); vv=[]; ff=[]
    for i,p in enumerate(ps):
        tangent=Vector(ps[min(i+1,len(ps)-1)][:3]-ps[max(0,i-1)][:3]).normalized()
        ref=Vector((0,1,0)) if abs(tangent.y)<.9 else Vector((1,0,0))
        x=tangent.cross(ref).normalized(); y=tangent.cross(x).normalized()
        for j in range(sides):
            a=j*math.tau/sides
            r=p[3]*(1+.085*math.sin(a*7+i*.09)+.04*math.sin(a*4-i*.04))
            vv.append(Vector(p[:3])+(x*math.cos(a)+y*math.sin(a))*r)
            if i: ff.append(((i-1)*sides+j,(i-1)*sides+(j+1)%sides,i*sides+(j+1)%sides,i*sides+j))
    ff.extend([tuple(reversed(range(sides))),tuple((len(ps)-1)*sides+j for j in range(sides))])
    return mesh_obj(name,vv,ff,col)

def image(name):
    im=bpy.data.images.load(str(ROOT/'assets/vegetation'/name),check_existing=True); im.pack()
    pixels=np.empty(len(im.pixels),dtype=np.float32); im.pixels.foreach_get(pixels)
    return im,pixels.reshape((im.size[1],im.size[0],4))

def sample(pixels,u,v):
    h,w,_=pixels.shape
    return pixels[min(h-1,max(0,int(v*h))),min(w-1,max(0,int(u*w)))]

def painted_material(name, im, color=False):
    mat=bpy.data.materials.new(name); mat.use_nodes=True; mat.use_backface_culling=False
    p=mat.node_tree.nodes.get('Principled BSDF'); p.inputs['Roughness'].default_value=.94
    p.inputs['Specular IOR Level'].default_value=.12
    tex=mat.node_tree.nodes.new('ShaderNodeTexImage'); tex.image=im
    if color:
        attr=mat.node_tree.nodes.new('ShaderNodeVertexColor'); attr.layer_name='Paint'
        mul=mat.node_tree.nodes.new('ShaderNodeMixRGB'); mul.blend_type='MULTIPLY'; mul.inputs[0].default_value=1
        mat.node_tree.links.new(tex.outputs['Color'],mul.inputs[1]); mat.node_tree.links.new(attr.outputs['Color'],mul.inputs[2])
        mat.node_tree.links.new(mul.outputs[0],p.inputs['Base Color'])
    else: mat.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color'])
    return mat

def bake_bark(obj, sid):
    """Bake the illustration's fine brushwork onto UVs, independent of vertex density."""
    mat=bpy.data.materials.new(sid+' - baked original bark brushwork');mat.use_nodes=True
    nodes=mat.node_tree.nodes;links=mat.node_tree.links;nodes.clear()
    output=nodes.new('ShaderNodeOutputMaterial');emit=nodes.new('ShaderNodeEmission')
    coordinates=nodes.new('ShaderNodeTexCoord')
    ns=[]
    for scale in [2.5,4.1]:
        n=nodes.new('ShaderNodeTexNoise');n.inputs['Scale'].default_value=scale;n.inputs['Detail'].default_value=2.3;n.inputs['Roughness'].default_value=.63
        links.new(coordinates.outputs['Object'],n.inputs['Vector']);ns.append(n)
    uv=nodes.new('ShaderNodeCombineXYZ')
    for n,axis,scale,offset in [(ns[0],'X',.20,.395),(ns[1],'Y',.28,.16)]:
        mult=nodes.new('ShaderNodeMath');mult.operation='MULTIPLY_ADD';mult.inputs[1].default_value=scale;mult.inputs[2].default_value=offset
        links.new(n.outputs['Fac'],mult.inputs[0]);links.new(mult.outputs[0],uv.inputs[axis])
    source=nodes.new('ShaderNodeTexImage');source.image=bark_image;links.new(uv.outputs[0],source.inputs['Vector'])
    mix=nodes.new('ShaderNodeMixRGB');mix.blend_type='MIX';mix.inputs[0].default_value=.12;mix.inputs[2].default_value=(.25,.13,.045,1)
    links.new(source.outputs['Color'],mix.inputs[1]);links.new(mix.outputs[0],emit.inputs[0]);links.new(emit.outputs[0],output.inputs['Surface'])
    obj.data.materials.clear();obj.data.materials.append(mat)
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(angle_limit=1.15,island_margin=.025);bpy.ops.object.mode_set(mode='OBJECT')
    baked=bpy.data.images.new(sid+'_bark',width=1024,height=1024,alpha=False)
    target=nodes.new('ShaderNodeTexImage');target.image=baked;nodes.active=target
    scene.render.bake.margin=12;bpy.ops.object.bake(type='EMIT')
    # Keep the bake packed in Blend/GLB; Godot extracts the runtime textures.
    # A separate source PNG here is unused and duplicates those textures.
    baked.file_format='PNG';baked.pack()
    nodes.clear();output=nodes.new('ShaderNodeOutputMaterial');p=nodes.new('ShaderNodeBsdfPrincipled');p.inputs['Roughness'].default_value=.96;p.inputs['Specular IOR Level'].default_value=.10
    texture=nodes.new('ShaderNodeTexImage');texture.image=baked
    links.new(texture.outputs['Color'],p.inputs['Base Color']);links.new(p.outputs[0],output.inputs['Surface'])
    # Color is already baked; keep neutral COLOR_0 for the shared import hook.
    colors=obj.data.color_attributes.get('Paint')
    for color in colors.data:color.color=(1,1,1,1)

CONFIGS=[
    dict(id='elder_oak',title='01 - Elder oak',ref='tree-oak-large.png',seed=117,radius=.62,
         spine=[(0,0,.04,.65),(.02,.04,.6,.55),(-.22,.02,1.45,.45),(-.05,.10,2.25,.36),(-.35,.15,3.25,.22),(-.12,.2,4.5,.075),(.12,.15,5.3,.014)],
         branches=[(-2.4,-.10,3.8), (2.30,.10,4.20),(-.75,1.9,4.60),(1.0,-1.5,4.65),(-1.35,.3,5.0)],cluster=(.87,.80,.57),leaves=56),
    dict(id='open_canopy',title='02 - Open canopy',ref='tree-canopy-medium.png',seed=214,radius=.47,
         spine=[(0,0,.04,.5),(-.12,.05,.8,.39),(.16,0,1.8,.30),(.40,.15,2.7,.22),(.15,.20,3.8,.09),(.45,.25,4.8,.013)],
         branches=[(-2.55,.0,3.65),(2.45,.3,3.8),(-.35,1.9,4.0),(.05,-1.85,3.9)],cluster=(1.02,.84,.48),leaves=60),
    dict(id='golden_leaning',title='03 - Golden leaning',ref='tree-yellow.png',seed=319,radius=.39,
         spine=[(0,0,.02,.44),(.08,.03,.7,.35),(.42,.10,1.7,.29),(.24,.15,2.6,.24),(.7,.20,3.7,.14),(1.0,.18,4.7,.055),(.86,.1,5.35,.012)],
         branches=[(-1.50,.05,3.25),(1.95,.2,3.9),(.10,1.30,4.6),(.25,-1.35,4.55)],cluster=(.73,.71,.63),leaves=49),
    dict(id='open_pine',title='04 - Open pine',ref='tree-pine-large.png',seed=420,radius=.39,
         spine=[(0,0,.02,.43),(-.08,.05,.7,.33),(.10,.05,2.0,.24),(-.13,0,3.4,.18),(.0,.04,4.8,.10),(-.14,.04,6.3,.018)],
         branches=[],cluster=(.85,.57,.29),leaves=29),
    dict(id='tall_pine',title='05 - Tall straight pine',ref='tree-pine-tall.png',seed=521,radius=.43,
         spine=[(0,0,.02,.46),(.015,0,.8,.36),(-.015,.01,2.4,.29),(.02,0,4.1,.22),(0,.01,5.9,.15),(.015,0,7.5,.08),(0,0,8.7,.026),(0,0,9.1,.009)],
         branches=[],cluster=(.74,.65,.43),leaves=24,density=1.45),
]
bark_image,_=image('tree-oak-large.png')
all_models=[]; reports=[]

for cfg in CONFIGS:
    rng=random.Random(cfg['seed']); sid=cfg['id']; pine=sid in ['open_pine','tall_pine']; tall=sid=='tall_pine'
    col=bpy.data.collections.new(cfg['title']); scene.collection.children.link(col)
    construction=bpy.data.collections.new(sid+' - editable branch construction'); col.children.link(construction)
    paths=[cfg['spine']]
    # Buttresses widen naturally into the foot, with asymmetric, buried tips.
    for i in range(7 if not pine else 6):
        a=math.tau*i/(7 if not pine else 6)+rng.uniform(-.12,.12); length=cfg['radius']*rng.uniform(2.35,3.3)
        paths.append([(0,0,.72,cfg['radius']*.50),(.42*math.cos(a),.42*math.sin(a),.28,cfg['radius']*.48),(.77*length*math.cos(a+.10),.77*length*math.sin(a+.10),.1,cfg['radius']*.26),(length*math.cos(a+.19),length*math.sin(a+.19),.015,.015)])
    clusters=[]
    if pine:
        for tier in range(9 if tall else 5):
            z=(1.90+tier*.77) if tall else (2.05+tier*.86)
            extent=(2.02-tier*.205) if tall else (1.90-tier*.30)
            branches=5 if tall else 4
            for j in range(branches):
                a=math.tau*j/branches+tier*.48+.20; end=Vector((extent*math.cos(a),extent*math.sin(a),z+(.27 if tall else .38)))
                paths.append([(0,0,z,max(.025,.13-tier*(.012 if tall else .018))),(*((Vector((0,0,z))+end)*.5+Vector((0,0,-.12))),max(.019,.077-tier*(.006 if tall else .010))),(*end,.013)])
                radii=tuple(v*(1-tier*(.082 if tall else .075)) for v in cfg['cluster'])
                count=max(10,int(cfg['leaves']*(1-tier*.055))) if tall else cfg['leaves']
                clusters.append((end+Vector((0,0,.16)),radii,count))
                inner=Vector((end.x*.53,end.y*.53,z+.20))
                clusters.append((inner,tuple(v*.75 for v in radii),max(5,int(count*.30))))
        clusters.append((Vector((0,0,8.85)) if tall else Vector((-.1,0,6.24)),(.24,.24,.44) if tall else (.33,.33,.43),30 if tall else 37))
    else:
        for i,xyz in enumerate(cfg['branches']):
            end=Vector(xyz); start=Vector((cfg['spine'][2][0],.04,1.50+i*.22))
            middle=start.lerp(end,.48)+Vector((0,0,-.43))
            near=start.lerp(end,.83)+Vector((0,0,-.38))
            paths.append([(*start,cfg['radius']*(.62-i*.038)),(*middle,.235-i*.015),(*near,.095),(*end,.018)])
            clusters.append((end+Vector((0,0,.30)),cfg['cluster'],cfg['leaves']))
            # Fill the outer bough as well as its tip, while keeping the lower fork visible.
            clusters.append((near+Vector((0,0,.33)),tuple(v*.76 for v in cfg['cluster']),int(cfg['leaves']*.35)))
            # A secondary fork grows outwards, leaving the crotch and inner bough bare.
            fork=end+Vector((rng.uniform(-.57,.57),rng.choice([-1,1])*.50,.68))
            base=middle.lerp(near,.38)
            paths.append([(*base,.10),(*base.lerp(fork,.57),.060),(*fork,.012)])
            clusters.append((fork+Vector((0,0,.21)),tuple(v*.78 for v in cfg['cluster']),int(cfg['leaves']*.72)))
        clusters.append((Vector(cfg['spine'][-1][:3])+Vector((0,0,.08)),cfg['cluster'],cfg['leaves']))
    pieces=[tube('Branch %02d'%i,p,construction,16 if i==0 else 12) for i,p in enumerate(paths)]
    # Low-relief growth collars add character to the visible front of the trunk.
    for k in range(2 if not pine else 1):
        z=1.0+k*.84;center=Vector((cfg['spine'][2][0]*.42,-cfg['radius']*(.78-k*.08),z))
        ring=[]
        for j in range(19):
            a=j*math.tau/18
            ring.append((*center+Vector((math.cos(a)*.14,-.018*math.sin(a*2),math.sin(a)*.22)),.041))
        pieces.append(tube('Old growth knot %d'%k,ring,construction,10))
    # Retain editable component paths, fuse duplicates into the actual game trunk.
    working=[]
    for obj in pieces:
        cp=obj.copy(); cp.data=obj.data.copy(); col.objects.link(cp); working.append(cp)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in working: obj.select_set(True)
    bpy.context.view_layer.objects.active=working[0]; bpy.ops.object.join(); trunk=bpy.context.object
    trunk.name='Trunk_LOD0'
    rem=trunk.modifiers.new('Continuous branch unions','REMESH'); rem.mode='VOXEL'; rem.voxel_size=.028; rem.use_smooth_shade=True
    bpy.ops.object.modifier_apply(modifier=rem.name)
    sm=trunk.modifiers.new('Round branch collars','SMOOTH'); sm.factor=.55; sm.iterations=3; bpy.ops.object.modifier_apply(modifier=sm.name)
    tri=sum(len(p.vertices)-2 for p in trunk.data.polygons)
    dec=trunk.modifiers.new('Trunk triangle budget','DECIMATE'); dec.ratio=min(1,8500/max(1,tri)); bpy.ops.object.modifier_apply(modifier=dec.name)
    trunk.data.validate(clean_customdata=True);trunk.data.update()
    for p in trunk.data.polygons: p.use_smooth=True
    trunk.data.uv_layers.new(name='Bark atlas')
    trunk.data.color_attributes.new(name='Paint',type='FLOAT_COLOR',domain='POINT')
    construction.hide_render=True; construction.hide_viewport=True
    bake_bark(trunk,sid)
    # Select only fully opaque, green/yellow foliage pixels; never sample the ground.
    im,px=image(cfg['ref']); patches=[]
    for _ in range(5000):
        u,v=rng.uniform(.12,.88),rng.uniform(.46,.92)
        samples=[sample(px,u+du,v+dv) for du,dv in [(-.022,-.027),(.022,-.027),(-.022,.027),(.022,.027),(0,0)]]
        if all(c[3]>.99 and c[1]>c[0]*.65 and c[1]>c[2]*1.45 for c in samples): patches.append((u,v))
    assert len(patches)>50,(sid,len(patches))
    leaf_mat=painted_material(sid+' - original painted leaves',im,True)
    leaves=[]
    for center,radii,count in clusters:
        count=round(count*cfg.get('density',1.60))
        radii=tuple(v*1.08 for v in radii)
        for j in range(count):
            a=rng.random()*math.tau; z=rng.uniform(-.42,1); r=math.sqrt(1-z*z)
            unit=Vector((r*math.cos(a),r*math.sin(a),z)); shell=rng.uniform(.40,1.0)
            offset=Vector([unit[i]*radii[i] for i in range(3)])*shell
            p=center+offset
            normal=(unit*.90+Vector((rng.uniform(-.45,.45),rng.uniform(-.45,.45),.43))).normalized()
            length=rng.uniform(.26,.40) if not pine else rng.uniform(.30,.46)
            leaves.append((p,normal,length,length*(rng.uniform(.52,.75) if pine else rng.uniform(.70,.92)),rng.choice(patches),rng.uniform(.94,1.10)))
    # Spread removal evenly across all clusters instead of collapsing whole crowns.
    order=list(range(len(leaves))); rng.shuffle(order)
    roots=[]; lod_report=[]
    for level,fraction in enumerate([1,.60,.30]):
        root=bpy.data.objects.new(sid+'_LOD'+str(level),None); col.objects.link(root); roots.append(root)
        wood=trunk if level==0 else trunk.copy()
        if level:
            wood.data=trunk.data.copy(); col.objects.link(wood); bpy.context.view_layer.objects.active=wood
            dec=wood.modifiers.new('Distant trunk simplification','DECIMATE'); dec.ratio=.50 if level==1 else .24
            bpy.ops.object.modifier_apply(modifier=dec.name)
            wood.data.validate(clean_customdata=True);wood.data.update()
        wood.name='Trunk_LOD'+str(level); wood.parent=root
        verts=[];faces=[];uvs=[];colors=[]
        for index in order[:int(len(leaves)*fraction)]:
            p,n,length,width,patch,tint=leaves[index]
            length*=1+level*.13; width*=1+level*.13
            ref=Vector((0,1,0)) if abs(n.y)<.9 else Vector((1,0,0))
            x=n.cross(ref).normalized(); y=n.cross(x).normalized()
            roll=(index*2.39996)%math.tau; right=x*math.cos(roll)+y*math.sin(roll); forward=n.cross(right)
            # Sixteen edges preserve a rounded, gently lobed brush-leaf silhouette.
            outline=[(0,-.51),(-.23,-.40),(-.46,-.28),(-.36,-.12),(-.51,.04),(-.38,.19),(-.34,.33),(-.17,.44),(0,.52),(.17,.44),(.34,.33),(.38,.19),(.51,.04),(.36,-.12),(.46,-.28),(.23,-.40)]
            start=len(verts); verts.append(p+n*length*.08); uvs.append(patch);colors.append((tint,tint,tint,1))
            for xx,yy in outline:
                verts.append(p+right*xx*width+forward*yy*length+n*length*(.02-.18*abs(yy)))
                uvs.append((patch[0]+xx*.039,patch[1]+yy*.049));colors.append((tint,tint,tint,1))
            for k in range(len(outline)):faces.append((start,start+1+(k+1)%len(outline),start+1+k))
        foliage=mesh_obj('Leaves_LOD'+str(level),verts,faces,col); foliage.parent=root; foliage.data.materials.append(leaf_mat)
        uv=foliage.data.uv_layers.new(name='Original foliage swatches')
        for l in foliage.data.loops: uv.data[l.index].uv=uvs[l.vertex_index]
        colors_attr=foliage.data.color_attributes.new(name='Paint',type='FLOAT_COLOR',domain='POINT')
        colors_attr.data.foreach_set('color',np.asarray(colors,dtype=np.float32).ravel())
        for p in foliage.data.polygons:p.use_smooth=True
        bpy.ops.object.select_all(action='DESELECT'); root.select_set(True); wood.select_set(True);foliage.select_set(True); bpy.context.view_layer.objects.active=wood
        bpy.ops.export_scene.gltf(filepath=str(OUT/(sid+'_lod%d.glb'%level)),export_format='GLB',use_selection=True,export_yup=True,export_animations=False,export_cameras=False,export_lights=False,export_vertex_color='ACTIVE',export_all_vertex_colors=False)
        triangles=sum(len(p.vertices)-2 for o in [wood,foliage] for p in o.data.polygons)
        lod_report.append(dict(level=level,triangles=triangles,leaves=int(len(leaves)*fraction),wood_triangles=sum(len(p.vertices)-2 for p in wood.data.polygons)))
        root.hide_render=level>0
        for o in root.children:o.hide_render=level>0;o.hide_set(level>0)
    report=dict(id=sid,reference='assets/vegetation/'+cfg['ref'],lods=lod_report,foliage_patches=len(patches))
    reports.append(report);all_models.append((cfg,col,roots))
    print('ILLUSTRATED_TREE',json.dumps(report),flush=True)

# Simple neutral studio. No illustrated floor pixels or shadow cards in any asset.
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.055)); ground=move_to(bpy.context.object,studio)
mat=bpy.data.materials.new('Studio - muted sage'); mat.use_nodes=True
mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.26,.32,.25,1)
mat.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=1; ground.data.materials.append(mat)
scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.65,.74,.82,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.65
bpy.ops.object.light_add(type='AREA',location=(-4,-6,10)); light=move_to(bpy.context.object,studio); light.data.energy=1250;light.data.shape='DISK';light.data.size=7
light.rotation_euler=(Vector((0,0,2.7))-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.light_add(type='SUN'); sun=move_to(bpy.context.object,studio);sun.data.energy=1.4;sun.data.angle=.22;sun.rotation_euler=(.40,-.46,-.40)
bpy.ops.object.camera_add();camera=move_to(bpy.context.object,studio);scene.camera=camera;camera.data.type='ORTHO'

def aim(position,target,scale):
    camera.location=position;camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=scale

def select_model(index):
    for i,(_,col,_) in enumerate(all_models):col.hide_render=i!=index

if '--render' in sys.argv:
    scene.render.resolution_x=1200;scene.render.resolution_y=1400;scene.render.resolution_percentage=100
    for index,(cfg,col,roots) in enumerate(all_models):
        select_model(index)
        aim((8,-14,8.4),(0,0,4.5),10.8) if cfg['id']=='tall_pine' else aim((8,-14,7.0),(0,0,3.0),7.5)
        scene.render.filepath=str(PREV/(cfg['id']+'.png'));bpy.ops.render.render(write_still=True)
        if index==0:
            aim((5,-11,3.1),(0,0,1.6),3.9);scene.render.filepath=str(PREV/'elder_oak_trunk.png');bpy.ops.render.render(write_still=True)
            aim((-8,12,6.7),(0,0,3.0),7.5);scene.render.filepath=str(PREV/'elder_oak_back.png');bpy.ops.render.render(write_still=True)

# Arrange an editable Blender gallery. Rendering-only floor and lights are separate.
for index,(cfg,col,roots) in enumerate(all_models):
    col.hide_render=False;offset=(index-(len(all_models)-1)/2)*7.0
    for root in roots:root.location.x=offset
    for child in col.children:
        for obj in child.objects:obj.location.x=offset
aim((0,-36,15),(0,0,3.8),36.0)
scene.render.resolution_x=2800;scene.render.resolution_y=1100
if '--render' in sys.argv:
    scene.render.filepath=str(PREV/'five_trees.png');bpy.ops.render.render(write_still=True)
    # Keep the existing four-tree comparison link current as well.
    all_models[-1][1].hide_render=True
    aim((-3.5,-30,14),(-3.5,0,2.5),29.5);scene.render.resolution_x=2400;scene.render.resolution_y=900
    scene.render.filepath=str(PREV/'four_trees.png');bpy.ops.render.render(write_still=True)
    all_models[-1][1].hide_render=False
    aim((0,-36,15),(0,0,3.8),36.0);scene.render.resolution_x=2800;scene.render.resolution_y=1100
for area in bpy.context.screen.areas:
    if area.type=='VIEW_3D':area.spaces.active.region_3d.view_perspective='CAMERA'
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/blender/illustrated_trees.blend'))
(OUT/'model_report.json').write_text(json.dumps(reports,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('ILLUSTRATED_TREES_READY',flush=True)
