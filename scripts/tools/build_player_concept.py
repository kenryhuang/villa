"""Author the approved farmer concept using the existing village deform rig.

Blender --background --disable-autoexec --python scripts/tools/build_player_concept.py
Uses build_village_characters' skinning/export pipeline, with player-only garments,
proportions and materials. Does not rebuild NPCs or modify their shared textures.
"""
from pathlib import Path
import sys
import math
import json

import bpy
import bmesh
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_village_characters as village
from player_locomotion import build_animations
from player_face import sculpt_face
from player_garments import trousers

ROOT = village.ROOT
ORIGINAL_MESH = village.mesh
ORIGINAL_ATLAS = village.atlas
ORIGINAL_ANIMATE = village.animate


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def torso_weights(obj):
    obj.vertex_groups.clear()
    for v in obj.data.vertices:
        chest = smoothstep(1.04, 1.24, v.co.z)
        pelvis=1-smoothstep(1.015,1.11,v.co.z)
        for bone, weight in [('pelvis',(1-chest)*pelvis),('spine',(1-chest)*(1-pelvis)), ('chest', chest)]:
            if weight:
                group = obj.vertex_groups.get(bone) or obj.vertex_groups.new(name=bone)
                group.add([v.index], weight, 'REPLACE')


def closed_volume(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=.0001)
    bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=0)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()


def atlas():
    # An independent atlas avoids recoloring any already-authored NPC garments.
    village.COLORS = ['e5dac1', '7c8054', '68869b', '819aab', '805d40', '493426',
                      'f0e6d1', 'c29b60', 'ba9456', '8c7664', '997656', '9b7654',
                      'd8bf9c', '544535', 'd8b47a', 'a27d56']
    mat = ORIGINAL_ATLAS()
    mat.name = 'Player | linen denim straw and leather'
    tex = next(n for n in mat.node_tree.nodes if n.type == 'TEX_IMAGE')
    tex.image.name = 'player_concept_fabric'
    return mat


