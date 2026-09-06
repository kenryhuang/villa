"""Complete the original crop catalog with rooted seed/mature Blender meshes.

blender --background --python scripts/tools/build_remaining_crops.py
Only writes the ten crops listed in CROPS. Previous models are not regenerated.
"""
from pathlib import Path
import sys
import math
import random
import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.dont_write_bytecode = True
from build_two_stage_crops import MeshPaint, material, tint, ROOT, TAU

CROPS = ["carrot", "strawberry", "blueberry", "watermelon", "sunflower",
         "pumpkin", "apple", "peach", "grape", "lemon"]
TREES = ["apple", "peach", "lemon"]
PALETTE = {"stems": (.26,.34,.085), "leaves": (.32,.45,.12)}


class GardenMesh(MeshPaint):
    def fruit(self, center, radii, crop, phase=0):
        center = Vector(center)
        vs, fs, cs = [], [], []
        rows, sides = 16, 48
        for i in range(rows+1):
            t = math.pi*i/rows
            for j in range(sides):
                a = TAU*j/sides
                radial, z = math.sin(t), math.cos(t)
                color = (.78,.04,.035)
                if crop == "watermelon":
                    stripe = .5+.5*math.sin(a*10+.12*math.sin(t*17))
                    color = (.08,.23,.075) if stripe < .48 else (.40,.55,.12)
                elif crop == "pumpkin":
                    radial *= 1+.11*math.cos(a*10)
                    z *= .88+.12*math.sin(t)
                    color = (.93,.31+.055*math.cos(a*10),.022)
                elif crop == "apple":
                    radial *= 1+.045*math.cos(a*5)*abs(z)
                    z *= .85+.15*math.sin(t)
                    color = (.78,.045+.11*max(0,-z),.025)
                elif crop == "peach":
                    radial *= 1-.10*math.exp(-((a-math.pi)/.15)**2)
                    blush = (.5+.5*math.cos(a+.4))**2
                    color = (.88,.52-.34*blush,.13-.035*blush)
                elif crop == "lemon":
                    radial *= .91+.09*math.sin(t)
                    z *= 1+.12*abs(z)**8
                    color = (.91,.71,.04)
                elif crop == "strawberry":
                    radial *= .65+.35*(z+1)*.5
                    z = z if z >= 0 else z*1.15
                    color = (.85,.035,.035)
                p = Vector((radii[0]*radial*math.cos(a),radii[1]*radial*math.sin(a),radii[2]*z))
                vs.append(center+p)
                cs.append(tint(color,i/rows,j/sides,phase))
                if i:
                    k, n = i*sides+j, i*sides+(j+1)%sides
                    fs.append((k,n,n-sides,k-sides))
        self.add("fruit",vs,fs,cs)
        if crop == "strawberry":
            # Small separate achenes avoid stretching painted dots into stripes.
            for ring in range(1,9):
                t=math.pi*ring/10
                count=max(5,int(15*math.sin(t)))
                for j in range(count):
                    a=TAU*(j+.5*(ring%2))/count
                    z=math.cos(t)
                    radial=math.sin(t)*(.65+.35*(z+1)*.5)
                    p=Vector((radii[0]*radial*math.cos(a),radii[1]*radial*math.sin(a),radii[2]*(z if z>=0 else z*1.15)))
                    normal=Vector((math.cos(a)*math.sin(t),math.sin(a)*math.sin(t),z)).normalized()
                    self.oval("fruit",center+p,(.0015,.0024,.0008),(.82,.52,.12),normal,detail=6)

    def scar(self, center, normal, size):
        rot=Vector((0,0,1)).rotation_difference(Vector(normal).normalized())
        center=Vector(center)
        vs=[center]
        for j in range(10):
            a=TAU*j/10
            r=size*(1 if j%2==0 else .52)
            vs.append(center+rot@Vector((r*math.cos(a),r*math.sin(a),0)))
        self.add("fruit",vs,[(0,1+j,1+(j+1)%10) for j in range(10)],[(.065,.07,.14,1)]*11)

    def palm_leaf(self, base, direction, size, phase=0, deep=False):
        # A continuous five-lobed, cupped leaf; real outline, no image alpha.
        center = Vector(base)
        rot = Vector((0,0,1)).rotation_difference(Vector(direction).normalized())
        vs,fs,cs = [],[],[]
        rings,sides = 6,60
        for i in range(rings+1):
            t=i/rings
            for j in range(sides):
                a=TAU*j/sides
                outline=(.73+.27*math.cos(a*5)) if deep else (.89+.11*math.cos(a*5))
                r=size*t*outline*(.97+.03*math.cos(a*25))
                p=Vector((r*math.cos(a),r*math.sin(a),size*(.14*t*t+.07*math.cos(a*5)*t)))
                vs.append(center+rot@p)
                vein=abs(math.sin(a*2.5))<.13
                color=(.49,.57,.21) if vein else self.palette["leaves"]
                cs.append(tint(color,t,j/sides,phase))
                if i:
                    k,n=i*sides+j,i*sides+(j+1)%sides
                    fs.append((k-sides,k,n,n-sides))
        self.add("leaves",vs,fs,cs)

    def curl(self, start, phase, size=.045):
        start=Vector(start)
        points=[]
        for i in range(20):
            t=i/19
            a=t*TAU*1.3+phase
            points.append(start+Vector((size*t*math.cos(a),size*t*math.sin(a),t*.045)))
        self.tube(points,.0025)

    def petal(self, base, radial, axis, length, width, phase):
        tangent=axis.cross(radial).normalized()
        vs,fs,cs=[],[],[]
        rows,cols=10,6
        for i in range(rows+1):
            t=i/rows
            for j in range(cols+1):
                u=j/cols*2-1
                point=base+radial*(length*t)+tangent*(width*.5*math.sin(t*math.pi)**.7*u)
                point+=axis*length*(.15*math.sin(t*math.pi)-.12*t*t+.07*u*u*math.sin(t*math.pi))
                vs.append(point)
                cs.append(tint((.98,.65+.12*t,.018),t,u,phase))
                if i and j:
                    k=i*(cols+1)+j
                    fs.append((k-1,k,k-cols-1,k-cols-2))
        self.add("flowers",vs,fs,cs)


