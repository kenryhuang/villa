"""Rebuild the village cast on Yun's continuous Sintel-derived game topology.

Blender --background --disable-autoexec --python scripts/tools/build_village_characters.py
Optional: -- --character=player --no-render
Yun and the licensed original are read-only. See SINTEL_LICENSE.md.
"""
from pathlib import Path
import bpy, bmesh, math, json, sys, struct, os, hashlib
import numpy as np
from mathutils import Vector, Quaternion
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/models/characters'
SOURCE=ROOT/'art/blender/characters'
TMP=ROOT/'tmp/character-rebuild'
TMP.mkdir(parents=True,exist_ok=True)
SPECS={
 'player':dict(height=1.10,width=1.20,head=1.04,jaw=.004,belly=.002,hair=5,coat=2),
 'farmer_ahe':dict(height=1.055,width=1.05,head=1.025,jaw=.003,belly=0,hair=5,coat=1),
 'lao_li':dict(height=1.075,width=1.88,head=1.23,jaw=.022,belly=.075,hair=5,coat=4),
 'xuezhe_lin':dict(height=1.13,width=1.25,head=1.025,jaw=.007,belly=.004,hair=5,coat=3),
}
COLORS=['dac99b','697447','3e6a83','2e6576','735037','302820','f2e3bc','bc9a64',
        'bd9247','938779','753b39','a78d63','c5b895','473b2d','debd78','8c6046']
PARTS=[]

def select(obj):
 bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj

def atlas():
 n=1024;t=n//4;pixels=np.ones((n,n,4),np.float32);y,x=np.mgrid[0:t,0:t]/t
 rng=np.random.default_rng(7129)
 for i,h in enumerate(COLORS):
  rgb=np.array([int(h[j:j+2],16)/255 for j in (0,2,4)])
  shade=1+.085*np.sin(x*18+np.sin(y*13))+.055*np.cos(y*33+x*17)+rng.normal(0,.008,(t,t))
  if i in (0,1,2,3,6,10):shade+=.018*np.cos(x*math.tau*108)*np.cos(y*math.tau*112)
  if i in (5,9):shade+=.07*np.sin(x*math.tau*32+np.sin(y*8))+.035*np.sin(x*math.tau*73)
  if i==14:shade+=.055*np.sin(x*math.tau*40)*np.cos(y*math.tau*64)
  pixels[i//4*t:(i//4+1)*t,i%4*t:(i%4+1)*t,:3]=np.clip(rgb*shade[:,:,None],0,1)
 image=bpy.data.images.new('village_fabric',n,n,alpha=False);image.pixels.foreach_set(pixels.ravel());image.pack()
 mat=bpy.data.materials.new('Village brushed linen leather and hair');mat.use_nodes=True
 tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=image
 p=mat.node_tree.nodes.get('Principled BSDF');p.inputs['Roughness'].default_value=.82
 mat.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color'])
 return mat

def finish(o,name,c,bone=None):
 select(o)
 if o.type!='MESH':bpy.ops.object.convert(target='MESH');o=bpy.context.object
 bpy.ops.object.transform_apply(location=True,rotation=True,scale=True);o.name=name
 if not o.data.uv_layers:
  select(o);bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(island_margin=.015);bpy.ops.object.mode_set(mode='OBJECT')
 o.data.uv_layers.active.name='UVMap'
 for uv in o.data.uv_layers.active.data:
  u,v=uv.uv;uv.uv=((c%4+.025+u*.95)/4,(c//4+.025+v*.95)/4)
 o.data.materials.clear();o.data.materials.append(MAT)
 for p in o.data.polygons:p.use_smooth=True;p.material_index=0
 o.vertex_groups.clear()
 if bone:o.vertex_groups.new(name=bone).add(list(range(len(o.data.vertices))),1,'REPLACE')
 else:skin(o)
 PARTS.append(o);return o

def mesh(name,vs,fs,c,bone=None,uv=None):
 d=bpy.data.meshes.new(name);d.from_pydata(vs,[],fs);d.update();o=bpy.data.objects.new(name,d);bpy.context.collection.objects.link(o)
 if uv:
  layer=d.uv_layers.new(name='UVMap')
  for loop in d.loops:layer.data[loop.index].uv=uv[loop.vertex_index]
 return finish(o,name,c,bone)

def sphere(name,p,s,c,bone='head'):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=12,location=p);o=bpy.context.object;o.scale=s
 return finish(o,name,c,bone)

def box(name,p,s,c,bone='pelvis'):
 bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.scale=s;select(o);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 mod=o.modifiers.new('Rounded sewn edges','BEVEL');mod.width=.008;mod.segments=3;bpy.ops.object.modifier_apply(modifier=mod.name)
 return finish(o,name,c,bone)

def path(points,steps=5):
 pts=[Vector(p) for p in points];result=[]
 for i in range(len(pts)-1):
  a,b,c,d=pts[max(0,i-1)],pts[i],pts[i+1],pts[min(len(pts)-1,i+2)]
  for j in range(steps):
   t=j/steps;result.append(.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t))
 return result+[pts[-1]]

def tube(name,points,r,c,bone=None,taper=False):
 pts=path(points,4);vs=[];fs=[];uv=[];n=8
 for i,p in enumerate(pts):
  tangent=(pts[min(i+1,len(pts)-1)]-pts[max(0,i-1)]).normalized()
  ref=Vector((0,1,0)) if abs(tangent.y)<.9 else Vector((1,0,0));a=tangent.cross(ref).normalized();b=tangent.cross(a)
  rad=r*(max(.05,math.sin(math.pi*(.08+.90*i/(len(pts)-1))))**.65 if taper else 1)
  for j in range(n+1):
   angle=j/n*math.tau;vs.append(p+rad*(math.cos(angle)*a+math.sin(angle)*b));uv.append((j/n,i/(len(pts)-1)))
 for i in range(len(pts)-1):
  for j in range(n):k=i*(n+1)+j;fs.append((k,k+1,k+n+2,k+n+1))
 return mesh(name,vs,fs,c,bone,uv)

def ribbon(name,points,w,c,bone=None):
 pts=path(points,6);vs=[];uv=[];fs=[]
 for i,p in enumerate(pts):
  vs.extend([p+Vector((-w/2,0,0)),p+Vector((w/2,0,0))]);uv.extend([(0,i/(len(pts)-1)),(1,i/(len(pts)-1))])
 for i in range(len(pts)-1):fs.append((i*2,i*2+1,i*2+3,i*2+2))
 o=mesh(name,vs,fs,c,bone,uv);thickness=o.modifiers.new('Woven thickness','SOLIDIFY');thickness.thickness=.002
 select(o);bpy.ops.object.modifier_apply(modifier=thickness.name);return o

def loft(name,rows,c,bone=None,arc=(0,math.tau),fold=.0):
 vs=[];fs=[];uv=[];n=48
 # Interpolated profiles preserve continuous clothing, avoiding separate limb pieces.
 for k,(z,rx,ry,cy) in enumerate(rows):
  for j in range(n+1):
   a=arc[0]+j/n*(arc[1]-arc[0]);f=1+fold*math.sin(a*12+z*9)
   vs.append((rx*math.cos(a)*f,cy+ry*math.sin(a)*f,z));uv.append((j/n,k/(len(rows)-1)))
 for k in range(len(rows)-1):
  for j in range(n):i=k*(n+1)+j;fs.append((i,i+1,i+n+2,i+n+1))
 return mesh(name,vs,fs,c,bone,uv)

def build_weight_source(body):
 body.data.calc_loop_triangles();vs=[v.co.copy() for v in body.data.vertices];tri=[tuple(t.vertices) for t in body.data.loop_triangles]
 valid=set(bpy.data.objects['CharacterRig'].data.bones.keys())
 weights=[{body.vertex_groups[g.group].name:g.weight for g in v.groups if body.vertex_groups[g.group].name in valid} for v in body.data.vertices]
 return BVHTree.FromPolygons(vs,tri,all_triangles=True),vs,tri,weights

def skin(obj):
 for v in obj.data.vertices:
  p,_,index,_=BVH.find_nearest(v.co)
  if index is None:continue
  ids=TRIS[index];f=barycentric_transform(p,*[VERTS[i] for i in ids],Vector((1,0,0)),Vector((0,1,0)),Vector((0,0,1)))
  weights={}
  for i,fac in zip(ids,f):
   for name,w in WEIGHTS[i].items():weights[name]=weights.get(name,0)+w*max(0,fac)
  weights=sorted(weights.items(),key=lambda x:-x[1])[:4];total=sum(w for _,w in weights)
  for name,w in weights:
   if w>0:(obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)).add([v.index],w/max(total,1e-8),'REPLACE')

