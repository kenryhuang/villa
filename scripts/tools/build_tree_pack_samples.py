"""Three trees and two shrubs from Trees & Bushes pack (Painkiller5555, CC BY 3.0).
Blender --background --disable-autoexec --python scripts/tools/build_tree_pack_samples.py
"""
from pathlib import Path
from collections import defaultdict
from mathutils import Vector, Matrix
import bpy
import bmesh
import math
import random
import json

ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'art/blender/import/Trees  Bushes pack/Trees & Bushes.blend'
OUT=ROOT/'assets/models/vegetation/tree_pack'
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(SOURCE),use_scripts=False)
bpy.ops.object.select_all(action='DESELECT')
bpy.context.preferences.filepaths.save_version=0
scene=bpy.data.scenes.new('Tree samples • game assets')
bpy.context.window.scene=scene
configs=[
    ('golden_broadleaf','tree.005',6.0,(7800,4800,2200),(3400,1500,650),'#939344','#c3b25f'),
    ('green_columnar','tree.007',6.4,(16000,8500,3500),(4500,1700,700),'#55764a','#96a963'),
    ('open_green','tree.008',6.2,(12500,7200,3200),(4000,1500,650),'#687e50','#a5b27b'),
    ('meadow_shrub','tree',1.25,(550,230,85),(350,150,65),'#607e3f','#a0b65b'),
    ('sage_shrub','leaves',1.05,(500,200,80),(320,140,60),'#667c54','#a2b58b'),
]

def linear_color(code):
    values=[int(code[i:i+2],16)/255 for i in (1,3,5)]
    return Vector([v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in values])

def material(name):
    mat=bpy.data.materials.new(name);mat.use_nodes=True;mat.diffuse_color=(1,1,1,1)
    p=mat.node_tree.nodes.get('Principled BSDF');p.inputs['Roughness'].default_value=.9
    attr=mat.node_tree.nodes.new('ShaderNodeVertexColor');attr.layer_name='Paint'
    mat.node_tree.links.new(attr.outputs['Color'],p.inputs['Base Color'])
    mat.use_backface_culling=False
    return mat

bark_mat=material('Tree bark • vertex paint');leaf_mat=material('Tree foliage • vertex paint')

def reshape_crown(p,height,index):
    """Spread the original branch centres into broad, irregular oak-like crowns."""
    if height<3:return p.copy()
    t=max(0,min(1,p.z/height))
    crown=max(0,min(1,(t-.23)/.58))
    crown=crown*crown*(3-2*crown)
    angle=math.atan2(p.y,p.x)
    # Unequal lobes and a slightly flattened apex, rather than a scaled cone.
    lobes=1+.09*math.sin(angle*3+index)+.045*math.cos(angle*5+t*3)
    width=[1.80,1.88,1.78][index]
    spread=1+(width*lobes-1)*crown
    z=p.z
    if t>.10:z=height*(.30+(t-.10)*(.64/.90))
    apex=max(0,min(1,(t-.78)/.22))
    z-=height*.045*apex*(1-min(1,math.hypot(p.x,p.y)/(height*.30)))
    z+=crown*.13*math.sin(angle*3+index)*min(1,math.hypot(p.x,p.y))
    return Vector((p.x*spread,p.y*spread*[.91,1.0,.95][index],z))

def append_tube(verts,faces,centers,radii,sides=12):
    offset=len(verts)
    for i,(center,radius) in enumerate(zip(centers,radii)):
        direction=(centers[min(i+1,len(centers)-1)]-centers[max(0,i-1)]).normalized()
        u=direction.cross(Vector((0,1,0))).normalized();v=direction.cross(u)
        for k in range(sides):
            a=k*math.tau/sides
            verts.append(center+(u*math.cos(a)+v*math.sin(a))*radius)
    for ring in range(len(centers)-1):
        for k in range(sides):
            a=offset+ring*sides+k;b=offset+ring*sides+(k+1)%sides
            faces.append((a,b,b+sides,a+sides))
    faces.append(tuple(offset+k for k in reversed(range(sides))))
    faces.append(tuple(offset+(len(centers)-1)*sides+k for k in range(sides)))

