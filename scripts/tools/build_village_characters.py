"""Sculpted cartoon village cast, using the original 2D character sheets.

Blender Z-up / forward -Y. Run with Blender --background --python this-file.
Source parts remain editable; only the selected deformed body exports to Godot.
"""
from pathlib import Path
import math
import json
import os
import struct
import sys
import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'assets/models/characters'
SOURCE = ROOT/'art/blender/characters'
PREVIEW = ROOT/'tmp/characters'
for folder in (OUT,SOURCE,PREVIEW): folder.mkdir(parents=True,exist_ok=True)
bpy.context.preferences.filepaths.save_version=0
PALETTE=['#cfbd8b','#596337','#365c77','#245667','#694327','#251e19','#fff0d1','#eeba8e',
         '#bd913d','#503326','#723d37','#99895b','#777264','#583820','#d6b469','#a26548']
PARTS=[];MAT=None;KIND='player'
ATLAS_ROWS=5
FACE_REFERENCES={
    'player':('assets/characters/player/player_farmer_atlas.png',97.0,120.0,[863,861,857.5,852.8,845.1,837,812],(65,810,129,875)),
    'farmer_ahe':('assets/characters/npcs/farmer_ahe/farmer_ahe_directions.png',328.0,265.0,[766,760,750,737.5,721.5,704,650],(267,645,389,788)),
    'lao_li':('assets/characters/npcs/lao_li/lao_li_directions.png',341.5,258.0,[793,785,767.5,749.5,732.5,711,658],(275,655,407,810)),
    'xuezhe_lin':('assets/characters/npcs/xuezhe_lin/xuezhe_lin_directions.png',329.5,215.0,[738,733,721.5,711.5,699.5,682,641],(280,638,379,752)),
}
FACE_Z=[1.46,1.535,1.576,1.651,1.715,1.80,1.936]

def face_uv(x,z,kind):
    _,cx,sx,ys,rect=FACE_REFERENCES[kind]
    px=cx+x*sx;py=float(np.interp(z,FACE_Z,ys))
    u=(px-rect[0])/(rect[2]-rect[0]);v=1-(py-rect[1])/(rect[3]-rect[1])
    index=list(FACE_REFERENCES).index(kind)
    return ((index+u)/4,(4+v)/ATLAS_ROWS)