def shirt(body,kind):
 start=len(PARTS);limit=.525 if kind=='xuezhe_lin' else .405
 o=loft('Continuous shirt torso',[(.986,.134,.134,0),(1.045,.131,.14,0),(1.12,.124,.139,.005),(1.23,.142,.135,.012),(1.30,.14,.107,.025),(1.335,.105,.075,.029),(1.372,.051,.052,.028)],0,'chest')
 # Close all component ends before voxel-union; a shirt is a continuous garment,
 # not a copy of the source body (which deliberately omits covered skin).
 for sign in [-1,1]:
  vs=[];fs=[];uv=[];n=32
  rows=[(.105,.059),(.16,.066),(.24,.061),(.32,.056),(limit,.05)]
  for k,(x,r) in enumerate(rows):
   for j in range(n):
    a=j/n*math.tau;f=1+.025*math.sin(a*7+x*30)
    vs.append((sign*x,.043+r*math.cos(a)*f,1.328+r*math.sin(a)*f));uv.append((j/n,k/(len(rows)-1)))
  for k in range(len(rows)-1):
   for j in range(n):i=k*n+j;fs.append((i,k*n+(j+1)%n,(k+1)*n+(j+1)%n,i+n))
  mesh('Sleeve union volume',vs,fs,0,'chest',uv)
 components=PARTS[start:]
 for part in components:
  bm=bmesh.new();bm.from_mesh(part.data)
  # Loft uses duplicated UV-seam vertices; weld before capping/remeshing.
  bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.0001)
  bmesh.ops.holes_fill(bm,edges=[e for e in bm.edges if e.is_boundary],sides=0)
  bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(part.data);bm.free()
 select(components[0])
 for part in components:part.select_set(True)
 bpy.ops.object.join();o=bpy.context.object
 remesh=o.modifiers.new('Continuous shoulder tailoring','REMESH');remesh.mode='VOXEL';remesh.voxel_size=.0035;remesh.use_smooth_shade=True
 bpy.ops.object.modifier_apply(modifier=remesh.name)
 smooth=o.modifiers.new('Soft fabric folds','SMOOTH');smooth.factor=.65;smooth.iterations=4;bpy.ops.object.modifier_apply(modifier=smooth.name)
 bm=bmesh.new();bm.from_mesh(o.data)
 bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.calc_center_median().z>1.369],context='FACES');bm.to_mesh(o.data);bm.free()
 dec=o.modifiers.new('Game garment topology','DECIMATE');dec.ratio=.10;bpy.ops.object.modifier_apply(modifier=dec.name)
 PARTS[start:]=[]
 finish(o,'Continuous tailored shirt',0 if kind!='xuezhe_lin' else 3)
 loft('Linen collar',[(1.351,.056,.055,.028),(1.39,.047,.050,.028)],6)
 for sign in [-1,1]:
  mesh('Turned collar point',[(sign*.005,-.032,1.389),(sign*.061,-.025,1.354),(sign*.053,-.10,1.304),(sign*.011,-.095,1.343)],[(0,1,2,3)],6)
 for sign,side in [(1,'L'),(-1,'R')]:
  x=limit-.014
  tube('Rolled sleeve cuff',[(sign*x,.043+.050*math.cos(a),1.328+.051*math.sin(a)) for a in np.linspace(0,math.tau,33)],.007,6,'forearm.'+side)


