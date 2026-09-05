"""Create a continuous sculpted oak with real, painted leaf geometry.

blender --background --python scripts/tools/build_painted_oak.py -- --render
The existing oak illustration is sampled as paint, never displayed as a billboard.
Only this tree's generated files are overwritten; the farm prototype is independent.
"""
from pathlib import Path
import math
import random
import sys
import bpy
import numpy as np
from mathutils import Vector, noise

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/models/vegetation"
SOURCE = ROOT / "art/blender"
IMAGES = ROOT / "docs/validation/images"
for directory in [OUT, SOURCE, IMAGES]:
    directory.mkdir(parents=True, exist_ok=True)
RNG = random.Random(90612)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.save_version = 0
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 48
scene.render.resolution_x = 1400
scene.render.resolution_y = 1400
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.view_settings.view_transform = "AgX"

tree_collection = bpy.data.collections.new("Oak • sculpt and painted leaves")
scene.collection.children.link(tree_collection)
studio = bpy.data.collections.new("Studio • not exported")
scene.collection.children.link(studio)
paint = bpy.data.images.load(str(ROOT / "assets/vegetation/tree-oak-large.png"), check_existing=True)
paint.name = "Original oak • hand-painted reference"
paint.pack()
pixels = np.empty(len(paint.pixels), dtype=np.float32)
paint.pixels.foreach_get(pixels)
pixels = pixels.reshape((paint.size[1], paint.size[0], 4))


def sample(u, v):
    return pixels[min(paint.size[1] - 1, max(0, int(v * paint.size[1]))),
                  min(paint.size[0] - 1, max(0, int(u * paint.size[0])))]


def move_to(obj, collection):
    for col in list(obj.users_collection):
        col.objects.unlink(obj)
    collection.objects.link(obj)
    return obj


def mesh_object(name, vertices, faces):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    tree_collection.objects.link(obj)
    return obj


