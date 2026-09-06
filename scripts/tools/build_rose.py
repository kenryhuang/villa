"""Build the rose's rooted, camera-independent meshes for the 3D farm.

blender --background --python scripts/tools/build_rose.py
Only rose assets and art/blender/rose.blend are written. The old illustration
is sampled for surface paint; it is never displayed as a sprite or flat card.
"""
from pathlib import Path
import math
import random
import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/models/crops/rose"
OUT.mkdir(parents=True, exist_ok=True)
SOURCE = ROOT / "art/blender/rose.blend"
RNG = random.Random(90626)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.save_version = 0
reference = bpy.data.images.load(str(ROOT / "assets/crops/rose/painted/stage_3/variant_0_front.png"))
reference.name = "Original rose painting - palette reference"
reference.pack()
pixels = np.empty(len(reference.pixels), dtype=np.float32)
reference.pixels.foreach_get(pixels)
pixels = pixels.reshape((reference.size[1], reference.size[0], 4))


def paint(kind, t, u, seed):
    # Use small areas inside the original painted petals/leaves as brush detail.
    if kind == "petal":
        x, y = .28 + (u + 1) * .07, .39 + t * .095
        base = (.70, .025, .045)
    else:
        x, y = .385 + (u + 1) * .052, .183 + t * .080
        base = (.35, .42, .10)
    px = pixels[int((1-y) * (reference.size[1]-1)), int(x * (reference.size[0]-1))]
    valid = px[3] > .8 and (px[0] > px[1] * 1.9 if kind == "petal" else px[1] > px[0] * .83)
    # The illustration already has strong baked shadows. Mix its brush colors
    # with a midtone palette so real 3D lighting does not shade it twice.
    rgb = np.array(px[:3] if valid else base) * .30 + np.array(base) * .70
    shade = .84 + .12 * math.sin(t*16+u*9+seed) + .045 * math.cos(t*41-u*13)
    if kind == "petal":
        shade *= .80 + .25*t
    else:
        shade *= .80 + .20 * (1-abs(u))
        if abs(u) < .08:
            rgb = rgb * .75 + np.array((.70,.65,.24)) * .25
    return tuple(np.clip(rgb * shade, 0, 1)) + (1,)


def material(name, double_sided=False):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.use_backface_culling = not double_sided
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = .82
    bsdf.inputs["Specular IOR Level"].default_value = .22
    color = mat.node_tree.nodes.new("ShaderNodeVertexColor")
    color.layer_name = "Paint"
    mat.node_tree.links.new(color.outputs["Color"], bsdf.inputs["Base Color"])
    return mat

MATERIALS = {"stems": material("Rose - olive stems"), "leaves": material("Rose - painted leaf surfaces", True),
             "petals": material("Rose - crimson painted petals", True), "seeds": material("Rose - sown seeds")}