def accessories(kind):
 coat=SPECS[kind]['coat']
 # Waist belt, shoulder straps and bags all inherit deform weights from the body.
 loft('Leather waist belt',[(.985,.137,.139,-.011),(1.016,.134,.135,-.010)],4,'pelvis')
 tube('Brass buckle',[(-.024,-.151,.985),(.024,-.151,.985),(.024,-.151,1.015),(-.024,-.151,1.015),(-.024,-.151,.985)],.0025,8,'pelvis')
 if kind in ('player','farmer_ahe'):
  loft('Denim bib' if kind=='player' else 'Olive apron bodice',[(1.015,.139,.151,-.005),(1.08,.126,.146,-.005),(1.17,.133,.151,-.005),(1.24,.13,.141,0)],coat,arc=(-2.40,-.74),fold=.012)
  for s in [-1,1]:
   ribbon('Sewn shoulder strap',[(s*.086,-.102,1.225),(s*.093,-.060,1.329),(s*.098,.047,1.338),(s*.102,.108,1.31),(s*.086,.127,1.14),(s*.08,.132,1.015)],.022,coat)
   sphere('Brass strap rivet',(s*.086,-.119,1.225),(.007,.003,.007),8,'chest')
  if kind=='farmer_ahe':
   loft('Linen underskirt',[(.66,.178,.162,-.006),(.74,.172,.15,-.009),(.86,.15,.139,-.008),(.995,.135,.13,-.01)],0,fold=.025)
   loft('Gathered olive apron',[(.697,.185,.173,-.006),(.78,.174,.164,-.006),(.87,.155,.156,-.005),(.997,.14,.148,-.004)],1,arc=(-2.85,-.29),fold=.035)
   ribbon('Apron pocket',[(-.08,-.173,.90),(-.08,-.184,.86),(-.08,-.188,.80)],.075,1,'pelvis')
   for j in range(4):
    x=-.10+j*.015
    tube('Wheat in seed pocket',[(x,-.19,.87),(x+.011,-.19,.985+j*.01)],.0012,7,'pelvis')
    for k in range(4):
     for s in [-1,1]:sphere('Wheat grain',(x+.011+s*.005,-.192,.947+k*.01+j*.01),(.005,.002,.009),14,'pelvis')
   for s in [-1,1]:ribbon('Apron back tie',[(0,.142,.995),(s*.065,.162,1.02),(s*.065,.178,.988),(0,.151,.99),(s*.04,.179,.87)],.02,1,'pelvis')
  else:
   ribbon('Bib pocket',[(0,-.166,1.188),(0,-.171,1.12),(0,-.173,1.105)],.085,2,'chest')
 else:
  o=loft('Fitted merchant waistcoat' if kind=='lao_li' else 'Fitted explorer coat',[(1.005,.147,.155,0),(1.045,.145,.161,0),(1.12,.139,.163,.005),(1.23,.157,.157,.012),(1.30,.154,.131,.025),(1.335,.120,.104,.029),(1.366,.066,.078,.028)],coat,arc=(-1.3,math.pi+1.3))
  o.vertex_groups.clear()
  for v in o.data.vertices:
   chest=max(0,min(1,(v.co.z-1.06)/.17))
   for bone,w in [('spine',1-chest),('chest',chest)]:
    if w>0:(o.vertex_groups.get(bone) or o.vertex_groups.new(name=bone)).add([v.index],w,'REPLACE')
  loft('Split tailored coat tails',[(.80,.19,.19,-.01),(.90,.178,.173,-.01),(1.015,.147,.157,-.01)],coat,arc=(-1.24,math.pi+1.24),fold=.02)
  for s in [-1,1]:
   ribbon('Lapel with contrasting lining',[(s*.03,-.06,1.35),(s*.067,-.10,1.28),(s*.046,-.152,1.17),(s*.034,-.17,1.06)],.021,10 if kind=='lao_li' else 3)
   tube('Fine lapel piping',[(s*.034,-.064,1.35),(s*.072,-.104,1.28),(s*.05,-.156,1.17),(s*.038,-.173,1.06)],.0015,8)
  if kind=='lao_li':
   loft('Wine sash',[(1.004,.151,.162,-.011),(1.043,.145,.166,-.011)],10,'pelvis')
   ribbon('Sash folded tail',[(.105,-.13,1.042),(.127,-.159,.94),(.14,-.158,.80)],.035,10,'pelvis')
   for z in [1.105,1.18,1.25]:tube('Traditional shirt clasp',[(-.02,-.177,z),(0,-.181,z),(.02,-.177,z)],.0025,8)
   for j in range(3):
    x=.14+j*.017;z=.91-j*.024;tube('Coin charm',[(x,-.12,.985),(x,-.134,z)],.0015,8,'pelvis');sphere('Lucky coin',(x,-.136,z),(.009,.002,.009),8,'pelvis')
  else:
   box('Explorer field backpack',(0,.16,1.16),(.19,.12,.25),4,'chest')
   box('Canvas pack lid',(0,.23,1.245),(.197,.018,.085),11,'chest')
   for s in [-1,1]:
    ribbon('Backpack shoulder harness',[(s*.074,-.122,1.16),(s*.112,-.08,1.29),(s*.105,.038,1.338),(s*.074,.20,1.32),(s*.063,.239,1.08)],.018,4,'chest')
    tube('Backpack buckle',[(s*.065-.012,.244,1.16),(s*.065+.012,.244,1.16),(s*.065+.012,.244,1.19),(s*.065-.012,.244,1.19),(s*.065-.012,.244,1.16)],.002,8,'chest')
   tube('Rolled survey parchment',[(.12,.175,1.05),(.12,.175,1.345)],.025,6,'chest')
   for z in [1.10,1.29]:tube('Parchment binding',[(.12+.026*math.cos(a),.175+.026*math.sin(a),z) for a in np.linspace(0,math.tau,25)],.004,4,'chest')
   tube('Compass cord',[(-.034,-.06,1.355),(0,-.19,1.145),(.034,-.06,1.355)],.0014,4,'chest')
   sphere('Brass compass',(0,-.194,1.15),(.018,.004,.018),8,'chest')
   tube('Compass needle',[(0,-.2,1.139),(0,-.2,1.162)],.0018,6,'chest')
 if kind!='xuezhe_lin':
  ribbon('Crossbody leather strap',[(-.101,.045,1.338),(-.106,-.080,1.31),(0,-.186,1.16),(.139,-.142,.99),(.161,.002,.93)],.017,4)
  box('Sewn hip satchel',(.168,.022,.91),(.092,.085,.13),4)
  box('Satchel flap',(.168,-.026,.944),(.095,.018,.071),15)
  sphere('Bag clasp',(.168,-.037,.917),(.005,.002,.007),8,'pelvis')
 if kind in ('lao_li','xuezhe_lin'):
  box('Bound merchant ledger' if kind=='lao_li' else 'Field notebook',(-.17,.018,.914),(.044,.107,.151),10)
  box('Paper page edges',(-.17,.006,.914),(.037,.089,.139),6)


