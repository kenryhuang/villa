#!/usr/bin/env python3
"""Generate .tres material files and .tscn stage scene files for all non-grain crops.

Follows the same patterns as the grain crop assets:
- Each .tres is a StandardMaterial3D with albedo_color and roughness
- Each .tscn is a Node3D with CropSpriteCluster script, painted texture paths,
  and 3D mesh children as fallback geometry
"""

import os

BASE_DIR = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "crops"))

# Crop definitions with per-crop color palettes for materials
CROPS = {
    "carrot": {
        "materials": {
            "stem_green": (0.22, 0.55, 0.22, 0.92),
            "leaf_green": (0.30, 0.63, 0.22, 0.90),
            "root_orange": (1.00, 0.55, 0.00, 0.88),
            "seed_brown": (0.55, 0.35, 0.17, 0.92),
        },
        "canvas_heights": [0.40, 0.50, 0.85, 0.90],
        "form": "annual_root",
    },
    "potato": {
        "materials": {
            "stem_green": (0.24, 0.55, 0.24, 0.92),
            "leaf_green": (0.31, 0.63, 0.24, 0.90),
            "tuber_brown": (0.71, 0.59, 0.35, 0.88),
            "seed_brown": (0.47, 0.33, 0.20, 0.92),
        },
        "canvas_heights": [0.40, 0.48, 0.82, 0.85],
        "form": "annual_root",
    },
    "tomato": {
        "materials": {
            "stem_green": (0.20, 0.51, 0.20, 0.92),
            "leaf_green": (0.24, 0.63, 0.16, 0.90),
            "fruit_red": (0.86, 0.16, 0.12, 0.86),
            "seed_beige": (0.63, 0.59, 0.51, 0.92),
        },
        "canvas_heights": [0.40, 0.50, 0.85, 1.10],
        "form": "annual_berry",
    },
    "strawberry": {
        "materials": {
            "stem_green": (0.20, 0.51, 0.20, 0.92),
            "leaf_green": (0.24, 0.63, 0.16, 0.90),
            "fruit_red": (0.82, 0.12, 0.20, 0.86),
            "seed_beige": (0.71, 0.67, 0.55, 0.92),
        },
        "canvas_heights": [0.40, 0.45, 0.65, 0.75],
        "form": "bush",
    },
    "blueberry": {
        "materials": {
            "stem_green": (0.20, 0.39, 0.24, 0.92),
            "leaf_green": (0.24, 0.51, 0.24, 0.90),
            "fruit_purple": (0.24, 0.20, 0.55, 0.86),
            "seed_beige": (0.63, 0.59, 0.47, 0.92),
        },
        "canvas_heights": [0.40, 0.45, 0.65, 0.78],
        "form": "bush",
    },
    "watermelon": {
        "materials": {
            "stem_green": (0.16, 0.47, 0.16, 0.92),
            "leaf_green": (0.20, 0.59, 0.20, 0.90),
            "fruit_green": (0.12, 0.47, 0.12, 0.86),
            "seed_brown": (0.20, 0.16, 0.08, 0.92),
        },
        "canvas_heights": [0.35, 0.42, 0.70, 0.90],
        "form": "annual_large",
    },
    "sunflower": {
        "materials": {
            "stem_green": (0.24, 0.47, 0.16, 0.92),
            "leaf_green": (0.27, 0.59, 0.20, 0.90),
            "flower_gold": (1.00, 0.78, 0.12, 0.86),
            "center_brown": (0.31, 0.24, 0.08, 0.88),
            "seed_brown": (0.24, 0.20, 0.12, 0.92),
        },
        "canvas_heights": [0.40, 0.55, 1.00, 1.20],
        "form": "flower_tall",
    },
    "lavender": {
        "materials": {
            "stem_green": (0.31, 0.43, 0.27, 0.92),
            "leaf_green": (0.39, 0.55, 0.35, 0.90),
            "flower_purple": (0.59, 0.39, 0.71, 0.86),
            "seed_brown": (0.47, 0.39, 0.31, 0.92),
        },
        "canvas_heights": [0.40, 0.52, 0.90, 1.05],
        "form": "flower_spike",
    },
    "pumpkin": {
        "materials": {
            "stem_green": (0.24, 0.47, 0.16, 0.92),
            "leaf_green": (0.27, 0.59, 0.20, 0.90),
            "fruit_orange": (0.90, 0.59, 0.12, 0.86),
            "seed_beige": (0.71, 0.63, 0.47, 0.92),
        },
        "canvas_heights": [0.35, 0.42, 0.70, 0.88],
        "form": "annual_large",
    },
    "rose": {
        "materials": {
            "stem_green": (0.20, 0.43, 0.20, 0.92),
            "leaf_green": (0.24, 0.55, 0.16, 0.90),
            "flower_red": (0.86, 0.20, 0.31, 0.86),
            "seed_brown": (0.67, 0.51, 0.39, 0.92),
        },
        "canvas_heights": [0.40, 0.52, 0.88, 1.05],
        "form": "flower_round",
    },
    "apple": {
        "materials": {
            "trunk_brown": (0.35, 0.24, 0.12, 0.92),
            "leaf_green": (0.20, 0.55, 0.20, 0.90),
            "fruit_red": (0.78, 0.16, 0.16, 0.86),
            "seed_brown": (0.43, 0.31, 0.20, 0.92),
        },
        "canvas_heights": [0.40, 0.55, 1.00, 1.30],
        "form": "tree",
    },
    "peach": {
        "materials": {
            "trunk_brown": (0.39, 0.25, 0.14, 0.92),
            "leaf_green": (0.24, 0.59, 0.24, 0.90),
            "fruit_pink": (1.00, 0.71, 0.59, 0.86),
            "seed_brown": (0.51, 0.35, 0.22, 0.92),
        },
        "canvas_heights": [0.40, 0.55, 1.00, 1.30],
        "form": "tree",
    },
    "grape": {
        "materials": {
            "vine_green": (0.27, 0.35, 0.20, 0.92),
            "leaf_green": (0.24, 0.51, 0.20, 0.90),
            "fruit_purple": (0.47, 0.20, 0.63, 0.86),
            "seed_brown": (0.39, 0.31, 0.24, 0.92),
        },
        "canvas_heights": [0.40, 0.50, 0.85, 1.10],
        "form": "vine",
    },
    "lemon": {
        "materials": {
            "trunk_brown": (0.33, 0.24, 0.12, 0.92),
            "leaf_green": (0.24, 0.55, 0.16, 0.90),
            "fruit_yellow": (0.94, 0.86, 0.20, 0.86),
            "seed_brown": (0.47, 0.39, 0.16, 0.92),
        },
        "canvas_heights": [0.40, 0.55, 1.00, 1.30],
        "form": "tree",
    },
}


