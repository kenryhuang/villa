"""Original sculpted grove. Run with Blender --background --python this_file -- --render.

Deterministic branch paths remain editable in the blend; only diverse_trees outputs
are regenerated. Six silhouettes, baked bark/vertex-painted leaves, three explicit LODs.
"""
from pathlib import Path
import bpy
import bmesh
import math
import random
import json
import sys
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from tree_bark_materials import bake_bark, share_bark_images
OUT = ROOT / 'assets/models/vegetation/diverse_trees'
EXPORT_TMP = ROOT / 'tmp/diverse-tree-export'
EXPORT_TMP.mkdir(parents=True, exist_ok=True)
(EXPORT_TMP/'.gdignore').touch()
PREVIEW = ROOT / 'docs/validation/diverse-trees'
OUT.mkdir(parents=True, exist_ok=True)
PREVIEW.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.save_version = 0
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 24
scene.cycles.use_denoising = True
scene.view_settings.view_transform = 'Standard'
scene.view_settings.look = 'None'

CONFIGS = [
    dict(id='warm_oak', height=6.2, radius=.48, bark=('57301c','a57542'), leaf=('315d24','9eb64a'), form='oak'),
    dict(id='forked_birch', height=7.5, radius=.30, bark=('a07d49','eddbad'), leaf=('4c7c28','c4cf62'), form='birch'),
    dict(id='copper_maple', height=5.4, radius=.39, bark=('633124','b16d42'), leaf=('922f26','ee9b3e'), form='maple'),
    dict(id='golden_poplar', height=8.4, radius=.31, bark=('67522a','ba9660'), leaf=('a28b24','ead260'), form='poplar'),
    dict(id='blue_pine', height=8.0, radius=.36, bark=('612f20','b77346'), leaf=('235849','73a18b'), form='pine'),
    dict(id='weeping_willow', height=5.9, radius=.45, bark=('554b26','9d8b4b'), leaf=('577b32','bdc85e'), form='willow'),
]

def linear(hexcode):
    rgb = [int(hexcode[i:i+2],16)/255 for i in (0,2,4)]
    return Vector([v/12.92 if v<.04045 else ((v+.055)/1.055)**2.4 for v in rgb])

def paint_material(name):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Roughness'].default_value = .92
    bsdf.inputs['Specular IOR Level'].default_value = .12
    attr = mat.node_tree.nodes.new('ShaderNodeVertexColor')
    attr.layer_name = 'Paint'
    mat.node_tree.links.new(attr.outputs['Color'],bsdf.inputs['Base Color'])
    return mat

def mesh_object(name, verts, faces, collection):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name,mesh)
    collection.objects.link(obj)
    return obj

def smooth_path(points):
    result=[]
    for i in range(len(points)-1):
        a,b,c,d=[Vector(points[max(0,min(len(points)-1,k))]) for k in (i-1,i,i+1,i+2)]
        for j in range(5):
            t=j/5
            p=.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t)
            p.w=max(.009,p.w)
            result.append(p)
    return result+[Vector(points[-1])]

def tube(points, collection, name):
    points=smooth_path(points)
    vv=[]; ff=[]; sides=12
    for i,p in enumerate(points):
        tangent=(points[min(i+1,len(points)-1)].xyz-points[max(0,i-1)].xyz).normalized()
        ref=Vector((0,1,0)) if abs(tangent.y)<.9 else Vector((1,0,0))
        u=tangent.cross(ref).normalized(); v=tangent.cross(u)
        for k in range(sides):
            angle=math.tau*k/sides
            radius=p.w*(1+.10*math.sin(angle*5+i*.08))
            vv.append(p.xyz+radius*(u*math.cos(angle)+v*math.sin(angle)))
            if i: ff.append(((i-1)*sides+k,(i-1)*sides+(k+1)%sides,i*sides+(k+1)%sides,i*sides+k))
    ff += [tuple(reversed(range(sides))),tuple((len(points)-1)*sides+k for k in range(sides))]
    return mesh_object(name,vv,ff,collection)