def shirt(body, kind):
    """Union a tailored T-shirt volume, trim true openings, then weight shoulders."""
    start = len(village.PARTS)
    village.loft('Linen torso volume', [(.975, .140, .145, 0), (1.04, .137, .149, 0),
        (1.12, .131, .148, .004), (1.23, .143, .139, .012),
        (1.30, .140, .112, .023), (1.337, .100, .073, .026),
        (1.39, .047, .047, .023), (1.41, .047, .047, .023)], 0, 'chest')
    for sign in [-1, 1]:
        vs, fs = [], []
        rows = [(.105, .041), (.15, .059), (.22, .066), (.29, .063),
                (.34, .059), (.388, .057), (.414, .055)]
        n = 32
        for x, radius in rows:
            for j in range(n):
                a = j / n * math.tau
                r = radius * (1 + .018 * math.sin(a * 6 + x * 25))
                vs.append((sign * x, .043 + r * math.cos(a), 1.329 + r * math.sin(a)))
        for k in range(len(rows) - 1):
            for j in range(n):
                fs.append((k*n+j, k*n+(j+1)%n, (k+1)*n+(j+1)%n, (k+1)*n+j))
        ORIGINAL_MESH('Linen sleeve volume', vs, fs, 0, 'chest')
    parts = village.PARTS[start:]
    for part in parts:
        closed_volume(part)
    village.select(parts[0])
    for part in parts:
        part.select_set(True)
    bpy.ops.object.join()
    obj = bpy.context.object
    remesh = obj.modifiers.new('Continuous sewn shoulder surface', 'REMESH')
    remesh.mode = 'VOXEL'
    remesh.voxel_size = .0038
    remesh.use_smooth_shade = True
    bpy.ops.object.modifier_apply(modifier=remesh.name)
    smooth = obj.modifiers.new('Relaxed linen', 'SMOOTH')
    smooth.factor = .7
    smooth.iterations = 5
    bpy.ops.object.modifier_apply(modifier=smooth.name)
    decimate = obj.modifiers.new('Garment game topology', 'DECIMATE')
    decimate.ratio = .17
    bpy.ops.object.modifier_apply(modifier=decimate.name)
    # A true neck opening avoids cutting through the shoulder caps at neck height.
    bpy.ops.mesh.primitive_cylinder_add(vertices=64,radius=.052,depth=.30,location=(0,.023,1.50))
    cutter=bpy.context.object
    village.select(obj)
    opening=obj.modifiers.new('Round neckline','BOOLEAN')
    opening.operation='DIFFERENCE';opening.solver='EXACT';opening.object=cutter
    bpy.ops.object.modifier_apply(modifier=opening.name)
    bpy.data.objects.remove(cutter,do_unlink=True)
    # Planar cuts leave clean garment rims instead of deleting whole triangles.
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for point, normal in [((0,0,1.005),(0,0,-1)),
                           ((.402,0,0),(1,0,0)), ((-.402,0,0),(-1,0,0))]:
        geometry=list(bm.verts)+list(bm.edges)+list(bm.faces)
        bmesh.ops.bisect_plane(bm, geom=geometry,
                              dist=.00001, plane_co=point, plane_no=normal,
                              clear_outer=True, clear_inner=False)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()
    village.PARTS[start:] = []
    for layer in list(obj.data.uv_layers):
        obj.data.uv_layers.remove(layer)
    village.finish(obj, 'Continuous rolled-sleeve linen shirt', 0)
    obj.vertex_groups.clear()
    for v in obj.data.vertices:
        x, y, z = v.co
        side = 'L' if x > 0 else 'R'
        arm = smoothstep(.105, .245, abs(x)) * smoothstep(1.19, 1.28, z)
        fore = smoothstep(.295, .385, abs(x))
        chest = smoothstep(1.06, 1.23, z)
        clavicle=.45*arm*(1-arm)
        pelvis=1-smoothstep(1.015,1.11,z)
        for bone, w in [('pelvis',(1-arm)*(1-chest)*pelvis),('spine',(1-arm)*(1-chest)*(1-pelvis)), ('chest',(1-arm)*chest-clavicle),
                        ('shoulder.'+side,clavicle),
                        ('upper_arm.'+side,arm*(1-fore)), ('forearm.'+side,arm*fore)]:
            if w:
                group = obj.vertex_groups.get(bone) or obj.vertex_groups.new(name=bone)
                group.add([v.index], w, 'REPLACE')
    for sign, side in [(1,'L'),(-1,'R')]:
        # Double rolled cuffs, with actual rounded volume visible in gameplay.
        for x, radius in [(.389,.062), (.405,.059)]:
            village.tube('Rolled linen cuff '+side,
                [(sign*x,.043+radius*math.cos(a),1.329+radius*math.sin(a))
                 for a in np.linspace(0,math.tau,33)], .006, 6, 'forearm.'+side)
        collar = ORIGINAL_MESH('Soft open collar '+side,
            [(sign*.030,-.023,1.390),(sign*.063,.008,1.380),
             (sign*.083,-.019,1.358),(sign*.078,-.102,1.317),
             (sign*.044,-.117,1.306),(sign*.022,-.079,1.350)],
             [(0,1,2,5),(5,2,3,4)], 6, 'chest')
        solid = collar.modifiers.new('Collar thickness','SOLIDIFY')
        solid.thickness = .002
        village.select(collar)
        bpy.ops.object.modifier_apply(modifier=solid.name)
    village.loft('Soft collar back',[(1.354,.055,.056,.023),(1.379,.047,.050,.023)],6,'chest',arc=(0,math.pi))
    village.ribbon('Shirt placket',[(0,-.111,1.316),(0,-.127,1.29),(0,-.14,1.25)],.011,6,'chest')
    for z,y in [(1.30,-.124),(1.269,-.138)]:
        village.sphere('Ivory shirt button',(0,y-.003,z),(.0035,.002,.0035),7,'chest')


