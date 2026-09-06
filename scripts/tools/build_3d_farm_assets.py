"""Build editable, original farm models with Blender, then export glTF assets.

Run: blender --background --python scripts/tools/build_3d_farm_assets.py
Optional: -- --render (writes a Blender overview to docs/validation/images).
Coordinates below use Blender Z-up; world placements use Godot X/Z via place().
"""
from pathlib import Path
import bpy
import math
import random
import sys
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/models/farm3d"
SOURCE = ROOT / "art/blender"
OUT.mkdir(parents=True, exist_ok=True)
SOURCE.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for collection in list(bpy.data.collections):
    if collection.name != "Collection":
        bpy.data.collections.remove(collection)
random.seed(9253)
bpy.context.scene.render.engine = "CYCLES"
bpy.context.scene.cycles.samples = 32
bpy.context.scene.render.resolution_x = 1500
bpy.context.scene.render.resolution_y = 1000
bpy.context.scene.render.resolution_percentage = 100
bpy.context.scene.render.image_settings.file_format = "PNG"
bpy.context.scene.view_settings.view_transform = "AgX"
bpy.context.scene.render.film_transparent = False
bpy.context.scene.render.fps = 30
bpy.context.scene.world.color = (0.35, 0.45, 0.55)
bpy.context.preferences.filepaths.save_version = 0


def material(name, color, roughness=0.83):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


M = {
    "shirt": material("Linen • warm ivory", (.79, .73, .53)),
    "denim": material("Overalls • indigo", (.055, .20, .31)),
    "seam": material("Denim • light stitching", (.27, .43, .46)),
    "skin": material("Skin • peach", (.68, .39, .23)),
    "cheek": material("Cheeks • terracotta", (.74, .29, .19)),
    "hair": material("Hair • chestnut", (.105, .053, .026)),
    "boot": material("Boots • worn leather", (.18, .088, .040)),
    "sole": material("Boot soles", (.061, .049, .033)),
    "hat": material("Straw • honey", (.67, .45, .17)),
    "straw": material("Straw • sunlit weave", (.83, .64, .29)),
    "eye": material("Eyes • dark umber", (.024, .030, .025), .32),
    "white": material("Eyes • ivory", (.95, .88, .70), .45),
    "bark": material("Oak bark", (.24, .135, .063)),
    "bark_light": material("Oak bark • highlights", (.33, .20, .095)),
    "soil": material("Fresh earth", (.25, .14, .071)),
    "soil_light": material("Furrows • umber", (.34, .20, .10)),
    "soil_dark": material("Furrows • shadow", (.17, .095, .048)),
    "grass": material("Meadow • sage", (.29, .43, .17)),
    "grass_light": material("Meadow • sunlit tips", (.43, .54, .22)),
    "grass_dark": material("Meadow • shade", (.18, .33, .12)),
    "path": material("Footpath • ochre", (.55, .42, .25)),
    "rock": material("River stone", (.37, .42, .35)),
    "wood": material("Fence • weathered cedar", (.44, .29, .14)),
    "stem": material("Wheat • golden stems", (.48, .40, .12)),
    "grain": material("Wheat • ripe grain", (.85, .57, .16)),
    "grain_light": material("Wheat • pale awns", (.97, .77, .32)),
    "leaf": material("Wheat • young leaves", (.26, .46, .11)),
    "flower": material("Wildflower • cream", (.98, .84, .48)),
}
LEAVES = [material("Oak foliage %02d" % i, col) for i, col in enumerate([
    (.15, .28, .075), (.22, .36, .10), (.29, .42, .13),
    (.35, .46, .15), (.42, .51, .19), (.47, .54, .23)])]


def collection(name):
    result = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(result)
    return result


ACTIVE = collection("01 • Farmer")
RIG_PARTS = {}


def finish(obj, name, mat, bone=None, smooth=False):
    obj.name = name
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    ACTIVE.objects.link(obj)
    if mat:
        obj.data.materials.append(mat)
    if smooth:
        for face in obj.data.polygons:
            face.use_smooth = True
    if bone:
        RIG_PARTS[obj.name] = bone
    return obj


