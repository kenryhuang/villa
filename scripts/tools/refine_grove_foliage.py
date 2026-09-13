"""Refine the five remaining grove species with attached, species-shaped leaves.

Blender --factory-startup --background --disable-autoexec --python this_file
Run after build_diverse_trees.py; refine_willow_foliage.py handles willow separately.
This edits foliage only and reuses the exact authored trunk meshes and bark UVs.
"""
from pathlib import Path
import bpy
import json
import math
import random
import sys
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(Path(__file__).resolve().parent))
from tree_bark_materials import share_bark_images

OUT=ROOT/'assets/models/vegetation/diverse_trees'
TEMP=ROOT/'tmp/grove-leaf-export'
TEMP.mkdir(parents=True,exist_ok=True)
(TEMP/'.gdignore').touch()
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'art/blender/diverse_trees.blend'),use_scripts=False)
bpy.context.preferences.filepaths.save_version=0
reports=json.loads((OUT/'model_report.json').read_text())

CONFIGS=[
    dict(id='warm_oak',form='oak',length=(.14,.23),width=.62,color=(.056,.139,.018),fresh=(.11,.23,.028),branches=7),
    dict(id='forked_birch',form='birch',length=(.105,.18),width=.77,color=(.085,.205,.025),fresh=(.16,.29,.045),branches=7),
    dict(id='copper_maple',form='maple',length=(.15,.24),width=1.10,color=(.34,.060,.017),fresh=(.60,.20,.025),branches=7),
    dict(id='golden_poplar',form='poplar',length=(.12,.20),width=.82,color=(.37,.255,.019),fresh=(.64,.45,.052),branches=12),
    dict(id='blue_pine',form='pine',length=(.13,.23),width=.08,color=(.022,.095,.063),fresh=(.05,.15,.105),branches=35),
]

# Counterclockwise outlines, with root at y=0 and blade tip at y=1.
SHAPES={
    'oak':[(0,0),(-.20,.09),(-.38,.16),(-.46,.26),(-.26,.32),(-.49,.43),(-.50,.53),(-.28,.58),(-.38,.71),(-.30,.84),(0,1),(.30,.84),(.38,.71),(.28,.58),(.50,.53),(.49,.43),(.26,.32),(.46,.26),(.38,.16),(.20,.09)],
    'birch':[(0,0),(-.36,.17),(-.50,.38),(-.40,.43),(-.44,.57),(-.26,.67),(0,1),(.26,.67),(.44,.57),(.40,.43),(.50,.38),(.36,.17)],
    'maple':[(0,0),(-.21,.14),(-.47,.13),(-.30,.35),(-.55,.52),(-.26,.51),(-.29,.76),(-.12,.66),(0,1),(.12,.66),(.29,.76),(.26,.51),(.55,.52),(.30,.35),(.47,.13),(.21,.14)],
    'poplar':[(0,0),(-.30,.09),(-.49,.27),(-.48,.50),(-.27,.73),(0,1),(.27,.73),(.48,.50),(.49,.27),(.30,.09)],
}

def sample(path,t):
    index=t*(len(path)-1);i=min(int(index),len(path)-2)
    return path[i].lerp(path[i+1],index-i)

def safe_side(direction):
    ref=Vector((0,0,1)) if abs(direction.z)<.94 else Vector((0,1,0))
    return direction.cross(ref).normalized()