def mesh(name, vs, fs, c, bone=None, uv=None):
    # The shared pipeline assigns leg weights after calling this mesh factory.
    if name.startswith('Tailored trouser '):
        sign = 1 if name.endswith('L') else -1
        vs, fs, uv = [], [], []
        rows = [(.205,.083,.051),(.235,.083,.057),(.30,.083,.064),
                (.39,.083,.066),(.49,.083,.063),(.56,.083,.066),
                (.66,.081,.073),(.79,.075,.080),(.94,.06,.085),(1.009,.051,.09)]
        n=40
        for k,(z,cx,r) in enumerate(rows):
            for j in range(n+1):
                a=j/n*math.tau
                f=1+.016*math.sin(a*7+z*17)+.013*math.cos(z*54+a*3)
                depth=r*1.08+(.150-r*1.08)*smoothstep(.80,1.009,z)
                vs.append((sign*cx+r*math.cos(a)*f,-.017+depth*math.sin(a)*f,z))
                uv.append((j/n,k/(len(rows)-1)))
        for k in range(len(rows)-1):
            for j in range(n):
                i=k*(n+1)+j
                fs.append((i,i+1,i+n+2,i+n+1))
    return ORIGINAL_MESH(name,vs,fs,c,bone,uv)


def accessories(kind):
    trousers(village)
    # The bib and back yoke follow the same torso weights as the shirt.
    bib = village.loft('Blue denim bib',[(1.006,.145,.163,-.005),
        (1.075,.137,.163,-.005),(1.17,.143,.159,-.005),(1.259,.130,.141,0)],
        2,arc=(-2.37,-.77),fold=.008)
    torso_weights(bib)
    yoke = village.loft('Denim back yoke',[(1.006,.145,.165,-.005),
        (1.10,.140,.160,.003),(1.17,.143,.155,.003)],2,arc=(.63,2.51))
    torso_weights(yoke)
    for s in [-1,1]:
        strap = village.ribbon('Denim shoulder strap',[(s*.091,-.128,1.25),
            (s*.096,-.087,1.319),(s*.102,-.025,1.369),
            (s*.100,.050,1.363),(s*.093,.113,1.313),
            (s*.066,.155,1.19),(s*.050,.158,1.11)],.030,2)
        torso_weights(strap)
        village.sphere('Brass bib button',(s*.091,-.136,1.25),(.006,.003,.006),8,'chest')
        village.tube('Bib seam',[(s*.094,-.117,1.253),(s*.10,-.131,1.17),
            (s*.100,-.144,1.07)],.0011,7,'chest')
    pocket=village.ribbon('Sewn bib pocket',[(0,-.168,1.205),(0,-.176,1.15),
        (0,-.178,1.125)],.079,2)
    torso_weights(pocket)
    village.tube('Pocket top seam',[(-.039,-.172,1.20),(.039,-.172,1.20)],.0011,7,'chest')
    village.loft('Brown work belt',[(.994,.149,.184,-.012),(1.018,.147,.179,-.009)],4,'pelvis')
    village.tube('Brass belt buckle',[(-.022,-.199,.993),(.022,-.199,.993),
        (.022,-.199,1.019),(-.022,-.199,1.019),(-.022,-.199,.993)],.0023,8,'pelvis')
    for s,side in [(1,'L'),(-1,'R')]:
        # Folded denim hems and real rear pockets make the back view readable.
        cuff=village.loft('Turned denim hem '+side,[(.207,.055,.060,-.017),
            (.212,.062,.066,-.017),(.244,.064,.068,-.017),(.253,.060,.065,-.017)],3,'shin.'+side)
        for v in cuff.data.vertices:
            v.co.x+=s*.083
        village.ribbon('Rear trouser pocket '+side,[(s*.074,.161,.963),
            (s*.074,.162,.928),(s*.074,.151,.889)],.061,2,'pelvis')
    # Front and back halves of one continuous cross-body strap.
    for name,points in [('Front',[(-.106,.037,1.372),(-.11,-.069,1.338),
            (-.073,-.149,1.274),(0,-.187,1.17),(.122,-.164,1.027),(.169,-.071,.954)]),
        ('Back',[(-.106,.037,1.372),(-.11,.116,1.30),(-.055,.17,1.20),
            (.054,.167,1.07),(.168,.06,.954)])]:
        strap=village.ribbon('Seed pouch strap '+name,points,.018,4)
        torso_weights(strap)
    village.box('Small rounded seed pouch',(.174,.015,.923),(.091,.081,.120),4,'pelvis')
    village.box('Seed pouch flap',(.174,-.029,.950),(.094,.014,.066),15,'pelvis')
    village.sphere('Seed pouch clasp',(.174,-.039,.925),(.005,.002,.006),8,'pelvis')
    for i in range(2):
        village.ribbon('Olive cloth tucked in seed pouch',[(.205+i*.014,-.030,.94),
            (.207+i*.018,-.034,.88),(.225+i*.012,-.035,.807+i*.025)],.022,1,'pelvis')