def tree(crop, seed=False):
    g=GardenMesh({"stems":(.28,.16,.065),"leaves":(.30,.44,.10)})
    rng=random.Random(719+CROPS.index(crop))
    if seed:
        g.tube([(0,0,-.03),(.015,0,.13),(-.006,.006,.31)],.012)
        for i in range(5):
            a=i*2.399
            g.leaf((0,0,.10+i*.037),(math.cos(a),math.sin(a),.5),.10,.045 if crop=="peach" else .065,i)
        return g
    g.tube([(0,0,-.035),(.035,.01,.35),(-.03,.03,.75),(.025,0,1.24),(0,.025,1.58)],.082)
    for i in range(5):
        a=i*TAU/5
        g.tube([(0,0,.08),(.075*math.cos(a),.075*math.sin(a),.015),(.15*math.cos(a),.15*math.sin(a),-.015)],.024)
    for branch in range(11):
        a=branch*2.399
        z=.70+branch*.064
        radius=.40*(1-.44*branch/11)
        tip=Vector((math.cos(a)*radius,math.sin(a)*radius,z+.24))
        at=Vector((0,0,z-.15))
        mid=at.lerp(tip,.58)-Vector((0,0,.05))
        g.tube([at,mid,tip],.028*(1-.4*branch/11))
        for twig in range(5):
            angle=a+twig*1.27
            begin=mid.lerp(tip,twig/5)
            end=begin+Vector((math.cos(angle)*.15,math.sin(angle)*.15,.08))
            g.tube([begin,end],.005)
            for k in range(5):
                leaf_a=angle+k*2.399
                length=rng.uniform(.15,.21) if crop!="peach" else rng.uniform(.19,.26)
                g.leaf(begin.lerp(end,(k+1)/5),(math.cos(leaf_a),math.sin(leaf_a),rng.uniform(.2,.7)),length,length*(.30 if crop=="peach" else .58),twig+k, crop=="apple")
        fruit=tip+Vector((math.cos(a)*.055,math.sin(a)*.055,-.08))
        r=.075 if crop=="lemon" else .082
        g.tube([tip,fruit+Vector((0,0,r*.8))],.004)
        g.fruit(fruit,(r,r*.92,r*(1.28 if crop=="lemon" else 1)),crop,branch)
    return g


def carrot():
    g=GardenMesh(PALETTE)
    for index,(x,y) in enumerate([(-.18,-.12),(.17,-.10),(0,.18)]):
        g.oval("fruit",(x,y,-.025),(.065,.062,.09),(.94,.32,.015),detail=20)
        for frond in range(7):
            a=frond*2.399+index
            base=Vector((x,y,.035))
            tip=base+Vector((math.cos(a)*.21,math.sin(a)*.21,.30+.08*math.sin(frond)))
            g.tube([base,base.lerp(tip,.5)+Vector((0,0,.055)),tip],.004)
            for level in range(9):
                t=.18+level*.087
                p=base.lerp(tip,t)+Vector((0,0,.045*math.sin(t*math.pi)))
                for side in [-1,1]:
                    d=Vector((math.cos(a+side*.95),math.sin(a+side*.95),.38))
                    length=.13*(1-.55*t)
                    g.leaf(p,d,length,.028,frond+level)
    return g