gallery=[]; reports=[]
for species_index,cfg in enumerate(CONFIGS):
    rng=random.Random(8103+species_index*177)
    sid=cfg['id']; h=cfg['height']; r=cfg['radius']; form=cfg['form']
    collection=bpy.data.collections.new(sid)
    scene.collection.children.link(collection)
    construction=bpy.data.collections.new(sid+' / editable branch paths')
    collection.children.link(construction)
    lean={'oak':-.32,'birch':.22,'maple':.85,'poplar':.12,'pine':-.13,'willow':-.50}[form]
    def spine(z):
        return Vector((lean*(z/h)**1.3+.11*math.sin(z*1.8)*min(1,z),.10*math.sin(z*.8),z))
    paths=[[(*spine(h*t),radius) for t,radius in [(0,r*1.3),(.10,r),(.25,r*.82),(.45,r*.59),(.68,r*.33),(.88,r*.13),(.97,.012)]]]
    # Low roots bury their terminal surfaces and can be fitted to the game terrain.
    for k in range(7):
        a=k*math.tau/7+rng.uniform(-.16,.16)
        length=rng.uniform(.85,1.28)
        paths.append([(0,0,.48,r*.6),(.36*math.cos(a),.36*math.sin(a),.18,r*.52),(.74*length*math.cos(a+.1),.74*length*math.sin(a+.1),.045,.08),(length*math.cos(a+.2),length*math.sin(a+.2),-.045,.012)])
    clusters=[]
    if form=='pine':
        for tier in range(7):
            z=1.75+tier*.84
            for j in range(5):
                a=j*math.tau/5+tier*.71
                reach=2.35-tier*.29
                end=spine(z)+Vector((math.cos(a)*reach,math.sin(a)*reach,.32))
                mid=spine(z).lerp(end,.54)-Vector((0,0,.17))
                paths.append([(*spine(z),.15-tier*.016),(*mid,.07),(*end,.012)])
                for t in (.54,.86,1.0):
                    center=spine(z).lerp(end,t)+Vector((0,0,.24))
                    clusters.append((center,(.72*(1-tier*.065),.60*(1-tier*.065),.34),60))
        clusters.append((spine(h*.95),(.35,.35,.55),100))
    else:
        count={'oak':7,'birch':7,'maple':7,'poplar':12,'willow':8}[form]
        for j in range(count):
            a=j*2.39996+.3
            if form=='poplar':
                z=2.1+j*.41; reach=1.25*(1-.45*j/count); top=z+1.4
            elif form=='birch':
                z=1.0+j*.49; reach=1.65 if j<4 else 1.15; top=min(h-.4,z+2.9)
            else:
                z=1.25+j*.29; reach=(2.55 if form in ('oak','willow') else 2.05)*rng.uniform(.83,1.12)
                top=h*.59+j*.15
            start=spine(z); end=Vector((lean*.7+math.cos(a)*reach,math.sin(a)*reach,top))
            middle=start.lerp(end,.48)-Vector((0,0,.35))
            radius=r*(.70 if form!='poplar' else .39)*(1-j/count*.42)
            paths.append([(*start,radius),(*middle,radius*.75),(*start.lerp(end,.83),radius*.36),(*end,.012)])
            cluster_radius=(.96,.85,.65) if form!='poplar' else (.66,.60,.90)
            if form=='willow': cluster_radius=(.81,.75,.48)
            clusters.append((end+Vector((0,0,.24)),cluster_radius,150))
            # Branches fork twice, producing visible gaps between unequal leaf sprays.
            for side in (-1,1):
                base=middle.lerp(end,.38)
                tip=end+Vector((math.cos(a+side*1.2)*.65,math.sin(a+side*1.2)*.65,.65 if form!='willow' else .12))
                paths.append([(*base,radius*.38),(*base.lerp(tip,.56),radius*.22),(*tip,.012)])
                clusters.append((tip,tuple(x*.8 for x in cluster_radius),100))
                if form=='willow':
                    droop=tip+Vector((math.cos(a)*.38,math.sin(a)*.38,-rng.uniform(1.5,2.5)))
                    paths.append([(*base,.045),(*tip,.030),(*tip.lerp(droop,.5),.019),(*droop,.009)])
                    for t in (.25,.55,.85):
                        clusters.append((tip.lerp(droop,t),(.32,.32,.50),65))
        clusters.append((spine(h*.91),(.72,.67,.70) if form!='poplar' else (.48,.45,.8),180))
    # Two short old bough stubs and growth collars keep exposed trunks readable.
    if form in ('oak','maple','willow'):
        for z,a in [(1.12,-1.8),(2.15,.5)]:
            start=spine(z)
            paths.append([(*start,.18),(*(start+Vector((math.cos(a)*.48,math.sin(a)*.48,.18))),.11),(*(start+Vector((math.cos(a)*.62,math.sin(a)*.62,.36))),.065)])
    parts=[tube(path,construction,'Bough_%02d'%i) for i,path in enumerate(paths)]
    # Copy editable paths, fuse only the game mesh for continuous branch junctions.
    bpy.ops.object.select_all(action='DESELECT')
    for part in parts:
        cp=part.copy(); cp.data=part.data.copy(); collection.objects.link(cp); cp.select_set(True)
    bpy.context.view_layer.objects.active=cp
    bpy.ops.object.join(); trunk=bpy.context.object; trunk.name='Trunk_LOD0'
    rem=trunk.modifiers.new('Fused branch collars','REMESH'); rem.mode='VOXEL'; rem.voxel_size=.032
    bpy.ops.object.modifier_apply(modifier=rem.name)
    # Voxelisation can isolate sub-voxel twig tips. Keep the connected trunk so
    # inspecting the bare model never exposes floating splinters.
    bm=bmesh.new();bm.from_mesh(trunk.data)
    unseen=set(bm.verts);components=[]
    while unseen:
        seed=unseen.pop();component={seed};queue=[seed]
        while queue:
            vertex=queue.pop()
            for edge in vertex.link_edges:
                neighbor=edge.other_vert(vertex)
                if neighbor in unseen:
                    unseen.remove(neighbor);component.add(neighbor);queue.append(neighbor)
        components.append(component)
    keep=max(components,key=len)
    bmesh.ops.delete(bm,geom=[v for component in components if component is not keep for v in component],context='VERTS')
    bm.to_mesh(trunk.data);bm.free()
    sm=trunk.modifiers.new('Soft growth transitions','SMOOTH'); sm.factor=.55; sm.iterations=3
    bpy.ops.object.modifier_apply(modifier=sm.name)
    tri=sum(len(p.vertices)-2 for p in trunk.data.polygons)
    dec=trunk.modifiers.new('Game budget','DECIMATE'); dec.ratio=min(1,6500/tri)
    bpy.ops.object.modifier_apply(modifier=dec.name)
    construction.hide_render=True; construction.hide_viewport=True
    bark_low,bark_high=map(linear,cfg['bark'])
    colors=trunk.data.color_attributes.new(name='Paint',type='FLOAT_COLOR',domain='POINT')
    for vertex,c in zip(trunk.data.vertices,colors.data):
        x,y,z=vertex.co; angle=math.atan2(y,x)
        grain=.5+.22*math.sin(angle*19+math.sin(z*1.8)*.6)+.13*math.sin(angle*37-z*.7)
        grain+=.08*math.sin(x*23+y*16+z*3)
        color=bark_low.lerp(bark_high,max(0,min(1,grain)))
        if form=='birch':
            band=math.sin(z*23+math.sin(angle*3)*1.6)
            if band>.88 and math.sin(angle*7+z*5)>.10: color*=.32
        if z<.45: color=color.lerp(linear('526133'),.24*(1-z/.45))
        c.color=(*color,1)
    trunk.data.materials.append(paint_material(sid+' / textured bark colors'))
    for p in trunk.data.polygons:p.use_smooth=True
    bake_bark(trunk, cfg, OUT)
    leaves=[]
    for center,radii,count in clusters:
        for k in range(count):
            a=rng.random()*math.tau; nz=rng.uniform(-.8,1); rr=math.sqrt(1-nz*nz)
            unit=Vector((rr*math.cos(a),rr*math.sin(a),nz))
            pos=center+Vector([unit[i]*radii[i] for i in range(3)])*rng.uniform(.25,1)
            normal=(unit*.6+Vector((0,0,.65))).normalized()
            length=rng.uniform(.23,.39) if form!='willow' else rng.uniform(.27,.44)
            width=length*({'pine':.46,'willow':.28,'maple':1.0}.get(form,.72))
            leaves.append((pos,normal,length,width,rng.random(),rng.random()*math.tau))
    rng.shuffle(leaves)
    leaf_low,leaf_high=map(linear,cfg['leaf'])
    leaf_mat=paint_material(sid+' / leaf color gradients')
    roots=[]; lods=[]
    for lod,fraction in enumerate((1,.52,.23)):
        parent=bpy.data.objects.new(sid+'_LOD%d'%lod,None); collection.objects.link(parent); roots.append(parent)
        wood=trunk if lod==0 else trunk.copy()
        if lod:
            wood.data=trunk.data.copy(); collection.objects.link(wood)
            bpy.context.view_layer.objects.active=wood
            dec=wood.modifiers.new('Distant boughs','DECIMATE'); dec.ratio=.5 if lod==1 else .22
            bpy.ops.object.modifier_apply(modifier=dec.name)
        wood.name='Trunk_LOD%d'%lod; wood.parent=parent
        vv=[]; ff=[]; cc=[]
        for pos,n,length,width,tint,roll in leaves[:int(len(leaves)*fraction)]:
            length*=1+lod*.24; width*=1+lod*.24
            ref=Vector((0,1,0)) if abs(n.y)<.9 else Vector((1,0,0))
            u=n.cross(ref).normalized(); v=n.cross(u)
            u,v=u*math.cos(roll)+v*math.sin(roll),v*math.cos(roll)-u*math.sin(roll)
            if form=='willow': v=Vector((0,0,1)); u=Vector((math.cos(roll),math.sin(roll),0))
            shape=[(0,-.55),(-.43,-.23),(-.50,.12),(0,.57),(.50,.12),(.43,-.23)]
            if form=='maple': shape=[(0,-.55),(-.26,-.2),(-.59,.08),(-.22,.16),(0,.60),(.22,.16),(.59,.08),(.26,-.2)]
            base=len(vv)
            color=leaf_low.lerp(leaf_high,max(0,min(1,.18+tint*.59+(pos.z/h-.5)*.34)))
            vv.append(pos+n*length*.08); cc.append((*color*1.07,1))
            for xx,yy in shape:
                vv.append(pos+u*xx*width+v*yy*length-n*abs(xx)*length*.10)
                cc.append((*color*(.87 if xx<0 else 1.02),1))
            for k in range(len(shape)):ff.append((base,base+1+(k+1)%len(shape),base+1+k))
        foliage=mesh_object('Leaves_LOD%d'%lod,vv,ff,collection); foliage.parent=parent
        attr=foliage.data.color_attributes.new(name='Paint',type='FLOAT_COLOR',domain='POINT')
        attr.data.foreach_set('color',[c for color in cc for c in color])
        foliage.data.materials.append(leaf_mat)
        for p in foliage.data.polygons:p.use_smooth=True
        bpy.ops.object.select_all(action='DESELECT')
        for o in (parent,wood,foliage):o.select_set(True)
        bpy.context.view_layer.objects.active=wood
        export_name = sid+'_lod%d.glb'%lod
        bpy.ops.export_scene.gltf(filepath=str(EXPORT_TMP/export_name),export_format='GLB',use_selection=True,export_yup=True,export_animations=False,export_vertex_color='ACTIVE')
        share_bark_images(EXPORT_TMP/export_name, OUT/export_name)
        lods.append(dict(level=lod,triangles=sum(len(p.vertices)-2 for o in (wood,foliage) for p in o.data.polygons),leaves=int(len(leaves)*fraction)))
        for o in (wood,foliage):o.hide_render=lod>0; o.hide_set(lod>0)
    reports.append(dict(**cfg,branch_paths=len(paths),lods=lods))
    gallery.append((collection,roots))
    print('DIVERSE_TREE',sid,lods,flush=True)