def hair(kind):
 c=SPECS[kind]['hair']
 for s in [-1,1]:
  for j in range(5):
   tube('Swept layered fringe',[(s*.014,.009,1.68),(s*(.035+j*.008),-.056,1.66-j*.004),(s*(.065+j*.006),-.084,1.61-j*.012),(s*(.085+j*.003),-.060,1.546-j*.014)],.0045 if kind!='lao_li' else .004,c,'head',True)
  for j in range(4):
   tube('Layered nape',[(s*.085,.025,1.63),(s*.106,.038+j*.015,1.56),(s*.080,.057+j*.015,1.48)],.004,c,'head',True)
 if kind=='lao_li':
  sphere('Tied merchant topknot',(0,.034,1.687),(.037,.036,.04),5)
  for s in [-1,1]:
   for j in range(4):tube('Silver temple strands',[(s*.075,-.05,1.618-j*.008),(s*.107,-.018,1.57-j*.010),(s*.094,.023,1.52-j*.006)],.0038,9,'head',True)
   tube('Sculpted swept moustache',[(0,-.103,1.481),(s*.014,-.118,1.478),(s*.028,-.106,1.481),(s*.038,-.095,1.487)],.0065,5,'head',True)
  tube('Wine topknot tie',[(.037*math.cos(a),.034+.036*math.sin(a),1.674) for a in np.linspace(0,math.tau,33)],.004,10,'head')
  tube('Brass hair pin',[(-.066,.034,1.7),(.066,.034,1.7)],.002,8,'head')
  ribbon('Merchant hair tie tails',[(0,.076,1.68),(.025,.117,1.57),(.021,.115,1.48)],.019,10,'head')
 elif kind=='xuezhe_lin':
  for j in range(2):tube('Tousled scholar crown',[(-.07+j*.03,.035,1.657),(-.053+j*.03,.014,1.694),(-.01+j*.03,-.016,1.683),(.024+j*.017,-.045,1.654)],.005,c,'head',True)
  for s in [-1,1]:
   cx=s*.038
   tube('Thin brass spectacles',[(cx+.028*math.cos(a),-.100,1.526+.024*math.sin(a)) for a in np.linspace(0,math.tau,41)],.0014,8,'head')
   tube('Spectacle temple',[(s*.066,-.097,1.53),(s*.098,-.015,1.533)],.0016,8,'head')
  tube('Spectacle bridge',[(-.010,-.102,1.529),(0,-.109,1.534),(.010,-.102,1.529)],.0014,8,'head')
 elif kind=='farmer_ahe':
  # Angled cloth cap leaves forehead and fringe visible.
  vs=[];fs=[];uv=[]
  for i in range(18):
   for j in range(49):
    a=j/48*math.tau;end=2.10-max(0,-math.sin(a))*1.27;p=i/17*end
    vs.append((.109*math.sin(p)*math.cos(a),.035+.111*math.sin(p)*math.sin(a),1.552+.14*math.cos(p)));uv.append((j/48,i/17))
  for i in range(17):
   for j in range(48):k=i*49+j;fs.append((k,k+1,k+50,k+49))
  mesh('Olive linen kerchief',vs,fs,1,'head',uv)
  sphere('Gathered hair bun',(0,.126,1.514),(.046,.036,.041),4)
  sphere('Kerchief knot',(0,.15,1.553),(.017,.014,.016),1)
  for s in [-1,1]:ribbon('Kerchief cloth tails',[(0,.151,1.555),(s*.024,.16,1.518),(s*.036,.158,1.454)],.026,1,'head')
  for j in range(9):
   x=-.072+j*.018;z=1.656-.026*(x/.074)**2
   tube('Kerchief wheat embroidery',[(x,-.056,z),(x+.008,-.058,z+.008)],.0014,7,'head')
 else:
  loft('Woven straw hat crown',[(1.644,.113,.111,.015),(1.69,.109,.104,.015),(1.737,.096,.092,.015),(1.75,.066,.063,.015),(1.755,.001,.001,.015)],14,'head')
  loft('Curved straw brim',[(1.645,.109,.108,.015),(1.638,.146,.137,.015),(1.634,.183,.166,.015),(1.644,.197,.175,.015),(1.649,.19,.17,.015)],14,'head')
  loft('Hat leather ribbon',[(1.652,.115,.112,.015),(1.674,.113,.110,.015)],4,'head')
  for r in [.139,.158,.179,.19]:tube('Concentric straw stitching',[(r*math.cos(a),.015+r*.91*math.sin(a),1.645) for a in np.linspace(0,math.tau,65)],.0008,7,'head')