def make_atlas():
    n=2048;t=n//4;pixels=np.ones((t*ATLAS_ROWS,n,4),dtype=np.float32)
    rng=np.random.default_rng(20260910)
    y,x=np.mgrid[0:t,0:t]/t
    for i,h in enumerate(PALETTE):
        base=np.array([int(h[k:k+2],16)/255 for k in (1,3,5)])
        grain=rng.normal(0,.006,(t,t))
        brush=.024*np.sin(x*18+np.cos(y*9)*2)+.017*np.cos(y*29+x*14)
        shade=1+brush+grain+.08*np.sin(y*math.pi)-.055*np.cos(x*math.tau)
        if i in (0,1,2,3,6,10,11):
            shade+=.008*np.cos(x*t*1.3)*np.sin(y*t*.93)
            shade+=.045*np.sin(x*34+np.sin(y*5)*2)
        if i in (4,5,9,15):shade+=.013*np.sin(x*97+y*34)
        if i==9:shade+=.045*np.cos(x*57+np.cos(y*4)*2)+.018*np.sin(x*177+np.cos(y*4)*5)
        rgb=np.clip(base[None,None,:]*shade[:,:,None],0,1)
        if i==7:
            rgb[:]=base
            cheek=np.exp(-((x-.24)/.115)**2-((y-.40)/.09)**2)+np.exp(-((x-.76)/.115)**2-((y-.40)/.09)**2)
            warm=np.array([.87,.32,.24]);mask=np.clip(cheek*.32,0,.5)
            rgb=rgb*(1-mask[:,:,None])+warm*mask[:,:,None]
            shade=.96+.075*np.sin(y*math.pi)
            rgb*=shade[:,:,None]
        pixels[(i//4)*t:(i//4+1)*t,(i%4)*t:(i%4+1)*t,:3]=np.clip(rgb,0,1)
    # Reproject the original authored faces onto a continuous sculpted head.
    # This retains the actual character-specific eyes, brows, lips and paintwork.
    for index,(kind,(path,cx,sx,ys,rect)) in enumerate(FACE_REFERENCES.items()):
        reference=bpy.data.images.load(str(ROOT/path),check_existing=True)
        sw,sh=reference.size;source=np.array(reference.pixels[:],dtype=np.float32).reshape(sh,sw,4)
        px=rect[0]+x*(rect[2]-rect[0]);py=sh-1-(rect[3]-y*(rect[3]-rect[1]))
        ix=np.clip(px.astype(int),0,sw-2);iy=np.clip(py.astype(int),0,sh-2)
        fx=(px-ix)[:,:,None];fy=(py-iy)[:,:,None]
        sample=(source[iy,ix]*(1-fx)+source[iy,ix+1]*fx)*(1-fy)+(source[iy+1,ix]*(1-fx)+source[iy+1,ix+1]*fx)*fy
        # Only facial paint belongs on skin: exclude the sheet's hair, scarf,
        # neck and background rather than pasting a rectangular portrait.
        wx=(px-cx)/sx
        source_y=sh-1-py
        wz=np.interp(source_y,np.array(ys)[::-1],np.array(FACE_Z)[::-1])
        mask=np.zeros((t,t))
        for ex,ez,rx,rz in [(-.081,1.714,.056,.046),(.081,1.714,.056,.046),(0,1.651,.033,.046),(0,1.576,.071,.025)]:
            mask=np.maximum(mask,np.exp(-((wx-ex)/rx)**6-((wz-ez)/rz)**6))
        if kind=='lao_li':mask=np.maximum(mask,np.exp(-(wx/.107)**6-((wz-1.607)/.046)**6))
        mask*=sample[:,:,3]
        # Remove pale painted skin around the mouth while retaining lip and moustache detail.
        lower=wz<1.62
        mask[lower]*=np.clip((.77-sample[:,:,1][lower])/.19,0,1)
        base=np.zeros((t,t,3))+np.array([.93,.73,.55])
        blush=(np.exp(-((wx-.107)/.04)**2-((wz-1.646)/.035)**2)+np.exp(-((wx+.107)/.04)**2-((wz-1.646)/.035)**2))*.15
        base=base*(1-blush[:,:,None])+np.array([.92,.43,.31])*blush[:,:,None]
        rgb=sample[:,:,:3]*mask[:,:,None]+base*(1-mask[:,:,None])
        if kind=='player':
            rgb=base.copy()
            def paint(color,alpha):
                nonlocal_rgb = np.clip(alpha,0,1)[:,:,None]
                rgb[:] = rgb*(1-nonlocal_rgb)+np.array(color)*nonlocal_rgb
            for side in [-1,1]:
                dx=(wx-side*.081)/.05;dz=(wz-1.714)/.034
                shape=dx*dx+dz*dz*(1+.65*np.abs(dx))
                paint([.24,.13,.075],np.clip((1.13-shape)*25,0,1))
                paint([1,.96,.86],np.clip((.96-shape)*25,0,1))
                r=np.sqrt(((wx-side*.081)/.030)**2+((wz-1.714)/.033)**2)
                iris=np.clip((1-r)*35,0,1)*np.clip((.96-shape)*25,0,1)
                paint([.20,.09,.038],iris)
                light=np.clip((1-r)*2,0,1)*iris
                paint([.54,.27,.075],light*.75)
                paint([.065,.039,.028],np.clip((.52-r)*35,0,1))
                for ox,oz,rad in [(-.009,.013,.007),(.009,-.012,.003)]:
                    glint=np.sqrt((wx-side*.081-ox)**2+(wz-1.714-oz)**2)
                    paint([1,.99,.91],np.clip((rad-glint)*1600,0,1))
            nose=np.exp(-(wx/.012)**2-((wz-1.638)/.008)**2)
            paint([.78,.40,.26],nose*.50)
            smile=1.569+.016*(wx/.059)**2
            line=np.exp(-((wz-smile)/.0028)**2)*np.clip((.062-np.abs(wx))*300,0,1)
            paint([.65,.31,.20],line*.85)
        pixels[4*t:5*t,index*t:(index+1)*t,:3]=rgb
        bpy.data.images.remove(reference)
    image=bpy.data.images.new('Village painted atlas',n,t*ATLAS_ROWS,alpha=False)
    image.pixels.foreach_set(pixels.ravel());image.filepath_raw=str(OUT/'village_painted_atlas.png')
    image.file_format='PNG';image.save();image.pack()
    mat=bpy.data.materials.new('Village painted cloth and skin');mat.use_nodes=True
    tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=image
    bsdf=mat.node_tree.nodes.get('Principled BSDF')
    mat.node_tree.links.new(tex.outputs['Color'],bsdf.inputs['Base Color'])
    bsdf.inputs['Roughness'].default_value=.88
    return mat

def select_only(obj):
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj

def finish(obj,name,color,bone='spine',uvs=None):
    select_only(obj)
    if obj.type!='MESH':bpy.ops.object.convert(target='MESH');obj=bpy.context.object
    obj.name=name;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    # Explicit one-layer UVs prevent the join operation from losing sphere/curve UVs.
    if uvs is not None or not obj.data.uv_layers:
        for layer in list(obj.data.uv_layers):obj.data.uv_layers.remove(layer)
        layer=obj.data.uv_layers.new(name='PaintedUV')
        vs=[v.co for v in obj.data.vertices]
        lo=Vector(tuple(min(v[a] for v in vs) for a in range(3)))
        hi=Vector(tuple(max(v[a] for v in vs) for a in range(3)))
        for loop in obj.data.loops:
            v=vs[loop.vertex_index]
            layer.data[loop.index].uv=uvs[loop.vertex_index] if uvs else ((v.x-lo.x)/max(.001,hi.x-lo.x),(v.z-lo.z)/max(.001,hi.z-lo.z))
    obj.data.uv_layers.active.name='PaintedUV'
    for uv in obj.data.uv_layers.active.data:
        if color is None:continue
        u,v=uv.uv
        if color==7 and not name.startswith('Face '):u=.5;v=.75
        uv.uv=((color%4+.035+u*.93)/4,(color//4+.035+v*.93)/ATLAS_ROWS)
    obj.data.materials.clear();obj.data.materials.append(MAT)
    for p in obj.data.polygons:p.use_smooth=True;p.material_index=0
    obj.vertex_groups.clear();obj.vertex_groups.new(name=bone).add(list(range(len(obj.data.vertices))),1,'REPLACE')
    PARTS.append(obj);return obj

def mesh(name,verts,faces,color,bone='spine',uvs=None):
    data=bpy.data.meshes.new(name);data.from_pydata(verts,[],faces);data.update()
    obj=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(obj)
    return finish(obj,name,color,bone,uvs)

def sphere(name,p,s,c,b='head',segments=24,rings=16):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments,ring_count=rings,location=p)
    o=bpy.context.object;o.scale=s;return finish(o,name,c,b)

def box(name,p,s,c,b='spine',r=.01):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.scale=s
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    mod=o.modifiers.new('Soft leather edges','BEVEL');mod.width=r;mod.segments=3;bpy.ops.object.modifier_apply(modifier=mod.name)
    return finish(o,name,c,b)

def smooth_path(points,steps=5):
    points=[np.array(p,dtype=float) for p in points];out=[]
    for j in range(len(points)-1):
        a,b,c,d=points[max(0,j-1)],points[j],points[j+1],points[min(len(points)-1,j+2)]
        for t in np.linspace(0,1,steps,endpoint=False):out.append(.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t))
    return out+[points[-1]]

def loft(name,rings,c,b='spine',segments=40,arc=(0,math.tau),fold=.0,smooth=4):
    rings=smooth_path(rings,smooth);vs=[];faces=[];uv=[]
    for k,(x,y,z,rx,ry) in enumerate(rings):
        for j in range(segments+1):
            a=arc[0]+(arc[1]-arc[0])*j/segments
            f=1+fold*(.6*math.sin(a*9+z*13)+.4*math.cos(a*13-z*8))
            vs.append((x+rx*math.cos(a)*f,y+ry*math.sin(a)*f,z))
            uv.append((j/segments,k/(len(rings)-1)))
    for k in range(len(rings)-1):
        for j in range(segments):
            a=k*(segments+1)+j;faces.append((a,a+1,a+segments+2,a+segments+1))
    if abs(arc[1]-arc[0]-math.tau)<.001:
        faces.append(tuple(reversed(range(segments+1))))
        faces.append(tuple((len(rings)-1)*(segments+1)+j for j in range(segments+1)))
    return mesh(name,vs,faces,c,b,uv)

def tube(name,points,r,c,b='spine'):
    curve=bpy.data.curves.new(name,'CURVE');curve.dimensions='3D';curve.resolution_u=5;curve.bevel_depth=r;curve.bevel_resolution=1
    spline=curve.splines.new('BEZIER');spline.bezier_points.add(len(points)-1)
    for knot,p in zip(spline.bezier_points,points):knot.co=p;knot.handle_left_type='AUTO';knot.handle_right_type='AUTO'
    obj=bpy.data.objects.new(name,curve);bpy.context.collection.objects.link(obj)
    return finish(obj,name,c,b)

def ribbon(name,points,width,c,b='spine',normal=(0,-1,0),taper=False):
    path=smooth_path(points,7);vs=[];faces=[];uv=[]
    for j,p in enumerate(path):
        t=j/(len(path)-1);tangent=Vector(path[min(j+1,len(path)-1)]-path[max(0,j-1)]).normalized()
        cross=tangent.cross(Vector(normal)).normalized();w=width*(math.sin(math.pi*t)**.35 if taper else 1)
        for side in [-1,1]:vs.append(Vector(p)+cross*w*side*.5);uv.append(((side+1)*.5,t))
    for j in range(len(path)-1):faces.append((j*2,j*2+1,j*2+3,j*2+2))
    obj=mesh(name,vs,faces,c,b,uv)
    select_only(obj);mod=obj.modifiers.new('Woven strap thickness','SOLIDIFY');mod.thickness=.003;bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj

def band(name,p,rx,ry,r,c,b='spine'):
    return loft(name,[(p[0],p[1],p[2]-r,rx,ry),(p[0],p[1],p[2]+r,rx,ry)],c,b,48,smooth=1)

def patch(name,pts,c,b='spine'):
    obj=mesh(name,pts,[tuple(range(len(pts)))],c,b)
    select_only(obj);mod=obj.modifiers.new('Cloth edge','SOLIDIFY');mod.thickness=.003;bpy.ops.object.modifier_apply(modifier=mod.name)
    mod=obj.modifiers.new('Softened edge','BEVEL');mod.width=.004;mod.segments=2;bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj

def fuse(objects,name,c,b,voxel=.004):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True);PARTS.remove(o)
    bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join();o=bpy.context.object
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    mod=o.modifiers.new('Continuous sculpt surface','REMESH');mod.mode='VOXEL';mod.voxel_size=voxel;mod.use_smooth_shade=True
    bpy.ops.object.modifier_apply(modifier=mod.name)
    mod=o.modifiers.new('Relax sculpt','SMOOTH');mod.factor=.7;mod.iterations=4;bpy.ops.object.modifier_apply(modifier=mod.name)
    mod=o.modifiers.new('Game topology','DECIMATE');mod.ratio=.32;bpy.ops.object.modifier_apply(modifier=mod.name)
    for layer in list(o.data.uv_layers):o.data.uv_layers.remove(layer)
    return finish(o,name,c,b)

def buckle(p,size=.8,b='spine'):
    x,y,z=p
    tube('Forged buckle',[(x-.033*size,y,z-.024*size),(x+.033*size,y,z-.024*size),(x+.033*size,y,z+.024*size),(x-.033*size,y,z+.024*size),(x-.033*size,y,z-.024*size)],.0045,8,b)
    tube('Buckle tongue',[(x,y-.003,z-.019*size),(x,y-.003,z+.019*size)],.0025,8,b)

def button(p,r=.008,c=8,b='spine'):
    return sphere('Sewn button',p,(r,.003,r),c,b,12,8)

def embroidery(points,c=8,b='spine'):
    tube('Fine seam',points,.0016,c,b)

def leaf(name,p,direction,length,c=8,b='spine'):
    p=Vector(p);d=Vector(direction).normalized()*length;cross=Vector((-d.z,0,d.x))*.26
    return patch(name,[p,p+d*.48+cross,p+d,p+d*.48-cross],c,b)

HEAD_RINGS=[]
def head_profile(z):
    columns=np.array(smooth_path(HEAD_RINGS,5))
    return tuple(float(np.interp(z,columns[:,2],columns[:,i])) for i in [0,1,3,4])

def face_y(x,z):
    _,cy,rx,ry=head_profile(z);r=min(.9999,abs(x)/max(.001,rx))
    y=cy-ry*(1-r*r)**.43
    # Nose, cheek planes and recessed eye sockets are sculpted into the head.
    y-=.021*math.exp(-(x/.030)**2-((z-1.651)/.040)**2)
    y-=.010*math.exp(-(x/.014)**2-((z-1.694)/.060)**2)
    y-=.008*math.exp(-((abs(x)-.107)/.05)**2-((z-1.626)/.046)**2)
    y+=.003*math.exp(-((abs(x)-.084)/.052)**2-((z-1.711)/.039)**2)
    return y

def face_surface(kind):
    global HEAD_RINGS
    w=1.18 if kind=='lao_li' else .94 if kind=='xuezhe_lin' else .97 if kind=='farmer_ahe' else 1
    HEAD_RINGS=[(0,.018,1.460,.032*w,.044),(0,.008,1.485,.094*w,.088),(0,.003,1.535,.144*w,.113),(0,0,1.602,.184*w,.139),(0,.003,1.681,.200*w,.153),(0,.01,1.76,.198*w,.153),(0,.018,1.84,.181*w,.141),(0,.025,1.9,.132*w,.111),(0,.026,1.936,.033*w,.033)]
    rows=smooth_path(HEAD_RINGS,5);vs=[];faces=[];uv=[];segments=80
    for k,(cx,cy,z,rx,ry) in enumerate(rows):
        for j in range(segments+1):
            a=j/segments*math.tau;x=rx*math.cos(a);front=math.sin(a)<0
            y=face_y(x,z) if front else cy+ry*math.sin(a)
            vs.append((x,y,z));uv.append(face_uv(x,z,kind) if front else ((3.5)/4,(1.75)/ATLAS_ROWS))
    for k in range(len(rows)-1):
        for j in range(segments):
            a=k*(segments+1)+j;faces.append((a,a+1,a+segments+2,a+segments+1))
    faces.append(tuple(reversed(range(segments+1))));faces.append(tuple((len(rows)-1)*(segments+1)+j for j in range(segments+1)))
    mesh('Face sculpt - continuous jaw cheeks nose',vs,faces,None,'head',uv)

def hair_lock(name,points,width,c=9):
    path=smooth_path(points,7);vs=[];faces=[];uv=[];crosses=[];normals=[]
    for i,p in enumerate(path):
        t=i/(len(path)-1);tangent=Vector(path[min(i+1,len(path)-1)]-path[max(0,i-1)]).normalized()
        normal=(Vector(p)-Vector((0,.015,1.73))).normalized()
        cross=tangent.cross(normal).normalized();normal=cross.cross(tangent).normalized()
        crosses.append(cross);normals.append(normal)
        w=width*(math.sin(math.pi*(.04+.96*t))**.62 if t<1 else .003)
        for j in range(9):
            a=j/8*math.tau
            vs.append(Vector(p)+cross*math.cos(a)*w+normal*math.sin(a)*w*.33)
            uv.append((j/8,t))
    for i in range(len(path)-1):
        for j in range(8):
            a=i*9+j;faces.append((a,a+1,a+10,a+9))
    faces.append(tuple(reversed(range(8))))
    faces.append(tuple((len(path)-1)*9+j for j in range(8)))
    mesh(name,vs,faces,c,'head',uv)
    # A restrained painted ridge follows each flowing mass, not separate rods.
    pts=[]
    for i in range(2,len(path)-3,3):
        t=i/(len(path)-1);w=width*math.sin(math.pi*(.04+.96*t))**.62
        pts.append(Vector(path[i])+normals[i]*(w*.34+.001)+crosses[i]*w*.15)
    if len(pts)>2 and c!=9:ribbon('Silver hair ridge',pts,.0015,12,'head',taper=True)

def hair(kind):
    hair_start=len(PARTS)
    vs=[];faces=[];uv=[];n=64;m=20
    for i in range(m+1):
        for j in range(n+1):
            a=j/n*math.tau;front=max(0,-math.sin(a));end=1.94-front*(.94 if kind=='lao_li' else .87)
            phi=i/m*end;rx=.256 if kind=='lao_li' else .228
            vs.append((rx*math.sin(phi)*math.cos(a),.012+.195*math.sin(phi)*math.sin(a),1.741+.235*math.cos(phi)))
            uv.append((j/n,i/m))
    for i in range(m):
        for j in range(n):
            a=i*(n+1)+j;faces.append((a,a+1,a+n+2,a+n+1))
    faces.append(tuple(reversed([m*(n+1)+j for j in range(n)])))
    mesh('Flowing scalp volume',vs,faces,9,'head',uv)
    if kind=='lao_li':
        for side in [-1,1]:
            for j in range(5):
                hair_lock('Swept mature hair',[(side*.012,-.092,1.956),(side*.09,-.146,1.926-j*.012),(side*.19,-.09,1.843-j*.018),(side*.213,.035,1.735-j*.018)],.030)
            for j in range(3):hair_lock('Silver temple sweep',[(side*.229,-.091,1.813-j*.016),(side*.258,-.037,1.750-j*.016),(side*.242,.065,1.681-j*.012)],.012,12)
    else:
        # Side-parted fans follow the skull, with deliberately unequal lengths.
        for j in range(3):
            hair_lock('Long swept fringe',[(.038-j*.026,-.043,1.962),(-.052-j*.018,-.144,1.937-j*.014),(-.126-j*.013,-.159,1.862-j*.022),(-.193+j*.024,-.135,1.766+j*.009)],.045-j*.004)
        for j in range(3):
            hair_lock('Short swept fringe',[(.038+j*.017,-.039,1.962),(.118+j*.01,-.126,1.924-j*.013),(.180+j*.004,-.136,1.841-j*.025),(.205-j*.022,-.114,1.749+j*.021)],.04-j*.004)
        if kind in ('farmer_ahe','xuezhe_lin'):
            hair_lock('Loose forelock',[(.018,-.105,1.962),(-.042,-.177,1.922),(-.077,-.180,1.846),(-.107,-.155,1.785)],.069)
        for side in [-1,1]:
            for j in range(3):
                hair_lock('Layered side locks',[(side*.125,.022-j*.043,1.94),(side*.206,-.065+j*.018,1.833),(side*.211,-.07+j*.04,1.738),(side*(.194+j*.013),.016+j*.034,1.666)],.035)
        if kind=='xuezhe_lin':
            hair_lock('Swept crown tuft',[(-.065,.105,1.928),(-.04,.05,1.98),(.061,.008,1.997),(.163,-.04,1.925)],.067)
    # Directional locks complete the silhouette from the third-person camera.
    for j in range(8):
        a=.15+j/7*(math.pi-.3)
        hair_lock('Layered nape',[(.15*math.cos(a),.027+.13*math.sin(a),1.91),(.215*math.cos(a),.027+.17*math.sin(a),1.8),(.20*math.cos(a),.03+.174*math.sin(a),1.66),(.175*math.cos(a),.025+.159*math.sin(a),1.617)],.035)
    if kind=='farmer_ahe':
        for side in [-1,1]:hair_lock('Soft cheek framing wave',[(side*.151,-.13,1.875),(side*.193,-.121,1.773),(side*.213,-.082,1.66),(side*.18,-.047,1.572)],.028)
        sphere('Hair bun',(0,.202,1.688),(.083,.065,.081),9)
        for j in range(6):
            a=j/6*math.tau
            hair_lock('Bun swept fold',[(.055*math.cos(a),.228,1.688+.064*math.sin(a)),(.063*math.cos(a+.6),.26,1.688+.065*math.sin(a+.6)),(.025*math.cos(a+1),.252,1.688+.03*math.sin(a+1))],.018)
    if kind=='lao_li':
        sphere('Tied topknot',(0,.035,1.992),(.076,.065,.073),9)
        band('Wine hair binding',(0,.035,1.958),.068,.06,.014,10,'head')
        tube('Brass hairpin',[(-.12,.039,1.995),(.12,.039,1.995)],.004,8,'head')
        ribbon('Hair tie tails',[(.03,.1,1.96),(.062,.20,1.86),(.042,.205,1.78)],.028,10,'head',normal=(0,1,0))
    if kind=='player':
        for part in PARTS[hair_start:]:
            for vertex in part.data.vertices:
                world=part.matrix_world@vertex.co
                if world.z>1.896:
                    world.z=1.896;vertex.co=part.matrix_world.inverted()@world
    pieces=[o for o in PARTS[hair_start:] if not any(word in o.name for word in ['Silver','silver','binding','hairpin','tie tails'])]
    if pieces:fuse(pieces,'Unified sculpted flowing hair',9,'head',.005)

def head(kind):
    face_surface(kind)
    for side in [-1,1]:
        ear=sphere('Sculpted ear',(side*(.217 if kind=='lao_li' else .196),.002,1.679),(.036,.024,.048),7)
        sphere('Ear recessed concha',(side*(.222 if kind=='lao_li' else .20),-.019,1.679),(.020,.004,.031),15)
    for side in [-1,1]:
        ex=side*.081
        points=[(ex-.043,1.783),(ex-.008,1.798),(ex+.042,1.783)]
        ribbon('Expressive sculpted brow',[(x,face_y(x,z)-.002,z) for x,z in points],.014 if kind=='lao_li' else .008,9,'head',taper=True)
    hair(kind)
    if kind=='xuezhe_lin':
        for side in [-1,1]:
            ex=side*.081
            tube('Fine brass spectacle rim',[(ex+.064*math.cos(a),face_y(ex+.064*math.cos(a),1.716+.05*math.sin(a))-.007,1.716+.05*math.sin(a)) for a in np.linspace(0,math.tau,49)],.0015,8,'head')
            tube('Spectacle temple',[(ex+side*.061,-.166,1.73),(side*.204,-.005,1.731)],.0025,8,'head')
        tube('Spectacle bridge',[(-.019,-.177,1.72),(0,-.18,1.732),(.019,-.177,1.72)],.0025,8,'head')

def hands(side,suf,gloves=False):
    start=len(PARTS);b='forearm.'+suf;x=side*.433
    loft('Forearm sculpt',[(side*.411,-.024,1.037,.060,.063),(side*.419,-.035,.97,.055,.056),(side*.430,-.05,.874,.039,.040),(x,-.06,.820,.035,.029),(x,-.067,.78,.040,.025)],7,b,32)
    sphere('Palm sculpt',(x,-.063,.789),(.042,.031,.050),7,b)
    for j in range(4):
        fx=x+(j-1.5)*.019;length=[.065,.077,.073,.054][j]
        loft('Relaxed finger',[(fx,-.065,.792,.011,.014),(fx,-.070,.756,.010,.012),(fx,-.084,.792-length,.007,.009),(fx,-.086,.785-length,.002,.003)],7,b,12,smooth=3)
    loft('Opposable thumb',[(x-side*.03,-.066,.817,.018,.018),(x-side*.045,-.072,.799,.014,.015),(x-side*.049,-.084,.770,.009,.011),(x-side*.043,-.093,.759,.003,.004)],7,b,16)
    fuse(PARTS[start:],'Continuous hand and forearm '+suf,7,b,.0038)
    if gloves:
        loft('Fingerless leather glove',[(x,-.064,.760,.044,.034),(x,-.064,.80,.045,.036),(x,-.057,.843,.038,.034)],4,b,32)
        band('Glove wrist strap',(x,-.057,.841),.04,.037,.010,5,b)
        button((x,-.095,.842),.005,8,b)

def trousers(kind):
    color=2 if kind=='player' else 1 if kind=='farmer_ahe' else 5
    start=len(PARTS);width=.25 if kind=='lao_li' else .218
    sphere('Trouser pelvis',(0,.018,.816),(width,.134,.128),color,'pelvis')
    for side,suf in [(-1,'L'),(1,'R')]:
        x=side*.132;bag=1.18 if kind=='lao_li' else 1
        loft('Continuous tailored trousers '+suf,[(x,0,.281,.070,.068),(x,-.006,.35,.083*bag,.083),(x,.002,.435,.106*bag,.10),(x,-.004,.535,.096*bag,.101),(x,.015,.62,.116*bag,.120),(x,.015,.75,.12*bag,.12),(side*.105,.02,.86,.126,.125)],color,'pelvis',40,fold=.045)
    obj=fuse(PARTS[start:],'Continuous trouser sculpt',color,'pelvis',.006)
    for v in obj.data.vertices:
        p=obj.matrix_world@v.co;side='L' if p.x<0 else 'R'
        weights={'pelvis':max(0,min(1,(p.z-.735)/.12))}
        thigh=max(0,min(1,(p.z-.475)/.11));weights['thigh.'+side]=(1-weights['pelvis'])*thigh;weights['shin.'+side]=(1-weights['pelvis'])*(1-thigh)
        for group in list(obj.vertex_groups):group.remove([v.index])
        for name,w in weights.items():
            if w>0:(obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)).add([v.index],w,'REPLACE')
    for side,suf in [(-1,'L'),(1,'R')]:
        x=side*.132;b='shin.'+suf
        loft('Folded linen gaiter',[(x,0,.265,.069,.071),(x,0,.295,.073,.073),(x,0,.347,.075,.074)],6,b,32,fold=.035)
        for z in [.277,.303,.33]:band('Woven sock crease',(x,0,z),.075,.077,.002,11,b)
        loft('Sculpted leather boot',[(x,-.052,.062,.087,.153),(x,-.052,.087,.091,.158),(x,-.06,.13,.085,.143),(x,-.035,.175,.075,.115),(x,-.009,.222,.069,.084),(x,0,.291,.075,.076)],4,b,48)
        loft('Fitted boot sole',[(x,-.052,.036,.088,.152),(x,-.052,.050,.095,.16),(x,-.052,.070,.093,.157)],5,b,48)
        band('Boot welt stitching',(x,-.052,.072),.094,.159,.0025,8,b)
        for z in [.16,.18,.20,.22,.24,.26]:
            y=-.096 if z>=.20 else -.13
            tube('Leather boot lace',[(x-.021,y-.004,z),(x+.021,y-.006,z+.012)],.0022,8,b)
            tube('Crossed boot lace',[(x+.021,y-.004,z),(x-.021,y-.006,z+.012)],.0022,8,b)
        ribbon('Boot tongue',[(x,-.083,.27),(x,-.084,.22),(x,-.116,.16)],.038,15,b)