def hair(kind):
    # Replace the inherited bob with a short cap and broad, pointed swept locks.
    for old in list(village.PARTS):
        if old.name=='Layered sculpted base hair':
            village.PARTS.remove(old);bpy.data.objects.remove(old,do_unlink=True)
    vs,fs=[],[]
    rings,segments=16,64
    for k in range(rings+1):
        for j in range(segments+1):
            a=j/segments*math.tau
            extent=1.48+.52*(1-math.cos(a))*.5
            t=.01+k/rings*extent
            vs.append((.103*math.sin(t)*math.sin(a),.015-.108*math.sin(t)*math.cos(a),1.577+.086*math.cos(t)))
    for k in range(rings):
        for j in range(segments):
            i=k*(segments+1)+j;fs.append((i,i+1,i+segments+2,i+segments+1))
    ORIGINAL_MESH('Short rounded hair cap',vs,fs,5,'head')
    def lock(name,points,width,depth):
        path=village.path(points,7);vs=[];fs=[];n=12
        for i,p in enumerate(path):
            t=i/(len(path)-1)
            taper=max(.025,math.sin(math.pi*(.12+.88*t)))**.65
            tangent=(path[min(i+1,len(path)-1)]-path[max(0,i-1)]).normalized()
            normal=Vector((p.x,(p.y-.015),.02)).normalized()
            across=tangent.cross(normal).normalized();normal=across.cross(tangent).normalized()
            for j in range(n):
                a=j/n*math.tau
                vs.append(p+taper*(across*width*math.cos(a)+normal*depth*math.sin(a)))
        for i in range(len(path)-1):
            for j in range(n):
                a=i*n+j;b=i*n+(j+1)%n;fs.append((a,b,b+n,a+n))
        ORIGINAL_MESH(name,vs,fs,5,'head')
    for j in range(6):
        lock('Swept fringe %d'%j,[(-.052+j*.012,-.048,1.653),
             (-.015+j*.013,-.095,1.628),(.027+j*.012,-.108,1.590),
             (.033+j*.013,-.097,1.563-j*.009)],.014,.006)
    for j in range(3):
        lock('Parted short fringe %d'%j,[(-.050-j*.012,-.041,1.650),
             (-.071-j*.011,-.079,1.619),(-.078-j*.010,-.072,1.568-j*.006)],.013,.006)
    for s in [-1,1]:
        for j in range(6):
            a=.90+j*.29
            lock('Tousled side and nape',[(s*.096*math.sin(a),.015-.096*math.cos(a),1.625),
                (s*.111*math.sin(a),.018-.114*math.cos(a),1.570),
                (s*.102*math.sin(a+.11),.021-.11*math.cos(a+.11),1.518-.018*j/5)],.016,.008)
    village.loft('Rounded woven straw crown',[(1.643,.117,.115,.014),
        (1.68,.116,.112,.014),(1.727,.105,.098,.014),
        (1.751,.086,.079,.014),(1.759,.04,.037,.014),(1.760,.001,.001,.014)],14,'head')
    brim=village.loft('Soft curved wide straw brim',[(1.647,.113,.112,.014),
        (1.630,.151,.139,.014),(1.621,.19,.169,.014),
        (1.633,.213,.183,.014),(1.639,.213,.183,.014),
        (1.630,.188,.168,.014),(1.638,.15,.139,.014),(1.651,.113,.112,.014)],14,'head')
    for v in brim.data.vertices:
        v.co.z+=.009*(v.co.x/.213)**2+.003*math.sin(v.co.y*20)
    village.loft('Brown hat band',[(1.651,.119,.117,.014),(1.675,.118,.114,.014)],4,'head')
    village.tube('Bound straw brim edge',[(.213*math.cos(a),.014+.183*math.sin(a),
        1.637+.009*math.cos(a)**2+.003*math.sin((.014+.183*math.sin(a))*20))
        for a in np.linspace(0,math.tau,81)],.0022,7,'head')
    for rx,ry,z in [(.15,.139,1.639),(.17,.153,1.633),(.19,.168,1.632)]:
        village.tube('Subtle woven brim rings',[(rx*math.cos(a),.014+ry*math.sin(a),
            z+.009*(rx*math.cos(a)/.213)**2) for a in np.linspace(0,math.tau,65)],.0006,7,'head')