def morph(p,kind):
 x,y,z=p;spec=SPECS[kind];w=spec['width']
 # Same continuous anatomy, but individually authored shoulder, waist and jaw shapes.
 if z<1.40:
  blend=max(0,min(1,(1.43-z)/.08));width=1+(w-1)*blend
  if kind in ('player','farmer_ahe'):
   # Shoulder breadth must not widen the thighs, ankles and shoes.
   lower_width=1.0 if kind=='player' else .98
   torso=max(0,min(1,(z-.95)/.25));torso=torso*torso*(3-2*torso)
   width=lower_width+(width-lower_width)*torso
  if abs(x)<.145:x*=width
  else:x=math.copysign(.145*width+(abs(x)-.145)*(1.06 if kind!='lao_li' else 1.12),x)
  if .90<z<1.36:
   t=math.exp(-((z-1.075)/.16)**2)*math.exp(-(abs(p.x)/.18)**6)
   y-=spec['belly']*t*max(.15,min(1,(-y+.04)/.13))
   if kind!='farmer_ahe':
    # Flatten the female chest under the male shirts while keeping continuous shoulders.
    chest=math.exp(-((z-1.235)/.07)**2)*math.exp(-(abs(p.x)/.135)**6)
    y+=.025*chest*max(0,min(1,(-y-.035)/.05))
  if z<.95:
   y*=1.10 if kind=='lao_li' else 1.02
 elif z>1.425:
  x*=spec['head'];y*=1.02 if kind!='lao_li' else 1.10
  if kind!='farmer_ahe':
   neck=math.exp(-((z-1.418)/.031)**2);x*=1+.22*neck
   nose=math.exp(-(p.x/.025)**2-((z-1.493)/.022)**2)
   if y<-.08:y-=(.0025 if kind=='player' else .007)*nose
  jaw=math.exp(-((z-1.465)/.04)**2)
  x+=math.copysign(spec['jaw']*jaw*min(1,abs(x)/.03),x)
  if kind=='lao_li':
   y-=.014*math.exp(-((z-1.49)/.055)**2)
   x*=1+.11*math.exp(-((z-1.49)/.035)**2)
 if kind in ('player','farmer_ahe'):
  # Raise knees and hips without scaling the head or changing total height.
  z+=float(np.interp(z,[0,.12,.52,.93,1.04,1.425],[0,0,.03,.055,.055,0],left=0,right=0))
 return Vector((x*spec['height'],y*spec['height'],z*spec['height']))


def refine_player_face(body):
 """Local facial subdivision retains the six expressions and deform weights."""
 bm=bmesh.new();bm.from_mesh(body.data)
 # Spend geometry on visible eyelids, nose, lips and cheeks, not the back of
 # the skull under the hat. This keeps the character inside its render budget.
 edges=[e for e in bm.edges if all(1.452<v.co.z<1.549 and v.co.y<-.061 and abs(v.co.x)<.065 for v in e.verts)]
 bmesh.ops.subdivide_edges(bm,edges=edges,cuts=1,use_grid_fill=True,smooth=.35)
 bm.to_mesh(body.data);bm.free()
 # Small skin-surface changes preserve the eyeball positions and mouth closure.
 # Apply the same offset to every expression, avoiding jumps when smiling.
 basis=body.data.shape_keys.key_blocks[0]
 offsets=[]
 for vertex in basis.data:
  x,y,z=vertex.co;offset=Vector((0,0,0))
  if z>1.435 and y<-.045:
   cheek=math.exp(-((abs(x)-.045)/.022)**2-((z-1.497)/.025)**2)
   bridge=math.exp(-(x/.012)**2-((z-1.522)/.022)**2)
   nostril=math.exp(-((abs(x)-.016)/.008)**2-((z-1.486)/.009)**2)
   offset.y=-.0028*cheek-.0022*bridge-.0015*nostril
  offsets.append(offset)
 for key in body.data.shape_keys.key_blocks:
  for vertex,offset in zip(key.data,offsets):vertex.co+=offset
 for face in body.data.polygons:face.use_smooth=True
 body.data.update()