def write_tres(filepath, mat_name, color_rgba):
    """Write a StandardMaterial3D .tres file."""
    r, g, b, roughness = color_rgba
    content = f"""[gd_resource type="StandardMaterial3D" format=3]

[resource]
albedo_color = Color({r}, {g}, {b}, 1)
roughness = {roughness}
"""
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)


STAGE_NAMES = ["seed", "sprout", "growing", "mature"]
STAGE_CAPS = ["Seed", "Sprout", "Growing", "Mature"]


def build_stage_tscn(crop_id, stage_index, materials_dict, canvas_height):
    """Build .tscn content for a crop stage scene."""
    stage = STAGE_NAMES[stage_index]
    stage_cap = STAGE_CAPS[stage_index]
    crop_cap = crop_id.capitalize()

    # Painted texture paths
    back_paths = []
    front_paths = []
    for v in range(3):
        back_paths.append(f"res://assets/crops/{crop_id}/painted/stage_{stage_index}/variant_{v}_back.png")
        front_paths.append(f"res://assets/crops/{crop_id}/painted/stage_{stage_index}/variant_{v}_front.png")

    back_arr = "Array[String]([" + ", ".join(f'"{p}"' for p in back_paths) + "])"
    front_arr = "Array[String]([" + ", ".join(f'"{p}"' for p in front_paths) + "])"

    # Material references
    mat_refs = {}
    ext_count = 1  # CropSpriteClusterScript
    for mat_name in materials_dict:
        mat_refs[mat_name] = ext_count
        ext_count += 1

    # Build ext_resource lines
    ext_lines = [
        f'[ext_resource path="res://scripts/visual/crop_sprite_cluster.gd" type="Script" id="CropSpriteClusterScript"]',
    ]
    for mat_name in materials_dict:
        ext_lines.append(
            f'[ext_resource path="res://assets/crops/{crop_id}/materials/{mat_name}.tres" type="Material" id="{mat_refs[mat_name]}"]'
        )

    # Build sub_resources and child nodes based on stage and form
    sub_resources = []
    child_nodes = []
    form = CROPS[crop_id]["form"]

    if stage_index == 0:
        # Seed stage: small sphere meshes on ground
        seed_mat = list(mat_refs.values())[0]  # first material (usually seed/soil colored)
        sub_resources.append(
            f'[sub_resource type="SphereMesh" id="KernelMesh"]\nmaterial = ExtResource("{seed_mat}")\nradius = 0.075\nheight = 0.1\nradial_segments = 8\nrings = 4'
        )
        child_nodes.append(f'[node name="KernelLeft" type="MeshInstance3D" parent="."]\nposition = Vector3(-0.11, 0.05, 0.02)\nrotation_degrees = Vector3(0, 24, -12)\nscale = Vector3(1.35, 0.72, 0.78)\nmesh = SubResource("KernelMesh")')
        child_nodes.append(f'[node name="KernelCenter" type="MeshInstance3D" parent="."]\nposition = Vector3(0.01, 0.048, -0.07)\nrotation_degrees = Vector3(4, -18, 8)\nscale = Vector3(1.3, 0.7, 0.76)\nmesh = SubResource("KernelMesh")')
        child_nodes.append(f'[node name="KernelRight" type="MeshInstance3D" parent="."]\nposition = Vector3(0.12, 0.052, 0.05)\nrotation_degrees = Vector3(-5, 42, 10)\nscale = Vector3(1.32, 0.74, 0.8)\nmesh = SubResource("KernelMesh")')

    elif stage_index == 1:
        # Sprout: stem + small leaves
        stem_mat = mat_refs.get("stem_green", mat_refs.get("trunk_brown", mat_refs.get("vine_green", 1)))
        leaf_mat = mat_refs.get("leaf_green", 1)
        sub_resources.append(
            f'[sub_resource type="CylinderMesh" id="StemMesh"]\nmaterial = ExtResource("{stem_mat}")\ntop_radius = 0.025\nbottom_radius = 0.035\nheight = 0.25\nradial_segments = 6\nrings = 1'
        )
        sub_resources.append(
            f'[sub_resource type="BoxMesh" id="LeafMesh"]\nmaterial = ExtResource("{leaf_mat}")\nsize = Vector3(0.055, 0.22, 0.018)'
        )
        child_nodes.append(f'[node name="Stem" type="MeshInstance3D" parent="."]\nposition = Vector3(0, 0.125, 0)\nmesh = SubResource("StemMesh")')
        child_nodes.append(f'[node name="LeafLeft" type="MeshInstance3D" parent="."]\nposition = Vector3(-0.07, 0.15, 0)\nrotation_degrees = Vector3(0, 0, -42)\nmesh = SubResource("LeafMesh")')
        child_nodes.append(f'[node name="LeafRight" type="MeshInstance3D" parent="."]\nposition = Vector3(0.075, 0.17, 0.015)\nrotation_degrees = Vector3(8, 18, 38)\nmesh = SubResource("LeafMesh")')
        child_nodes.append(f'[node name="LeafBack" type="MeshInstance3D" parent="."]\nposition = Vector3(0.015, 0.13, -0.065)\nrotation_degrees = Vector3(-38, 0, 4)\nmesh = SubResource("LeafMesh")')

    elif stage_index == 2:
        # Growing: taller stem, more leaves, maybe fruit bud
        stem_mat = mat_refs.get("stem_green", mat_refs.get("trunk_brown", mat_refs.get("vine_green", 1)))
        leaf_mat = mat_refs.get("leaf_green", 1)
        sub_resources.append(
            f'[sub_resource type="CylinderMesh" id="StemMesh"]\nmaterial = ExtResource("{stem_mat}")\ntop_radius = 0.022\nbottom_radius = 0.032\nheight = 0.56\nradial_segments = 6\nrings = 1'
        )
        sub_resources.append(
            f'[sub_resource type="BoxMesh" id="LeafMesh"]\nmaterial = ExtResource("{leaf_mat}")\nsize = Vector3(0.06, 0.3, 0.018)'
        )

        if form in ("tree",):
            trunk_mat = mat_refs.get("trunk_brown", 1)
            leaf_m = mat_refs.get("leaf_green", 1)
            fruit_key = [k for k in mat_refs if "fruit" in k]
            fruit_m = mat_refs[fruit_key[0]] if fruit_key else leaf_m
            sub_resources = [
                f'[sub_resource type="CylinderMesh" id="TrunkMesh"]\nmaterial = ExtResource("{trunk_mat}")\ntop_radius = 0.06\nbottom_radius = 0.08\nheight = 0.6\nradial_segments = 6\nrings = 1',
                f'[sub_resource type="SphereMesh" id="CanopyMesh"]\nmaterial = ExtResource("{leaf_m}")\nradius = 0.35\nheight = 0.6\nradial_segments = 8\nrings = 4',
                f'[sub_resource type="SphereMesh" id="FruitBudMesh"]\nmaterial = ExtResource("{fruit_m}")\nradius = 0.035\nheight = 0.06\nradial_segments = 8\nrings = 4',
            ]
            child_nodes = [
                f'[node name="Trunk" type="MeshInstance3D" parent="."]\nposition = Vector3(0, 0.3, 0)\nmesh = SubResource("TrunkMesh")',
                f'[node name="Canopy" type="MeshInstance3D" parent="."]\nposition = Vector3(0, 0.75, 0)\nmesh = SubResource("CanopyMesh")',
                f'[node name="FruitBud1" type="MeshInstance3D" parent="."]\nposition = Vector3(-0.12, 0.68, 0.08)\nmesh = SubResource("FruitBudMesh")',
                f'[node name="FruitBud2" type="MeshInstance3D" parent="."]\nposition = Vector3(0.15, 0.72, -0.06)\nmesh = SubResource("FruitBudMesh")',
            ]
        elif form == "bush":
            sub_resources.append(
                f'[sub_resource type="SphereMesh" id="BushMesh"]\nmaterial = ExtResource("{leaf_mat}")\nradius = 0.2\nheight = 0.35\nradial_segments = 8\nrings = 4'
            )
            child_nodes = [
                f'[node name="StemCenter" type="MeshInstance3D" parent="."]\nposition = Vector3(0, 0.28, 0)\nmesh = SubResource("StemMesh")',
                f'[node name="LeafLeft" type="MeshInstance3D" parent="."]\nposition = Vector3(-0.09, 0.29, 0)\nrotation_degrees = Vector3(0, 0, -48)\nmesh = SubResource("LeafMesh")',
                f'[node name="LeafRight" type="MeshInstance3D" parent="."]\nposition = Vector3(0.09, 0.43, 0)\nrotation_degrees = Vector3(0, 0, 48)\nmesh = SubResource("LeafMesh")',
                f'[node name="BushMound" type="MeshInstance3D" parent="."]\nposition = Vector3(0, 0.45, 0)\nmesh = SubResource("BushMesh")',
            ]
        elif form == "vine":
            sub_resources.append(
                f'[sub_resource type="CylinderMesh" id="HorizontalStem"]\nmaterial = ExtResource("{stem_mat}")\ntop_radius = 0.02\nbottom_radius = 0.025\nheight = 0.8\nradial_segments = 6\nrings = 1'
            )
            child_nodes = [
                f'[node name="MainStem" type="MeshInstance3D" parent="."]\nposition = Vector3(0, 0.4, 0)\nrotation_degrees = Vector3(0, 0, 90)\nmesh = SubResource("HorizontalStem")',
                f'[node name="LeafA" type="MeshInstance3D" parent="."]\nposition = Vector3(-0.15, 0.45, 0.02)\nrotation_degrees = Vector3(0, 0, -35)\nmesh = SubResource("LeafMesh")',
                f'[node name="LeafB" type="MeshInstance3D" parent="."]\nposition = Vector3(0.15, 0.38, -0.03)\nrotation_degrees = Vector3(0, 0, 40)\nmesh = SubResource("LeafMesh")',
            ]
        else:
            # annual / flower forms: similar to grain growing
            sub_resources.append(
                f'[sub_resource type="SphereMesh" id="YoungHeadMesh"]\nmaterial = ExtResource("{stem_mat}")\nradius = 0.055\nheight = 0.16\nradial_segments = 8\nrings = 4'
            )
            child_nodes = [
                f'[node name="StemLeft" type="MeshInstance3D" parent="."]\nposition = Vector3(-0.2, 0.28, 0.05)\nrotation_degrees = Vector3(0, 0, -3)\nmesh = SubResource("StemMesh")',
                f'[node name="LeafLeftA" type="MeshInstance3D" parent="."]\nposition = Vector3(-0.29, 0.27, 0.05)\nrotation_degrees = Vector3(0, 0, -50)\nmesh = SubResource("LeafMesh")',
                f'[node name="LeafLeftB" type="MeshInstance3D" parent="."]\nposition = Vector3(-0.12, 0.4, 0.04)\nrotation_degrees = Vector3(8, 0, 45)\nmesh = SubResource("LeafMesh")',
                f'[node name="HeadLeft" type="MeshInstance3D" parent="."]\nposition = Vector3(-0.22, 0.63, 0.05)\nmesh = SubResource("YoungHeadMesh")',
                f'[node name="StemCenter" type="MeshInstance3D" parent="."]\nposition = Vector3(0, 0.3, -0.07)\nmesh = SubResource("StemMesh")',
                f'[node name="LeafCenterA" type="MeshInstance3D" parent="."]\nposition = Vector3(-0.09, 0.29, -0.07)\nrotation_degrees = Vector3(0, 0, -48)\nmesh = SubResource("LeafMesh")',
                f'[node name="LeafCenterB" type="MeshInstance3D" parent="."]\nposition = Vector3(0.09, 0.43, -0.06)\nrotation_degrees = Vector3(0, 0, 48)\nmesh = SubResource("LeafMesh")',
                f'[node name="HeadCenter" type="MeshInstance3D" parent="."]\nposition = Vector3(0, 0.66, -0.07)\nmesh = SubResource("YoungHeadMesh")',
                f'[node name="StemRight" type="MeshInstance3D" parent="."]\nposition = Vector3(0.21, 0.27, 0.08)\nrotation_degrees = Vector3(0, 0, 4)\nmesh = SubResource("StemMesh")',
                f'[node name="LeafRightA" type="MeshInstance3D" parent="."]\nposition = Vector3(0.12, 0.26, 0.08)\nrotation_degrees = Vector3(0, 0, -46)\nmesh = SubResource("LeafMesh")',
                f'[node name="LeafRightB" type="MeshInstance3D" parent="."]\nposition = Vector3(0.3, 0.39, 0.08)\nrotation_degrees = Vector3(0, 0, 48)\nmesh = SubResource("LeafMesh")',
                f'[node name="HeadRight" type="MeshInstance3D" parent="."]\nposition = Vector3(0.23, 0.62, 0.08)\nmesh = SubResource("YoungHeadMesh")',
            ]

    elif stage_index == 3:
        # Mature: full plant with fruit
        if form == "tree":
            trunk_mat = mat_refs.get("trunk_brown", 1)
            leaf_mat = mat_refs.get("leaf_green", 1)
            fruit_mat_key = [k for k in mat_refs if "fruit" in k]
            fruit_mat = mat_refs[fruit_mat_key[0]] if fruit_mat_key else leaf_mat
            sub_resources = [
                f'[sub_resource type="CylinderMesh" id="TrunkMesh"]\nmaterial = ExtResource("{trunk_mat}")\ntop_radius = 0.07\nbottom_radius = 0.10\nheight = 0.8\nradial_segments = 6\nrings = 1',
                f'[sub_resource type="SphereMesh" id="CanopyMesh"]\nmaterial = ExtResource("{leaf_mat}")\nradius = 0.5\nheight = 0.8\nradial_segments = 8\nrings = 4',
                f'[sub_resource type="SphereMesh" id="FruitMesh"]\nmaterial = ExtResource("{fruit_mat}")\nradius = 0.06\nheight = 0.1\nradial_segments = 8\nrings = 4',
            ]
            child_nodes = [
                f'[node name="Trunk" type="MeshInstance3D" parent="."]\nposition = Vector3(0, 0.4, 0)\nmesh = SubResource("TrunkMesh")',
                f'[node name="Canopy" type="MeshInstance3D" parent="."]\nposition = Vector3(0, 1.05, 0)\nmesh = SubResource("CanopyMesh")',
                f'[node name="Fruit1" type="MeshInstance3D" parent="."]\nposition = Vector3(-0.2, 0.85, 0.15)\nmesh = SubResource("FruitMesh")',
                f'[node name="Fruit2" type="MeshInstance3D" parent="."]\nposition = Vector3(0.25, 0.9, -0.1)\nmesh = SubResource("FruitMesh")',
                f'[node name="Fruit3" type="MeshInstance3D" parent="."]\nposition = Vector3(0.05, 1.1, 0.2)\nmesh = SubResource("FruitMesh")',
                f'[node name="Fruit4" type="MeshInstance3D" parent="."]\nposition = Vector3(-0.15, 1.15, -0.15)\nmesh = SubResource("FruitMesh")',
            ]
        elif form == "bush":
            stem_mat = mat_refs.get("stem_green", 1)
            leaf_mat = mat_refs.get("leaf_green", 1)
            fruit_mat_key = [k for k in mat_refs if "fruit" in k]
            fruit_mat = mat_refs[fruit_mat_key[0]] if fruit_mat_key else leaf_mat
            sub_resources = [
                f'[sub_resource type="CylinderMesh" id="StemMesh"]\nmaterial = ExtResource("{stem_mat}")\ntop_radius = 0.02\nbottom_radius = 0.03\nheight = 0.35\nradial_segments = 6\nrings = 1',
                f'[sub_resource type="SphereMesh" id="BushMesh"]\nmaterial = ExtResource("{leaf_mat}")\nradius = 0.3\nheight = 0.5\nradial_segments = 8\nrings = 4',
                f'[sub_resource type="SphereMesh" id="FruitMesh"]\nmaterial = ExtResource("{fruit_mat}")\nradius = 0.04\nheight = 0.07\nradial_segments = 8\nrings = 4',
            ]
            child_nodes = [
                f'[node name="Stem1" type="MeshInstance3D" parent="."]\nposition = Vector3(-0.1, 0.175, 0)\nmesh = SubResource("StemMesh")',
                f'[node name="Stem2" type="MeshInstance3D" parent="."]\nposition = Vector3(0.1, 0.175, 0.05)\nmesh = SubResource("StemMesh")',
                f'[node name="BushMound" type="MeshInstance3D" parent="."]\nposition = Vector3(0, 0.55, 0)\nmesh = SubResource("BushMesh")',
                f'[node name="Fruit1" type="MeshInstance3D" parent="."]\nposition = Vector3(-0.15, 0.5, 0.12)\nmesh = SubResource("FruitMesh")',
                f'[node name="Fruit2" type="MeshInstance3D" parent="."]\nposition = Vector3(0.2, 0.55, -0.08)\nmesh = SubResource("FruitMesh")',
                f'[node name="Fruit3" type="MeshInstance3D" parent="."]\nposition = Vector3(0.05, 0.65, 0.15)\nmesh = SubResource("FruitMesh")',
                f'[node name="Fruit4" type="MeshInstance3D" parent="."]\nposition = Vector3(-0.08, 0.45, -0.12)\nmesh = SubResource("FruitMesh")',
                f'[node name="Fruit5" type="MeshInstance3D" parent="."]\nposition = Vector3(0.12, 0.6, 0.08)\nmesh = SubResource("FruitMesh")',
            ]
        elif form == "vine":
            vine_mat = mat_refs.get("vine_green", 1)
            leaf_mat = mat_refs.get("leaf_green", 1)
            fruit_mat_key = [k for k in mat_refs if "fruit" in k]
            fruit_mat = mat_refs[fruit_mat_key[0]] if fruit_mat_key else leaf_mat
            sub_resources = [
                f'[sub_resource type="CylinderMesh" id="HorizontalStem"]\nmaterial = ExtResource("{vine_mat}")\ntop_radius = 0.018\nbottom_radius = 0.022\nheight = 1.0\nradial_segments = 6\nrings = 1',
                f'[sub_resource type="BoxMesh" id="LeafMesh"]\nmaterial = ExtResource("{leaf_mat}")\nsize = Vector3(0.06, 0.25, 0.016)',
                f'[sub_resource type="SphereMesh" id="FruitClusterMesh"]\nmaterial = ExtResource("{fruit_mat}")\nradius = 0.05\nheight = 0.08\nradial_segments = 8\nrings = 4',
            ]
            child_nodes = [
                f'[node name="MainStem" type="MeshInstance3D" parent="."]\nposition = Vector3(0, 0.5, 0)\nrotation_degrees = Vector3(0, 0, 90)\nmesh = SubResource("HorizontalStem")',
                f'[node name="Leaf1" type="MeshInstance3D" parent="."]\nposition = Vector3(-0.2, 0.55, 0.03)\nrotation_degrees = Vector3(0, 0, -30)\nmesh = SubResource("LeafMesh")',
                f'[node name="Leaf2" type="MeshInstance3D" parent="."]\nposition = Vector3(0.15, 0.48, -0.03)\nrotation_degrees = Vector3(0, 0, 35)\nmesh = SubResource("LeafMesh")',
                f'[node name="Leaf3" type="MeshInstance3D" parent="."]\nposition = Vector3(-0.35, 0.52, -0.02)\nrotation_degrees = Vector3(0, 0, -42)\nmesh = SubResource("LeafMesh")',
                f'[node name="Cluster1" type="MeshInstance3D" parent="."]\nposition = Vector3(-0.1, 0.62, 0.04)\nmesh = SubResource("FruitClusterMesh")',
                f'[node name="Cluster2" type="MeshInstance3D" parent="."]\nposition = Vector3(0.08, 0.58, -0.02)\nmesh = SubResource("FruitClusterMesh")',
                f'[node name="Cluster3" type="MeshInstance3D" parent="."]\nposition = Vector3(-0.3, 0.6, 0.01)\nmesh = SubResource("FruitClusterMesh")',
                f'[node name="Cluster4" type="MeshInstance3D" parent="."]\nposition = Vector3(0.25, 0.55, -0.04)\nmesh = SubResource("FruitClusterMesh")',
            ]
        elif form in ("flower_tall", "flower_spike", "flower_round"):
            stem_mat = mat_refs.get("stem_green", 1)
            leaf_mat = mat_refs.get("leaf_green", 1)
            flower_mat_key = [k for k in mat_refs if "flower" in k]
            flower_mat = mat_refs[flower_mat_key[0]] if flower_mat_key else leaf_mat
            sub_resources = [
                f'[sub_resource type="CylinderMesh" id="StemMesh"]\nmaterial = ExtResource("{stem_mat}")\ntop_radius = 0.018\nbottom_radius = 0.03\nheight = 0.78\nradial_segments = 6\nrings = 1',
                f'[sub_resource type="BoxMesh" id="LeafMesh"]\nmaterial = ExtResource("{leaf_mat}")\nsize = Vector3(0.055, 0.32, 0.016)',
                f'[sub_resource type="SphereMesh" id="FlowerMesh"]\nmaterial = ExtResource("{flower_mat}")\nradius = 0.12\nheight = 0.2\nradial_segments = 10\nrings = 5',
            ]
            child_nodes = [
                f'[node name="Stem1" type="MeshInstance3D" parent="."]\nposition = Vector3(0, 0.39, 0)\nmesh = SubResource("StemMesh")',
                f'[node name="Leaf1A" type="MeshInstance3D" parent="."]\nposition = Vector3(-0.09, 0.34, 0)\nrotation_degrees = Vector3(0, 0, -52)\nmesh = SubResource("LeafMesh")',
                f'[node name="Leaf1B" type="MeshInstance3D" parent="."]\nposition = Vector3(0.09, 0.51, 0)\nrotation_degrees = Vector3(0, 0, 48)\nmesh = SubResource("LeafMesh")',
                f'[node name="FlowerHead" type="MeshInstance3D" parent="."]\nposition = Vector3(0, 0.82, 0)\nmesh = SubResource("FlowerMesh")',
            ]
            if form == "flower_tall":
                center_key = [k for k in mat_refs if "center" in k]
                if center_key:
                    sub_resources.append(
                        f'[sub_resource type="SphereMesh" id="CenterMesh"]\nmaterial = ExtResource("{mat_refs[center_key[0]]}")\nradius = 0.06\nheight = 0.1\nradial_segments = 8\nrings = 4'
                    )
                    child_nodes.append(f'[node name="FlowerCenter" type="MeshInstance3D" parent="."]\nposition = Vector3(0, 0.85, 0)\nmesh = SubResource("CenterMesh")')
        else:
            # annual forms (root, berry, large) - grain-like mature
            stem_mat = mat_refs.get("stem_green", 1)
            leaf_mat = mat_refs.get("leaf_green", 1)
            fruit_mat_key = [k for k in mat_refs if "fruit" in k or "root" in k or "tuber" in k]
            fruit_mat = mat_refs[fruit_mat_key[0]] if fruit_mat_key else leaf_mat
            sub_resources = [
                f'[sub_resource type="CylinderMesh" id="StemMesh"]\nmaterial = ExtResource("{stem_mat}")\ntop_radius = 0.018\nbottom_radius = 0.03\nheight = 0.78\nradial_segments = 6\nrings = 1',
                f'[sub_resource type="BoxMesh" id="LeafMesh"]\nmaterial = ExtResource("{leaf_mat}")\nsize = Vector3(0.055, 0.32, 0.016)',
                f'[sub_resource type="SphereMesh" id="FruitMesh"]\nmaterial = ExtResource("{fruit_mat}")\nradius = 0.052\nheight = 0.12\nradial_segments = 8\nrings = 4',
            ]
            child_nodes = [
                f'[node name="Stem1" type="MeshInstance3D" parent="."]\nposition = Vector3(-0.2, 0.39, 0.05)\nrotation_degrees = Vector3(0, 0, -3)\nmesh = SubResource("StemMesh")',
                f'[node name="Leaf1A" type="MeshInstance3D" parent="."]\nposition = Vector3(-0.29, 0.34, 0.05)\nrotation_degrees = Vector3(0, 0, -50)\nmesh = SubResource("LeafMesh")',
                f'[node name="Leaf1B" type="MeshInstance3D" parent="."]\nposition = Vector3(-0.12, 0.51, 0.04)\nrotation_degrees = Vector3(8, 0, 45)\nmesh = SubResource("LeafMesh")',
                f'[node name="Fruit1" type="MeshInstance3D" parent="."]\nposition = Vector3(-0.22, 0.82, 0.05)\nmesh = SubResource("FruitMesh")',
                f'[node name="Stem2" type="MeshInstance3D" parent="."]\nposition = Vector3(0, 0.4, -0.07)\nmesh = SubResource("StemMesh")',
                f'[node name="Leaf2A" type="MeshInstance3D" parent="."]\nposition = Vector3(-0.09, 0.36, -0.07)\nrotation_degrees = Vector3(0, 0, -48)\nmesh = SubResource("LeafMesh")',
                f'[node name="Leaf2B" type="MeshInstance3D" parent="."]\nposition = Vector3(0.09, 0.54, -0.06)\nrotation_degrees = Vector3(0, 0, 48)\nmesh = SubResource("LeafMesh")',
                f'[node name="Fruit2" type="MeshInstance3D" parent="."]\nposition = Vector3(0, 0.86, -0.07)\nmesh = SubResource("FruitMesh")',
                f'[node name="Stem3" type="MeshInstance3D" parent="."]\nposition = Vector3(0.2, 0.38, 0.08)\nrotation_degrees = Vector3(0, 0, 4)\nmesh = SubResource("StemMesh")',
                f'[node name="Leaf3A" type="MeshInstance3D" parent="."]\nposition = Vector3(0.11, 0.33, 0.08)\nrotation_degrees = Vector3(0, 0, -46)\nmesh = SubResource("LeafMesh")',
                f'[node name="Leaf3B" type="MeshInstance3D" parent="."]\nposition = Vector3(0.29, 0.51, 0.08)\nrotation_degrees = Vector3(0, 0, 50)\nmesh = SubResource("LeafMesh")',
                f'[node name="Fruit3" type="MeshInstance3D" parent="."]\nposition = Vector3(0.22, 0.8, 0.08)\nmesh = SubResource("FruitMesh")',
            ]

    # Assemble the .tscn file
    load_steps = ext_count + len(sub_resources)
    lines = [f"[gd_scene load_steps={load_steps} format=3]", ""]
    lines.extend(ext_lines)
    lines.append("")
    lines.extend(sub_resources)
    lines.append("")
    # Root node
    lines.append(f'[node name="{crop_cap}Stage{stage_index}{stage_cap}" type="Node3D"]')
    lines.append(f'script = ExtResource("CropSpriteClusterScript")')
    lines.append(f'back_texture_paths = {back_arr}')
    lines.append(f'front_texture_paths = {front_arr}')
    lines.append(f'canvas_world_height = {canvas_height}')
    lines.append("")
    lines.extend(child_nodes)

    return "\n".join(lines)


def main():
    total_tres = 0
    total_tscn = 0

    for crop_id, crop_data in CROPS.items():
        # Write material files
        mat_dir = os.path.join(BASE_DIR, crop_id, "materials")
        os.makedirs(mat_dir, exist_ok=True)
        for mat_name, color_rgba in crop_data["materials"].items():
            tres_path = os.path.join(mat_dir, f"{mat_name}.tres")
            write_tres(tres_path, mat_name, color_rgba)
            total_tres += 1

        # Write stage scene files
        for stage_index in range(4):
            canvas_height = crop_data["canvas_heights"][stage_index]
            content = build_stage_tscn(crop_id, stage_index, crop_data["materials"], canvas_height)
            tscn_path = os.path.join(BASE_DIR, crop_id, f"{crop_id}_stage_{stage_index}_{STAGE_NAMES[stage_index]}.tscn")
            with open(tscn_path, 'w', encoding='utf-8') as f:
                f.write(content)
            total_tscn += 1

        print(f"  {crop_id}: {len(crop_data['materials'])} materials, 4 stage scenes")

    print(f"\nDone! Generated {total_tres} .tres materials and {total_tscn} .tscn stage scenes.")


if __name__ == "__main__":
    main()