def clothes(kind):
    width=.294 if kind=='lao_li' else .215 if kind in ('farmer_ahe','xuezhe_lin') else .238
    waist=.262 if kind=='lao_li' else .183 if kind=='farmer_ahe' else .195
    depth=.19 if kind=='lao_li' else .145
    trousers(kind)
    loft('Fitted linen torso',[(0,0,.855,waist+.01,depth*.85),(0,0,.94,waist,depth*.88),(0,0,1.06,width*.97,depth),(0,0,1.19,width,depth*.95),(0,0,1.29,width*.99,depth*.82),(0,0,1.345,.165,.092),(0,0,1.386,.072,.068)],0,fold=.027)
    loft('Slender neck',[(0,.005,1.35,.067,.063),(0,.009,1.43,.061,.060),(0,.01,1.495,.079,.077)],7,'head',40)
    for side,suf in [(-1,'L'),(1,'R')]:
        sleeve_color=3 if kind=='xuezhe_lin' else 0
        loft('Draped sleeve '+suf,[(side*.405,-.024,1.025,.066,.067),(side*.391,-.018,1.084,.078,.080),(side*.346,-.005,1.18,.089,.086),(side*.282,0,1.285,.097,.089),(side*.242,0,1.316,.081,.075)],sleeve_color,'upper_arm.'+suf,40,fold=.04)
        if kind!='xuezhe_lin':loft('Rolled cuff '+suf,[(side*.405,-.024,1.025,.069,.070),(side*.404,-.024,1.043,.077,.078),(side*.400,-.021,1.060,.074,.076)],6,'upper_arm.'+suf,36,fold=.025)
        hands(side,suf,kind=='xuezhe_lin')
        if kind=='xuezhe_lin':
            loft('Tailored coat forearm sleeve '+suf,[(side*.430,-.05,.871,.044,.045),(side*.422,-.039,.944,.056,.059),(side*.411,-.024,1.040,.069,.070)],3,'forearm.'+suf,36,fold=.025)
            loft('Turned linen wrist cuff '+suf,[(side*.430,-.05,.864,.046,.047),(side*.428,-.048,.894,.05,.050)],6,'forearm.'+suf,32,fold=.012)
            pieces=[o for o in PARTS if o.name in ('Draped sleeve '+suf,'Tailored coat forearm sleeve '+suf)]
            sleeve=fuse(pieces,'Continuous tailored coat sleeve '+suf,3,'upper_arm.'+suf,.0045)
            forearm=sleeve.vertex_groups.new(name='forearm.'+suf)
            for vertex in sleeve.data.vertices:
                z=(sleeve.matrix_world@vertex.co).z
                w=max(0,min(1,(1.065-z)/.09));w=w*w*(3-2*w)
                sleeve.vertex_groups['upper_arm.'+suf].add([vertex.index],1-w,'REPLACE')
                forearm.add([vertex.index],w,'REPLACE')
        ribbon('Cuff button tab',[(side*.444,-.063,1.035),(side*.428,-.072,1.117)],.019,sleeve_color,'upper_arm.'+suf)
        button((side*.427,-.079,1.105),.006,8,'upper_arm.'+suf)
    if kind!='xuezhe_lin':
        pieces=[o for o in PARTS if o.name.startswith(('Fitted linen torso','Draped sleeve'))]
        shirt=fuse(pieces,'Continuous linen shirt with soft shoulders',0,'spine',.005)
        for vertex in shirt.data.vertices:
            p=shirt.matrix_world@vertex.co
            t=max(0,min(1,(abs(p.x)-(.25 if kind=='lao_li' else .20))/.105)) if p.z>1.0 else 0
            w=t*t*(3-2*t);side='L' if p.x<0 else 'R'
            shirt.vertex_groups['spine'].add([vertex.index],1-w,'REPLACE')
            if w>0:(shirt.vertex_groups.get('upper_arm.'+side) or shirt.vertex_groups.new(name='upper_arm.'+side)).add([vertex.index],w,'REPLACE')
    for side in [-1,1]:
        patch('Turned linen collar',[(side*.01,-.071,1.381),(side*.093,-.086,1.352),(side*.072,-.142,1.264),(side*.024,-.147,1.313)],6)
    for z in [1.23,1.29]:button((0,-depth-.008,z),.006,4)
    if kind=='player':
        loft('Tailored overall waist',[(0,0,.81,.238,.169),(0,0,.87,.239,.164),(0,0,.91,.228,.158)],2,'pelvis',48)
        loft('Shaped denim bib',[(0,0,.80,.238,.168),(0,0,.89,.230,.159),(0,0,1.04,.242,.16),(0,0,1.19,.231,.153)],2,arc=(-2.3,-.84),fold=.018)
        patch('Bib pocket',[(-.067,-.167,1.118),(.067,-.167,1.118),(.063,-.170,1.03),(0,-.175,1.013),(-.063,-.170,1.03)],2)
        embroidery([(-.063,-.171,1.114),(-.06,-.175,1.038),(0,-.178,1.021),(.06,-.175,1.038),(.063,-.171,1.114)],11)
        for side in [-1,1]:
            ribbon('Flat overall strap',[(side*.133,-.136,1.184),(side*.15,-.09,1.325),(side*.13,.072,1.351),(side*.04,.145,1.15),(-side*.12,.142,.92)],.034,2)
            button((side*.133,-.145,1.18),.011)
            patch('Back denim pocket',[(side*.045,.143,.86),(side*.17,.13,.86),(side*.16,.139,.75),(side*.075,.149,.75)],2,'pelvis')
        loft('Soft straw crown',[(0,.018,1.902,.218,.185),(0,.018,1.963,.203,.171),(0,.018,2.037,.175,.143),(0,.018,2.062,.12,.103),(0,.018,2.066,.012,.012)],14,'head',64)
        loft('Turned straw brim',[(0,.018,1.91,.208,.179),(0,.018,1.899,.26,.22),(0,.018,1.885,.318,.265),(0,.018,1.898,.341,.282),(0,.018,1.91,.334,.277)],14,'head',64)
        band('Hat woven ribbon',(0,.018,1.937),.216,.182,.017,4,'head')
        for radius in [.25,.28,.31,.334]:tube('Fine straw weave',[(radius*math.cos(a),.018+radius*.83*math.sin(a),1.9) for a in np.linspace(0,math.tau,65)],.0012,8,'head')
    elif kind=='farmer_ahe':
        loft('Gathered linen dress',[(0,0,.48,.269,.18),(0,0,.515,.284,.191),(0,0,.64,.257,.177),(0,0,.80,.22,.158),(0,0,.92,.188,.141)],0,'pelvis',56,fold=.045)
        loft('Flowing apron skirt',[(0,0,.535,.284,.201),(0,0,.69,.257,.181),(0,0,.83,.225,.166),(0,0,.95,.196,.155)],1,'pelvis',48,arc=(-2.92,-.22),fold=.035)
        loft('Fitted apron bodice',[(0,0,.915,.196,.155),(0,0,1.05,.224,.157),(0,0,1.20,.219,.147)],1,arc=(-2.48,-.66),fold=.015)
        for side in [-1,1]:ribbon('Apron shoulder band',[(side*.13,-.119,1.20),(side*.142,-.084,1.335),(side*.13,.09,1.341),(side*.11,.136,1.13),(side*.10,.142,.94)],.033,1)
        band('Narrow apron belt',(0,0,.945),.215,.175,.018,4);buckle((0,-.181,.945),.8)
        patch('Seed and wheat pocket',[(-.19,-.129,.82),(-.067,-.181,.82),(-.064,-.193,.687),(-.182,-.151,.687)],1,'pelvis')
        embroidery([(-.187,-.135,.814),(-.181,-.157,.695),(-.068,-.199,.695),(-.070,-.187,.814)],8,'pelvis')
        for j in range(4):
            x=-.168+j*.025;y=-.16-j*.011
            tube('Wheat stem',[(x,y,.78),(x+.02,y,.925+j*.009)],.0013,8,'pelvis')
            for k in range(4):
                for side in [-1,1]:leaf('Wheat grain',(x+.014,y-.003,.873+k*.014),(side*.7,0,1),.020,14,'pelvis')
        for side in [-1,1]:
            ribbon('Apron back bow',[(0,.156,.943),(side*.07,.185,.985),(side*.102,.175,.947),(0,.16,.943)],.025,1)
            ribbon('Apron flowing tie',[(side*.01,.16,.94),(side*.047,.185,.82),(side*.06,.19,.70)],.028,1,'pelvis',normal=(0,1,0))
        # Kerchief follows the skull and wraps around the bun, leaving bangs free.
        loft('Draped olive kerchief',[(0,.079,1.754,.205,.143),(0,.06,1.843,.213,.167),(0,.05,1.93,.163,.146),(0,.035,1.982,.074,.072),(0,.034,1.991,.01,.01)],1,'head',56)
        for side in [-1,1]:
            ribbon('Kerchief folded tail',[(0,.246,1.74),(side*.047,.25,1.68),(side*.078,.242,1.575)],.043,1,'head',normal=(0,1,0),taper=True)
        sphere('Kerchief knot',(0,.25,1.747),(.028,.021,.021),1)
        for j in range(8):
            x=-.17+j*.048;z=1.89+.06*(1-(x/.2)**2)
            leaf('Kerchief leaf embroidery',(x,-.082,z),(1,0,.7),.021,11,'head')
        patch('Embroidered handkerchief',[(.13,-.135,.88),(.21,-.12,.81),(.20,-.16,.685),(.11,-.18,.741)],6,'pelvis')
        leaf('Kerchief botanical motif',(.16,-.169,.765),(.3,0,1),.05,1,'pelvis')
    else:
        coat=4 if kind=='lao_li' else 3
        loft('Tailored open jacket',[(0,0,.93,waist+.018,depth+.018),(0,0,1.06,width+.022,depth+.024),(0,0,1.25,width+.016,depth*.92+.018),(0,0,1.295,width+.012,depth*.83+.021),(0,0,1.347,.184,.118),(0,0,1.385,.085,.081)],coat,segments=48,arc=(-1.29,math.pi+1.29),fold=.012)
        loft('Split jacket skirt',[(0,0,.69,waist+.079,depth+.04),(0,0,.76,waist+.055,depth+.028),(0,0,.93,waist+.012,depth+.008)],coat,'pelvis',48,arc=(-1.25,math.pi+1.25),fold=.025)
        for side in [-1,1]:
            pts=[(side*.063,-.105,1.34),(side*.105,-depth*.84-.018,1.27),(side*.068,-depth-.017,1.15),(side*.051,-depth-.02,.97)]
            ribbon('Contrasting jacket lapel',pts,.030,10 if kind=='lao_li' else 3)
            embroidery([(x-side*.013,y-.003,z) for x,y,z in pts])
            embroidery([(side*(waist+.07)*.31,-depth-.04,.70),(side*(waist+.07)*.75,-depth*.7-.024,.70),(side*(waist+.07)*.98,-.015,.71)],8,'pelvis')
        band('Leather waist belt',(0,0,.947),waist+.038,depth+.037,.019,4)
        buckle((0,-depth-.042,.948),1)
        if kind=='lao_li':
            band('Wine silk sash',(0,0,.973),waist+.040,depth+.038,.015,10)
            ribbon('Silk sash tail',[(.20,-.17,.99),(.225,-.16,.86),(.22,-.18,.67)],.061,10,'pelvis')
            for z in [1.08,1.17,1.25]:
                tube('Frog clasp',[(-.03,-depth-.012,z),(0,-depth-.020,z),(.03,-depth-.012,z)],.0035,8)
                for side in [-1,1]:button((side*.028,-depth-.015,z),.006)
            for j in range(3):
                x=.20+j*.023;z=.87-j*.04
                tube('Coin charm chain',[(x,-.18,.94),(x,-.20,z)],.0018,8,'pelvis')
                sphere('Hanging lucky coin',(x,-.202,z),(.015,.004,.015),8,'pelvis',20,12)
        else:
            box('Travel pack',(0,.196,1.14),(.29,.14,.31),4,r=.028)
            box('Linen backpack lid',(0,.272,1.24),(.30,.025,.13),11,r=.018)
            for side in [-1,1]:
                ribbon('Backpack shoulder harness',[(side*.10,.274,1.0),(side*.11,.272,1.28),(side*.16,.065,1.369),(side*.17,-.08,1.30),(side*.17,-.13,1.15)],.025,4)
                band('Pack horizontal strap',(0,.205,1.08),.152,.077,.01,15)
                tube('Pack vertical strap',[(side*.075,.279,1.01),(side*.075,.287,1.30)],.006,4)
            loft('Rolled survey parchment',[(.195,.21,1.00,.032,.031),(.195,.21,1.35,.032,.031)],6,segments=32)
            for z in [1.06,1.29]:band('Scroll leather binding',(.195,.21,z),.034,.034,.012,4)
            for radius in [.01,.019,.027]:tube('Scroll spiral',[(.195+radius*math.cos(a),.21+radius*math.sin(a),1.352) for a in np.linspace(0,math.tau,25)],.0014,11)
            tube('Compass cord',[(-.045,-.09,1.36),(-.026,-.18,1.14),(.028,-.18,1.14),(.045,-.09,1.36)],.0025,4)
            sphere('Compass case',(0,-.185,1.14),(.024,.005,.024),8,'spine',24,12)
            leaf('Compass needle',(0,-.193,1.123),(0,0,1),.035,6)
            for side in [-1,1]:leaf('Jacket leaf ornament',(side*.18,-.135,.73),(side*.5,0,1),.042,8,'pelvis')
    if kind!='xuezhe_lin':
        y=-depth-.015
        ribbon('Crossbody leather strap',[(-.15,.04,1.355),(-.15,-.10,1.33),(.015,y-.02,1.14),(.20,y,.965),(.25,.01,.87)],.022,4)
        box('Soft leather satchel',(.255,.025,.80),(.137,.105,.18),4,'pelvis',.027)
        box('Rounded satchel flap',(.255,-.033,.839),(.141,.018,.101),15,'pelvis',.019)
        buckle((.255,-.046,.801),.55,'pelvis')
    if kind in ('lao_li','xuezhe_lin'):
        box('Leather bound ledger',(-.24,.01,.83),(.07,.14,.20),10,'pelvis',.007)
        box('Ledger pages',(-.24,-.004,.834),(.062,.119,.177),6,'pelvis',.003)
        ribbon('Ledger retaining strap',[(-.28,-.055,.90),(-.28,-.061,.76)],.017,4,'pelvis',normal=(-1,0,0))