def animate(rig):
 for action in list(bpy.data.actions):bpy.data.actions.remove(action)
 rig.animation_data_create()
 def rotate(name,axis,angle):
  b=rig.pose.bones[name]
  def basis(b):
   r=b.bone.matrix_local.to_3x3()
   if b.parent:r=basis(b.parent)@b.parent.bone.matrix_local.to_3x3().inverted()@r
   return r@b.rotation_quaternion.to_matrix()
  r=b.bone.matrix_local.to_3x3()
  if b.parent:r=basis(b.parent)@b.parent.bone.matrix_local.to_3x3().inverted()@r
  b.rotation_quaternion=Quaternion(r.inverted()@Vector(axis),angle)@b.rotation_quaternion
 for name,duration in [('Idle',90),('Walk',30),('Run',24),('Work',30)]:
  action=bpy.data.actions.new(name);action.use_fake_user=True;rig.animation_data.action=action
  for frame in range(0,duration+1,2):
   phase=frame/duration*math.tau
   for b in rig.pose.bones:b.rotation_mode='QUATERNION';b.rotation_quaternion=(1,0,0,0);b.location=(0,0,0)
   for sign,s in [(1,'L'),(-1,'R')]:
    rotate('upper_arm.'+s,(0,1,0),sign*math.radians(76))
    for finger in ['finger_index','finger_middle','finger_ring','finger_pinky']:
     for digit in ['02','03']:rotate(finger+'.'+digit+'.'+s,(1,0,0),-.25)
   if name in ('Walk','Run'):
    fast=name=='Run'
    for sign,s in [(1,'L'),(-1,'R')]:
     swing=math.sin(phase)*sign
     rotate('thigh.'+s,(1,0,0),(.65 if fast else .38)*swing)
     rotate('shin.'+s,(1,0,0),-(.85 if fast else .53)*max(0,-swing))
     rotate('foot.'+s,(1,0,0),.17*max(0,-swing))
     rotate('upper_arm.'+s,(1,0,0),-(.53 if fast else .30)*swing)
     rotate('forearm.'+s,(1,0,0),-.7 if fast else -.13-.12*max(0,swing))
    rig.pose.bones['root'].location.z=(.025 if fast else .01)*(1-math.cos(phase*2))
    rotate('chest',(1,0,0),.12 if fast else .02)
   elif name=='Work':
    wave=.5-.5*math.cos(phase);rotate('spine',(1,0,0),.16*wave)
    for s in ['L','R']:
     rotate('upper_arm.'+s,(1,0,0),-.55*wave);rotate('forearm.'+s,(1,0,0),-.6*wave)
   else:
    rotate('chest',(1,0,0),.011*math.sin(phase));rotate('head',(0,0,1),.015*math.sin(phase))
   for b in rig.pose.bones:
    b.keyframe_insert('rotation_quaternion',frame=frame,group=b.name)
    if b.name=='root':b.keyframe_insert('location',frame=frame,group=b.name)
 rig.animation_data.action=bpy.data.actions['Idle'];bpy.context.scene.frame_set(0)


def external_images(filename,destination):
 raw=filename.read_bytes();size=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+size]);binary=raw[28+size:];removed=set()
 for img in doc.get('images',[]):
  index=img['bufferView'];view=doc['bufferViews'][index];payload=binary[view.get('byteOffset',0):view.get('byteOffset',0)+view['byteLength']]
  digest=hashlib.sha256(payload).hexdigest()
  target=next((p for p in OUT.glob('resident_yun_*.png') if hashlib.sha256(p.read_bytes()).hexdigest()==digest),None)
  if target is None:
   named={'village_fabric':'village_fabric.png','player_concept_fabric':'player_concept_fabric.png','player_hands_skin':'player_hands_skin.png','player_face_skin':'player_face_skin.png'}
   target=OUT/named.get(img.get('name'),'village_'+digest[:12]+'.png')
   if not target.exists() or target.read_bytes()!=payload:target.write_bytes(payload)
  img.pop('bufferView');img.pop('mimeType',None);img['uri']=os.path.relpath(target,destination.parent).replace('\\','/');removed.add(index)
 views=[];data=bytearray();indices={}
 for i,v in enumerate(doc['bufferViews']):
  if i in removed:continue
  indices[i]=len(views);data.extend(b'\0'*(-len(data)%4));offset=v.get('byteOffset',0)
  new=dict(v,byteOffset=len(data));data.extend(binary[offset:offset+v['byteLength']]);views.append(new)
 def remap(o):
  if isinstance(o,dict):
   for k,v in o.items():
    if k=='bufferView':o[k]=indices[v]
    else:remap(v)
  elif isinstance(o,list):
   for v in o:remap(v)
 remap(doc);doc['bufferViews']=views;doc['buffers'][0]['byteLength']=len(data)
 encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*(-len(encoded)%4);data.extend(b'\0'*(-len(data)%4))
 result=struct.pack('<III',0x46546c67,2,28+len(encoded)+len(data))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(data),0x004e4942)+data
 destination.write_bytes(result)
 return [i['uri'] for i in doc.get('images',[])]