for species_index,cfg in enumerate(CONFIGS):
    if '--species' in sys.argv and cfg['id'] != sys.argv[sys.argv.index('--species')+1]:
        continue
    sid=cfg['id'];form=cfg['form'];rng=random.Random(260915+species_index*419)
    collection=bpy.data.collections[sid]
    construction=next(c for c in collection.children if 'editable branch paths' in c.name)
    paths={}
    for obj in construction.objects:
        number=int(obj.name.split('_')[1].split('.')[0])
        paths[number]=[sum((v.co for v in obj.data.vertices[i:i+12]),Vector())/12
                       for i in range(0,len(obj.data.vertices),12)]
    shoots=[];leaves=[]
    low=Vector(cfg['color']);fresh=Vector(cfg['fresh'])

    def leaf(point,direction,length,rank=None):
        direction=direction.normalized()
        side=safe_side(direction)
        normal=side.cross(direction).normalized()
        # Diverse planes reveal the folded surface instead of forming flat stacks.
        roll=rng.uniform(-.85,.85)
        side=side*math.cos(roll)+normal*math.sin(roll)
        normal=side.cross(direction).normalized()
        width=length*cfg['width']*rng.uniform(.87,1.12)
        color=low.lerp(fresh,rng.uniform(.05,.50))*rng.uniform(.87,1.10)
        leaves.append((point,direction,side,normal,length,width,color,rng.random() if rank is None else rank))

    def shoot(root,angle,reach,rise,arch,secondary=True):
        radial=Vector((math.cos(angle),math.sin(angle),0))
        side=Vector((-radial.y,radial.x,0))
        bend=rng.uniform(-.11,.11)
        path=[root+radial*reach*t+side*bend*math.sin(t*math.pi)
              +Vector((0,0,rise*t+arch*math.sin(t*math.pi))) for t in [i/6 for i in range(7)]]
        shoots.append(path)
        arc=sum((b-a).length for a,b in zip(path,path[1:]))
        if form=='pine':
            count=max(8,int(arc/.039))
            phase=rng.random()*math.tau
            for k in range(count):
                t=.12+.85*(k+.4)/count
                p=sample(path,t)
                tangent=(sample(path,min(1,t+.025))-sample(path,max(0,t-.025))).normalized()
                u=safe_side(tangent);v=tangent.cross(u)
                # Whorled pairs of individually modeled narrow needles.
                for n in range(4):
                    angle_n=phase+k*2.39996+n*math.tau/4+rng.uniform(-.15,.15)
                    direction=(tangent*.55+u*math.cos(angle_n)+v*math.sin(angle_n)).normalized()
                    leaf(p,direction,rng.uniform(*cfg['length'])*(1-.24*t))
            if secondary:
                for t,sign in [(.45,-1),(.72,1)]:
                    shoot(sample(path,t),angle+sign*rng.uniform(.65,1.15),reach*.58,
                          rng.uniform(.03,.14),.04,False)
        else:
            count=max(7,int(arc/rng.uniform(.042,.062)))
            phase=rng.random()*math.tau
            for k in range(count):
                t=.14+.82*(k+rng.uniform(.1,.9))/count
                p=sample(path,t)
                leaf_angle=angle+phase+k*2.39996+rng.uniform(-.20,.20)
                direction=Vector((math.cos(leaf_angle),math.sin(leaf_angle),rng.uniform(-.65,.45)))
                leaf(p,direction,rng.uniform(*cfg['length'])*(1-.12*t))
            if secondary:
                for t,sign in [(.45,-1),(.73,1)]:
                    shoot(sample(path,t),angle+sign*rng.uniform(.65,1.35),reach*rng.uniform(.34,.53),
                          rng.uniform(-.15,.20),.06,False)

    if form=='pine':
        for number in range(8,43):
            path=paths[number]
            end=path[-1];a=math.atan2(end.y,end.x)
            tier=(number-8)//5
            for k in range(9):
                t=.30+.69*(k+.5)/9
                root=sample(path,t)
                side=-1 if k%2 else 1
                shoot(root,a+side*rng.uniform(.35,1.15),rng.uniform(.29,.60)*(1-tier*.065),
                      rng.uniform(.05,.21),.075,True)
        for k in range(22):
            root=sample(paths[0],.83+.165*(k+.3)/22)
            shoot(root,k*2.39996,rng.uniform(.13,.31),rng.uniform(.08,.26),.03,False)
    else:
        for j in range(cfg['branches']):
            a=j*2.39996+.3
            for number in range(8+j*3,11+j*3):
                path=paths[number]
                count=5 if form=='poplar' else 6
                for k in range(count):
                    t=.56+.43*(k+.5)/count
                    root=sample(path,t)
                    reach=rng.uniform(.37,.77)*( .72 if form=='poplar' else 1)
                    rise=rng.uniform(-.14,.27) if form!='poplar' else rng.uniform(.16,.46)
                    shoot(root,a+rng.uniform(-1.8,1.8),reach,rise,rng.uniform(.07,.22))
        for k in range(30):
            root=sample(paths[0],.76+.235*(k+.2)/30)
            reach=rng.uniform(.27,.60)*( .65 if form=='poplar' else 1)
            shoot(root,k*2.39996,reach,rng.uniform(-.02,.22),.08)

    material=bpy.data.materials.new(sid+' / modeled leaves and twigs')
    material.use_nodes=True;material.use_backface_culling=False
    bsdf=material.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Roughness'].default_value=.9
    bsdf.inputs['Specular IOR Level'].default_value=.15
    attr=material.node_tree.nodes.new('ShaderNodeVertexColor');attr.layer_name='Paint'
    material.node_tree.links.new(attr.outputs['Color'],bsdf.inputs['Base Color'])
    lods=[]
    for lod,retention in enumerate((1,.62,.32)):
        parent=bpy.data.objects[sid+'_LOD%d'%lod]
        wood=next(o for o in parent.children if o.name.startswith('Trunk'))
        for obj in list(parent.children):
            if obj.name.startswith('Leaves'):bpy.data.objects.remove(obj,do_unlink=True)
        verts=[];faces=[];colors=[]
        def vertex(p,c):
            verts.append(p);colors.append((*c,1))
        for path in shoots:
            rings=path[::(1 if lod==0 else 2 if lod==1 else 3)]
            base=len(verts)
            for i,p in enumerate(rings):
                tangent=(rings[min(i+1,len(rings)-1)]-rings[max(0,i-1)]).normalized()
                side=safe_side(tangent);normal=tangent.cross(side)
                radius=.0065*(1-i/(len(rings)-1))+.0018
                for k in range(3):
                    a=k*math.tau/3
                    vertex(p+(side*math.cos(a)+normal*math.sin(a))*radius,Vector((.095,.074,.028)))
                    if i:
                        aa=base+(i-1)*3+k;bb=base+(i-1)*3+(k+1)%3
                        cc=base+i*3+(k+1)%3;dd=base+i*3+k
                        faces.extend([(aa,bb,cc),(aa,cc,dd)])
        kept=0
        for point,direction,side,normal,length,width,color,rank in leaves:
            if rank>=retention:continue
            kept+=1
            length*=(1,1.04,1.09)[lod];width*=(1,1.15,1.36)[lod]
            base=len(verts)
            if form=='pine':
                vertex(point,color*.86)
                vertex(point+direction*length*.45-side*width*.5+normal*width*.1,color)
                vertex(point+direction*length+normal*length*.06,color*1.04)
                vertex(point+direction*length*.45+side*width*.5-normal*width*.1,color*.95)
                faces.extend([(base,base+1,base+2),(base,base+2,base+3)])
            else:
                outline=SHAPES[form]
                if lod==2 and form in ('oak','birch'):
                    outline=[(0,0),(-.40,.18),(-.50,.45),(-.30,.72),(0,1),(.30,.72),(.50,.45),(.40,.18)]
                vertex(point+direction*length*.43+normal*width*.10,color*1.04)
                for x,y in outline:
                    vertex(point+direction*length*y+side*width*x-normal*length*.07*y*y,
                           color*(.94 if x<0 else 1.02))
                for k in range(len(outline)):faces.append((base,base+1+k,base+1+(k+1)%len(outline)))
        mesh=bpy.data.meshes.new(sid+' detailed foliage LOD%d'%lod)
        mesh.from_pydata(verts,[],faces);mesh.update()
        paint=mesh.color_attributes.new(name='Paint',type='FLOAT_COLOR',domain='POINT')
        paint.data.foreach_set('color',[x for c in colors for x in c]);mesh.materials.append(material)
        foliage=bpy.data.objects.new('Leaves_LOD%d'%lod,mesh)
        collection.objects.link(foliage);foliage.parent=parent
        saved_position=parent.location.copy();parent.location=Vector()
        wood.hide_set(False);wood.hide_render=False
        bpy.ops.object.select_all(action='DESELECT')
        for obj in (parent,wood,foliage):obj.select_set(True)
        bpy.context.view_layer.objects.active=wood
        name=sid+'_lod%d.glb'%lod
        bpy.ops.export_scene.gltf(filepath=str(TEMP/name),export_format='GLB',use_selection=True,
                                 export_yup=True,export_animations=False,export_vertex_color='ACTIVE')
        share_bark_images(TEMP/name,OUT/name)
        parent.location=saved_position
        for obj in (wood,foliage):obj.hide_render=lod>0;obj.hide_set(lod>0)
        lods.append(dict(level=lod,leaves=kept,shoots=len(shoots),
                         triangles=len(faces)+sum(len(p.vertices)-2 for p in wood.data.polygons)))
    for entry in reports:
        if entry['id']==sid:
            entry['lods']=lods
            entry['foliage']='Attached branching shoots; individually folded '+form+' leaves with local leaf lighting.'
            entry['foliage_palette_linear']=[cfg['color'],cfg['fresh']]
    print('GROVE_LEAVES',sid,json.dumps(lods),flush=True)

bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/blender/diverse_trees.blend'))
(OUT/'model_report.json').write_text(json.dumps(reports,indent=2)+'\n')
print('GROVE_FOLIAGE_READY',flush=True)
