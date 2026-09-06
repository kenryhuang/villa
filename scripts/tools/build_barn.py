"""Editable painted timber barn. Run with Blender --background --python this_file.

Exports only art/blender/barn.blend and assets/models/buildings/barn/.
Blender Z is up; the door faces -Y (Godot +Z). Existing 2 x 2 m footprint.
"""
from pathlib import Path
import math
import random
import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/models/buildings/barn"
OUT.mkdir(parents=True, exist_ok=True)
PAINT = ROOT / "tmp/barn_paint"
PAINT.mkdir(parents=True, exist_ok=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
random.seed(260906)


def painted_material(kind, base):
    """Small repeating paint studies, used as surface texture on real geometry."""
    n = 512
    y, x = np.mgrid[0:n, 0:n].astype(float) / n
    rng = np.random.default_rng(72)
    brush = np.zeros((n, n))
    for frequency, amplitude in [(3, .06), (11, .045), (27, .025)]:
        brush += amplitude * np.sin(x * math.tau * frequency + np.sin(y * math.tau * 2)) * np.cos(y * math.tau * frequency)
    if kind == "timber":
        bend = x + .016 * np.sin(y * math.tau * 2) + .009 * np.sin(y * math.tau * 5)
        grain = np.sin(bend * math.tau * 43 + .5 * np.sin(y * math.tau))
        brush += .10 * grain + .035 * np.sin(bend * math.tau * 97)
        brush -= .12 * np.maximum(0, np.cos(bend * math.tau * 19)) ** 20
    elif kind == "slate":
        moss = np.sin(x * math.tau * 5 + np.cos(y * math.tau * 7)) * np.cos(y * math.tau * 9)
        brush += .10 * np.sin(y * math.tau * 31 + x * 8)
    else:
        brush += .045 * np.sin(x * 118 + y * 149)
    values = np.clip(np.array(base)[None, None, :] * (1 + brush[:, :, None]) + rng.normal(0, .012, (n, n, 1)), 0, 1)
    if kind == "slate":
        mask = np.clip((moss - .45) * 1.8, 0, .65)[:, :, None]
        values = values * (1-mask) + np.array((.34, .37, .14)) * mask
    image = bpy.data.images.new("Barn " + kind + " paint", n, n)
    rgba = np.concatenate([values, np.ones((n, n, 1))], axis=2).astype(np.float32)
    image.pixels.foreach_set(rgba.ravel())
    # glTF embeds these temporary paint studies. Godot extracts the canonical
    # barn_*_paint.png assets, avoiding a second copy beside the model.
    image.filepath_raw = str(PAINT / (kind + "_paint.png"))
    image.file_format = "PNG"
    image.save()
    mat = bpy.data.materials.new("Painted " + kind)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = .88
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


WOOD = painted_material("timber", (.66, .45, .23))
ROOF = painted_material("slate", (.35, .40, .34))
STONE = painted_material("stone", (.46, .45, .35))


def plain(name, rgb, metal=0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*rgb, 1)
    shader.inputs["Roughness"].default_value = .72
    shader.inputs["Metallic"].default_value = metal
    return mat


IRON = plain("Forged iron", (.065, .072, .065), .5)
DARK = plain("Deep joint shadow", (.045, .026, .014))
WALL = WOOD.copy()
WALL.name = "Weathered red cedar"
nodes = WALL.node_tree.nodes
mix = nodes.new("ShaderNodeMixRGB")
mix.blend_type = "MULTIPLY"
mix.inputs[0].default_value = 1
mix.inputs[2].default_value = (.76, .52, .37, 1)
# glTF supports a constant base factor, keep it in the exported material too.
WALL.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = (.76, .52, .37, 1)
# glTF's image factor is set explicitly after export (below) for identical rendering.

groups = {}
for name in ["Foundation", "Frame", "Walls", "Roof", "Details"]:
    group = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(group)
    groups[name] = group


def finish(obj, name, material, stage, bevel=0):
    obj.name = name
    obj.parent = groups[stage]
    obj.data.materials.append(material)
    if obj.type == "MESH" and obj.data.polygons:
        # Map grain along each board's longest dimension, including braces.
        for existing in list(obj.data.uv_layers):
            obj.data.uv_layers.remove(existing)
        uv = obj.data.uv_layers.new(name="PaintUV")
        dims = obj.dimensions
        for poly in obj.data.polygons:
            normal_axis = max(range(3), key=lambda a: abs(poly.normal[a]))
            axes = [a for a in range(3) if a != normal_axis]
            axes.sort(key=lambda a: dims[a])
            offset = random.random()
            for loop in poly.loop_indices:
                p = obj.data.vertices[obj.data.loops[loop].vertex_index].co
                uv.data[loop].uv = (p[axes[0]] / max(dims[axes[0]], .001) + offset, p[axes[1]] / max(dims[axes[1]], .001))
    if bevel:
        mod = obj.modifiers.new("Soft worn edges", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
        normal = obj.modifiers.new("Weighted corner light", "WEIGHTED_NORMAL")
        bpy.ops.object.modifier_apply(modifier=normal.name)
    return obj


def box(name, center, size, material=WOOD, stage="Frame", bevel=.012):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    obj = bpy.context.object
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, name, material, stage, bevel)


def beam(name, a, b, width=.10, depth=None, stage="Frame", material=WOOD):
    a, b = Vector(a), Vector(b)
    obj = box(name, (a+b)/2, (width, depth or width, (b-a).length), material, stage)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(b-a)
    return obj


# Deep footings overlap the earth slightly; no baked grass pad or floating sprite.
box("Mortar plinth", (0, 0, .01), (1.91, 1.91, .48), STONE, "Foundation", .025)
for row in range(2):
    for side in range(4):
        for col in range(6):
            t = -.79 + col * .31 + (row % 2) * .055
            t = min(t, .82)
            position = (t, -.925, .02 + row*.14) if side == 0 else (t, .925, .02+row*.14) if side == 1 else (-.925, t, .02+row*.14) if side == 2 else (.925, t, .02+row*.14)
            size = (.29, .115, .13) if side < 2 else (.115, .29, .13)
            stone = box("Individual foundation stone", position, size, STONE, "Foundation", .026)
            stone.rotation_euler.z = random.uniform(-.025, .025)
box("Door threshold", (0,-.94,.075), (.93,.15,.15), STONE, "Foundation", .02)

# Timber skeleton, side studs and complete gable trusses.
for y in [-.88, .88]:
    for x in [-.87, .87]:
        beam("Corner post", (x,y,.19),(x,y,2.05), .14)
    beam("Gable crossbeam",(-.89,y,2.02),(.89,y,2.02),.14)
    beam("Left gable rafter",(-1.04,y,1.99),(0,y,3.02),.13)
    beam("Right gable rafter",(0,y,3.02),(1.04,y,1.99),.13)
    beam("Gable king post",(0,y,2.03),(0,y,3.0),.105)
for x in [-.87,.87]:
    beam("Side wall plate",(x,-.90,2.02),(x,.90,2.02),.14)
    beam("Lower sill",(x,-.90,.25),(x,.90,.25),.12)
    for y in [-.35,.35]:
        beam("Side stud",(x,y,.25),(x,y,2),.085)
    for y, direction in [(-.78,1),(.78,-1)]:
        beam("Side diagonal brace",(x,y,.35),(x,y+direction*.65,1.05),.085)
beam("Ridge timber",(0,-1.08,3.07),(0,1.08,3.07),.14)

# Separate narrow cedar boards; all four sides have real thickness.
for x in [-.865,.865]:
    for i in range(15):
        box("Side cedar board",(x,-.80+i*.114,1.13),(.065,.108,1.74),WALL,"Walls",.006)
for y in [-.865,.865]:
    for i in range(15):
        x = -.80+i*.114
        if y > 0 or abs(x) > .48:
            box("End cedar board",(x,y,1.13),(.108,.065,1.74),WALL,"Walls",.006)
        roof_height = 3.0-abs(x)
        height = max(.04,roof_height-2.08)
        box("Gable cedar board",(x,y,2.06+height/2),(.108,.065,height),WALL,"Walls",.005)

# Closed double doors, timber Z braces, forged straps and ring handles.
box("Door recess",(0,-.909,1.05),(1.0,.025,1.8),DARK,"Walls",.004)
for side in [-1,1]:
    for i in range(4):
        x = side*(.06+i*.115)
        box("Door plank",(x,-.93,1.05),(.11,.06,1.72),WOOD,"Details",.008)
    for z in [.34,1.63]:
        box("Door cross rail",(side*.24,-.978,z),(.43,.048,.075),WOOD,"Details",.01)
    beam("Door diagonal",(side*.06,-.98,.38),(side*.43,-.98,1.59),.072,.045,"Details")
    for z in [.36,1.65]:
        box("Iron hinge strap",(side*.37,-1.011,z),(.23,.024,.042),IRON,"Details",.01)
        for offset in [-.07,.07]:
            bpy.ops.mesh.primitive_uv_sphere_add(segments=8,ring_count=4,radius=.012,location=(side*.37+offset,-1.028,z))
            finish(bpy.context.object,"Hinge rivet",IRON,"Details")
    box("Handle plate",(side*.07,-.989,.94),(.06,.024,.11),IRON,"Details",.012)
    bpy.ops.mesh.primitive_torus_add(major_segments=16,minor_segments=6,location=(side*.07,-1.017,.91),major_radius=.035,minor_radius=.007,rotation=(math.pi/2,0,0))
    finish(bpy.context.object,"Iron door ring",IRON,"Details")
for x in [-.51,.51]:
    box("Door jamb",(x,-.966,1.07),(.085,.105,1.86),WOOD,"Frame")
box("Door lintel",(0,-.961,1.98),(1.14,.115,.13),WOOD,"Frame")

# Loft hatch and slatted side vents distinguish front, sides and rear.
for y in [-.92,.92]:
    box("Loft hatch shadow",(0,y,2.43),(.42,.045,.44),DARK,"Details",.008)
    for i in range(4):
        box("Loft shutter board",(-.147+i*.098,y*1.02,2.43),(.09,.045,.38),WOOD,"Details",.006)
    for z in [2.20,2.66]:
        box("Loft hatch trim",(0,y*1.04,z),(.53,.065,.065),WOOD,"Details")
    for x in [-.245,.245]:
        box("Loft hatch trim",(x,y*1.04,2.43),(.055,.065,.47),WOOD,"Details")
for side in [-1,1]:
    box("Side vent recess",(side*.909,.15,1.43),(.026,.51,.46),DARK,"Details")
    for i in range(5):
        box("Side vent louver",(side*.935,.15,1.25+i*.086),(.056,.49,.044),WOOD,"Details",.006)
    for y in [-.13,.43]:
        box("Vent frame",(side*.941,y,1.43),(.066,.055,.56),WOOD,"Details")

# Hundreds of overlapping, softly bevelled slate shingles. Moss is painted
# into their surface texture; thickness and uneven eaves remain visible in orbit.
for side in [-1,1]:
    slope = math.atan2(1.03,1.10)
    length = math.hypot(1.10,1.03)
    under = box("Roof underboarding",(side*.55,0,2.46),(length,2.13,.06),DARK,"Roof",.006)
    under.rotation_euler.y = side*slope
    for row in range(8):
        t = .96-row*.125
        for col in range(12):
            y = -1.015+col*.183 + (.042 if row%2 else 0)
            y = min(y,1.055)
            obj = box("Mossy slate shingle",(side*1.10*t,y,3.045-1.03*t+.012*row/8),(.265,.178,.037),ROOF,"Roof",.009)
            obj.rotation_euler.y = side*slope+random.uniform(-.015,.015)
            obj.rotation_euler.z = random.uniform(-.018,.018)
for y in [-1.09,1.10]:
    for side in [-1,1]:
        beam("Carved bargeboard",(side*1.14,y,1.98),(0,y,3.09),.11,.075,"Roof")
for side in [-1,1]:
    beam("Eaves fascia",(side*1.105,-1.1,2.01),(side*1.105,1.1,2.01),.08,.085,"Roof")

# Consolidate by construction group and material, retaining editable stages
# while reducing the hundreds of authored pieces to a few game draw calls.
for stage, parent in groups.items():
    pieces = list(parent.children)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in pieces:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = pieces[0]
    bpy.ops.object.join()
    mesh_obj = bpy.context.object
    mesh_obj.name = stage+"Mesh"
    mesh_obj.parent = parent

bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=str(OUT/"barn.glb"),export_format="GLB",use_selection=True,export_yup=True,export_animations=False)
# Blender glTF ignores a BSDF constant when an image is linked. Apply the cedar
# multiplier to the standard glTF material so both Godot and Blender share it.
import json, struct
path = OUT/"barn.glb"
blob = path.read_bytes()
json_len, json_type = struct.unpack_from("<II",blob,12)
document = json.loads(blob[20:20+json_len])
for mat in document.get("materials",[]):
    if mat.get("name") == WALL.name:
        mat["pbrMetallicRoughness"]["baseColorFactor"] = [.76,.52,.37,1]