def ellipsoid(name, loc, scale, mat, bone=None, subdivisions=2, smooth=True):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1, location=loc)
    obj = bpy.context.object
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, name, mat, bone, smooth)


def cube(name, loc, scale, mat, bevel=0.035, bone=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.object
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = obj.modifiers.new("Soft handmade edges", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        bpy.ops.object.modifier_apply(modifier=mod.name)
        normal = obj.modifiers.new("Weighted corner normals", "WEIGHTED_NORMAL")
        bpy.ops.object.modifier_apply(modifier=normal.name)
    return finish(obj, name, mat, bone)


def taper(name, start, end, radius1, radius2, mat, bone=None, vertices=9):
    a, b = Vector(start), Vector(end)
    delta = b - a
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius1, radius2=radius2,
                                  depth=delta.length, location=(a + b) * .5)
    obj = bpy.context.object
    obj.rotation_euler = delta.to_track_quat("Z", "Y").to_euler()
    return finish(obj, name, mat, bone)


def torus(name, loc, major, minor, mat, bone=None):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor,
                                   major_segments=40, minor_segments=6, location=loc)
    return finish(bpy.context.object, name, mat, bone, True)


def join_objects(objects, name):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = name
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    return obj


def export(col, filename):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in col.objects:
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = next(iter(col.objects))
    bpy.ops.export_scene.gltf(filepath=str(OUT / (filename + ".glb")),
        export_format="GLB", use_selection=True, export_yup=True,
        export_animations=True, export_animation_mode="ACTIONS",
        export_materials="EXPORT", export_cameras=False, export_lights=False)
    print("EXPORTED", filename, flush=True)


# Farmer: deliberately readable from both the face and follow camera.
for side, suffix in [(-1, "L"), (1, "R")]:
    x = side * .145
    cube("Leather sole " + suffix, (x, -.035, .065), (.245, .40, .10), M["sole"], .035, "shin." + suffix)
    cube("Round work boot " + suffix, (x, -.053, .17), (.235, .35, .18), M["boot"], .06, "shin." + suffix)
    taper("Boot collar " + suffix, (x, .025, .17), (x, .025, .33), .104, .092, M["boot"], "shin." + suffix)
    taper("Trouser shin " + suffix, (x, .02, .28), (x, 0, .55), .091, .112, M["denim"], "shin." + suffix)
    taper("Trouser thigh " + suffix, (x, 0, .52), (x, 0, .85), .115, .14, M["denim"], "thigh." + suffix)
    ellipsoid("Trouser knee " + suffix, (x, 0, .53), (.114, .114, .095), M["denim"], "shin." + suffix)
    cube("Trouser cuff " + suffix, (x, -.003, .30), (.21, .205, .065), M["seam"], .022, "shin." + suffix)
    for j in range(3):
        cube("Boot lace", (x, -.168 + j * .035, .25 + j * .006), (.105, .018, .015), M["hat"], .006, "shin." + suffix)
ellipsoid("Overalls seat", (0, .0, .82), (.27, .19, .18), M["denim"], "pelvis")
ellipsoid("Linen shirt", (0, 0, 1.13), (.325, .21, .335), M["shirt"], "spine")
cube("Overall bib", (0, -.188, 1.03), (.405, .055, .34), M["denim"], .055, "spine")
cube("Bib pocket seam", (0, -.224, 1.032), (.225, .021, .15), M["seam"], .022, "spine")
cube("Bib pocket", (0, -.24, 1.044), (.195, .013, .137), M["denim"], .021, "spine")
for side in [-1, 1]:
    suffix = "L" if side < 0 else "R"
    cube("Front strap " + suffix, (side * .17, -.177, 1.26), (.065, .052, .25), M["denim"], .018, "spine")
    strap = cube("Back strap " + suffix, (side * .115, .189, 1.19), (.065, .037, .39), M["denim"], .015, "spine")
    strap.rotation_euler.y = side * -.35
    ellipsoid("Brass overall button", (side * .17, -.21, 1.18), (.027, .013, .027), M["straw"], "spine", 2)
    taper("Shirt sleeve " + suffix, (side * .285, 0, 1.30), (side * .40, -.018, 1.035), .128, .091, M["shirt"], "upper_arm." + suffix, 12)
    ellipsoid("Rounded shoulder " + suffix, (side * .285, 0, 1.295), (.128, .125, .115), M["shirt"], "upper_arm." + suffix)
    taper("Rolled sleeve " + suffix, (side * .395, -.018, 1.065), (side * .414, -.024, 1.0), .105, .105, M["white"], "upper_arm." + suffix, 12)
    taper("Forearm " + suffix, (side * .413, -.022, 1.005), (side * .432, -.064, .83), .077, .063, M["skin"], "forearm." + suffix, 12)
    ellipsoid("Hand " + suffix, (side * .434, -.068, .78), (.076, .069, .098), M["skin"], "forearm." + suffix)
    ellipsoid("Thumb " + suffix, (side * .384, -.104, .81), (.038, .043, .062), M["skin"], "forearm." + suffix)
