"""Build potato, tomato and lavender seed/mature assets, without touching roses.

blender --background --python scripts/tools/build_two_stage_crops.py
Overwrites these three crops' GLBs and art/blender/{crop}.blend only.
"""
from pathlib import Path
import math
import random
import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
TAU = math.tau
bpy.context.preferences.filepaths.save_version = 0


def tint(rgb, t, u=0, phase=0):
    brush = .89 + .07 * math.sin(t * 19 + u * 7 + phase) + .04 * math.cos(t * 31 - u * 9)
    return tuple(min(1, c * brush) for c in rgb) + (1,)


def material(name, double=False):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.use_backface_culling = not double
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = .48 if name == "fruit" else .85
    bsdf.inputs["Specular IOR Level"].default_value = .28
    color = mat.node_tree.nodes.new("ShaderNodeVertexColor")
    color.layer_name = "Paint"
    mat.node_tree.links.new(color.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


class MeshPaint:
    def __init__(self, palette):
        self.parts = {}
        self.palette = palette

    def add(self, kind, vertices, faces, colors):
        vs, fs, cs = self.parts.setdefault(kind, ([], [], []))
        start = len(vs)
        vs.extend(vertices)
        fs.extend(tuple(i + start for i in f) for f in faces)
        cs.extend(colors)

    def tube(self, controls, radius, color=None):
        # Catmull-Rom interpolation keeps branching stems organic and continuous.
        controls = [Vector(p) for p in controls]
        points = []
        for i in range(len(controls)-1):
            a, b, c, d = [controls[max(0, min(len(controls)-1, j))] for j in [i-1, i, i+1, i+2]]
            for step in range(4):
                t = step / 4
                points.append(.5*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t))
        points.append(controls[-1])
        vs, fs, cs = [], [], []
        sides = 7
        for i, p in enumerate(points):
            direction = (points[min(i+1,len(points)-1)]-points[max(0,i-1)]).normalized()
            ref = Vector((0,1,0)) if abs(direction.y) < .9 else Vector((1,0,0))
            right = direction.cross(ref).normalized()
            up = direction.cross(right).normalized()
            r = radius * (1 - .68 * i / (len(points)-1))
            for j in range(sides):
                a = TAU * j / sides
                vs.append(p + r*(right*math.cos(a)+up*math.sin(a)))
                cs.append(tint(color or self.palette["stems"],i*.07,j*.14))
                if i:
                    k, n = i*sides+j, i*sides+(j+1)%sides
                    fs.append((k-sides,n-sides,n,k))
        fs.extend([tuple(reversed(range(sides))), tuple((len(points)-1)*sides+j for j in range(sides))])
        self.add("stems", vs, fs, cs)

    def leaf(self, base, direction, length, width, phase=0, lobes=False, kind="leaves", color=None):
        base, direction = Vector(base), Vector(direction).normalized()
        side = direction.cross(Vector((0,0,1))).normalized()
        if side.length < .1:
            side = Vector((1,0,0))
        up = side.cross(direction).normalized()
        vs, fs, cs = [], [], []
        rows, cols = 12, 6
        for i in range(rows+1):
            t = i/rows
            span = math.sin(math.pi*t)**.78 * width*.5
            if lobes:
                span *= .80 + .20*math.cos(t*math.pi*10)
            for j in range(cols+1):
                u = 2*j/cols-1
                bend = length*(.17*math.sin(t*math.pi)-.19*t*t)
                vs.append(base+direction*length*t+side*span*u+up*(bend+abs(u)*width*.13*math.sin(t*math.pi)))
                rgb = np.array(color or self.palette[kind])
                rgb *= .83 + .20*t + .10*(1-abs(u))
                if abs(u) < .01:
                    rgb = rgb*.7 + np.array((.57,.62,.25))*.3
                cs.append(tint(rgb,t,u,phase))
                if i and j:
                    k = i*(cols+1)+j
                    fs.append((k-cols-2,k-cols-1,k,k-1))
        self.add(kind,vs,fs,cs)

    def oval(self, kind, center, radii, color, direction=(0,0,1), phase=0, lobes=0, detail=12):
        center = Vector(center)
        rot = Vector((0,0,1)).rotation_difference(Vector(direction).normalized())
        vs, fs, cs = [], [], []
        rows, sides = 8, detail
        for i in range(rows+1):
            t = math.pi*i/rows
            for j in range(sides):
                a = TAU*j/sides
                ripple = 1 + lobes*math.cos(a*6)*math.sin(t)
                p = Vector((math.sin(t)*math.cos(a)*radii[0]*ripple, math.sin(t)*math.sin(a)*radii[1]*ripple, math.cos(t)*radii[2]))
                vs.append(center+rot@p)
                cs.append(tint(color,i/rows,j/sides,phase))
                if i:
                    k, n = i*sides+j, i*sides+(j+1)%sides
                    fs.append((k,n,n-sides,k-sides))
        self.add(kind,vs,fs,cs)

    def flower(self, center, direction, radius, color):
        center = Vector(center)
        rot = Vector((0,0,1)).rotation_difference(Vector(direction).normalized())
        vs, fs, cs = [], [], []
        # One continuous, cupped five-lobed corolla around the golden anthers.
        rings, sides = 5, 50
        for i in range(rings+1):
            t = i/rings
            for j in range(sides):
                a = TAU*j/sides
                r = radius*t*(.78+.22*math.cos(a*5))
                p = Vector((math.cos(a)*r,math.sin(a)*r,radius*(.20*t*t+.09*math.cos(a*5)*t)))
                vs.append(center+rot@p)
                cs.append(tint(color,t,j/sides))
                if i:
                    k, n = i*sides+j, i*sides+(j+1)%sides
                    fs.append((k-sides,k,n,n-sides))
        self.add("flowers",vs,fs,cs)
        self.oval("flowers",center+rot@Vector((0,0,radius*.17)),(radius*.16,radius*.16,radius*.33),(.95,.56,.025),direction)

    def export(self, crop, stage, materials):
        name = crop+"_"+stage
        collection = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(collection)
        bpy.ops.object.select_all(action="DESELECT")
        for kind,(vs,fs,cs) in self.parts.items():
            mesh = bpy.data.meshes.new(name+"_"+kind)
            mesh.from_pydata(vs,[],fs)
            mesh.update()
            mesh.materials.append(materials[kind])
            paint = mesh.color_attributes.new(name="Paint",type="FLOAT_COLOR",domain="POINT")
            paint.data.foreach_set("color",np.array(cs,dtype=np.float32).ravel())
            for polygon in mesh.polygons:
                polygon.use_smooth = True
            obj = bpy.data.objects.new(kind,mesh)
            collection.objects.link(obj)
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
        out = ROOT / "assets/models/crops" / crop
        out.mkdir(parents=True,exist_ok=True)
        bpy.ops.export_scene.gltf(filepath=str(out/(name+".glb")),export_format="GLB",use_selection=True,
            export_yup=True,export_animations=False,export_cameras=False,export_lights=False,
            export_materials="EXPORT",export_vertex_color="ACTIVE")
        print(name,"vertices",sum(len(v[0]) for v in self.parts.values()),flush=True)
        return collection


