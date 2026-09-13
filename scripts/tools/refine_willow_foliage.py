"""Replace willow leaf clumps with attached, folded leaves on pendant shoots.

Run after build_diverse_trees.py to apply the willow-only refinement. Existing
trunks, bark atlases, other species and game placements are preserved.
"""
from pathlib import Path
import bpy
import json
import math
import random
import sys
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from tree_bark_materials import share_bark_images

OUT = ROOT / 'assets/models/vegetation/diverse_trees'
TEMP = ROOT / 'tmp/willow-leaf-export'
TEMP.mkdir(parents=True, exist_ok=True)
(TEMP / '.gdignore').touch()
bpy.ops.wm.open_mainfile(filepath=str(ROOT / 'art/blender/diverse_trees.blend'), use_scripts=False)
bpy.context.preferences.filepaths.save_version = 0
collection = bpy.data.collections['weeping_willow']
construction = next(c for c in collection.children if 'editable branch paths' in c.name)
paths = {}
for obj in construction.objects:
    number = int(obj.name.split('_')[1].split('.')[0])
    paths[number] = [sum((v.co for v in obj.data.vertices[i:i+12]), Vector()) / 12
                     for i in range(0, len(obj.data.vertices), 12)]

rng = random.Random(260914)
shoots = []
leaves = []

def sample(path, t):
    index = t * (len(path)-1)
    i = min(int(index), len(path)-2)
    return path[i].lerp(path[i+1], index-i)

def shoot(root, angle, reach, drop, lift):
    """A short arch blends into a hanging tip, rooted on an authored bough."""
    radial = Vector((math.cos(angle), math.sin(angle), 0))
    sideways = Vector((-radial.y, radial.x, 0))
    bend = rng.uniform(-.13, .13)
    points = [root + radial * reach * math.sin(t*math.pi*.5)
              + sideways*bend*math.sin(math.pi*t)
              + Vector((0, 0, lift*math.sin(math.pi*t)-drop*t*t))
              for t in [i/10 for i in range(11)]]
    shoots.append(points)
    arc = sum((b-a).length for a,b in zip(points,points[1:]))
    count = max(8, int(arc/rng.uniform(.052,.072)))
    phase = rng.random()*math.tau
    for k in range(count):
        t = .10 + .86*(k+rng.uniform(.05,.85))/count
        point = sample(points,t)
        leaf_angle = angle + phase + k*2.39996 + rng.uniform(-.25,.25)
        direction = Vector((math.cos(leaf_angle),math.sin(leaf_angle),rng.uniform(-1.35,.18))).normalized()
        length = rng.uniform(.15,.235)*(1-.20*t)
        width = length*rng.uniform(.24,.34)
        side = direction.cross(Vector((0,0,1))).normalized()
        normal = side.cross(direction).normalized()
        roll = rng.uniform(-.8,.8)
        side = side*math.cos(roll)+normal*math.sin(roll)
        normal = side.cross(direction).normalized()
        tint = rng.uniform(.83,1.13)
        # Close to mawais green, with slightly lighter olive new growth.
        color = Vector((.059,.1424,.0105))*tint
        color = color.lerp(Vector((.095,.195,.021)),t*.22)
        leaves.append((point,direction,side,normal,length,width,color,rng.random()))

for j in range(8):
    a = j*2.39996+.3
    for number in (8+5*j,9+5*j,11+5*j):
        path = paths[number]
        for k in range(7):
            t = .55+.45*(k+.4)/7
            root = sample(path,t)
            shoot(root,a+rng.uniform(-1.9,1.9),rng.uniform(.34,.78),rng.uniform(.24,.72),rng.uniform(.10,.26))
    for number in (10+5*j,12+5*j):
        path = paths[number]
        for k in range(7):
            root = sample(path,.32+.22*(k+.3)/7)
            drop = min(root.z-1.22,rng.uniform(1.05,2.25))
            shoot(root,a+rng.uniform(-1.8,1.8),rng.uniform(.17,.61),drop,rng.uniform(.04,.16))

# The leader gets attached side sprays instead of a floating spherical leaf tuft.
for k in range(28):
    root = sample(paths[0],.66+.33*(k+.3)/28)
    shoot(root,k*2.39996,rng.uniform(.30,.67),rng.uniform(.22,.65),.06)