taper("Neck", (0, 0, 1.33), (0, 0, 1.47), .098, .105, M["skin"], "head", 16)
ellipsoid("Head", (0, -.007, 1.62), (.228, .199, .255), M["skin"], "head", 3)
ellipsoid("Hair cap", (0, .052, 1.735), (.234, .171, .171), M["hair"], "head", 2)
for side in [-1, 1]:
    ellipsoid("Ear", (side * .224, .0, 1.62), (.052, .052, .071), M["skin"], "head")
    ellipsoid("Eye white", (side * .084, -.187, 1.66), (.055, .022, .047), M["white"], "head")
    ellipsoid("Eye pupil", (side * .082, -.206, 1.66), (.027, .012, .033), M["eye"], "head")
    ellipsoid("Eye glint", (side * .082 - .008, -.215, 1.671), (.009, .006, .011), M["white"], "head")
    eyebrow = cube("Eyebrow", (side * .085, -.186, 1.721), (.104, .024, .026), M["hair"], .011, "head")
    eyebrow.rotation_euler.y = side * -.10
    ellipsoid("Warm cheek", (side * .131, -.16, 1.566), (.047, .014, .024), M["cheek"], "head")
    ellipsoid("Sideburn", (side * .197, -.045, 1.705), (.034, .074, .077), M["hair"], "head")
ellipsoid("Button nose", (0, -.208, 1.61), (.048, .048, .047), M["skin"], "head")
smile_points = [(-.04, -.204, 1.543), (-.017, -.209, 1.530), (.017, -.209, 1.530), (.04, -.204, 1.543)]
for i in range(3):
    taper("Small smile", smile_points[i], smile_points[i + 1], .006, .006, M["hair"], "head", 8)
# Squashed dome brim, crown, leather band and woven circular accents.
ellipsoid("Broad straw brim", (0, .02, 1.86), (.46, .407, .047), M["hat"], "head", 3)
taper("Straw hat crown", (0, .02, 1.86), (0, .02, 2.048), .274, .221, M["hat"], "head", 32)
ellipsoid("Soft hat top", (0, .02, 2.045), (.224, .224, .034), M["straw"], "head", 2)
taper("Hat leather ribbon", (0, .02, 1.888), (0, .02, 1.931), .270, .258, M["boot"], "head", 32)
for radius in [.29, .335, .38, .423]:
    ring = torus("Woven brim ring", (0, .02, 1.875), radius, .0055, M["straw"], "head")
    ring.scale.y = .88
for i in range(5):
    torus("Woven crown ring", (0, .02, 1.946 + i * .021), .253 - i * .007, .004, M["straw"], "head")

