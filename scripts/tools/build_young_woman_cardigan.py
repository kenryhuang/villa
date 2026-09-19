"""Build an original young-adult woman inspired by the supplied outfit reference.

The character reuses the project's licensed Sintel-derived continuous face,
55-bone game rig and facial expression topology.  The outfit, silhouette, hair,
materials and accessories are authored here.  The supplied picture is embedded
as a hidden Blender reference only; it is not used as a face texture.

Run from the repository root:
  blender --background --disable-autoexec --python-exit-code 1 \
    --python scripts/tools/build_young_woman_cardigan.py
"""
from pathlib import Path
import json
import math
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_village_characters as village
import build_player_concept as player_concept


ROOT = Path(__file__).resolve().parents[2]
SOURCE_BLEND = ROOT / "art/blender/characters/resident_yun.blend"
REFERENCE_IMAGE = Path(r"D:\downloads\26717816-4977-4abd-98ea-d237b32085d0.png")
BLEND_OUT = ROOT / "art/blender/characters/young_woman_cardigan.blend"
GLB_OUT = ROOT / "assets/models/characters/young_woman_cardigan.glb"
PREVIEW_OUT = ROOT / "art/concepts/young_woman_cardigan-preview.png"
SKIN_MATERIAL = None


def select(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def retile(obj, material, tile):
    """Keep source weights and topology while moving UVs into our atlas tile."""
    obj.data.materials.clear()
    obj.data.materials.append(material)
    layer = obj.data.uv_layers.active or obj.data.uv_layers.new(name="UVMap")
    for item in layer.data:
        u, v = item.uv
        item.uv = ((tile % 4 + .025 + (u % 1.0) * .95) / 4,
                   (tile // 4 + .025 + (v % 1.0) * .95) / 4)
    for polygon in obj.data.polygons:
        polygon.material_index = 0
        polygon.use_smooth = True


def assign_plain_skin(obj):
    obj.data.materials.clear()
    obj.data.materials.append(SKIN_MATERIAL)
    for polygon in obj.data.polygons:
        polygon.material_index = 0
        polygon.use_smooth = True


def make_skin_material():
    material = bpy.data.materials.new("Young woman | warm painted skin")
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (.74, .46, .37, 1)
    shader.inputs["Roughness"].default_value = .72
    return material


def torso_weights(obj):
    obj.vertex_groups.clear()
    for vert in obj.data.vertices:
        z = vert.co.z
        chest = max(0.0, min(1.0, (z - 1.08) / .18))
        pelvis = 1.0 - max(0.0, min(1.0, (z - 1.015) / .10))
        values = {
            "pelvis": (1.0 - chest) * pelvis,
            "spine": (1.0 - chest) * (1.0 - pelvis),
            "chest": chest,
        }
        total = sum(values.values()) or 1.0
        for bone, value in values.items():
            if value > 0:
                (obj.vertex_groups.get(bone) or obj.vertex_groups.new(name=bone)).add(
                    [vert.index], value / total, "REPLACE"
                )


def make_atlas():
    # Tile 0 cardigan, 1 skirt, 2 top, 5 hair, 7 buttons, 13 skin,
    # 14 sneaker upper and 15 sneaker sole.
    village.COLORS = [
        "a9bddb", "f2e9de", "f8f4ee", "c3d1e5",
        "8d6c58", "49342f", "fffaf1", "e6d6c7",
        "d9c2a9", "aa8a78", "c98f82", "8b6a5e",
        "d6b19d", "e0a48c", "f5f3ed", "b7b8ba",
    ]
    material = village.atlas()
    material.name = "Young woman | cardigan skirt hair skin and sneakers"
    texture = next(node for node in material.node_tree.nodes if node.type == "TEX_IMAGE")
    texture.image.name = "young_woman_cardigan_atlas"
    texture.image.pack()
    return material


def make_tank_top():
    # A fitted front shell floats just above the blue cardigan body.
    tank = village.loft(
        "Ivory ribbed camisole",
        [(1.018, .141, .164, -.005), (1.15, .139, .163, .003),
         (1.265, .137, .156, .006), (1.325, .102, .116, .010)],
        2, arc=(-2.48, -.66), fold=.006,
    )
    torso_weights(tank)
    # Fine raised ribs catch light without requiring a large normal texture.
    for x in np.linspace(-.082, .082, 13):
        height = 1.315 - .018 * (abs(x) / .082) ** 1.7
        rib = village.tube(
            "Camisole knit rib",
            [(float(x), -.150, 1.055), (float(x), -.158, 1.18),
             (float(x), -.143, height)],
            .00115, 6, "chest",
        )
        torso_weights(rib)
    for sign in (-1, 1):
        strap = village.ribbon(
            "Camisole shoulder strap",
            [(sign * .079, -.129, 1.306), (sign * .093, -.083, 1.362),
             (sign * .098, -.018, 1.386)],
            .015, 2, "chest",
        )
        torso_weights(strap)
    village.tube(
        "Scalloped camisole neckline",
        [(.094 * math.cos(a), -.126 - .014 * math.sin(a),
          1.313 + .018 * math.sin(a)) for a in np.linspace(math.pi, math.tau, 41)],
        .0021, 6, "chest",
    )


def make_cardigan_details():
    # The continuous blue shirt provides the back and sleeves.  These soft
    # front edges make it read as an open cardigan around the ivory camisole.
    for sign, side in ((-1, "R"), (1, "L")):
        edge = village.ribbon(
            "Cardigan open edge " + side,
            [(sign * .091, -.145, 1.325), (sign * .083, -.161, 1.245),
             (sign * .068, -.167, 1.145), (sign * .060, -.164, 1.035)],
            .024, 3, "chest",
        )
        torso_weights(edge)
    for z in (1.235, 1.165, 1.095):
        village.sphere(
            "Pearl cardigan button", (.073, -.177, z), (.0062, .0032, .0062),
            7, "chest",
        )
    # Knitted sleeve ridges are deliberately restrained at gameplay distance.
    for sign, side in ((-1, "R"), (1, "L")):
        for x in (.275, .305, .335, .365, .393):
            village.tube(
                "Cardigan sleeve knit " + side,
                [(sign * x, .043 + .059 * math.cos(a),
                  1.329 + .059 * math.sin(a)) for a in np.linspace(0, math.tau, 25)],
                .00125, 3, "forearm." + side,
            )


def make_skirt():
    segments = 96
    rows = [
        (1.028, .151, .151, .004),
        (.987, .175, .166, .009),
        (.850, .235, .205, .021),
        (.675, .303, .249, .032),
    ]
    vertices, faces, uvs = [], [], []
    pleats = 24
    for row_index, (z, rx, ry, depth) in enumerate(rows):
        for index in range(segments + 1):
            angle = index / segments * math.tau
            # Crisp accordion folds softened toward the waistband.
            wave = math.sin(angle * pleats)
            radius = 1.0 + depth * wave / max(rx, ry)
            vertices.append((rx * radius * math.cos(angle),
                             -.005 + ry * radius * math.sin(angle), z))
            uvs.append((index / segments, row_index / (len(rows) - 1)))
    for row_index in range(len(rows) - 1):
        for index in range(segments):
            base = row_index * (segments + 1) + index
            faces.append((base, base + 1, base + segments + 2, base + segments + 1))
    skirt = village.mesh("Ivory pleated knee skirt", vertices, faces, 1, "pelvis", uvs)
    select(skirt)
    solid = skirt.modifiers.new("Double-sided woven skirt", "SOLIDIFY")
    solid.thickness = .0035
    solid.offset = 0
    bpy.ops.object.modifier_apply(modifier=solid.name)
    bevel = skirt.modifiers.new("Soft pleat highlights", "BEVEL")
    bevel.width = .0015
    bevel.segments = 2
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    village.loft(
        "Skirt fitted waistband",
        [(1.008, .153, .154, -.005), (1.040, .151, .151, -.005)],
        1, "pelvis",
    )


def make_anatomical_legs():
    """Continuous bare legs aligned with Yun's hip/knee/ankle rest joints.

    Yun's skin stops inside her boots. Complete that covered area with an
    asymmetric calf, narrow Achilles/ankle and a subtly projecting kneecap.
    Each row is z, lateral center, depth center, half width, half depth.
    """
    profile = np.array([
        (.100, .0815, .0089, .028, .033),
        (.145, .0815, .0060, .027, .030),
        (.190, .0830, .0050, .028, .033),
        (.250, .0860, .0080, .034, .043),
        (.320, .0880, .0060, .044, .055),
        (.370, .0870, .0000, .049, .058),
        (.415, .0850, -.010, .047, .055),
        (.465, .0830, -.025, .040, .047),
        (.5211,.0831, -.042, .041, .049),
        (.560, .0820, -.039, .045, .056),
        (.625, .0800, -.037, .052, .063),
        (.700, .0770, -.032, .060, .069),
        (.800, .0740, -.022, .069, .077),
        (.930, .0690, -.010, .077, .085),
        (1.005,.0660, -.005, .080, .088),
    ])
    levels, values = profile[:, 0], profile[:, 1:]
    slopes = np.diff(values, axis=0) / np.diff(levels)[:, None]
    tangents = np.zeros_like(values)
    tangents[0], tangents[-1] = slopes[0], slopes[-1]
    for i in range(1, len(values)-1):
        for column in range(4):
            a, b = slopes[i-1, column], slopes[i, column]
            if a*b > 0:
                tangents[i, column] = 2*a*b/(a+b)

    def sample(z):
        i = min(len(levels)-2, max(0, int(np.searchsorted(levels, z)-1)))
        h = levels[i+1]-levels[i]
        t = (z-levels[i])/h
        return ((2*t**3-3*t*t+1)*values[i] + (t**3-2*t*t+t)*h*tangents[i]
                + (-2*t**3+3*t*t)*values[i+1] + (t**3-t*t)*h*tangents[i+1])

    for sign, side in ((1, 'L'), (-1, 'R')):
        vertices, faces, uvs = [], [], []
        sides, rings = 48, 100
        for row, z in enumerate(np.linspace(levels[0], levels[-1], rings+1)):
            cx, cy, rx, ry = sample(z)
            calf = math.exp(-((z-.36)/.09)**2)
            ankle = math.exp(-((z-.155)/.022)**2)
            knee = math.exp(-((z-.5211)/.027)**2)
            for j in range(sides):
                a = j/sides*math.tau
                # Fuller medial calf, narrow front shin and soft ankle bones.
                lateral = math.cos(a)
                x = cx + rx*lateral*(1-.075*calf*lateral)
                y = cy + ry*math.sin(a)
                y -= .005*knee*max(0, -math.sin(a))**8
                x += .0025*ankle*lateral**5
                vertices.append((sign*x, y, float(z)))
                uvs.append((j/sides, row/rings))
        for row in range(rings):
            for j in range(sides):
                a = row*sides+j
                b = row*sides+(j+1)%sides
                faces.append((a, b, b+sides, a+sides))
        leg = village.mesh('Anatomical bare leg '+side, vertices, faces, 13, 'shin.'+side, uvs)
        assign_plain_skin(leg)
        leg.vertex_groups.clear()
        def smoothstep(lo, hi, x):
            t = max(0, min(1, (x-lo)/(hi-lo)))
            return t*t*(3-2*t)
        for v in leg.data.vertices:
            z = v.co.z
            thigh = smoothstep(.475, .568, z)
            pelvis = smoothstep(.85, .995, z)
            foot = 1-smoothstep(.100, .170, z)
            for bone, weight in [('foot.'+side, foot),
                                 ('shin.'+side, (1-foot)*(1-thigh)),
                                 ('thigh.'+side, thigh*(1-pelvis)), ('pelvis', pelvis)]:
                if weight > 0:
                    (leg.vertex_groups.get(bone) or leg.vertex_groups.new(name=bone)).add([v.index],weight,'REPLACE')


def make_legs_and_sneakers():
    # The village generator's fitted lower-body shells become clean bare legs
    # through the skin atlas tile.  Add ankles and low-profile court sneakers.
    old_boots = next((obj for obj in list(village.PARTS) if obj.name.endswith("boots")), None)
    if old_boots is not None:
        village.PARTS.remove(old_boots)
        bpy.data.objects.remove(old_boots, do_unlink=True)
    for sign, side in ((1, "L"), (-1, "R")):
        village.box(
            "Sneaker sole " + side,
            (sign * .083, -.052, .021), (.069, .137, .022), 15, "foot." + side,
        )
        # One tapered ellipsoid gives the upper a court-shoe silhouette without
        # the bulbous double toe produced by overlapping primitives.
        village.sphere(
            "White sneaker upper " + side,
            (sign * .083, -.052, .068), (.061, .126, .037), 14, "foot." + side,
        )
        tongue = village.box(
            "Padded sneaker tongue " + side,
            (sign * .083, -.071, .104), (.036, .067, .010), 14, "foot." + side,
        )
        tongue.rotation_euler.x = math.radians(-8)
        village.tube(
            "Sneaker collar " + side,
            [(sign * .083 + .041 * math.cos(a), .020 + .035 * math.sin(a), .108)
             for a in np.linspace(0, math.tau, 33)],
            .005, 15, "foot." + side,
        )
        for lace_y in (-.145, -.120, -.095, -.070):
            village.tube(
                "White shoe lace " + side,
                [(sign * .083 - .034, lace_y, .112),
                 (sign * .083 + .034, lace_y, .112)],
                .0016, 15, "foot." + side,
            )


def hair_lock(name, points, width, depth):
    points = village.path(points, 7)
    vertices, faces = [], []
    sides = 12
    for index, point in enumerate(points):
        t = index / (len(points) - 1)
        taper = max(.03, math.sin(math.pi * (.08 + .90 * t))) ** .62
        tangent = (points[min(index + 1, len(points) - 1)] -
                   points[max(0, index - 1)]).normalized()
        reference = Vector((0, 1, 0)) if abs(tangent.y) < .92 else Vector((1, 0, 0))
        across = tangent.cross(reference).normalized()
        normal = tangent.cross(across).normalized()
        for side in range(sides):
            angle = side / sides * math.tau
            vertices.append(point + taper * (
                across * width * math.cos(angle) + normal * depth * math.sin(angle)
            ))
    for index in range(len(points) - 1):
        for side in range(sides):
            a = index * sides + side
            b = index * sides + (side + 1) % sides
            faces.append((a, b, b + sides, a + sides))
    return village.mesh(name, vertices, faces, 5, "head")


def make_hair():
    rings, segments = 16, 64
    vertices, faces = [], []
    for ring in range(rings + 1):
        polar = .02 + ring / rings * 2.05
        for segment in range(segments + 1):
            angle = segment / segments * math.tau
            vertices.append((.108 * math.sin(polar) * math.sin(angle),
                             .014 - .112 * math.sin(polar) * math.cos(angle),
                             1.574 + .098 * math.cos(polar)))
    for ring in range(rings):
        for segment in range(segments):
            base = ring * (segments + 1) + segment
            faces.append((base, base + 1, base + segments + 2, base + segments + 1))
    village.mesh("Smooth chestnut hair cap", vertices, faces, 5, "head")

    # Braided crown suggested by the photo.
    for side in (-1, 1):
        points = []
        for index in range(8):
            angle = -.55 + index * .16
            points.append((side * (.035 + index * .008),
                           -.081 + .010 * math.sin(index * math.pi),
                           1.654 - .011 * index))
        hair_lock("Braided crown", points, .012, .008)

    # High ponytail and layered ends, all head-weighted for robust animation.
    village.sphere("High ponytail tie", (0, .105, 1.664), (.044, .035, .038), 5, "head")
    village.tube(
        "Powder blue hair ribbon",
        [(0, .139, 1.676), (.038, .155, 1.646), (0, .143, 1.622),
         (-.038, .155, 1.646), (0, .139, 1.676)],
        .006, 3, "head",
    )
    for index, x in enumerate((-.050, -.025, 0, .025, .050)):
        hair_lock(
            "Layered high ponytail",
            [(x * .35, .105, 1.665), (x, .170 + .008 * abs(index - 2), 1.58),
             (x * .8 + .012 * math.sin(index), .178, 1.455),
             (x * .55 - .012 * math.cos(index), .145, 1.335 + .015 * abs(index - 2))],
            .026, .018,
        )
    for side in (-1, 1):
        for index in range(3):
            hair_lock(
                "Loose face-framing strand",
                [(side * (.035 + index * .017), -.092, 1.646 - index * .006),
                 (side * (.068 + index * .012), -.112, 1.570 - index * .022),
                 (side * (.075 + index * .008), -.095, 1.455 - index * .028)],
                .010 - index * .0015, .005,
            )


def apply_soft_young_woman_morph(point):
    result = village.morph(point, "farmer_ahe")
    # Preserve the game's stylized face while softening jaw breadth slightly.
    if result.z > 1.50:
        blend = max(0.0, min(1.0, (result.z - 1.50) / .18))
        result.x *= 1.0 - .025 * (1.0 - blend)
    return result


def add_reference_to_blend():
    if not REFERENCE_IMAGE.exists():
        return
    reference_collection = bpy.data.collections.new("REFERENCE | supplied outfit photo")
    bpy.context.scene.collection.children.link(reference_collection)
    image = bpy.data.images.load(str(REFERENCE_IMAGE), check_existing=False)
    image.name = "REFERENCE | blue cardigan and pleated skirt"
    image.pack()
    bpy.ops.object.empty_add(type="IMAGE", location=(-1.35, .45, 1.05))
    reference = bpy.context.object
    for collection in list(reference.users_collection):
        collection.objects.unlink(reference)
    reference_collection.objects.link(reference)
    reference.name = "REFERENCE | young woman outfit front"
    reference.data = image
    reference.empty_display_size = 1.4
    reference.rotation_euler = (math.pi / 2, 0, 0)
    reference.hide_render = True
    reference.hide_viewport = True
    reference["usage"] = "Outfit, palette and hairstyle reference only; not a face texture"


def add_studio():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 768
    scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    background.inputs[0].default_value = (.62, .65, .68, 1)
    background.inputs[1].default_value = .55

    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.006))
    floor = bpy.context.object
    floor.name = "STUDIO | warm floor"
    floor_material = bpy.data.materials.new("Studio warm neutral")
    floor_material.diffuse_color = (.55, .52, .48, 1)
    floor.data.materials.append(floor_material)

    for location, energy, size, color in [
        ((-3.2, -4.2, 5.2), 720, 4.5, (1.0, .82, .68)),
        ((3.0, -1.0, 3.2), 360, 3.0, (.72, .83, 1.0)),
        ((0, 3.0, 4.0), 520, 3.5, (1.0, .92, .82)),
    ]:
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = "STUDIO | soft area"
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        light.data.color = color
        light.rotation_euler = (Vector((0, 0, 1.0)) - light.location).to_track_quat("-Z", "Y").to_euler()

    bpy.ops.object.camera_add(location=(1.72, -6.2, 2.18))
    camera = bpy.context.object
    camera.name = "STUDIO | portrait camera"
    target = Vector((0, 0, .92))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 1.95
    scene.camera = camera


def build():
    global SKIN_MATERIAL
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE_BLEND), use_scripts=False)
    bpy.context.preferences.filepaths.save_version = 0
    rig = bpy.data.objects["YunRig"]
    rig.data.pose_position = "REST"
    # Shared skin-transfer helpers resolve the production rig by this name.
    rig.name = "CharacterRig"
    rig.data.name = "YoungWomanSkeleton"

    keep = {
        "body", "body_mouth", "eyeballs", "gloves",
        "emit_brows", "emit_lash_btm", "emit_lash_top",
    }
    village.PARTS = []
    for obj in list(bpy.data.objects):
        short_name = obj.name.removeprefix("Yun ")
        if obj.type == "MESH" and short_name in keep:
            obj.name = "Young woman " + short_name
            village.PARTS.append(obj)
        elif obj != rig:
            bpy.data.objects.remove(obj, do_unlink=True)

    body = bpy.data.objects["Young woman body"]
    for key in body.data.shape_keys.key_blocks:
        key.value = 0
    body.data.shape_keys.key_blocks["Smile.L"].value = .08
    body.data.shape_keys.key_blocks["Smile.R"].value = .08

    village.BVH, village.VERTS, village.TRIS, village.WEIGHTS = village.build_weight_source(body)
    village.MAT = make_atlas()
    SKIN_MATERIAL = make_skin_material()
    hands = bpy.data.objects["Young woman gloves"]
    assign_plain_skin(hands)

    # Player garment has a true neckline and continuous shoulder topology; in
    # blue it becomes the cardigan body beneath our open-front tailoring.
    player_concept.shirt(body, "young_woman_cardigan")
    inherited_trim = (
        "Soft open collar", "Soft collar back", "Shirt placket",
        "Ivory shirt button", "Rolled linen cuff",
    )
    for obj in list(village.PARTS):
        if obj.name.startswith(inherited_trim):
            village.PARTS.remove(obj)
            bpy.data.objects.remove(obj, do_unlink=True)
    make_tank_top()
    make_cardigan_details()

    make_anatomical_legs()

    make_skirt()
    make_legs_and_sneakers()
    make_hair()

    # Hide source skin under garments while preserving face, neck and hands.
    mesh_data = bmesh.new()
    mesh_data.from_mesh(body.data)
    hidden_faces = []
    for face in mesh_data.faces:
        center = face.calc_center_median()
        if center.z < 1.035 or (
            center.z < 1.391
            and (center.z < 1.35 or abs(center.x) > .052)
            and abs(center.x) < .397
        ):
            hidden_faces.append(face)
    bmesh.ops.delete(mesh_data, geom=hidden_faces, context="FACES")
    mesh_data.to_mesh(body.data)
    mesh_data.free()

    # Apply the same proportion transform to basis, expressions, clothing and rig.
    for obj in village.PARTS:
        if obj.data.shape_keys:
            for key in obj.data.shape_keys.key_blocks:
                for vertex in key.data:
                    vertex.co = apply_soft_young_woman_morph(vertex.co)
            for vertex, basis in zip(obj.data.vertices, obj.data.shape_keys.key_blocks[0].data):
                vertex.co = basis.co
        else:
            for vertex in obj.data.vertices:
                vertex.co = apply_soft_young_woman_morph(vertex.co)
        obj.data.update()

    select(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    for bone in rig.data.edit_bones:
        bone.head = apply_soft_young_woman_morph(bone.head)
        bone.tail = apply_soft_young_woman_morph(bone.tail)
    bpy.ops.object.mode_set(mode="OBJECT")
    rig.data.pose_position = "POSE"

    for obj in village.PARTS:
        obj.parent = rig
        if not any(mod.type == "ARMATURE" for mod in obj.modifiers):
            obj.modifiers.new("Game skin", "ARMATURE").object = rig

    extras = [obj for obj in village.PARTS if not obj.data.shape_keys]
    select(extras[0])
    for obj in extras:
        obj.select_set(True)
    bpy.ops.object.join()
    joined = bpy.context.object
    joined.name = "Young woman clothing hair eyes and accessories"
    # Upper and lower bare-leg rings are authored to identical coordinates.
    # Weld them after the material-preserving join to remove the knee normal seam.
    joined_mesh = bmesh.new()
    joined_mesh.from_mesh(joined.data)
    bmesh.ops.remove_doubles(joined_mesh, verts=list(joined_mesh.verts), dist=.00002)
    bmesh.ops.recalc_face_normals(joined_mesh, faces=list(joined_mesh.faces))
    joined_mesh.to_mesh(joined.data)
    joined_mesh.free()
    village.PARTS = [body, joined]

    village.animate(rig)
    rig["character_id"] = "young_woman_cardigan"
    rig["display_name"] = "Young woman in blue cardigan"
    rig["age_design"] = "young adult"
    rig["reference_usage"] = "outfit, palette and hairstyle only"
    rig["style_reference"] = "villa resident_yun game topology"
    rig["license"] = "CC BY 3.0 / BenDansie Sintel Lite derivative"

    # Export only the gameplay character, before adding reference and studio objects.
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    body.select_set(True)
    joined.select_set(True)
    bpy.context.view_layer.objects.active = rig
    GLB_OUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_OUT), export_format="GLB", use_selection=True,
        export_yup=True, export_animations=True, export_animation_mode="ACTIONS",
        export_materials="EXPORT", export_cameras=False, export_lights=False,
        export_extras=True,
    )

    add_reference_to_blend()
    add_studio()
    BLEND_OUT.parent.mkdir(parents=True, exist_ok=True)
    PREVIEW_OUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_OUT))
    bpy.context.scene.render.filepath = str(PREVIEW_OUT)
    bpy.ops.render.render(write_still=True)

    triangles = 0
    for obj in village.PARTS:
        obj.data.calc_loop_triangles()
        triangles += len(obj.data.loop_triangles)
    report = {
        "id": "young_woman_cardigan",
        "blend": str(BLEND_OUT),
        "glb": str(GLB_OUT),
        "preview": str(PREVIEW_OUT),
        "triangles": triangles,
        "bones": len(rig.data.bones),
        "mesh_nodes": len(village.PARTS),
        "clips": ["Idle", "Walk", "Run", "Work"],
        "reference_embedded": REFERENCE_IMAGE.exists(),
    }
    print("YOUNG WOMAN CHARACTER COMPLETE", json.dumps(report), flush=True)
    return report


if __name__ == "__main__":
    build()