material = bpy.data.materials.new('Willow / folded individual leaves')
material.use_nodes = True
material.use_backface_culling = False
bsdf = material.node_tree.nodes.get('Principled BSDF')
bsdf.inputs['Roughness'].default_value = .9
bsdf.inputs['Specular IOR Level'].default_value = .15
attr = material.node_tree.nodes.new('ShaderNodeVertexColor')
attr.layer_name = 'Paint'
material.node_tree.links.new(attr.outputs['Color'],bsdf.inputs['Base Color'])

reports = []
for lod,retention in enumerate((1,.70,.40)):
    parent = bpy.data.objects['weeping_willow_LOD%d'%lod]
    wood = next(o for o in parent.children if o.name.startswith('Trunk'))
    for obj in list(parent.children):
        if obj.name.startswith('Leaves'): bpy.data.objects.remove(obj,do_unlink=True)
    verts,faces,colors = [],[],[]
    def vertex(p,c):
        verts.append(p);colors.append((*c,1))
    for path in shoots:
        # Short connected tubes make individual sprays legible in close views.
        rings = path if lod==0 else path[::2]
        base = len(verts)
        for i,p in enumerate(rings):
            tangent = (rings[min(i+1,len(rings)-1)]-rings[max(0,i-1)]).normalized()
            side = tangent.cross(Vector((0,1,0))).normalized()
            normal = tangent.cross(side)
            radius = .008*(1-i/(len(rings)-1))+.0015
            for k in range(3):
                angle = k*math.tau/3
                vertex(p+(side*math.cos(angle)+normal*math.sin(angle))*radius,Vector((.075,.085,.022)))
                if i:
                    a=base+(i-1)*3+k;b=base+(i-1)*3+(k+1)%3
                    c=base+i*3+(k+1)%3;d=base+i*3+k
                    faces.extend([(a,b,c),(a,c,d)])
    kept = 0
    for point,direction,side,normal,length,width,color,rank in leaves:
        if rank >= retention: continue
        kept += 1
        width *= (1,1.12,1.30)[lod]
        length *= (1,1.04,1.08)[lod]
        base=len(verts)
        # Six triangles define a curved lance-shaped blade and raised midrib.
        vertex(point+direction*length*.46+normal*width*.12,color*1.05)
        outline=[(0,0),(-.40,.25),(-.5,.51),(0,1),(.5,.51),(.40,.25)]
        for x,y in outline:
            vertex(point+direction*length*y+side*width*x-normal*length*.10*y*y,
                   color*(.96 if x<0 else 1.02))
        for k in range(6):faces.append((base,base+1+k,base+1+(k+1)%6))
    mesh=bpy.data.meshes.new('Willow pendant foliage LOD%d'%lod)
    mesh.from_pydata(verts,[],faces);mesh.update()
    paint=mesh.color_attributes.new(name='Paint',type='FLOAT_COLOR',domain='POINT')
    paint.data.foreach_set('color',[x for c in colors for x in c])
    mesh.materials.append(material)
    # Flat facets retain local leaf lighting, as in mawais' modeled leaves.
    foliage=bpy.data.objects.new('Leaves_LOD%d'%lod,mesh)
    collection.objects.link(foliage);foliage.parent=parent
    saved_position=parent.location.copy();parent.location=Vector()
    wood.hide_set(False);wood.hide_render=False
    bpy.ops.object.select_all(action='DESELECT')
    for obj in (parent,wood,foliage):obj.select_set(True)
    bpy.context.view_layer.objects.active=wood
    name='weeping_willow_lod%d.glb'%lod
    bpy.ops.export_scene.gltf(filepath=str(TEMP/name),export_format='GLB',use_selection=True,
                             export_yup=True,export_animations=False,export_vertex_color='ACTIVE')
    share_bark_images(TEMP/name,OUT/name)
    parent.location=saved_position
    for obj in (wood,foliage):obj.hide_render=lod>0;obj.hide_set(lod>0)
    reports.append(dict(level=lod,leaves=kept,shoots=len(shoots),
                        triangles=len(faces)+sum(len(p.vertices)-2 for p in wood.data.polygons)))

# Save the editable gallery too, so subsequent leaf edits start from this result.
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/blender/diverse_trees.blend'))
report=json.loads((OUT/'model_report.json').read_text())
for entry in report:
    if entry['id']=='weeping_willow':
        entry['lods']=reports
        entry['foliage']='Attached pendant shoots with small folded lanceolate leaves; mawais-inspired green and local leaf lighting.'
(OUT/'model_report.json').write_text(json.dumps(report,indent=2)+'\n')
print('WILLOW_REFINED',json.dumps(reports),flush=True)