# Real skeleton and weighted meshes; individual garment parts are rigidly weighted.
farmer = ACTIVE
arm_data = bpy.data.armatures.new("Farmer skeleton")
rig = bpy.data.objects.new("FarmerRig", arm_data)
farmer.objects.link(rig)
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
bones = {
    "root": ((0, 0, 0), (0, 0, .25), None),
    "pelvis": ((0, 0, .79), (0, 0, .95), "root"),
    "spine": ((0, 0, .95), (0, 0, 1.37), "pelvis"),
    "head": ((0, 0, 1.37), (0, 0, 1.87), "spine"),
}
for side, suffix in [(-1, "L"), (1, "R")]:
    x = side * .145
    bones["thigh." + suffix] = ((x, 0, .81), (x, 0, .53), "pelvis")
    bones["shin." + suffix] = ((x, 0, .53), (x, 0, .10), "thigh." + suffix)
    bones["upper_arm." + suffix] = ((side * .28, 0, 1.31), (side * .412, -.022, 1.01), "spine")
    bones["forearm." + suffix] = ((side * .412, -.022, 1.01), (side * .434, -.065, .77), "upper_arm." + suffix)
for name, (head, tail, parent) in bones.items():
    bone = arm_data.edit_bones.new(name)
    bone.head, bone.tail = head, tail
    if parent:
        bone.parent = arm_data.edit_bones[parent]
bpy.ops.object.mode_set(mode="OBJECT")
meshes = [o for o in farmer.objects if o.type == "MESH"]
for obj in meshes:
    group = obj.vertex_groups.new(name=RIG_PARTS[obj.name])
    group.add(list(range(len(obj.data.vertices))), 1, "REPLACE")
body = join_objects(meshes, "Farmer • skinned mesh")
body.parent = rig
modifier = body.modifiers.new("Farmer skeleton", "ARMATURE")
modifier.object = rig
rig.animation_data_create()
for action_name, duration in [("Idle", 60), ("Walk", 30)]:
    action = bpy.data.actions.new(action_name)
    action.use_fake_user = True
    rig.animation_data.action = action
    for frame in range(1, duration + 2, 3):
        phase = (frame - 1) / duration * math.tau
        for bone in rig.pose.bones:
            bone.rotation_mode = "XYZ"
            bone.rotation_euler = (0, 0, 0)
            bone.location = (0, 0, 0)
        if action_name == "Walk":
            for sign, suffix in [(1, "L"), (-1, "R")]:
                swing = math.sin(phase) * sign
                rig.pose.bones["thigh." + suffix].rotation_euler.x = .53 * swing
                rig.pose.bones["shin." + suffix].rotation_euler.x = -.52 * max(0, -swing)
                rig.pose.bones["upper_arm." + suffix].rotation_euler.x = -.39 * swing
                rig.pose.bones["forearm." + suffix].rotation_euler.x = -.10 - .12 * max(0, swing)
            rig.pose.bones["pelvis"].location.y = .016 * (1 - math.cos(phase * 2))
            rig.pose.bones["spine"].rotation_euler.z = .035 * math.sin(phase)
        else:
            rig.pose.bones["spine"].rotation_euler.x = .012 * math.sin(phase)
            rig.pose.bones["head"].rotation_euler.z = .023 * math.sin(phase)
        for bone in rig.pose.bones:
            bone.keyframe_insert("rotation_euler", frame=frame, group=bone.name)
            bone.keyframe_insert("location", frame=frame, group=bone.name)
bpy.context.scene.frame_set(1)
export(farmer, "player_farmer")

# Oak with buttress roots, tapering bent branches and irregular crown clusters.
ACTIVE = collection("02 • Oak tree")
oak = ACTIVE
for i in range(7):
    angle = i * math.tau / 7
    taper("Buttress root", (.03, 0, .25), (math.cos(angle) * .85, math.sin(angle) * .85, .045),
          .18, .035, M["bark"], vertices=7)
trunk = [(0, 0, 0), (.06, -.04, .8), (-.02, .05, 1.65), (.10, .04, 2.5), (.22, .01, 3.5)]
for i in range(4):
    taper("Main oak trunk", trunk[i], trunk[i + 1], .37 - i * .066, .30 - i * .065, M["bark"], vertices=10)
    if i:
        radius = .305 - (i - 1) * .065
        ellipsoid("Trunk joint", trunk[i], (radius, radius, radius * .75), M["bark"], subdivisions=1, smooth=False)