def catmull(points, steps=7):
    result = []
    for i in range(len(points) - 1):
        p0 = np.array(points[max(0, i - 1)], dtype=float)
        p1 = np.array(points[i], dtype=float)
        p2 = np.array(points[i + 1], dtype=float)
        p3 = np.array(points[min(len(points) - 1, i + 2)], dtype=float)
        for j in range(steps):
            t = j / steps
            value = .5 * ((2 * p1) + (-p0 + p2) * t +
                          (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t +
                          (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t)
            value[3] = max(.005, value[3])
            result.append(value)
    result.append(np.array(points[-1], dtype=float))
    return result


def wood_tube(name, points, segments=18):
    points = catmull(points)
    vertices, faces = [], []
    for i, point in enumerate(points):
        center = Vector(point[:3])
        tangent = Vector(points[min(i + 1, len(points) - 1)][:3] - points[max(0, i - 1)][:3]).normalized()
        ref = Vector((0, 1, 0)) if abs(tangent.y) < .88 else Vector((1, 0, 0))
        right = tangent.cross(ref).normalized()
        up = right.cross(tangent).normalized()
        for j in range(segments):
            angle = j * math.tau / segments
            # Long, irregular bark flutes follow the branch rather than straight cylinders.
            radius = point[3] * (1 + .10 * math.sin(angle * 7 + i * .075) + .055 * math.sin(angle * 11 - i * .055))
            vertices.append(center + (right * math.cos(angle) + up * math.sin(angle)) * radius)
            if i:
                k = i * segments + j
                next_j = i * segments + (j + 1) % segments
                faces.append((k - segments, next_j - segments, next_j, k))
    faces.append(tuple(reversed(range(segments))))
    faces.append(tuple((len(points) - 1) * segments + j for j in range(segments)))
    return mesh_object(name, vertices, faces)


# Roots and all principal limbs fuse into one sculpted surface.
wood = []
wood.append(wood_tube("Heartwood", [
    (0, 0, .02, .58), (.06, .02, .48, .51), (-.03, .06, 1.12, .42),
    (-.17, .04, 1.82, .36), (.02, .08, 2.45, .30),
    (-.20, .13, 3.24, .20), (-.05, .19, 4.15, .075), (.16, .23, 4.8, .015)]))
for i in range(7):
    angle = i * math.tau / 7 + RNG.uniform(-.18, .18)
    extent = RNG.uniform(1.15, 1.68)
    bend = angle + RNG.uniform(-.25, .25)
    wood.append(wood_tube("Buttress root %02d" % i, [
        (.07 * math.cos(angle), .07 * math.sin(angle), .66, .30),
        (.43 * math.cos(angle), .43 * math.sin(angle), .25, .27),
        (.86 * math.cos(bend), .86 * math.sin(bend), .12, .15),
        (extent * math.cos(bend), extent * math.sin(bend), .045, .022)], 16))

limbs = [
    [(-.09, .03, 1.35, .29), (-.57, -.04, 1.89, .25), (-1.07, -.08, 2.15, .18), (-1.74, -.23, 2.52, .11), (-2.12, -.27, 3.25, .022)],
    [(-.11, .05, 1.77, .27), (.42, .13, 2.25, .235), (1.02, .12, 2.43, .17), (1.57, .26, 3.13, .09), (1.76, .45, 3.95, .015)],
    [(-.02, .05, 1.95, .245), (.01, .60, 2.53, .19), (-.22, 1.11, 3.13, .125), (-.40, 1.46, 3.91, .032)],
    [(-.12, .02, 2.07, .235), (-.29, -.55, 2.65, .18), (-.63, -1.06, 3.14, .12), (-.93, -1.57, 3.71, .022)],
    [(-.14, .08, 2.70, .19), (-.61, .24, 3.29, .15), (-1.02, .40, 3.91, .09), (-1.17, .51, 4.72, .013)],
    [(-.13, .16, 3.14, .17), (.40, -.13, 3.65, .14), (.77, -.49, 4.2, .08), (.89, -.69, 4.87, .015)],
]
for index, limb in enumerate(limbs):
    wood.append(wood_tube("Sweeping bough %02d" % index, limb))
    for j in range(2, len(limb) - 1):
        start = Vector(limb[j][:3])
        angle = index * 1.9 + j * 2.3
        end = start + Vector((math.cos(angle) * .75, math.sin(angle) * .75, .75))
        middle = start.lerp(end, .5) + Vector((0, 0, -.06))
        wood.append(wood_tube("Fine branch", [(*start, limb[j][3] * .48), (*middle, .04), (*end, .008)], 10))

bpy.ops.object.select_all(action="DESELECT")
for obj in wood:
    obj.select_set(True)
bpy.context.view_layer.objects.active = wood[0]
bpy.ops.object.join()
trunk = bpy.context.object
trunk.name = "Oak • continuous roots trunk and boughs"
remesh = trunk.modifiers.new("Fuse root and branch junctions", "REMESH")
remesh.mode = "VOXEL"
remesh.voxel_size = .035
remesh.use_smooth_shade = True
bpy.ops.object.modifier_apply(modifier=remesh.name)
smooth = trunk.modifiers.new("Soften sculpted junctions", "SMOOTH")
smooth.factor = .7
smooth.iterations = 4
bpy.ops.object.modifier_apply(modifier=smooth.name)
decimate = trunk.modifiers.new("Game mesh", "DECIMATE")
decimate.ratio = .58
bpy.ops.object.modifier_apply(modifier=decimate.name)
trunk.data.validate(clean_customdata=True)
trunk.data.update()
for face in trunk.data.polygons:
    face.use_smooth = True

bark = bpy.data.materials.new("Bark • ochre brushwork and moss")
bark.use_nodes = True
bark.diffuse_color = (.25, .19, .085, 1)
bsdf = bark.node_tree.nodes.get("Principled BSDF")
bsdf.inputs["Roughness"].default_value = .96
attr = bark.node_tree.nodes.new("ShaderNodeVertexColor")
attr.layer_name = "BarkPaint"
bark.node_tree.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
trunk.data.materials.append(bark)
colors = trunk.data.color_attributes.new(name="BarkPaint", type="FLOAT_COLOR", domain="POINT")
for vertex in trunk.data.vertices:
    p = vertex.co
    angle = math.atan2(p.y, p.x)
    brush = float(noise.noise_vector(Vector((p.x * 7, p.y * 7, p.z * 4)))[0])
    grain = math.sin(angle * 15 + p.z * 1.4 + math.sin(p.z * 4) * .35)
    pigment = sample(.493 + .065 * math.sin(angle + p.z * .8), .276 + .055 * math.sin(p.z * .91 + angle * .2))[:3]
    base = np.array([.255, .182, .075])
    color = base * .42 + pigment * .58
    color *= .82 + .16 * grain + .22 * brush
    moss = max(0, 1 - p.z / .9) * max(0, .3 + noise.noise_vector(p * 3)[1]) * .55
    color = color * (1 - moss) + np.array([.15, .22, .065]) * moss
    colors.data[vertex.index].color = (*np.clip(color, .015, .65), 1)

# UV paint patches are selected from foliage in the old illustration.
# Actual leaf outlines are meshes, so they remain three-dimensional from every view.
patches = []
for _ in range(4000):
    u, v = RNG.uniform(.12, .88), RNG.uniform(.39, .91)
    samples = [sample(u + du, v + dv) for du, dv in [(-.018, -.024), (.018, -.024), (-.018, .024), (.018, .024), (0, 0)]]
    if all(c[3] > .99 and c[1] > c[0] * .72 and c[1] > c[2] * 1.5 for c in samples):
        patches.append((u, v))
if len(patches) < 30:
    raise RuntimeError("Not enough valid foliage paint patches in original oak illustration")

leaf_mat = bpy.data.materials.new("Leaves • original watercolor brush texture")
leaf_mat.use_nodes = True
leaf_mat.use_backface_culling = False
leaf_mat.diffuse_color = (.34, .44, .105, 1)
leaf_nodes = leaf_mat.node_tree.nodes
bsdf = leaf_nodes.get("Principled BSDF")
bsdf.inputs["Roughness"].default_value = 1
bsdf.inputs["Specular IOR Level"].default_value = .12
tex = leaf_nodes.new("ShaderNodeTexImage")
tex.image = paint
leaf_tint = leaf_nodes.new("ShaderNodeVertexColor")
leaf_tint.layer_name = "LeafPaint"
paint_mix = leaf_nodes.new("ShaderNodeMixRGB")
paint_mix.blend_type = "MULTIPLY"
paint_mix.inputs[0].default_value = 1
leaf_mat.node_tree.links.new(tex.outputs["Color"], paint_mix.inputs[1])
leaf_mat.node_tree.links.new(leaf_tint.outputs["Color"], paint_mix.inputs[2])
leaf_mat.node_tree.links.new(paint_mix.outputs[0], bsdf.inputs["Base Color"])

vertices, faces, leaf_uvs, leaf_colors = [], [], [], []


def leaf(center, direction, length, width, uv, tint):
    normal = direction.normalized()
    reference = Vector((0, 0, 1)) if abs(normal.z) < .9 else Vector((0, 1, 0))
    axis = normal.cross(reference).normalized()
    roll = RNG.uniform(0, math.tau)
    across = normal.cross(axis).normalized()
    forward = axis * math.cos(roll) + across * math.sin(roll)
    right = normal.cross(forward).normalized()
    # Broad, softly lobed oak leaf, with a curved central ridge.
    outline = [(0, -.52), (-.23, -.38), (-.50, -.23), (-.34, -.11),
               (-.56, .04), (-.38, .14), (-.45, .28), (-.22, .41),
               (0, .52), (.23, .40), (.45, .26), (.34, .12),
               (.56, -.01), (.38, -.13), (.48, -.27), (.21, -.40)]
    # Round each lobe rather than exposing the polygon corners in the silhouette.
    rounded = []
    for i, p in enumerate(outline):
        q = outline[(i + 1) % len(outline)]
        rounded.extend([(.75 * p[0] + .25 * q[0], .75 * p[1] + .25 * q[1]),
                        (.25 * p[0] + .75 * q[0], .25 * p[1] + .75 * q[1])])
    outline = rounded
    start = len(vertices)
    vertices.append(center + normal * length * .105)
    leaf_uvs.append(uv)
    leaf_colors.append((*tint, 1))
    for x, y in outline:
        bow = (1 - (2 * y) ** 2) * length * .024
        vertices.append(center + right * (x * width) + forward * (y * length) + normal * bow)
        leaf_uvs.append((uv[0] + x * .034, uv[1] + y * .046))
        leaf_colors.append((*tint, 1))
    for j in range(len(outline)):
        faces.append((start, start + 1 + (j + 1) % len(outline), start + 1 + j))


crown_lobes = [
    ((0, .05, 4.35), (1.77, 1.57, 1.32), 1100),
    ((-1.23, -.05, 3.67), (1.30, 1.27, 1.13), 880),
    ((1.22, .16, 3.89), (1.36, 1.29, 1.08), 900),
    ((.02, 1.19, 3.85), (1.37, 1.13, 1.12), 780),
    ((-.15, -1.16, 3.71), (1.36, 1.14, 1.12), 850),
    ((-.68, .36, 4.94), (1.22, 1.23, .94), 850),
    ((.77, -.35, 4.96), (1.18, 1.25, .89), 800),
    ((-1.87, -.14, 3.03), (.82, .85, .70), 430),
    ((1.84, .41, 3.16), (.82, .86, .76), 450),
    ((.63, -1.57, 3.05), (.96, .79, .72), 420),
]
for lobe_center, radii, count in crown_lobes:
    center = Vector(lobe_center)
    for i in range(count):
        a = RNG.uniform(0, math.tau)
        z = RNG.uniform(-1, 1)
        r = math.sqrt(1 - z * z)
        unit = Vector((r * math.cos(a), r * math.sin(a), z))
        shell = RNG.uniform(.65, 1.04) if i % 5 else RNG.uniform(.18, .77)
        distortion = 1 + .09 * math.sin(a * 5 + z * 8) + .06 * math.cos(a * 9 - z * 4)
        offset = Vector((unit.x * radii[0], unit.y * radii[1], unit.z * radii[2])) * shell * distortion
        position = center + offset
        # Leaf fans point outwards/upwards with variation, giving depth without cards facing the camera.
        outward = (offset.normalized() * .65 + Vector((0, 0, .55)) +
                   Vector((RNG.uniform(-.55, .55), RNG.uniform(-.55, .55), RNG.uniform(-.35, .35)))).normalized()
        length = RNG.uniform(.17, .29)
        uv = RNG.choice(patches)
        # Match original sunlight-to-shadow palette; glTF exports this as COLOR_0.
        height_t = max(0, min(1, (position.z - 2.2) / 3.5))
        brightness = .83 + height_t * .22 + RNG.uniform(-.05, .05)
        tint = (brightness * (.91 + height_t * .09), brightness, brightness * (1.09 - height_t * .12))
        leaf(position, outward, length, length * RNG.uniform(.65, .91), uv, tint)

foliage = mesh_object("Oak • %d individually curved painted leaves" % sum(x[2] for x in crown_lobes), vertices, faces)
foliage.data.materials.append(leaf_mat)
uv_layer = foliage.data.uv_layers.new(name="Paint patches")
for loop in foliage.data.loops:
    uv_layer.data[loop.index].uv = leaf_uvs[loop.vertex_index]
paint_colors = foliage.data.color_attributes.new(name="LeafPaint", type="FLOAT_COLOR", domain="POINT")
paint_colors.data.foreach_set("color", np.array(leaf_colors, dtype=np.float32).ravel())
for face in foliage.data.polygons:
    face.use_smooth = True
print("OAK_GEOMETRY", {"trunk_vertices": len(trunk.data.vertices), "leaf_count": sum(x[2] for x in crown_lobes),
                       "leaf_triangles": len(faces), "paint_patches": len(patches)}, flush=True)

# Export the two material meshes only, with the paint image embedded.
bpy.ops.object.select_all(action="DESELECT")
trunk.select_set(True)
foliage.select_set(True)
bpy.context.view_layer.objects.active = trunk
bpy.ops.export_scene.gltf(filepath=str(OUT / "painted_oak.glb"), export_format="GLB",
    use_selection=True, export_yup=True, export_animations=False,
    export_cameras=False, export_lights=False, export_materials="EXPORT",
    export_vertex_color="ACTIVE", export_all_vertex_colors=False)

# Studio belongs only to the Blender source, not to the reusable model.
ground_mat = bpy.data.materials.new("Studio meadow")
ground_mat.diffuse_color = (.30, .38, .22, 1)
ground_mat.use_nodes = True
ground_mat.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = (.30, .38, .22, 1)
ground_mat.node_tree.nodes.get("Principled BSDF").inputs["Roughness"].default_value = 1
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.045))
ground = move_to(bpy.context.object, studio)
ground.name = "Studio ground"
ground.data.materials.append(ground_mat)
bpy.ops.object.light_add(type="AREA", location=(-5, -7, 11))
light = move_to(bpy.context.object, studio)
light.name = "Broad warm key"
light.data.energy = 1700
light.data.shape = "DISK"
light.data.size = 7
light.rotation_euler = (Vector((0, 0, 2.5)) - light.location).to_track_quat("-Z", "Y").to_euler()
bpy.ops.object.light_add(type="SUN", location=(-5, -5, 10))
sun = move_to(bpy.context.object, studio)
sun.data.energy = 1.3
sun.data.angle = .15
sun.rotation_euler = (math.radians(23), math.radians(-28), math.radians(-25))
world = scene.world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (.64, .72, .80, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = .45
bpy.ops.object.camera_add(location=(8, -12, 6.7))
camera = move_to(bpy.context.object, studio)
camera.name = "Oak portrait"
camera.data.lens = 52
camera.rotation_euler = (Vector((0, 0, 2.8)) - camera.location).to_track_quat("-Z", "Y").to_euler()
scene.camera = camera
bpy.ops.object.select_all(action="DESELECT")
trunk.select_set(True)
foliage.select_set(True)
bpy.context.view_layer.objects.active = trunk
for area in bpy.context.screen.areas:
    if area.type == "VIEW_3D":
        area.spaces.active.region_3d.view_perspective = "CAMERA"
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "painted_oak.blend"))
if "--render" in sys.argv:
    scene.render.filepath = str(IMAGES / "painted_oak_blender_front.png")
    bpy.ops.render.render(write_still=True)
print("PAINTED_OAK_READY", flush=True)