def strawberry():
    g=GardenMesh({"stems":(.31,.34,.085),"leaves":(.23,.41,.16)})
    for i in range(9):
        a=i*2.399
        top=Vector((math.cos(a)*.18,math.sin(a)*.18,.18+.08*math.sin(i)))
        g.tube([(0,0,-.025),top*.5,top],.005)
        for j in [-1,0,1]:
            angle=a+j*.85
            g.leaf(top,(math.cos(angle),math.sin(angle),.35),.18,.14,i+j,True)
        center=Vector((math.cos(a)*.29,math.sin(a)*.29,.08+.025*(i%2)))
        g.tube([top,center+Vector((0,0,.065))],.004)
        g.fruit(center,(.047,.046,.065),"strawberry",i)
        for j in range(5):
            angle=j*TAU/5
            g.leaf(center+Vector((0,0,.054)),(math.cos(angle),math.sin(angle),.35),.047,.016,j)
        if i%3==0:
            g.flower(top+Vector((0,0,.045)),(.2,-.4,.9),.035,(.90,.86,.73))
    return g


def blueberry():
    g=GardenMesh({"stems":(.32,.19,.085),"leaves":(.27,.43,.16)})
    for i in range(8):
        a=i*2.399
        tip=Vector((math.cos(a)*.28,math.sin(a)*.28,.56+i*.035))
        base=Vector((0,0,-.025))
        g.tube([base,tip*.48,tip],.015)
        for k in range(7):
            p=base.lerp(tip,.25+k*.10)
            angle=a+k*2.399
            g.leaf(p,(math.cos(angle),math.sin(angle),.4),.16,.083,k)
            g.leaf(p,(math.cos(angle+1.1),math.sin(angle+1.1),.3),.12,.063,k+1)
        for cluster in range(2):
            center=tip-Vector((0,0,cluster*.21))
            for j in range(6):
                b=j*2.399
                p=center+Vector((.052*math.cos(b),.052*math.sin(b),-.018*(j%3)))
                g.tube([center,p],.002)
                g.oval("fruit",p,(.033,.033,.031),(.13,.22,.48),phase=j)
                # Dark five-point blossom scar identifies blueberries from all sides.
                normal=Vector((math.cos(b),math.sin(b),.2)).normalized()
                g.scar(p+normal*.032,normal,.009)
    return g


def vine(crop):
    g=GardenMesh({"stems":(.30,.36,.10),"leaves":(.27,.40,.11)})
    for i in range(6):
        a=i*TAU/6+.2
        root=Vector((0,0,-.025))
        end=Vector((math.cos(a)*.42,math.sin(a)*.42,.025))
        g.tube([root,end*.45+Vector((0,0,.045)),end],.009)
        for j in range(3):
            t=.35+j*.25
            p=root.lerp(end,t)+Vector((0,0,.065+(j%2)*.07))
            g.tube([root.lerp(end,t),p],.004)
            g.palm_leaf(p,(math.cos(a)*.45,math.sin(a)*.45,1),.125,i+j,crop=="watermelon")
        g.curl(end,a)
        if i%2==0:
            g.flower(end+Vector((0,0,.075)),(0,-.2,1),.038,(.95,.63,.035))
    for i,(x,y,r) in enumerate([(-.16,-.10,.155),(.19,.12,.12)]):
        p=Vector((x,y,r*.79-.014))
        g.fruit(p,(r,r*.90,r*.79),crop,i)
        g.tube([p+Vector((0,0,r*.74)),p+Vector((.025,.012,r*.98)),Vector((x+.08,y+.04,.045))],.013 if crop=="pumpkin" else .006)
    return g


def sunflower():
    g=GardenMesh(PALETTE)
    for i,(x,y,h,r) in enumerate([(0,.07,1.12,.15),(-.19,-.10,.82,.11),(.20,-.02,.72,.10)]):
        tip=Vector((x,y,h))
        g.tube([(x*.3,y*.3,-.03),(x*.7,y*.6,h*.55),tip],.018)
        for j in range(6):
            a=j*2.399+i
            g.leaf((x*j/6,y*j/6,.15+j*h*.125),(math.cos(a),math.sin(a),.30),.22,.15,j)
        axis=Vector((.15*math.sin(i),-.82,.55)).normalized()
        rot=Vector((0,0,1)).rotation_difference(axis)
        g.oval("flowers",tip,(r,r,.029),(.20,.085,.025),axis,detail=32)
        for j in range(24):
            a=j*TAU/24
            radial=rot@Vector((math.cos(a),math.sin(a),0))
            g.petal(tip+radial*r*.88,radial,axis,r*.74,r*.45,j)
        for j in range(95):
            a=j*2.399
            rad=r*.88*math.sqrt(j/95)
            p=tip+rot@Vector((math.cos(a)*rad,math.sin(a)*rad,.026+.008*(1-rad/r)))
            g.oval("flowers",p,(.007,.007,.006),(.43+.10*(j%3),.24,.045),axis,detail=6)
    return g