for i in range(7):
    a = i * 2.399
    start = (.04, 0, 1.55 + (i % 3) * .36)
    mid = (math.cos(a) * .8, math.sin(a) * .8, 2.4 + (i % 3) * .30)
    end = (math.cos(a) * 1.53, math.sin(a) * 1.53, 3.12 + (i % 3) * .27)
    taper("Crown branch", start, mid, .17, .10, M["bark"])
    taper("Crown twig", mid, end, .10, .026, M["bark_light"])
for i in range(28):
    a = i * 2.399
    radius = 1.55 * math.sqrt((i % 10 + 1) / 10)
    z = 3.25 + (1 - radius / 2) * .80 + random.uniform(-.32, .32)
    if i > 21:
        radius *= .52
        z += .65
    obj = ellipsoid("Leaf crown %02d" % i,
        (math.cos(a) * radius, math.sin(a) * radius, z),
        (random.uniform(.65, 1.03), random.uniform(.62, .93), random.uniform(.56, .85)),
        None, subdivisions=2, smooth=False)
    for mat in LEAVES:
        obj.data.materials.append(mat)
    for face in obj.data.polygons:
        face.material_index = max(0, min(5, int(2.8 + face.normal.z * 1.5 + random.uniform(-.8, .8))))
join_objects(list(oak.objects), "Oak • branches and canopy")
export(oak, "tree_oak")

# A reusable 2.8 m square plot with actual raised earth and alternating grooves.
ACTIVE = collection("03 • Tilled earth")
field = ACTIVE
cube("Earth bed", (0, 0, -.005), (2.8, 2.8, .13), M["soil"], .10)
for row in range(7):
    y = -.99 + row * .33
    obj = ellipsoid("Raised furrow", (0, y, .054), (1.31, .115, .088), M["soil_light"], subdivisions=2, smooth=False)
    for j in range(6):
        x = -1.1 + j * .43 + random.uniform(-.1, .1)
        ellipsoid("Soil clod", (x, y + random.uniform(-.06, .06), .117), (.055, .042, .026), M["soil"], subdivisions=1)
join_objects(list(field.objects), "Farmland • sculpted furrows")
export(field, "farmland_tile")


def blade(name, base, angle, length, width, mat, droop=.16):
    # A bowed, ridged leaf: two faces per segment, readable from both sides.
    origin = Vector(base)
    direction = Vector((math.cos(angle), math.sin(angle), 0))
    sideways = Vector((-math.sin(angle), math.cos(angle), 0))
    vertices, faces = [], []
    for k in range(5):
        t = k / 4
        center = origin + direction * length * t
        center.z += length * .48 * math.sin(t * math.pi * .8) - droop * t * t
        w = math.sin(math.pi * t) * width
        vertices.extend([center - sideways * w, center + Vector((0, 0, w * .3)), center + sideways * w])
        if k:
            j = k * 3
            faces.extend([(j - 3, j, j + 1, j - 2), (j - 2, j + 1, j + 2, j - 1)])
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    ACTIVE.objects.link(obj)
    mesh.materials.append(mat)
    # Thin solidify keeps foliage visible from every angle without double-sided exports.
    bpy.context.view_layer.objects.active = obj
    solid = obj.modifiers.new("Leaf thickness", "SOLIDIFY")
    solid.thickness = .003
    bpy.ops.object.modifier_apply(modifier=solid.name)
    return obj