encoded = json.dumps(document,separators=(",",":")).encode()
encoded += b" "*((-len(encoded))%4)
tail = blob[20+json_len:]
path.write_bytes(struct.pack("<III",0x46546C67,2,20+len(encoded)+len(tail))+struct.pack("<II",len(encoded),json_type)+encoded+tail)
# Match the same multiply in the editable Blender material after glTF export.
tex = next(n for n in nodes if n.type == "TEX_IMAGE")
WALL.node_tree.links.new(tex.outputs["Color"],mix.inputs[1])
WALL.node_tree.links.new(mix.outputs[0],nodes.get("Principled BSDF").inputs["Base Color"])

scene = bpy.context.scene
scene.world.color = (.35,.40,.45)
scene.render.engine = "CYCLES"
scene.cycles.samples = 32
bpy.ops.object.camera_add(location=(4,-6,3.6))
camera = bpy.context.object
camera.rotation_euler = (Vector((0,0,1.4))-camera.location).to_track_quat("-Z","Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = 4.6
scene.camera = camera
bpy.ops.object.light_add(type="AREA",location=(-3,-4,6))
bpy.context.object.data.energy = 450
bpy.context.object.data.shape = "DISK"
bpy.context.object.data.size = 5
for image in bpy.data.images:
    if image.filepath:
        image.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/blender/barn.blend"))
print("BARN EXPORT COMPLETE:",path)