def refine_face(body):
    # The source already has dense facial loops; preserve them instead of adding
    # another local subdivision pass, leaving room for the garment geometry.
    # Bake a small symmetric smile into every expression's neutral geometry.
    sculpt_face(body)
    # Shorten the source tall boots; preserve the weighted foot/toe topology.
    boots=bpy.data.objects['Yun boots']
    for v in boots.data.vertices:
        if v.co.z>.115:
            factor=1-.30*smoothstep(.115,.30,v.co.z)
            center=.083 if v.co.x>0 else -.083
            v.co.x=center+(v.co.x-center)*factor
            v.co.y=.005+(v.co.y-.005)*factor
            v.co.z=.115+(v.co.z-.115)*.29
    # The inherited mesh assigned every shoe to the shin. Rebind the sole to
    # the foot and blend only the ankle shaft, so a planted shoe stays flat.
    boots.vertex_groups.clear()
    for v in boots.data.vertices:
        side='L' if v.co.x>0 else 'R'
        shin=smoothstep(.115,.205,v.co.z)
        for name,weight in [('foot.'+side,1-shin),('shin.'+side,shin)]:
            if weight:
                group=boots.vertex_groups.get(name) or boots.vertex_groups.new(name=name)
                group.add([v.index],weight,'REPLACE')
    # The original hand surface is split between fingers and a glove shell.
    # Reuse its finger weights and silhouette with a dedicated bare-skin material.
    gloves=bpy.data.objects['Yun gloves']
    image=bpy.data.images.new('player_hands_skin',512,512,alpha=False)
    pixels=np.ones((512,512,4),np.float32)
    yy,xx=np.mgrid[0:512,0:512]/512
    shade=1+.025*np.sin(xx*math.tau)*np.sin(yy*math.tau)
    pixels[:,:,:3]=np.array([.918,.655,.510])*shade[:,:,None]
    image.pixels.foreach_set(pixels.ravel())
    image.pack()
    mat=bpy.data.materials.new('Player | bare hands')
    mat.use_nodes=True
    tex=mat.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image=image
    shader=mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Roughness'].default_value=.74
    mat.node_tree.links.new(tex.outputs['Color'],shader.inputs['Base Color'])
    gloves.data.materials.clear()
    gloves.data.materials.append(mat)
    for v in gloves.data.vertices:
        # Reduce the raised glove cuff so it reads as a wrist, not a leather lip.
        v.co.y=.034+(v.co.y-.034)*.95
        v.co.z=1.326+(v.co.z-1.326)*.95
    body.data.calc_loop_triangles()
    from mathutils.bvhtree import BVHTree
    wrist_surface=BVHTree.FromPolygons([v.co for v in body.data.vertices],
        [tuple(t.vertices) for t in body.data.loop_triangles],all_triangles=True)
    for v in gloves.data.vertices:
        if abs(v.co.x)<.56:
            nearest,normal,_,distance=wrist_surface.find_nearest(v.co)
            if distance<.015:
                v.co=nearest+normal*.0004