def grain_cluster(mature):
    for i in range(6):
        a = i * 2.399
        x, y = math.cos(a) * .15, math.sin(a) * .15
        h = random.uniform(.76, .97) if mature else random.uniform(.26, .43)
        lean = Vector((math.cos(a) * .075, math.sin(a) * .075, 0))
        base = Vector((x, y, 0))
        top = base + lean + Vector((0, 0, h))
        taper("Cereal stem", base, top, .012 if mature else .009, .007, M["stem"] if mature else M["leaf"], vertices=6)
        for j in range(3):
            point = base + lean * (j * .18 + .15) + Vector((0, 0, h * (.18 + j * .19)))
            blade("Cereal leaf", point, a + j * 2.4, .27 if mature else .21, .029 if mature else .036,
                  M["stem"] if mature else M["leaf"], .14 if mature else .035)
        if not mature:
            continue
        taper("Ear spine", top, top + Vector((0, 0, .26)), .012, .005, M["grain"], vertices=6)
        for tier in range(6):
            for sign in [-1, 1]:
                axis = Vector((math.cos(a), math.sin(a), 0)) * sign
                center = top + axis * (.027 + (5 - tier) * .002) + Vector((0, 0, .025 + tier * .039))
                grain = ellipsoid("Wheat kernel", center, (.027, .022, .053), M["grain_light"] if tier % 3 == 0 else M["grain"], subdivisions=1)
                grain.rotation_euler = (sign * .25 * math.sin(a), sign * .25 * math.cos(a), a)
                end = center + axis * .037 + Vector((0, 0, .15))
                taper("Wheat awn", center, end, .0027, .0005, M["grain_light"], vertices=4)


ACTIVE = collection("04 • Young grain")
young = ACTIVE
grain_cluster(False)
join_objects(list(young.objects), "Young grain • six shoots")
export(young, "grain_young")
ACTIVE = collection("05 • Ripe grain")
ripe = ACTIVE
grain_cluster(True)
join_objects(list(ripe.objects), "Ripe grain • six ears")
export(ripe, "grain_mature")

# Composed environment uses linked copies, still editable in the .blend source.
ACTIVE = collection("06 • Farm environment")
environment = ACTIVE


def place(col, x, z, y=0, scale=1, angle=0):
    for source in col.objects:
        if source.type != "MESH":
            continue
        obj = source.copy()
        obj.data = source.data
        ACTIVE.objects.link(obj)
        obj.location = (x, -z, y)
        obj.scale = (scale, scale, scale)
        obj.rotation_euler.z = angle
    return obj


cube("Meadow foundation", (0, 0, -.38), (44, 44, .75), M["grass"], .28)
cube("Earth beneath meadow", (0, 0, -.88), (43.95, 43.95, .45), M["soil"], .24)
# A gently curving, irregular path down the western edge of the vegetable garden.
verts, faces = [], []
for i in range(35):
    z = -19 + i * 1.15
    x = -2.8 + math.sin(z * .14) * 1.3
    width = 1.05 + random.uniform(-.13, .13)
    verts.extend([(x - width, -z, .009), (x + width, -z, .009)])
    if i:
        faces.append((i * 2 - 2, i * 2, i * 2 + 1, i * 2 - 1))
mesh = bpy.data.meshes.new("Winding path")
mesh.from_pydata(verts, [], faces)
obj = bpy.data.objects.new("Winding ochre path", mesh)
environment.objects.link(obj)
obj.data.materials.append(M["path"])

TREE_POSITIONS = [(-8, -5), (-10, 2), (12, -9), (10, 5), (-5, -12), (5, -14)]
TREE_SCALES = [.92, .74, 1.05, .86, .76, .94]
for x, z in TREE_POSITIONS:
    for j in range(5):
        a = j * 1.25
        ellipsoid("Mossy root stone", (x + math.cos(a) * .8, -z + math.sin(a) * .8, .07),
                  (.19, .15, .11), M["rock"], subdivisions=1, smooth=False)

# Fence deliberately leaves the front open for walking into the farm.
for x in [0.7, 3, 5.3, 7.6, 9.9]:
    cube("Fence post", (x, 9.66, .52), (.14, .15, 1.04), M["wood"], .025)
    taper("Fence post cap", (x, 9.66, 1.04), (x, 9.66, 1.12), .105, .02, M["wood"], vertices=4)
for x in [1.85, 4.15, 6.45, 8.75]:
    for height in [.40, .81]:
        rail = cube("Fence rail", (x, 9.66, height), (2.38, .08, .105), M["wood"], .015)
        rail.rotation_euler.y = random.uniform(-.025, .025)

