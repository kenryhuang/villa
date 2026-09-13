"""Continuous bifurcated trouser topology and a shaped seat for the farmer."""
import math
import bpy
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree

SEAT_SURFACE=None
SEAT_OBJECT=None
DENIM=None


def smooth(a,b,x):
    t=max(0,min(1,(x-a)/(b-a)))
    return t*t*(3-2*t)


def trousers(village):
    global DENIM
    for obj in list(village.PARTS):
        if obj.name.startswith('Tailored trouser '):
            village.PARTS.remove(obj);bpy.data.objects.remove(obj,do_unlink=True)
    vertices,faces=[],[]
    n=16
    # Each lower leg becomes half of a single pelvis above the saddle seam.
    # Inner half-rings meet at x=0; omit their collapsed interior faces.
    rows=[(.205,.083,.051,.060,.060),(.212,.083,.054,.061,.061),(.253,.083,.062,.068,.068),
          (.36,.083,.067,.071,.071),(.49,.083,.064,.071,.074),
          (.59,.083,.067,.075,.080),(.70,.081,.075,.085,.098),
          (.79,.080,.078,.098,.128),(.86,0,.153,.116,.152),
          (.93,0,.151,.124,.162),(.985,0,.147,.162,.170),
          (1.014,0,.145,.175,.171)]
    for sign in [1,-1]:
        offset=len(vertices)
        for k,(z,cx,rx,front,back) in enumerate(rows):
            for j in range(n):
                a=-math.pi/2+j/n*math.tau
                c,s=math.cos(a),math.sin(a)
                if k<8:
                    x=sign*(cx+rx*c)
                    zz=z
                else:
                    x=sign*rx*max(0,c)
                    # A curved crotch seam rises to the front/back of the pelvis.
                    zz=z-(.070*(max(0,-c)**2) if k==8 else 0)
                depth=front if s<0 else back
                y=-.010+depth*s
                # Subtle cloth ease, fading to zero at the welded center seam.
                if k<8:y+=.0015*math.sin(a*5+z*18)
                vertices.append((x,y,zz))
        for k in range(len(rows)-1):
            for j in range(n):
                a=-math.pi/2+(j+.5)/n*math.tau
                if k>=8 and math.cos(a)<0:continue
                ids=(offset+k*n+j,offset+k*n+(j+1)%n,
                     offset+(k+1)*n+(j+1)%n,offset+(k+1)*n+j)
                faces.append(ids if sign==1 else tuple(reversed(ids)))
    mesh=bpy.data.meshes.new('Continuous pelvis seat and legs')
    mesh.from_pydata(vertices,[],faces);mesh.update()
    uv=mesh.uv_layers.new(name='UVMap')
    for loop in mesh.loops:
        index=loop.vertex_index%(len(rows)*n)
        ring,index_on_ring=divmod(index,n)
        uv.data[loop.index].uv=(index_on_ring/n,(vertices[loop.vertex_index][2]-.205)/.809)
    # Unwrap the closure across 1.0 instead of spanning the whole atlas tile.
    for polygon in mesh.polygons:
        values=[uv.data[i].uv.x for i in polygon.loop_indices]
        if max(values)-min(values)>.5:
            for i in polygon.loop_indices:
                if uv.data[i].uv.x<.5:uv.data[i].uv.x+=1
    obj=bpy.data.objects.new('Continuous tailored overalls',mesh)
    bpy.context.collection.objects.link(obj)
    bm=bmesh.new();bm.from_mesh(mesh)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00005)
    bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=.00001)
    bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(mesh);bm.free()
    village.select(obj)
    village.finish(obj,'Continuous tailored overalls',2,'pelvis')
    DENIM=village.MAT.copy();DENIM.name='Player | soft denim'
    obj.data.materials[0]=DENIM
    obj.vertex_groups.clear()
    for vertex in obj.data.vertices:
        x,y,z=vertex.co
        # Keep the buttocks on the pelvis; gradually share the lower seat with
        # both thighs at the crotch, instead of pinning half the waist to each leg.
        hip=smooth(.77,.96,z)
        shin=1-smooth(.46,.60,z)
        left=smooth(-.032,.032,x)
        for bone,w in [('pelvis',hip),('thigh.L',(1-hip)*(1-shin)*left),
                       ('thigh.R',(1-hip)*(1-shin)*(1-left)),
                       ('shin.L',(1-hip)*shin*left),('shin.R',(1-hip)*shin*(1-left))]:
            if w>1e-6:
                group=obj.vertex_groups.get(bone) or obj.vertex_groups.new(name=bone)
                group.add([vertex.index],w,'REPLACE')
    return obj


def smooth_seat(obj):
    """Round the seat after the proportion remap, without moving the waistband."""
    global SEAT_SURFACE,SEAT_OBJECT
    if obj.name.startswith('Rear trouser pocket') and SEAT_SURFACE:
        obj.data.materials[0]=DENIM
        # Project a single outward cloth surface, not both sides of a solidified
        # ribbon onto the same plane (which causes z-fighting).
        bm=bmesh.new();bm.from_mesh(obj.data)
        bmesh.ops.delete(bm,geom=[p for p in bm.faces if p.normal.y<.1],context='FACES')
        bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
        bm.to_mesh(obj.data);bm.free()
        bpy.context.view_layer.objects.active=obj
        subdiv=obj.modifiers.new('Pocket surface grid','SUBSURF');subdiv.subdivision_type='SIMPLE';subdiv.levels=1
        bpy.ops.object.modifier_apply(modifier=subdiv.name)
        obj.vertex_groups.clear()
        for vertex in obj.data.vertices:
            hit,normal,triangle,_=SEAT_SURFACE.ray_cast(Vector((vertex.co.x,.5,vertex.co.z)),Vector((0,-1,0)))
            if hit is None:continue
            vertex.co.y=hit.y+.0025
            ids=SEAT_OBJECT.data.loop_triangles[triangle].vertices
            nearest=min((SEAT_OBJECT.data.vertices[i] for i in ids),key=lambda v:(v.co-hit).length)
            for influence in nearest.groups:
                name=SEAT_OBJECT.vertex_groups[influence.group].name
                group=obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)
                group.add([vertex.index],influence.weight,'REPLACE')
        return
    if obj.name!='Continuous tailored overalls':return
    # Subdivide in the final proportions so the seat and inseam stay rounded.
    bpy.context.view_layer.objects.active=obj
    sub=obj.modifiers.new('Continuous cloth hip transition','SUBSURF')
    sub.levels=2;sub.render_levels=2
    bpy.ops.object.modifier_apply(modifier=sub.name)
    group=obj.vertex_groups.new(name='Seat shaping')
    for vertex in obj.data.vertices:
        z=vertex.co.z
        w=smooth(.64,.83,z)*(1-smooth(.985,1.065,z))
        if w:group.add([vertex.index],w,'REPLACE')
    bpy.context.view_layer.objects.active=obj
    mod=obj.modifiers.new('Soft seat and crotch transition','SMOOTH')
    mod.vertex_group=group.name;mod.factor=.65;mod.iterations=8
    bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.vertex_groups.remove(obj.vertex_groups['Seat shaping'])
    obj.data.calc_loop_triangles()
    SEAT_OBJECT=obj
    SEAT_SURFACE=BVHTree.FromPolygons([v.co for v in obj.data.vertices],
        [tuple(t.vertices) for t in obj.data.loop_triangles],all_triangles=True)