def morph(point, kind):
    x,y,z=point
    # Measured from the concept's orthographic front: waist ~55% of total height,
    # crotch ~43%. Remap anatomy, all garments, expressions AND rest bones together.
    height=float(np.interp(z,[0,.12,.205,.253,.52,.79,.93,1.01,1.15,1.33,1.425,1.46,1.65,1.76],
                           [0,.125,.225,.277,.49,.827,.90,1.065,1.25,1.455,1.535,1.574,1.825,1.96]))
    if z<1.40:
        torso=smoothstep(.95,1.25,z)
        width=1.13+.22*torso
        if abs(x)<.145:
            x*=width
        else:
            # Modest shoulder breadth, shorter forearms/hands than the source cast.
            x=math.copysign(.145*width+(abs(x)-.145)*1.04,x)
        # Taper the waist and lower ribcage in depth, keeping the chest and
        # shoulder girdle broader. Apply to clothes, straps and bones together.
        depth=float(np.interp(z,[.79,.93,1.005,1.10,1.23,1.33,1.40],
                              [1,1,.68,.66,.84,.98,1]))
        y*=1.08*depth
    else:
        x*=1.26
        y*=1.12
        # Blend into the neck and side planes continuously. A hard front-face
        # cutoff made a serrated strip along the jaw when the chin was lifted.
        front=smoothstep(.012,.080,-y)
        cheek=math.exp(-((abs(point.x)-.042)/.023)**2-((z-1.492)/.032)**2)
        y-=.004*cheek*front
        jaw=math.exp(-((z-1.455)/.040)**2)
        x*=1+.045*jaw*front
        height+=.010*math.exp(-((z-1.429)/.023)**2)*front
        y+=.004*math.exp(-(point.x/.020)**2-((z-1.493)/.020)**2)*smoothstep(.08,.13,-y)
    return Vector((x,y,height))


def build():
    village.atlas=atlas
    village.shirt=shirt
    village.mesh=mesh
    village.accessories=accessories
    village.hair=hair
    village.refine_player_face=refine_face
    village.morph=morph
    village.animate=lambda rig: build_animations(rig,ORIGINAL_ANIMATE)
    village.SPECS['player']['jaw']=.008
    village.TMP=ROOT/'tmp/player-concept'
    village.TMP.mkdir(parents=True,exist_ok=True)
    report=village.build('player')
    report['style_reference']='art/concepts/player/player-farmer-design.png'
    report['generator']='scripts/tools/build_player_concept.py'
    rig=bpy.data.objects['CharacterRig']
    rig['style_reference']=report['style_reference']
    reference=bpy.data.objects.new('REFERENCE | approved farmer design',None)
    bpy.context.collection.objects.link(reference)
    reference.empty_display_type='IMAGE'
    reference.data=bpy.data.images.load(str(ROOT/report['style_reference']),check_existing=True)
    reference.data.pack()
    reference.empty_display_size=2.4
    reference.location=(2.1,.5,1.1)
    reference.rotation_euler=(math.pi/2,0,0)
    reference.hide_render=True
    reference.hide_select=True
    notes=bpy.data.texts.new('PLAYER_CONCEPT.txt')
    notes.write('Approved reference: '+report['style_reference']+'\n'
        'Rebuild: scripts/tools/build_player_concept.py\n'
        'Runtime: assets/models/farm3d/player_farmer.glb\n'
        '55 deform bones; Idle, Walk, Run, Work; six facial expressions.\n'
        'Garments use a player-only fabric atlas. See CREDITS.txt for base topology attribution.\n')
    bpy.data.texts['CREDITS.txt'].write('\nLocomotion adapted from Quaternius Universal Animation Library 1 Standard, CC0-1.0.\nhttps://quaternius.itch.io/universal-animation-library\nSee art/animations/player/QUATERNIUS_LICENSE.txt.\n')
    bpy.ops.wm.save_as_mainfile(filepath=str(village.SOURCE/'player.blend'))
    return report


def main():
    report=build()
    reportfile=village.OUT/'model_report.json'
    reports=json.loads(reportfile.read_text(encoding='utf8'))
    reports=[report if item['id']=='player' else item for item in reports]
    reportfile.write_text(json.dumps(reports,indent=2)+'\n',encoding='utf8')


if __name__=='__main__':
    main()