class Geometry:
    def __init__(self):
        self.parts = {}

    def add(self, kind, vertices, faces, colors):
        verts, polys, cols = self.parts.setdefault(kind, ([],[],[]))
        offset = len(verts)
        verts.extend(vertices)
        polys.extend(tuple(i+offset for i in face) for face in faces)
        cols.extend(colors)

    def tube(self, points, radii, color=(.20,.26,.05), sides=7):
        points = [Vector(p) for p in points]
        vertices, faces = [], []
        for i, point in enumerate(points):
            tangent = (points[min(i+1,len(points)-1)]-points[max(0,i-1)]).normalized()
            right = tangent.cross(Vector((0,1,0))).normalized()
            up = right.cross(tangent).normalized()
            for j in range(sides):
                a = j*math.tau/sides
                vertices.append(point + radii[i]*(right*math.cos(a)+up*math.sin(a)))
                if i:
                    k=i*sides+j
                    n=i*sides+(j+1)%sides
                    faces.append((k,n,n-sides,k-sides))
        faces.append(tuple(range(sides)))
        faces.append(tuple(reversed([(len(points)-1)*sides+j for j in range(sides)])))
        colors=[tuple(c*(.88+.12*math.sin(i*.73)) for c in color)+(1,) for i in range(len(vertices))]
        self.add("stems",vertices,faces,colors)

    def leaf(self, base, direction, length, width, seed, dry=False):
        base, direction = Vector(base), Vector(direction).normalized()
        side = direction.cross(Vector((0,0,1))).normalized()
        if side.length < .1:
            side = Vector((1,0,0))
        up = side.cross(direction).normalized()
        vertices, faces, colors = [], [], []
        rows, columns = 9, 6
        for i in range(rows+1):
            t=i/rows
            span=math.sin(math.pi*t)**.82 * width
            span*=1+ .09*math.sin(i*math.pi*.95)
            for j in range(columns+1):
                u=j/columns*2-1
                bend=length*(.13*math.sin(t*math.pi) - (.36 if dry else .12)*t*t)
                point=base+direction*(length*t)+side*(span*u*.5)+up*(bend + abs(u)*width*.11*math.sin(math.pi*t))
                vertices.append(point)
                colors.append((.13+.08*t,.08+.05*t,.026,1) if dry else paint("leaf",t,u,seed))
                if i and j:
                    k=i*(columns+1)+j
                    faces.append((k-columns-2,k-columns-1,k,k-1))
        self.add("leaves",vertices,faces,colors)
        # A raised midrib is real geometry, visible from low angles.
        end=base+direction*length
        self.tube([base,base.lerp(end,.5)+up*length*.135,end-up*length*.12],
                  [.0022,.0014,.0005],(.20,.23,.055) if not dry else (.12,.075,.025),5)

    def flower(self, center, direction, size, seed, bud=False):
        rotation=Vector((0,0,1)).rotation_difference(Vector(direction).normalized())
        center=Vector(center)
        rings=[(5,.044,.105)] if bud else [(7,.14,.09),(7,.115,.12),(6,.078,.14),(5,.042,.148)]
        for layer,(count,radius,height) in enumerate(rings):
            for petal in range(count):
                angle=petal*math.tau/count+layer*.56+seed*.71
                vertices,faces,colors=[],[],[]
                rows,columns=12,8
                for i in range(rows+1):
                    t=i/rows
                    for j in range(columns+1):
                        u=j/columns*2-1
                        # Keep a broad, rounded outer lip instead of converging to a spike.
                        spread=(.68 if bud else .64)*max(.03, math.sin(math.pi*t*(1 if bud else .76))**.60)
                        theta=angle+spread*u
                        rounded_t=t*(1-.18*u*u)
                        r=.008+radius*rounded_t**.72
                        if bud:
                            r*=math.sin(math.pi*t)*.8+.1
                        z=height*math.sin(rounded_t*math.pi*.5)
                        z-= (.004 if bud else .027/(layer+1))*max(0,(t-.62)/.38)**2
                        z+=.005*u*u*math.sin(math.pi*t)+.001*math.sin(u*7+seed)*t
                        v=Vector((r*math.cos(theta),r*math.sin(theta),z))*size
                        vertices.append(center+rotation@v)
                        colors.append(paint("petal",t,u,seed+layer))
                        if i and j:
                            k=i*(columns+1)+j
                            faces.append((k-1,k,k-columns-1,k-columns-2))
                self.add("petals",vertices,faces,colors)
        for i in range(5):
            a=i*math.tau/5
            direction=rotation@Vector((math.cos(a)*.65,math.sin(a)*.65,.65))
            self.leaf(center,direction,.065*size,.022*size,seed+i)

    def seed(self, center, size, angle):
        vertices,faces,colors=[],[],[]
        center=Vector(center)
        for i in range(9):
            latitude=math.pi*i/8
            for j in range(10):
                a=math.tau*j/10
                x=math.sin(latitude)*math.cos(a)*size
                y=math.sin(latitude)*math.sin(a)*size*.5
                z=math.cos(latitude)*size*.43
                vertices.append(center+Vector((x*math.cos(angle)-y*math.sin(angle),x*math.sin(angle)+y*math.cos(angle),z)))
                colors.append((.32+.16*math.sin(latitude),.16+.10*math.sin(latitude),.038,1))
                if i:
                    k=i*10+j
                    n=i*10+(j+1)%10
                    faces.append((k,n,n-10,k-10))
        self.add("seeds",vertices,faces,colors)

    def export(self, name):
        collection=bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(collection)
        objects=[]
        for kind,(vertices,faces,colors) in self.parts.items():
            mesh=bpy.data.meshes.new(name+"_"+kind)
            mesh.from_pydata(vertices,[],faces)
            mesh.update()
            mesh.materials.append(MATERIALS[kind])
            color=mesh.color_attributes.new(name="Paint",type="FLOAT_COLOR",domain="POINT")
            color.data.foreach_set("color",np.array(colors,dtype=np.float32).ravel())
            for poly in mesh.polygons:
                poly.use_smooth=True
            obj=bpy.data.objects.new(kind,mesh)
            collection.objects.link(obj)
            objects.append(obj)
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active=objects[0]
        bpy.ops.export_scene.gltf(filepath=str(OUT/(name+".glb")),export_format="GLB",use_selection=True,
            export_yup=True,export_animations=False,export_cameras=False,export_lights=False,
            export_materials="EXPORT",export_vertex_color="ACTIVE",export_all_vertex_colors=False)
        print(name,{"vertices":sum(len(o.data.vertices) for o in objects),"meshes":len(objects)},flush=True)
        return collection