# Meadow blades and flowers are authored at runtime by PaintedMeadow.  This
# leaves every grid cell initially available for the real farming simulation;
# it also lets a tilled or planted cell immediately reveal its soil/crop model.
for i in range(25):
    z = random.uniform(-15, 12)
    x = -2.8 + math.sin(z * .14) * 1.3 + random.choice([-1, 1]) * random.uniform(1.1, 1.5)
    ellipsoid("Path pebble", (x, -z, .035), (.06, .085, .04), M["rock"], subdivisions=1, smooth=False)
# A pair of small rocks and a stump give foreground scale without new gameplay.
for x, z, scale in [(-6, 6, .7), (11, 1, .5), (-11, -8, .9)]:
    ellipsoid("Field boulder", (x, -z, scale * .35), (scale, scale * .8, scale * .6), M["rock"], subdivisions=2, smooth=False)

# Keep the source composition editable; export a merged copy for fewer draw calls.
export_collection = collection("07 • Optimized export")
copies = []
for source in environment.objects:
    obj = source.copy()
    obj.data = source.data.copy()
    export_collection.objects.link(obj)
    copies.append(obj)
combined = join_objects(copies, "Farm environment • static mesh")
export(export_collection, "farm_environment")
export_collection.hide_render = True
export_collection.hide_viewport = True

# Godot instances painted_oak.tscn separately, including its matching collisions.
# Mirror those placements in the editable Blender composition after terrain export.
painted_source = SOURCE / "painted_oak.blend"
if not painted_source.exists():
    raise FileNotFoundError("Run build_painted_oak.py before building the farm composition")
with bpy.data.libraries.load(str(painted_source), link=False) as (available, imported):
    imported.collections = ["Oak • sculpt and painted leaves"]
painted_oak = imported.collections[0]
ACTIVE = collection("09 • Painted oaks")
for i, (x, z) in enumerate(TREE_POSITIONS):
    place(painted_oak, x, z, scale=TREE_SCALES[i], angle=i * 1.9)

# Source opens as a composed scene, original assets remain in labeled collections.
for col in [oak, field, young, ripe]:
    col.hide_render = True
    col.hide_viewport = True
rig.location = (-2, -4, 0)
rig.rotation_euler.z = -.35
rig.animation_data.action = bpy.data.actions.get("Idle")
bpy.context.scene.frame_set(1)

ACTIVE = collection("08 • Studio")
bpy.ops.object.light_add(type="AREA", location=(-7, -10, 16))
key = bpy.context.object
key.name = "Large warm sky light"
key.data.energy = 2300
key.data.shape = "DISK"
key.data.size = 12
key.rotation_euler = (Vector((0, 0, 0)) - key.location).to_track_quat("-Z", "Y").to_euler()
bpy.ops.object.light_add(type="SUN", location=(-10, -10, 12))
sun = bpy.context.object
sun.name = "Late afternoon sunlight"
sun.data.energy = 2.1
sun.data.angle = .12
sun.rotation_euler = (math.radians(27), math.radians(-23), math.radians(-32))
world = bpy.context.scene.world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (.48, .65, .80, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = .45
bpy.ops.object.camera_add(location=(17, -23, 17))
camera = bpy.context.object
camera.name = "Farm overview"
camera.rotation_euler = (Vector((0, 2, .8)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.type = "PERSP"
camera.data.lens = 44
bpy.context.scene.camera = camera
for area in bpy.context.screen.areas:
    if area.type == "VIEW_3D":
        area.spaces.active.region_3d.view_perspective = "CAMERA"
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "farm3d.blend"))
if "--render" in sys.argv:
    target = ROOT / "docs/validation/images/farm_3d_blender_overview.png"
    target.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.scene.render.filepath = str(target)
    bpy.ops.render.render(write_still=True)
    camera.location = (0, -8.4, 2.8)
    camera.rotation_euler = (Vector((-2, -4, 1.06)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.lens = 60
    bpy.context.scene.render.resolution_x = 1000
    bpy.context.scene.render.resolution_y = 1100
    bpy.context.scene.render.filepath = str(target.with_name("farm_3d_blender_player.png"))
    bpy.ops.render.render(write_still=True)
print("FARM_ASSETS_READY", flush=True)