objects=[];report=[]
for species_index,(species,source,height,leaf_counts,trunk_counts,low_hex,high_hex) in enumerate(configs):
    src=bpy.data.objects[source];mesh=src.data
    points=[src.matrix_world@v.co for v in mesh.vertices]
    low=Vector([min(p[i] for p in points) for i in range(3)]);high=Vector([max(p[i] for p in points) for i in range(3)])
    origin=Vector(((low.x+high.x)/2,(low.y+high.y)/2,low.z))
    # Tree origin follows the trunk base, not the asymmetric crown bounding box.
    base=[p for p in points if p.z<low.z+(high.z-low.z)*.015]
    origin.x=sum(p.x for p in base)/len(base);origin.y=sum(p.y for p in base)/len(base)
    original_points=[(p-origin)*height/(high.z-low.z) for p in points]
    points=[reshape_crown(p,height,species_index) for p in original_points]
    leaf_slot=0 if source=='leaves' else 1
    leaf_polys=[p for p in mesh.polygons if p.material_index==leaf_slot]
    trunk_polys=[p for p in mesh.polygons if p.material_index!=leaf_slot]
    parents=list(range(len(points)))
    def find(a):
        while parents[a]!=a:parents[a]=parents[parents[a]];a=parents[a]
        return a
    for p in leaf_polys:
        for v in p.vertices[1:]:parents[find(v)]=find(p.vertices[0])
    groups=defaultdict(list)
    for p in leaf_polys:groups[find(p.vertices[0])].append(tuple(p.vertices))
    leaves=[]
    for polys in groups.values():
        ids=sorted({i for p in polys for i in p})
        original_center=sum((original_points[i] for i in ids),Vector())/len(ids)
        center=reshape_crown(original_center,height,species_index)
        leaves.append((ids,polys,center,original_center))
    # Round-robin spatial cells keeps outer silhouette and low-density branches.
    bins=defaultdict(list);rng=random.Random(78071)
    for index,(_,_,center,_) in enumerate(leaves):bins[tuple(math.floor(v/.22) for v in center)].append(index)
    buckets=list(bins.values());rng.shuffle(buckets)
    for bucket in buckets:rng.shuffle(bucket)
    order=[]
    while buckets:
        next_buckets=[]
        for bucket in buckets:
            order.append(bucket.pop())
            if bucket:next_buckets.append(bucket)
        buckets=next_buckets
    record={'id':species,'source_object':source,'height':height,'original_triangles':sum(len(p.vertices)-2 for p in mesh.polygons),'original_leaves':len(leaves),'lods':[]}
    for level,(leaf_count,trunk_target) in enumerate(zip(leaf_counts,trunk_counts)):
        leaf_count=min(leaf_count,len(leaves))
        root=bpy.data.objects.new(species+'_LOD'+str(level),None);scene.collection.objects.link(root);objects.append(root)
        remap={};verts=[];faces=[]
        for p in trunk_polys:
            face=[]
            for i in p.vertices:
                if i not in remap:remap[i]=len(verts);verts.append(points[i])
                face.append(remap[i])
            faces.append(face)
        trunk_mesh=bpy.data.meshes.new('Trunk');trunk_mesh.from_pydata(verts,[],faces)
        # The legacy generator duplicated vertices along branch seams. Welding
        # them first lets collapse decimation simplify continuous branch tubes.
        bm=bmesh.new();bm.from_mesh(trunk_mesh)
        bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.0001)
        # Sapling stored thousands of separate tapered twig segments. Their
        # open boundaries resist collapse; remove the thinnest twigs before
        # simplifying the retained trunk and thicker branch segments.
        unseen=set(bm.verts);segments=[];stem_centers=[];old_stem=[]
        while unseen:
            stack=[unseen.pop()];component=[]
            while stack:
                vertex=stack.pop();component.append(vertex)
                for edge in vertex.link_edges:
                    other=edge.other_vert(vertex)
                    if other in unseen:unseen.remove(other);stack.append(other)
            if height>3 and min(v.co.z for v in component)<.06:
                # The original main stem has only a few rings and a long point.
                # Recover its bent centreline, then replace the abrupt cone.
                rings=[]
                for vertex in sorted(component,key=lambda v:v.co.z):
                    if not rings or abs(vertex.co.z-rings[-1][0].co.z)>height*.018:rings.append([])
                    rings[-1].append(vertex)
                stem_centers=[sum((v.co for v in ring),Vector())/len(ring) for ring in rings]
                old_stem.extend(component)
                continue
            a=max(component,key=lambda v:(v.co-component[0].co).length_squared).co
            b=max(component,key=lambda v:(v.co-a).length_squared).co
            axis=(b-a).normalized()
            thickness=max(((v.co-a)-(v.co-a).dot(axis)*axis).length for v in component)
            polys={f for v in component for f in v.link_faces}
            segments.append((thickness,component,sum(len(f.verts)-2 for f in polys)))
        segments.sort(key=lambda item:item[0],reverse=True)
        retained=0;discard=list(old_stem)
        for _,component,triangles in segments:
            if retained<trunk_target*2:retained+=triangles
            else:discard.extend(component)
        bmesh.ops.delete(bm,geom=discard,context='VERTS')
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        bm.normal_update()
        # Modest branch thickening; do not turn the upper branches into clubs.
        for thickness,component,_ in segments:
            for v in component:
                if not v.is_valid: continue
                offset=min(.025 if height>3 else .018, thickness*(.22 if height>3 else .45))
                v.co+=v.normal*offset
                v.co.z=max(0,v.co.z)
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        bm.to_mesh(trunk_mesh);bm.free()
        trunk=bpy.data.objects.new('Trunk',trunk_mesh);scene.collection.objects.link(trunk);trunk.parent=root
        bpy.context.window.scene=scene;bpy.ops.object.select_all(action='DESELECT');trunk.select_set(True);bpy.context.view_layer.objects.active=trunk
        decimate=trunk.modifiers.new('Simplified branches','DECIMATE');decimate.ratio=min(1,trunk_target/max(1,retained));decimate.use_collapse_triangulate=True
        bpy.ops.object.modifier_apply(modifier=decimate.name)
        # Smooth stem taper and shallow, asymmetric roots, not a five-foot stand.
        if height>3:
            root_verts=[];root_faces=[]
            assert len(stem_centers)>=2,species+' missing stem centreline'
            centers=[];radii=[]
            for ring in range(25):
                t=ring/24;z=stem_centers[0].z+(stem_centers[-1].z-stem_centers[0].z)*t
                for a,b in zip(stem_centers,stem_centers[1:]):
                    if z<=b.z+.0001:
                        center=a.lerp(b,max(0,min(1,(z-a.z)/max(.0001,b.z-a.z))))
                        centers.append(Vector((center.x,center.y,max(-.04,z))))
                        radii.append(.30*max(.045,1-t)**.72+.035*math.exp(-z/.22))
                        break
            append_tube(root_verts,root_faces,centers,radii,14)
            for branch in range(5):
                angle=branch*math.tau/5+.18*math.sin(branch*3+species_index)
                length=.48+.11*math.sin(branch*2+species_index)
                direction=Vector((math.cos(angle),math.sin(angle),0))
                append_tube(root_verts,root_faces,[direction*.15+Vector((0,0,.18)),direction*.34+Vector((0,0,.04)),direction*length+Vector((0,0,-.06))],[.105,.075,.012],8)
            root_mesh=bpy.data.meshes.new('Continuous tapered stem and shallow roots');root_mesh.from_pydata(root_verts,[],root_faces)
            roots=bpy.data.objects.new('Stem and roots',root_mesh);scene.collection.objects.link(roots)
            bpy.ops.object.select_all(action='DESELECT');trunk.select_set(True);roots.select_set(True);bpy.context.view_layer.objects.active=trunk
            bpy.ops.object.join();trunk_mesh=trunk.data
        trunk.data.materials.append(bark_mat)
        paint=trunk.data.color_attributes.new(name='Paint',type='FLOAT_COLOR',domain='CORNER')
        dark=linear_color('#685038');light=linear_color('#aa8955')
        for poly in trunk.data.polygons:
            poly.use_smooth=True
            for index in poly.loop_indices:
                p=trunk.data.vertices[trunk.data.loops[index].vertex_index].co
                blend=.42+.21*math.sin(math.atan2(p.y,p.x)*13+p.z*.8)+.10*math.sin(p.z*4)
                color=dark.lerp(light,blend);paint.data[index].color=(*color,1)
        leaf_verts=[];leaf_faces=[];leaf_colors=[]
        enlarge=([1.30,1.35,1.75][level] if height>3 else min(3.2+level*2.4,math.sqrt(len(leaves)/leaf_count)*1.08))
        dark=linear_color(low_hex);light=linear_color(high_hex)
        for chosen in order[:leaf_count]:
            ids,polys,center,original_center=leaves[chosen];mapping={}
            # Preserve the original small curved leaf geometry and orientation;
            # crown reshaping moves attachment centres, not individual vertices.
            for i in ids:mapping[i]=len(leaf_verts);leaf_verts.append(center+(original_points[i]-original_center)*enlarge)
            shade=max(0,min(1,.30+.38*center.z/height+.24*rng.uniform(-1,1)))
            color=dark.lerp(light,shade)
            for face in polys:leaf_faces.append([mapping[i] for i in face]);leaf_colors.append(color)
        leaves_mesh=bpy.data.meshes.new('Leaves');leaves_mesh.from_pydata(leaf_verts,[],leaf_faces);leaves_mesh.materials.append(leaf_mat)
        foliage=bpy.data.objects.new('Leaves',leaves_mesh);scene.collection.objects.link(foliage);foliage.parent=root
        paint=leaves_mesh.color_attributes.new(name='Paint',type='FLOAT_COLOR',domain='CORNER')
        for poly,color in zip(leaves_mesh.polygons,leaf_colors):
            for index in poly.loop_indices:paint.data[index].color=(*color,1)
        bpy.ops.object.select_all(action='DESELECT');root.select_set(True);trunk.select_set(True);foliage.select_set(True)
        path=OUT/(species+'_lod'+str(level)+'.glb')
        bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_animations=False,export_cameras=False,export_lights=False)
        trunk.data.calc_loop_triangles();foliage.data.calc_loop_triangles()
        base_points=[v.co for v in trunk.data.vertices if v.co.z<.2]
        record['lods'].append({'level':level,'leaves':leaf_count,'leaf_scale':enlarge,'triangles':len(trunk.data.loop_triangles)+len(foliage.data.loop_triangles),'base_width':max(p.x for p in base_points)-min(p.x for p in base_points) if base_points else 0,'crown_size':[max(p[i] for p in leaf_verts)-min(p[i] for p in leaf_verts) for i in range(3)],'bytes':path.stat().st_size})
        objects.extend([trunk,foliage])
        root.location.x=species_index*8
        root.location.y=level*10
    report.append(record)
for obj in list(bpy.data.objects):
    if obj not in objects:bpy.data.objects.remove(obj,do_unlink=True)
for old in list(bpy.data.scenes):
    if old!=scene:bpy.data.scenes.remove(old)
bpy.data.orphans_purge(do_recursive=True)
text=bpy.data.texts.new('CREDITS.txt');text.write('Trees & Bushes pack by Painkiller5555\nhttp://www.blendswap.com/blends/view/78071\nCC BY 3.0 https://creativecommons.org/licenses/by/3.0/\nVilla adaptation: three trees and two shrubs, spatial leaf thinning, thicker branches and root flares, vertex paint, three LODs, normalized ground origins.\n')
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/blender/tree_pack_samples.blend'))
(OUT/'model_report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')
print('TREE SAMPLES COMPLETE',json.dumps(report),flush=True)