def grape():
    g=GardenMesh({"stems":(.32,.20,.085),"leaves":(.34,.43,.12)})
    for x in [-.34,.34]:
        g.tube([(x,0,-.025),(x+.008,0,.55),(x,0,1.10)],.030,(.40,.27,.14))
    g.tube([(-.37,0,.86),(0,.012,.86),(.37,0,.86)],.026,(.40,.27,.14))
    g.tube([(0,0,-.03),(-.06,.01,.30),(.07,0,.65),(-.02,0,.95)],.036)
    for side in [-1,1]:
        g.tube([(0,0,.62),(side*.18,.015,.83),(side*.32,0,.94)],.013)
    for i in range(18):
        a=i*2.399
        x=-.34+(i%6)*.136
        z=.42+(i//6)*.23
        p=Vector((x,.07*math.cos(a),z))
        at=Vector((x*.7,0,z-.08))
        g.tube([at,p],.004)
        g.palm_leaf(p,(.25*math.sin(a),(-1 if i%2 else 1)*.6,.75),.12,i,True)
        if i%5==0:
            g.curl(p,a)
    for cluster,(x,y,z) in enumerate([(-.25,-.11,.77),(.18,-.12,.70),(0,.14,.89),(-.16,.13,.51),(.30,.08,.45)]):
        top=Vector((x,y,z))
        g.tube([(x*.6,0,z+.08),top,top-Vector((0,0,.19))],.004)
        for ring in range(5):
            count=6-ring
            for j in range(count):
                a=j*TAU/count+ring*.65
                radius=.040*(1-ring/6)
                p=top+Vector((math.cos(a)*radius,math.sin(a)*radius,-ring*.035))
                g.oval("fruit",p,(.029,.029,.034),(.27+.025*(j%3),.055,.39+.03*ring),phase=cluster+j)
    return g


def seed_model(crop):
    if crop in TREES:
        return tree(crop,True)
    g=GardenMesh(PALETTE)
    for i,(x,y) in enumerate([(-.14,-.12),(.14,-.11),(-.11,.14),(.14,.15),(0,0)]):
        size=.023 if crop in ["pumpkin","sunflower","watermelon"] else .016
        color=(.67,.53,.29)
        if crop in ["watermelon","sunflower","grape"]:
            color=(.18,.13,.07)
        g.oval("seeds",(x,y,-.004),(size,size*.6,.010),color,phase=i)
    return g


def main():
    for crop in CROPS:
        # Remove scene collections, including hidden seed collections from the last crop.
        for obj in list(bpy.data.objects):
            bpy.data.objects.remove(obj,do_unlink=True)
        for collection in list(bpy.data.collections):
            bpy.data.collections.remove(collection)
        reference=bpy.data.images.load(str(ROOT/"assets/crops"/crop/"painted/stage_3/variant_0_front.png"))
        reference.name=crop+" - original painted reference"
        reference.pack()
        materials={kind:material(kind,kind in ["leaves","flowers"]) for kind in ["stems","leaves","flowers","fruit","seeds"]}
        seed_collection=seed_model(crop).export(crop,"seed",materials)
        builders={"carrot":carrot,"strawberry":strawberry,"blueberry":blueberry,"sunflower":sunflower,"grape":grape}
        grown=tree(crop) if crop in TREES else (vine(crop) if crop in ["watermelon","pumpkin"] else builders[crop]())
        grown.export(crop,"mature",materials)
        seed_collection.hide_viewport=True
        seed_collection.hide_render=True
        bpy.ops.object.camera_add(location=(2.0,-2.6,1.8))
        camera=bpy.context.object
        camera.rotation_euler=(Vector((0,0,.65 if crop in TREES else .4))-camera.location).to_track_quat("-Z","Y").to_euler()
        camera.data.lens=55
        bpy.context.scene.camera=camera
        bpy.ops.object.light_add(type="AREA",location=(-2,-3,4))
        bpy.context.object.data.energy=450
        bpy.context.object.data.size=4
        bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/blender"/(crop+".blend")))
    print("REMAINING_CROPS_READY",flush=True)


if __name__ == "__main__":
    main()