studio=bpy.data.collections.new('STUDIO / not exported');scene.collection.children.link(studio)
def studio_object(obj):
    for col in list(obj.users_collection):col.objects.unlink(obj)
    studio.objects.link(obj)
    return obj
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.10))
floor=studio_object(bpy.context.object)
mat=bpy.data.materials.new('Warm sage backdrop');mat.diffuse_color=(.23,.28,.23,1);floor.data.materials.append(mat)
scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.72,.80,.90,1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value=.7
bpy.ops.object.light_add(type='AREA',location=(-7,-10,16));light=studio_object(bpy.context.object)
light.data.energy=2000;light.data.shape='DISK';light.data.size=12
light.rotation_euler=(Vector((0,0,3))-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.light_add(type='SUN');sun=studio_object(bpy.context.object);sun.data.energy=1.4;sun.data.angle=.2;sun.rotation_euler=(.45,-.5,-.4)
bpy.ops.object.camera_add();camera=studio_object(bpy.context.object);scene.camera=camera;camera.data.type='ORTHO'
def aim(pos,target,scale):
    camera.location=pos;camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=scale
for i,(col,roots) in enumerate(gallery):
    for root in roots:root.location.x=(i-2.5)*6.5
    for child in col.children:
        for obj in child.objects:obj.location.x=(i-2.5)*6.5
aim((0,-40,15),(0,0,3.8),40)
scene.render.resolution_x=2600;scene.render.resolution_y=900;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
if '--render' in sys.argv:
    scene.render.filepath=str(PREVIEW/'six_trees.png');bpy.ops.render.render(write_still=True)
    for _,roots in gallery:
        for obj in roots[0].children:
            if obj.name.startswith('Leaves'):obj.hide_render=True
    scene.render.filepath=str(PREVIEW/'six_trunks.png');bpy.ops.render.render(write_still=True)
    for _,roots in gallery:
        for obj in roots[0].children:obj.hide_render=False
for area in bpy.context.screen.areas:
    if area.type=='VIEW_3D':area.spaces.active.region_3d.view_perspective='CAMERA'
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/blender/diverse_trees.blend'))
(OUT/'model_report.json').write_text(json.dumps(reports,indent=2)+'\n',encoding='utf-8')
print('DIVERSE_TREES_READY',flush=True)