def broad_plant(crop, palette):
    g = MeshPaint(palette)
    rng = random.Random(90631 if crop == "potato" else 90632)
    tomato = crop == "tomato"
    tips = [(-.20,-.10,.53),(.18,-.13,.57),(-.04,.13,.72),(.19,.16,.46),(-.23,.17,.39)]
    if tomato:
        tips = [(0,0,.99),(-.22,-.08,.72),(.23,.05,.63),(-.10,.20,.53)]
    for index,tip in enumerate(tips):
        tip = Vector(tip)
        base = Vector((tip.x*.12,tip.y*.12,-.025))
        mid = Vector((tip.x*.48,tip.y*.60,tip.z*.52))
        g.tube([base,mid,tip],.019 if tomato else .014)
        for level in range(6):
            t = .20+level*.13
            at = base.lerp(mid,t/.52) if t<.52 else mid.lerp(tip,(t-.52)/.48)
            a = index*2.4+level*2.39
            d = Vector((math.cos(a),math.sin(a),.24))
            end = at+d*.07
            g.tube([at,end],.004)
            length = rng.uniform(.18,.24) if tomato else rng.uniform(.20,.27)
            g.leaf(end,d,length,length*(.55 if tomato else .65),index+level,tomato)
            if level%2 == 0:
                for side in [-1,1]:
                    angle = a+side*.85
                    g.leaf(end+d*.018,(math.cos(angle),math.sin(angle),.22),length*.66,length*.43,index,tomato)
        if not tomato:
            for j in range(2):
                offset = Vector((.06*math.cos(index+j*2),.06*math.sin(index+j*2),j*.015))
                center = tip+offset
                g.tube([tip,center],.004)
                g.flower(center,(.3*math.sin(index),-.50,.8),.056,(.78,.70,.87))
        else:
            g.flower(tip,(.4,-.5,.8),.04,(.96,.65,.045))
    if tomato:
        for index,(x,y,z,r) in enumerate([(-.15,-.18,.30,.095),(.20,-.13,.51,.092),(-.12,.08,.75,.087),(.18,.20,.33,.08),(-.23,.12,.51,.085),(.05,-.15,.86,.052)]):
            center = Vector((x,y,z))
            top = center+Vector((0,0,r*.82))
            g.tube([Vector((x*.35,y*.35,z+.08)),top],.006)
            g.oval("fruit",center,(r,r*.95,r*.91),(.85,.065,.018),phase=index,lobes=.045,detail=24)
            for j in range(5):
                a = TAU*j/5+index
                g.leaf(top,(math.cos(a),math.sin(a),.20),r*.85,r*.25,j,kind="fruit",color=(.26,.38,.055))
    return g