def build(kind):
 global PARTS,MAT,BVH,VERTS,TRIS,WEIGHTS
 bpy.ops.wm.open_mainfile(filepath=str(SOURCE/'resident_yun.blend'),use_scripts=False)
 bpy.context.preferences.filepaths.save_version=0
 rig=bpy.data.objects['YunRig'];rig.data.pose_position='REST';rig.name='CharacterRig';rig.data.name='VillageSkeleton'
 PARTS=[]
 keep=['body','body_mouth','boots','gloves','hair_proxy','eyeballs','emit_brows','emit_lash_btm','emit_lash_top']
 if kind=='player':
  # These source objects are particle emitter sheets, not eyebrow geometry.
  # Their exposed triangles fight the refined skin; the painted brows and
  # modeled eyelids already supply the required detail.
  keep=[name for name in keep if not name.startswith('emit_')]
 for obj in list(bpy.data.objects):
  if obj.type=='MESH' and obj.name.removeprefix('Yun ') in keep:PARTS.append(obj)
  elif obj!=rig:bpy.data.objects.remove(obj,do_unlink=True)
 body=bpy.data.objects['Yun body']
 for key in body.data.shape_keys.key_blocks:key.value=0
 if kind in ('farmer_ahe','lao_li'):
  body.data.shape_keys.key_blocks['Smile.L'].value=.15;body.data.shape_keys.key_blocks['Smile.R'].value=.15
 if kind=='player':
  refine_player_face(body)
  for name,roughness in [('Yun body',.68),('Yun eyeballs',.28)]:
   obj=bpy.data.objects[name];mat=obj.data.materials[0].copy();obj.data.materials[0]=mat
   mat.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=roughness
 BVH,VERTS,TRIS,WEIGHTS=build_weight_source(body);MAT=atlas()
 # Keep the continuous painted facial mesh, real eyes/mouth and all six expressions.
 # The source lips, eyelids and ear loops stay intact under character-specific morphs.
 for obj in list(PARTS):
  if obj.name=='Yun hair_proxy':
   for v in obj.data.vertices:
    if v.co.z<1.52:v.co.z=1.52+(v.co.z-1.52)*(.4 if kind=='farmer_ahe' else .13)
    if kind=='player':v.co.z=min(v.co.z,1.635)
   PARTS.remove(obj);finish(obj,'Layered sculpted base hair',SPECS[kind]['hair'],'head')
  else:obj.name=obj.name.replace('Yun ',kind+' ')
 shirt(body,kind)
 # A closed cloth trouser shell covers the source's cut-away combat leggings.
 for s,side in [(1,'L'),(-1,'R')]:
  vs=[];fs=[];uv=[];rows=[(.40,.085,.047),(.46,.085,.061),(.55,.086,.081),(.65,.081,.095),(.79,.075,.10),(.94,.060,.10),(1.005,.051,.09)];n=40
  if kind in ('player','farmer_ahe'):
   rows=[(.40,.083,.044),(.46,.083,.050),(.55,.083,.052),(.65,.081,.062),(.79,.075,.071),(.94,.060,.080),(1.005,.051,.087)]
  for k,(z,cx,r) in enumerate(rows):
   for j in range(n+1):
    a=j/n*math.tau;f=1+.025*math.sin(a*9+z*15);vs.append((s*cx+r*math.cos(a)*f,-.017+r*.96*math.sin(a)*f,z));uv.append((j/n,k/(len(rows)-1)))
  for k in range(len(rows)-1):
   for j in range(n):i=k*(n+1)+j;fs.append((i,i+1,i+n+2,i+n+1))
  o=mesh('Tailored trouser '+side,vs,fs,2 if kind=='player' else 1 if kind=='farmer_ahe' else 13)
  o.vertex_groups.clear()
  for v in o.data.vertices:
   pelvis=max(0,min(1,(v.co.z-.84)/.15));shin=max(0,min(1,(.59-v.co.z)/.12))
   for bone,w in [('pelvis',pelvis),('thigh.'+side,(1-pelvis)*(1-shin)),('shin.'+side,(1-pelvis)*shin)]:
    if w>0:(o.vertex_groups.get(bone) or o.vertex_groups.new(name=bone)).add([v.index],w,'REPLACE')
 accessories(kind);hair(kind)
 profile=[(1.005,.147,.155,0),(1.045,.145,.161,0),(1.12,.139,.163,.005),(1.23,.157,.157,.012),(1.30,.154,.131,.025),(1.335,.120,.104,.029),(1.366,.066,.078,.028)]
 for obj in PARTS:
  if 'lapel' not in obj.name.lower():continue
  obj.vertex_groups.clear()
  for v in obj.data.vertices:
   z=v.co.z;rx=float(np.interp(z,[r[0] for r in profile],[r[1] for r in profile]));ry=float(np.interp(z,[r[0] for r in profile],[r[2] for r in profile]));cy=float(np.interp(z,[r[0] for r in profile],[r[3] for r in profile]))
   v.co.y=min(v.co.y,cy-ry*math.sqrt(max(0,1-(v.co.x/rx)**2))-.006)
   chest=max(0,min(1,(z-1.06)/.17))
   for bone,w in [('spine',1-chest),('chest',chest)]:
    if w>0:(obj.vertex_groups.get(bone) or obj.vertex_groups.new(name=bone)).add([v.index],w,'REPLACE')
 bm=bmesh.new();bm.from_mesh(body.data)
 bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.calc_center_median().z<1.035 or (f.calc_center_median().z<1.391 and (f.calc_center_median().z<1.35 or abs(f.calc_center_median().x)>.052) and abs(f.calc_center_median().x)<(.517 if kind=='xuezhe_lin' else .397))],context='FACES')
 bm.to_mesh(body.data);bm.free()
 # Apply the same continuous morph to rest mesh, expressions and skeleton.
 for obj in PARTS:
  if obj.data.shape_keys:
   for key in obj.data.shape_keys.key_blocks:
    for v in key.data:v.co=morph(v.co,kind)
   if kind=='player':
    for vertex,basis in zip(obj.data.vertices,obj.data.shape_keys.key_blocks[0].data):vertex.co=basis.co
  else:
   for v in obj.data.vertices:v.co=morph(v.co,kind)
  obj.data.update()
  if kind=='player':
   from player_garments import smooth_seat
   smooth_seat(obj)
 select(rig);bpy.ops.object.mode_set(mode='EDIT')
 for b in rig.data.edit_bones:b.head=morph(b.head,kind);b.tail=morph(b.tail,kind)
 bpy.ops.object.mode_set(mode='OBJECT');rig.data.pose_position='POSE'
 for obj in PARTS:
  obj.parent=rig
  if not any(m.type=='ARMATURE' for m in obj.modifiers):obj.modifiers.new('Game skin','ARMATURE').object=rig
 # Join accessories into one material surface: retain separate facial shape-key mesh.
 extras=[o for o in PARTS if not o.data.shape_keys]
 select(extras[0])
 for o in extras:o.select_set(True)
 bpy.ops.object.join();joined=bpy.context.object;joined.name=kind+' clothing eyes and accessories'
 PARTS=[body,joined]
 animate(rig)
 # Gameplay attachment convention is derived from the rig, not guessed limb lengths.
 rig['character_id']=kind;rig['style_reference']='resident_yun';rig['license']='CC BY 3.0 / BenDansie Sintel Lite'
 bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
 for obj in PARTS:obj.select_set(True)
 bpy.context.view_layer.objects.active=rig
 staged=TMP/(kind+'.glb');dest=ROOT/'assets/models/farm3d/player_farmer.glb' if kind=='player' else OUT/(kind+'.glb')
 bpy.ops.export_scene.gltf(filepath=str(staged),export_format='GLB',use_selection=True,export_yup=True,export_animations=True,export_animation_mode='ACTIONS',export_materials='EXPORT',export_cameras=False,export_lights=False,export_extras=True)
 textures=external_images(staged,dest)
 tris=0
 for obj in PARTS:obj.data.calc_loop_triangles();tris+=len(obj.data.loop_triangles)
 for text in list(bpy.data.texts):bpy.data.texts.remove(text)
 credits=bpy.data.texts.new('CREDITS.txt');credits.write('Sintel Lite by BenDansie / Blender Foundation. CC BY 3.0.\nDerived from the Yun game conversion; new body/face proportions, clothing, hair, accessories and animations for '+kind+'.\nSee assets/models/characters/SINTEL_LICENSE.md.\n')
 bpy.data.orphans_purge(do_recursive=True)
 scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True;scene.render.fps=30
 scene.render.resolution_x=850;scene.render.resolution_y=1000;scene.render.resolution_percentage=100;scene.view_settings.view_transform='AgX'
 scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.44,.49,.46,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.65
 for loc,power,size in [((-3,-4,5),430,4),((3,-1,3),230,3),((0,3,4),450,3)]:
  bpy.ops.object.light_add(type='AREA',location=loc);l=bpy.context.object;l.data.energy=power;l.data.shape='DISK';l.data.size=size;l.rotation_euler=(Vector((0,0,1))-l.location).to_track_quat('-Z','Y').to_euler()
 bpy.ops.object.camera_add(location=(1.8,-6,2.3));camera=bpy.context.object;camera.rotation_euler=(Vector((0,0,1))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=2.10;scene.camera=camera
 bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(kind+'.blend')))
 if '--no-render' not in sys.argv:
  scene.render.filepath=str(TMP/(kind+'.png'));bpy.ops.render.render(write_still=True)
 report=dict(id=kind,triangles=tris,bones=len(rig.data.bones),meshes=len(PARTS),bytes=dest.stat().st_size,textures=textures,clips=['Idle','Walk','Run','Work'],style_reference='resident_yun')
 print('CHARACTER COMPLETE',json.dumps(report),flush=True)
 return report

if __name__=='__main__':
 reports=[]
 for kind in SPECS:
  if any(a.startswith('--character=') for a in sys.argv) and '--character='+kind not in sys.argv:continue
  if kind=='player':
   # Preserve the approved concept when rebuilding the complete village cast.
   sys.path.insert(0,str(Path(__file__).resolve().parent))
   from build_player_concept import build as build_concept_player
   reports.append(build_concept_player())
  else:reports.append(build(kind))
 reportfile=OUT/'model_report.json'
 if len(reports)<4 and reportfile.exists():
  old=json.loads(reportfile.read_text());reports=[r for r in old if r['id'] not in [v['id'] for v in reports]]+reports
 reportfile.write_text(json.dumps(reports,indent=2)+'\n',encoding='utf8')