def weight_character():
    # Clothing below the waist follows the hips; soft elbow transition under cuffs.
    for obj in PARTS:
        groups=list(obj.vertex_groups)
        if len(groups)!=1:continue  # continuous trousers already have anatomical weights
        name=groups[0].name
        if name=='spine' and ('skirt' in obj.name.lower() or 'apron' in obj.name.lower()):
            pelvis=obj.vertex_groups.new(name='pelvis')
            for v in obj.data.vertices:
                z=(obj.matrix_world@v.co).z;w=max(0,min(1,(z-.84)/.16))
                groups[0].add([v.index],w,'REPLACE');pelvis.add([v.index],1-w,'REPLACE')

def skeleton(kind):
    data=bpy.data.armatures.new('VillageSkeleton');rig=bpy.data.objects.new('CharacterRig',data)
    bpy.context.collection.objects.link(rig);bpy.context.view_layer.objects.active=rig;rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    bones={'root':((0,0,0),(0,0,.25),None),'pelvis':((0,0,.79),(0,0,.95),'root'),'spine':((0,0,.95),(0,0,1.37),'pelvis'),'head':((0,0,1.37),(0,0,1.87),'spine')}
    for side,suf in [(-1,'L'),(1,'R')]:
        x=side*.145
        bones['thigh.'+suf]=((x,0,.81),(x,0,.53),'pelvis')
        bones['shin.'+suf]=((x,0,.53),(x,0,.10),'thigh.'+suf)
        bones['upper_arm.'+suf]=((side*.28,0,1.31),(side*.412,-.022,1.01),'spine')
        bones['forearm.'+suf]=((side*.412,-.022,1.01),(side*.434,-.065,.77),'upper_arm.'+suf)
    for name,(h,t,parent) in bones.items():
        bone=data.edit_bones.new(name);bone.head=h;bone.tail=t
        if parent:bone.parent=data.edit_bones[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    weight_character()
    # Retain named rest-pose pieces for later hands-on Blender editing. The
    # hidden collection is excluded from rendering and the selected GLB export.
    source=bpy.data.collections.new('Source parts (rest pose)')
    bpy.context.scene.collection.children.link(source)
    for obj in PARTS:
        editable=obj.copy();editable.data=obj.data.copy();source.objects.link(editable)
    source.hide_viewport=True;source.hide_render=True
    bpy.ops.object.select_all(action='DESELECT')
    for obj in PARTS:obj.select_set(True)
    bpy.context.view_layer.objects.active=PARTS[0];bpy.ops.object.join();body=bpy.context.object
    body.data.validate(clean_customdata=False)
    body.name='PaintedCharacter';bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    body.parent=rig;mod=body.modifiers.new('Deform','ARMATURE');mod.object=rig
    rig.animation_data_create()
    for name,duration in [('Idle',60),('Walk',30),('Work',30)]:
        action=bpy.data.actions.new(name);action.use_fake_user=True;rig.animation_data.action=action
        for frame in range(0,duration+1,3):
            phase=frame/duration*math.tau
            for bone in rig.pose.bones:
                bone.rotation_mode='XYZ';bone.rotation_euler=(0,0,0);bone.location=(0,0,0)
            if name=='Walk':
                for sign,suf in [(1,'L'),(-1,'R')]:
                    swing=math.sin(phase)*sign
                    rig.pose.bones['thigh.'+suf].rotation_euler.x=.43*swing
                    rig.pose.bones['shin.'+suf].rotation_euler.x=-.44*max(0,-swing)
                    rig.pose.bones['upper_arm.'+suf].rotation_euler.x=-.32*swing
                    rig.pose.bones['forearm.'+suf].rotation_euler.x=-.08-.12*max(0,swing)
                rig.pose.bones['pelvis'].location.y=.012*(1-math.cos(phase*2))
                rig.pose.bones['spine'].rotation_euler.z=.026*math.sin(phase)
            elif name=='Work':
                lift=.5-.5*math.cos(phase)
                rig.pose.bones['spine'].rotation_euler.x=.20*lift
                for suf in ['L','R']:
                    rig.pose.bones['upper_arm.'+suf].rotation_euler.x=-.6*lift
                    rig.pose.bones['forearm.'+suf].rotation_euler.x=-.35*lift
            else:
                rig.pose.bones['spine'].rotation_euler.x=.01*math.sin(phase)
                rig.pose.bones['head'].rotation_euler.z=.012*math.sin(phase)
            for bone in rig.pose.bones:
                bone.keyframe_insert('rotation_euler',frame=frame,group=bone.name)
                bone.keyframe_insert('location',frame=frame,group=bone.name)
    rig.animation_data.action=bpy.data.actions['Idle'];bpy.context.scene.frame_set(0)
    return rig,body

def share_atlas(filename):
    """Keep one real texture asset in Godot, rather than four extracted copies."""
    raw=filename.read_bytes();json_size=struct.unpack_from('<I',raw,12)[0]
    document=json.loads(raw[20:20+json_size]);binary=raw[28+json_size:]
    assert len(document['images'])==1
    removed={document['images'][0]['bufferView']}
    document['images'][0]={'uri':os.path.relpath(OUT/'village_painted_atlas.png',filename.parent).replace('\\','/'),'name':'Village painted atlas'}
    views=[];payload=bytearray();indices={}
    for index,view in enumerate(document['bufferViews']):
        if index in removed:continue
        payload.extend(b'\0'*(-len(payload)%4))
        indices[index]=len(views);updated=dict(view);updated['byteOffset']=len(payload)
        start=view.get('byteOffset',0);payload.extend(binary[start:start+view['byteLength']]);views.append(updated)
    def remap(value):
        if isinstance(value,dict):
            for key,item in value.items():
                if key=='bufferView':value[key]=indices[item]
                else:remap(item)
        elif isinstance(value,list):
            for item in value:remap(item)
    remap(document);document['bufferViews']=views
    document['buffers'][0]['byteLength']=len(payload)
    encoded=json.dumps(document,separators=(',',':')).encode();encoded+=b' '*(-len(encoded)%4)
    payload.extend(b'\0'*(-len(payload)%4))
    filename.write_bytes(struct.pack('<III',0x46546C67,2,28+len(encoded)+len(payload))+struct.pack('<II',len(encoded),0x4E4F534A)+encoded+struct.pack('<II',len(payload),0x004E4942)+payload)

def studio():
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=32
    scene.render.resolution_x=900;scene.render.resolution_y=1050;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='AgX'
    scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.65,.73,.70,1)
    scene.world.node_tree.nodes['Background'].inputs[1].default_value=.65
    bpy.ops.mesh.primitive_plane_add(size=200);ground=bpy.context.object
    mat=bpy.data.materials.new('Studio sage');mat.diffuse_color=(.19,.24,.20,1);ground.data.materials.append(mat)
    for loc,energy,size in [((-3,-4,6),450,4),((3,-1,3),230,3),((0,4,5),600,3)]:
        bpy.ops.object.light_add(type='AREA',location=loc);light=bpy.context.object;light.data.energy=energy;light.data.shape='DISK';light.data.size=size
        light.rotation_euler=(Vector((0,0,1))-light.location).to_track_quat('-Z','Y').to_euler()
    bpy.ops.object.camera_add(location=(2.4,-8,2.8));camera=bpy.context.object
    camera.rotation_euler=(Vector((0,0,1.05))-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.type='ORTHO';camera.data.ortho_scale=2.42;scene.camera=camera

report=[]
for kind in [k for k in ['player','farmer_ahe','lao_li','xuezhe_lin'] if not any(a.startswith('--character=') for a in sys.argv) or '--character='+k in sys.argv]:
    bpy.context.scene.render.fps=30
    for obj in list(bpy.data.objects):bpy.data.objects.remove(obj,do_unlink=True)
    for collection in list(bpy.data.collections):
        if collection.name.startswith('Source parts'):bpy.data.collections.remove(collection)
    for action in list(bpy.data.actions):bpy.data.actions.remove(action)
    bpy.data.orphans_purge(do_recursive=True)
    PARTS=[];MAT=make_atlas();clothes(kind);head(kind)
    for part in PARTS:
        if len(part.vertex_groups)==1 and part.vertex_groups[0].name=='head':
            part.location.z-=.028
    rig,body=skeleton(kind)
    # Only the skinned mesh and rig are selected for the game export.
    bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);body.select_set(True)
    bpy.context.view_layer.objects.active=rig
    filename=ROOT/'assets/models/farm3d/player_farmer.glb' if kind=='player' else OUT/(kind+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(filename),export_format='GLB',use_selection=True,export_yup=True,export_animations=True,export_animation_mode='ACTIONS',export_materials='EXPORT',export_cameras=False,export_lights=False)
    share_atlas(filename)
    body.data.calc_loop_triangles()
    report.append({'id':kind,'vertices':len(body.data.vertices),'triangles':len(body.data.loop_triangles),'bones':len(rig.data.bones),'bytes':filename.stat().st_size})
    studio();bpy.context.scene.render.fps=30;bpy.context.scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(kind+'.blend')))
    bpy.context.scene.render.filepath=str(PREVIEW/(kind+'.png'));bpy.ops.render.render(write_still=True)
    print('CHARACTER COMPLETE',kind,report[-1],flush=True)
(OUT/'model_report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
