"""Convert xablend1122's hair grass into small instanced game meshes (CC BY 3.0)."""
from pathlib import Path
import bpy,json,math,random
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'art/blender/import/Photorealistic Grass/GrasTest.blend'
OUT=ROOT/'assets/models/vegetation/photoreal_grass'
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(SOURCE),use_scripts=False)
obj=bpy.data.objects['Plane'];settings=obj.particle_systems[0].settings
source_count=settings.count;source_children=settings.rendered_child_count
settings.child_type='NONE'
dg=bpy.context.evaluated_depsgraph_get();dg.update()
evaluated=obj.evaluated_get(dg)
curves=[]
for particle in evaluated.particle_systems[0].particles:
    points=[obj.matrix_world@key.co for key in particle.hair_keys]
    root=points[0];points=[p-root for p in points]
    if points[-1].z>.15 and sum((b-a).length for a,b in zip(points,points[1:]))>.18:
        curves.append(points)
assert len(curves)>100
for obj in list(bpy.data.objects):bpy.data.objects.remove(obj,do_unlink=True)
bpy.context.preferences.filepaths.save_version=0
mat=bpy.data.materials.new('Photoreal grass / adapted olive green')
mat.use_nodes=True;mat.use_backface_culling=False
bsdf=mat.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Roughness'].default_value=.94
paint=mat.node_tree.nodes.new('ShaderNodeVertexColor');paint.layer_name='BladeColor'
mat.node_tree.links.new(paint.outputs['Color'],bsdf.inputs['Base Color'])
reports=[]
for variant in range(3):
    rng=random.Random(69868+variant*173)
    blades=[]
    for i in range(52):
        source=rng.choice(curves)
        height=rng.uniform(.16,.29)
        angle=rng.uniform(0,math.tau);c=math.cos(angle);s=math.sin(angle)
        radius=math.sqrt(rng.random())*.16
        root_angle=rng.uniform(0,math.tau)
        root=Vector((math.cos(root_angle)*radius,math.sin(root_angle)*radius,0))
        points=[]
        bend_angle=rng.uniform(0,math.tau)
        bend=rng.uniform(.025,.09)
        for j,p in enumerate(source):
            t=j/(len(source)-1)
            p=p*(height/source[-1].z)
            points.append(root+Vector((p.x*c-p.y*s+math.cos(bend_angle)*bend*t*t,
                                      p.x*s+p.y*c+math.sin(bend_angle)*bend*t*t,p.z)))
        blades.append((points,rng.uniform(.006,.013),rng.uniform(0,math.tau),rng.uniform(.85,1.13)))
    for lod in range(2):
        vv=[];ff=[];cc=[];uv=[]
        kept=blades if lod==0 else blades[::3]
        for points,width,angle,tint in kept:
            path=points if lod==0 else [points[0],points[len(points)//2],points[-1]]
            width*=1 if lod==0 else 1.65
            side=Vector((math.cos(angle),math.sin(angle),0))
            base=len(vv)
            for i,p in enumerate(path):
                t=i/(len(path)-1)
                if i==len(path)-1:
                    vv.append(p);uv.append((.5,1))
                    cc.append((.11*tint,.255*tint,.024*tint,1))
                    ff.append((base+(i-1)*2,base+(i-1)*2+1,base+i*2))
                else:
                    color=Vector((.018,.052,.005)).lerp(Vector((.095,.22,.018)),t**.55)*tint
                    for sign in [-1,1]:
                        vv.append(p+side*width*(1-t*.85)*sign*.5)
                        uv.append(((sign+1)*.5,t));cc.append((*color,1))
                    if i:
                        a=base+(i-1)*2;b=a+1;c=base+i*2;d=c+1
                        ff.extend([(a,b,d),(a,d,c)])
        mesh=bpy.data.meshes.new('Grass blades');mesh.from_pydata(vv,[],ff);mesh.update()
        color=mesh.color_attributes.new(name='BladeColor',type='FLOAT_COLOR',domain='POINT')
        color.data.foreach_set('color',[x for v in cc for x in v])
        uvlayer=mesh.uv_layers.new(name='BladeUV')
        for loop in mesh.loops:uvlayer.data[loop.index].uv=uv[loop.vertex_index]
        mesh.materials.append(mat)
        for p in mesh.polygons:p.use_smooth=True
        tuft=bpy.data.objects.new('GrassTuft_%d_LOD%d'%(variant,lod),mesh);bpy.context.collection.objects.link(tuft)
        bpy.ops.object.select_all(action='DESELECT');tuft.select_set(True);bpy.context.view_layer.objects.active=tuft
        bpy.ops.export_scene.gltf(filepath=str(OUT/('tuft_%d_lod%d.glb'%(variant,lod))),export_format='GLB',use_selection=True,
                                 export_yup=True,export_animations=False,export_vertex_color='ACTIVE')
        reports.append(dict(variant=variant,lod=lod,blades=len(kept),triangles=len(ff)))
        tuft.location.x=variant*.6;tuft.location.y=lod*.65
info=dict(source='Photorealistic Grass by xablend1122 / Blend Swap 69868',license='CC BY 3.0',
          parent_hairs=source_count,children_per_parent=source_children,usable_parent_shapes=len(curves),
          adaptation='Source hair curves converted to tapered mesh blades; 16-29 cm height, olive root/tip colours, three variants and two LODs.',models=reports)
(OUT/'model_report.json').write_text(json.dumps(info,indent=2)+'\n')
(OUT/'LICENSE.txt').write_bytes((SOURCE.parent/'BLENDSWAP_LICENSE.txt').read_bytes())
credit=bpy.data.texts.new('SOURCE_AND_LICENSE.txt');credit.write(json.dumps(info,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/blender/photoreal_grass_game.blend'))
print('GRASS_CONVERSION',json.dumps(info),flush=True)