stages=[]
g=Geometry()
for x,y in [(-.15,-.12),(.14,-.1),(-.10,.14),(.15,.15),(0,0)]:
    # Bury the lower half, including the troughs between sculpted soil ridges.
    g.seed((x,y,-.004),.025,RNG.uniform(0,math.tau))
stages.append(g.export("rose_seed"))


def plant(stage):
    g=Geometry()
    if stage==1:
        for index,(x,y) in enumerate([(-.12,-.10),(.11,.12),(0,-.01)]):
            stem=[(x,y,-.016),(x+.006,y,.05),(x-.008,y,.11)]
            g.tube(stem,[.006,.004,.0025])
            for side in [-1,1]:
                g.leaf(stem[1],(side,.25,.48),.09,.054,index+side)
            g.leaf(stem[-1],(.3,-.7,.7),.068,.035,index)
        return g
    shoot_tips=[(-.21,-.13,.57),(.19,-.07,.70),(-.06,.15,.80),(.21,.20,.49),(-.27,.15,.39),(.07,-.26,.38)]
    scale=.65 if stage==2 else 1
    dry=stage==4
    for index,tip in enumerate(shoot_tips):
        tip=Vector(tip)*scale
        base=Vector((tip.x*.25,tip.y*.25,-.018))
        points=[base,Vector((tip.x*.3,tip.y*.2,tip.z*.25)),Vector((tip.x*.6,tip.y*.8,tip.z*.58)),tip]
        if dry:
            points[-1]+=Vector((.07*math.sin(index),-.06,-.08))
        g.tube(points,[.013*scale,.011*scale,.006*scale,.0035*scale],(.12,.09,.028) if dry else (.10,.16,.024))
        for leaf_index in range(5 if stage==2 else 7):
            t=.18+leaf_index*.11
            attachment=points[1].lerp(points[2],max(0,min(1,(t-.25)/.33))) if t<.58 else points[2].lerp(points[3],(t-.58)/.42)
            angle=index*2.1+leaf_index*2.38
            direction=Vector((math.cos(angle),math.sin(angle),.26 if not dry else -.38)).normalized()
            petiole=attachment+direction*.04*scale
            g.tube([attachment,petiole],[.0027,.0015],(.09,.12,.02))
            length=(.13+RNG.random()*.05)*scale
            g.leaf(petiole,direction,length,length*.56,index+leaf_index,dry)
            if leaf_index%2==0 and not dry:
                for offset in [-.58,.58]:
                    d=Vector((math.cos(angle+offset),math.sin(angle+offset),.18))
                    g.leaf(petiole+direction*length*.22,d,length*.64,length*.39,index+leaf_index+offset)
        if dry:
            g.seed(points[-1],.018,0)
        else:
            aim=(.12*math.sin(index*1.7),-.45+.18*math.cos(index),.84)
            g.flower(tip,aim,.65 if stage==2 else (.85 if index>3 else 1),index,bud=stage==2 or index>=4)
    return g

for stage,name in [(1,"rose_sprout"),(2,"rose_growing"),(3,"rose_mature"),(4,"rose_withered")]:
    stages.append(plant(stage).export(name))

# Editable source opens on the mature bush; stages share the exact root origin.
for stage in stages:
    stage.hide_viewport=stage.name!="rose_mature"
    stage.hide_render=stage.name!="rose_mature"
scene=bpy.context.scene
scene.render.engine="CYCLES"
scene.render.resolution_x=1100
scene.render.resolution_y=1100
scene.render.resolution_percentage=100
scene.world.color=(.38,.45,.33)
bpy.ops.object.camera_add(location=(1.35,-1.75,1.05))
camera=bpy.context.object
camera.rotation_euler=(Vector((0,0,.40))-camera.location).to_track_quat("-Z","Y").to_euler()
camera.data.lens=55
scene.camera=camera
bpy.ops.object.light_add(type="AREA",location=(-2,-3,4))
bpy.context.object.data.energy=450
bpy.context.object.data.size=4
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE))
print("ROSE_ASSETS_READY",flush=True)