def lavender(palette):
    g = MeshPaint(palette)
    rng = random.Random(90633)
    for index in range(19):
        a = index*2.399
        radius = .10+.20*math.sqrt(index/19)
        height = .81-index*.018+rng.uniform(-.06,.06)
        tip = Vector((math.cos(a)*radius,math.sin(a)*radius,height))
        base = Vector((tip.x*.13,tip.y*.13,-.025))
        mid = Vector((tip.x*.42,tip.y*.42,height*.52))
        g.tube([base,mid,tip],.0055)
        for level in range(4):
            t = .15+level*.135
            at = base.lerp(tip,t)
            for side in [-1,1]:
                angle = a+side*1.1+level*.35
                g.leaf(at,(math.cos(angle),math.sin(angle),.7),.20+level*.012,.024,index)
        axis = (tip-mid).normalized()
        rot = Vector((0,0,1)).rotation_difference(axis)
        for ring in range(7):
            radius = .023*(1-.75*(ring/7)**2)
            center = tip+axis*(ring*.023-.10)
            for j in range(5):
                angle = TAU*j/5+ring*.6
                radial = rot@Vector((math.cos(angle),math.sin(angle),0))
                pos = center+radial*radius
                color = np.array((.38,.14,.70))*(.87+.20*ring/6)
                g.oval("flowers",pos,(.011,.013,.021),color,axis*.85+radial*.4,phase=index+ring,detail=8)
        g.oval("flowers",tip+axis*.055,(.012,.013,.025),(.47,.23,.77),axis,detail=8)
    return g


def main():
    for crop in ["potato","tomato","lavender"]:
        bpy.ops.object.select_all(action="SELECT")
        bpy.ops.object.delete(use_global=False)
        for collection in list(bpy.data.collections):
            bpy.data.collections.remove(collection)
        # Pack the original illustration as an editable art reference, not a card.
        reference = bpy.data.images.load(str(ROOT/"assets/crops"/crop/"painted/stage_3/variant_0_front.png"))
        reference.pack()
        reference.name = crop+" - original painted reference"
        palette = {"stems":(.28,.36,.075),"leaves":(.32,.44,.09)}
        if crop == "lavender":
            palette = {"stems":(.32,.39,.18),"leaves":(.40,.47,.25)}
        materials = {kind: material(kind,kind in ["leaves","flowers","fruit"]) for kind in ["stems","leaves","flowers","fruit","seeds"]}
        seeds = MeshPaint(palette)
        for i,(x,y) in enumerate([(-.14,-.12),(.14,-.11),(-.11,.14),(.14,.15),(0,0)]):
            radii = (.044,.035,.028) if crop == "potato" else ((.023,.016,.010) if crop == "tomato" else (.018,.011,.010))
            center = Vector((x,y,-.015 if crop == "potato" else -.004))
            color = (.46,.30,.13) if crop == "potato" else ((.64,.47,.23) if crop == "tomato" else (.32,.22,.14))
            seeds.oval("seeds",center,radii,color,phase=i,lobes=.07 if crop == "potato" else 0)
            if crop == "potato":
                for j in range(3):
                    eye = center+Vector((.018*math.cos(i+j*2),.018*math.sin(i+j*2),.025))
                    seeds.oval("seeds",eye,(.003,.003,.002),(.22,.13,.045),detail=8)
        seed_collection = seeds.export(crop,"seed",materials)
        grown = lavender(palette) if crop == "lavender" else broad_plant(crop,palette)
        grown.export(crop,"mature",materials)
        seed_collection.hide_viewport = True
        seed_collection.hide_render = True
        bpy.ops.object.camera_add(location=(1.3,-1.8,1.2))
        camera = bpy.context.object
        camera.rotation_euler = (Vector((0,0,.4))-camera.location).to_track_quat("-Z","Y").to_euler()
        camera.data.lens = 55
        bpy.context.scene.camera = camera
        bpy.ops.object.light_add(type="AREA",location=(-2,-3,4))
        bpy.context.object.data.energy = 450
        bpy.context.object.data.size = 4
        bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/blender"/(crop+".blend")))
    print("TWO_STAGE_CROPS_READY",flush=True)


if __name__ == "__main__":
    main()
