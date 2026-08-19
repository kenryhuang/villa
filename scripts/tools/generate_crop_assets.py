#!/usr/bin/env python3
"""Generate hand-painted style crop textures for all non-grain crops.

Each crop gets 4 stages × 3 variants × 2 layers = 24 PNGs (1024×1024, RGBA).
The textures mimic the grain art style: organic shapes, soft painterly edges,
color variation, and proper botanical silhouettes per growth form.

Uses PIL + numpy for noise-based painterly effects.
"""

import os
import math
import random
from PIL import Image, ImageDraw, ImageFilter, ImageChops
import numpy as np

# Seed for reproducibility (change for different variants)
RNG_SEED = 42

# Crop definitions with expanded palettes
CROPS = [
    # Annual vegetables
    {
        "id": "carrot", "name": "胡萝卜", "form": "annual_root",
        "stem": (60, 140, 50), "stem_dark": (40, 100, 35),
        "leaf": (50, 170, 40), "leaf_dark": (35, 120, 28), "leaf_light": (80, 200, 60),
        "fruit": (255, 140, 30), "fruit_dark": (200, 100, 15), "fruit_light": (255, 180, 80),
        "seed": (139, 90, 43), "seed_dark": (110, 70, 30),
    },
    {
        "id": "potato", "name": "土豆", "form": "annual_root",
        "stem": (65, 145, 55), "stem_dark": (45, 105, 38),
        "leaf": (75, 165, 55), "leaf_dark": (50, 120, 38), "leaf_light": (100, 190, 75),
        "fruit": (190, 155, 95), "fruit_dark": (150, 120, 70), "fruit_light": (220, 185, 130),
        "seed": (120, 85, 50), "seed_dark": (95, 65, 35),
    },
    {
        "id": "tomato", "name": "番茄", "form": "annual_berry",
        "stem": (55, 135, 50), "stem_dark": (38, 100, 35),
        "leaf": (55, 165, 40), "leaf_dark": (38, 120, 28), "leaf_light": (80, 195, 55),
        "fruit": (210, 45, 35), "fruit_dark": (170, 25, 20), "fruit_light": (240, 90, 70),
        "seed": (160, 150, 130), "seed_dark": (130, 120, 100),
    },
    {
        "id": "watermelon", "name": "西瓜", "form": "annual_large",
        "stem": (45, 125, 40), "stem_dark": (30, 90, 28),
        "leaf": (50, 155, 50), "leaf_dark": (35, 115, 35), "leaf_light": (75, 185, 70),
        "fruit": (35, 130, 35), "fruit_dark": (25, 95, 25), "fruit_light": (55, 170, 55),
        "seed": (50, 40, 20), "seed_dark": (35, 28, 15),
    },
    {
        "id": "pumpkin", "name": "南瓜", "form": "annual_large",
        "stem": (65, 125, 42), "stem_dark": (45, 90, 30),
        "leaf": (75, 155, 50), "leaf_dark": (50, 115, 35), "leaf_light": (100, 185, 70),
        "fruit": (230, 155, 35), "fruit_dark": (190, 120, 20), "fruit_light": (255, 195, 80),
        "seed": (180, 160, 120), "seed_dark": (145, 125, 90),
    },
    # Bushes
    {
        "id": "strawberry", "name": "草莓", "form": "bush",
        "stem": (55, 135, 50), "stem_dark": (38, 100, 35),
        "leaf": (55, 165, 40), "leaf_dark": (38, 120, 28), "leaf_light": (80, 195, 55),
        "fruit": (210, 35, 55), "fruit_dark": (170, 20, 40), "fruit_light": (240, 80, 95),
        "seed": (180, 170, 140), "seed_dark": (145, 135, 110),
    },
    {
        "id": "blueberry", "name": "蓝莓", "form": "bush",
        "stem": (55, 105, 65), "stem_dark": (38, 75, 45),
        "leaf": (60, 135, 60), "leaf_dark": (42, 100, 42), "leaf_light": (80, 165, 80),
        "fruit": (65, 55, 145), "fruit_dark": (45, 35, 110), "fruit_light": (100, 85, 180),
        "seed": (160, 150, 120), "seed_dark": (130, 120, 95),
    },
    # Flowers
    {
        "id": "sunflower", "name": "向日葵", "form": "flower_tall",
        "stem": (65, 125, 42), "stem_dark": (45, 90, 30),
        "leaf": (75, 155, 50), "leaf_dark": (50, 115, 35), "leaf_light": (100, 185, 70),
        "fruit": (255, 205, 35), "fruit_dark": (220, 170, 20), "fruit_light": (255, 230, 100),
        "seed": (60, 50, 30), "seed_dark": (42, 35, 20),
    },
    {
        "id": "lavender", "name": "薰衣草", "form": "flower_spike",
        "stem": (85, 115, 72), "stem_dark": (60, 85, 50),
        "leaf": (100, 145, 92), "leaf_dark": (70, 110, 65), "leaf_light": (130, 175, 120),
        "fruit": (155, 105, 185), "fruit_dark": (120, 75, 150), "fruit_light": (185, 140, 215),
        "seed": (120, 100, 80), "seed_dark": (95, 75, 60),
    },
    {
        "id": "rose", "name": "玫瑰", "form": "flower_round",
        "stem": (55, 115, 50), "stem_dark": (38, 85, 35),
        "leaf": (60, 145, 42), "leaf_dark": (42, 110, 30), "leaf_light": (85, 175, 60),
        "fruit": (220, 55, 85), "fruit_dark": (180, 35, 60), "fruit_light": (245, 100, 125),
        "seed": (170, 130, 100), "seed_dark": (140, 100, 75),
    },
    # Trees
    {
        "id": "apple", "name": "苹果", "form": "tree",
        "stem": (95, 65, 32), "stem_dark": (70, 45, 22),
        "leaf": (55, 145, 52), "leaf_dark": (38, 110, 38), "leaf_light": (80, 180, 72),
        "fruit": (205, 45, 45), "fruit_dark": (165, 30, 30), "fruit_light": (235, 85, 80),
        "seed": (110, 80, 50), "seed_dark": (85, 60, 35),
    },
    {
        "id": "peach", "name": "桃子", "form": "tree",
        "stem": (105, 70, 38), "stem_dark": (78, 50, 25),
        "leaf": (65, 155, 62), "leaf_dark": (45, 115, 45), "leaf_light": (90, 190, 82),
        "fruit": (255, 185, 155), "fruit_dark": (225, 145, 115), "fruit_light": (255, 215, 195),
        "seed": (130, 90, 55), "seed_dark": (100, 68, 40),
    },
    {
        "id": "lemon", "name": "柠檬", "form": "tree",
        "stem": (90, 65, 32), "stem_dark": (65, 45, 22),
        "leaf": (65, 145, 45), "leaf_dark": (45, 110, 30), "leaf_light": (90, 180, 62),
        "fruit": (245, 225, 55), "fruit_dark": (210, 190, 35), "fruit_light": (255, 245, 110),
        "seed": (120, 100, 40), "seed_dark": (95, 78, 28),
    },
    # Vine
    {
        "id": "grape", "name": "葡萄", "form": "vine",
        "stem": (75, 95, 55), "stem_dark": (52, 68, 38),
        "leaf": (65, 135, 52), "leaf_dark": (45, 100, 38), "leaf_light": (90, 170, 72),
        "fruit": (125, 55, 165), "fruit_dark": (95, 35, 130), "fruit_light": (160, 90, 200),
        "seed": (100, 80, 60), "seed_dark": (75, 58, 42),
    },
]

SIZE = 1024


def make_noise_texture(w, h, scale=1.0, seed=0):
    """Generate a smooth noise texture for painterly variation."""
    rng = np.random.RandomState(seed)
    # Low-res noise upscaled for smooth variation
    small_w = max(1, w // 8)
    small_h = max(1, h // 8)
    noise = rng.uniform(-1, 1, (small_h, small_w, 3)).astype(np.float32)
    # Upscale with bilinear interpolation
    from PIL import Image as PILImage
    noise_img = PILImage.fromarray(((noise + 1) * 127.5).astype(np.uint8), 'RGB')
    noise_img = noise_img.resize((w, h), PILImage.BILINEAR)
    arr = np.array(noise_img, dtype=np.float32) / 255.0
    # Center around 0, scale for subtle effect
    arr = (arr - 0.5) * 2 * scale
    return arr


def apply_painterly_texture(img, intensity=0.08, seed=0):
    """Apply subtle noise to mimic hand-painted color variation."""
    w, h = img.size
    noise = make_noise_texture(w, h, intensity, seed)
    arr = np.array(img, dtype=np.float32)
    mask = arr[:, :, 3] > 0  # only modify non-transparent pixels
    for c in range(3):
        channel = arr[:, :, c].copy()
        channel[mask] = np.clip(channel[mask] + noise[:, :, c][mask] * 255, 0, 255)
        arr[:, :, c] = channel
    return Image.fromarray(arr.astype(np.uint8), 'RGBA')


def lerp_color(c1, c2, t):
    """Linearly interpolate between two RGB colors."""
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


def draw_organic_shape(draw, center_x, center_y, base_radius, color, num_points=12,
                       irregularity=0.25, alpha=255, seed=0):
    """Draw an irregular organic blob shape (like a painted leaf or fruit)."""
    rng = random.Random(seed)
    points = []
    for i in range(num_points):
        angle = 2 * math.pi * i / num_points
        r = base_radius * (1.0 + rng.uniform(-irregularity, irregularity))
        x = center_x + r * math.cos(angle)
        y = center_y + r * math.sin(angle)
        points.append((x, y))
    # Smooth the polygon with spline-like intermediate points
    smooth_points = []
    for i in range(len(points)):
        p0 = points[(i - 1) % len(points)]
        p1 = points[i]
        p2 = points[(i + 1) % len(points)]
        # Midpoints with control-point influence
        for t in [0.0, 0.33, 0.67]:
            mx = p0[0] * (1 - t) * (1 - t) * 0.25 + p1[0] * (0.5 + t * 0.5) + p2[0] * t * t * 0.25
            my = p0[1] * (1 - t) * (1 - t) * 0.25 + p1[1] * (0.5 + t * 0.5) + p2[1] * t * t * 0.25
            smooth_points.append((mx, my))
    fill_color = color + (alpha,) if len(color) == 3 else color
    draw.polygon(smooth_points, fill=fill_color)


def draw_leaf(draw, tip_x, tip_y, length, width, angle, color, color_dark, seed=0):
    """Draw a leaf shape with a midrib and organic outline."""
    rng = random.Random(seed)
    # Leaf extends from base to tip
    base_x = tip_x - length * math.cos(angle)
    base_y = tip_y - length * math.sin(angle)
    mid_x = (base_x + tip_x) / 2
    mid_y = (base_y + tip_y) / 2
    # Perpendicular direction for width
    perp_angle = angle + math.pi / 2
    hw = width / 2
    # Leaf outline points
    points = [
        (base_x, base_y),
        (mid_x + hw * math.cos(perp_angle) * (1 + rng.uniform(-0.1, 0.1)),
         mid_y + hw * math.sin(perp_angle) * (1 + rng.uniform(-0.1, 0.1))),
        (tip_x + hw * 0.15 * math.cos(perp_angle), tip_y + hw * 0.15 * math.sin(perp_angle)),
        (tip_x, tip_y),
        (tip_x - hw * 0.15 * math.cos(perp_angle), tip_y - hw * 0.15 * math.sin(perp_angle)),
        (mid_x - hw * math.cos(perp_angle) * (1 + rng.uniform(-0.1, 0.1)),
         mid_y - hw * math.sin(perp_angle) * (1 + rng.uniform(-0.1, 0.1))),
    ]
    fill_color = color + (255,) if len(color) == 3 else color
    draw.polygon(points, fill=fill_color)
    # Midrib (dark line down the center)
    rib_color = color_dark + (200,) if len(color_dark) == 3 else color_dark
    draw.line([(base_x, base_y), (tip_x, tip_y)], fill=rib_color, width=max(2, int(width * 0.08)))


def draw_stem_segment(draw, x0, y0, x1, y1, thickness, color, color_dark, seed=0):
    """Draw a stem with a slightly irregular width and center vein."""
    rng = random.Random(seed)
    dx = x1 - x0
    dy = y1 - y0
    length = math.sqrt(dx * dx + dy * dy)
    if length < 1:
        return
    # Perpendicular direction
    nx = -dy / length
    ny = dx / length
    # Draw stem as a polygon
    t = thickness / 2
    points = [
        (x0 + nx * t * (1 + rng.uniform(-0.1, 0.1)), y0 + ny * t * (1 + rng.uniform(-0.1, 0.1))),
        (x1 + nx * t * 0.7 * (1 + rng.uniform(-0.1, 0.1)), y1 + ny * t * 0.7 * (1 + rng.uniform(-0.1, 0.1))),
        (x1 - nx * t * 0.7 * (1 + rng.uniform(-0.1, 0.1)), y1 - ny * t * 0.7 * (1 + rng.uniform(-0.1, 0.1))),
        (x0 - nx * t * (1 + rng.uniform(-0.1, 0.1)), y0 - ny * t * (1 + rng.uniform(-0.1, 0.1))),
    ]
    fill_color = color + (255,) if len(color) == 3 else color
    draw.polygon(points, fill=fill_color)
    # Center highlight
    highlight = tuple(min(255, c + 25) for c in color[:3])
    hl_color = highlight + (100,) if len(highlight) == 3 else highlight
    mid_points = [((p[0] + q[0]) / 2, (p[1] + q[1]) / 2) for p, q in zip(points[:2], points[2:])]
    draw.line(mid_points, fill=hl_color, width=max(1, int(thickness * 0.2)))


def draw_fruit_sphere(draw, cx, cy, radius, color, color_dark, color_light, seed=0):
    """Draw a round fruit with a highlight for 3D depth."""
    rng = random.Random(seed)
    # Main body
    draw_organic_shape(draw, cx, cy, radius, color, 16, 0.12, 255, seed)
    # Shadow on lower-right
    shadow_cx = cx + radius * 0.2
    shadow_cy = cy + radius * 0.25
    draw_organic_shape(draw, shadow_cx, shadow_cy, radius * 0.7, color_dark, 12, 0.15, 160, seed + 1)
    # Highlight on upper-left
    hl_cx = cx - radius * 0.25
    hl_cy = cy - radius * 0.3
    hl_radius = radius * 0.35
    hl_color = color_light + (120,) if len(color_light) == 3 else color_light
    draw_organic_shape(draw, hl_cx, hl_cy, hl_radius, hl_color[:3], 10, 0.2, 120, seed + 2)


def draw_seed_cluster(draw, cx, cy, crop, variant, seed=0):
    """Stage 0: Small seeds scattered on ground."""
    rng = random.Random(seed)
    color = crop["seed"]
    color_dark = crop["seed_dark"]
    # 2-4 small seeds with organic shapes
    count = 2 + variant
    for i in range(count):
        ox = rng.randint(-50, 50)
        oy = rng.randint(-20, 20)
        r = 20 + variant * 5 + rng.randint(-5, 5)
        draw_organic_shape(draw, cx + ox, cy + oy, r, color, 8, 0.3, 255, seed + i * 7)
        # Tiny highlight
        hl_c = tuple(min(255, c + 40) for c in color)
        draw_organic_shape(draw, cx + ox - r * 0.2, cy + oy - r * 0.25, r * 0.3, hl_c, 6, 0.3, 150, seed + i * 7 + 1)


def draw_sprout_common(draw, cx, base_y, top_y, crop, variant, seed=0):
    """Stage 1: Small sprout with stem and tiny leaves."""
    rng = random.Random(seed)
    stem_c = crop["stem"]
    stem_d = crop["stem_dark"]
    leaf_c = crop["leaf"]
    leaf_d = crop["leaf_dark"]
    # Main stem
    sway = rng.uniform(-15, 15)
    draw_stem_segment(draw, cx, base_y, cx + sway, top_y, 8, stem_c, stem_d, seed)
    # Cotyledon leaves (first two small leaves)
    leaf_len = 55 + variant * 10
    leaf_w = 22 + variant * 5
    draw_leaf(draw, cx + sway - 20, top_y + 40, leaf_len, leaf_w,
              math.pi * 0.6 + rng.uniform(-0.1, 0.1), leaf_c, leaf_d, seed + 1)
    draw_leaf(draw, cx + sway + 20, top_y + 55, leaf_len, leaf_w,
              math.pi * 0.4 + rng.uniform(-0.1, 0.1), leaf_c, leaf_d, seed + 2)


def draw_growing_annual(draw, cx, base_y, top_y, crop, variant, seed=0):
    """Stage 2: Medium annual plant with more leaves."""
    rng = random.Random(seed)
    stem_c = crop["stem"]
    stem_d = crop["stem_dark"]
    leaf_c = crop["leaf"]
    leaf_d = crop["leaf_dark"]
    # Main stem
    sway = rng.uniform(-10, 10)
    draw_stem_segment(draw, cx, base_y, cx + sway, top_y, 10, stem_c, stem_d, seed)
    # Side branches
    for i, (bx, by, angle) in enumerate([
        (-35, 120, 0.55), (30, 80, 0.4), (-25, 60, 0.6), (20, 40, 0.35)
    ]):
        leaf_len = 50 + variant * 8
        leaf_w = 25 + variant * 4
        draw_leaf(draw, cx + sway + bx, top_y + by, leaf_len, leaf_w,
                  math.pi * angle + rng.uniform(-0.08, 0.08), leaf_c, leaf_d, seed + i + 10)


def draw_mature_annual_root(draw, cx, base_y, crop, variant, seed=0):
    """Stage 3: Root vegetable with visible root."""
    rng = random.Random(seed)
    stem_c = crop["stem"]
    stem_d = crop["stem_dark"]
    leaf_c = crop["leaf"]
    leaf_d = crop["leaf_dark"]
    fruit_c = crop["fruit"]
    fruit_d = crop["fruit_dark"]
    fruit_l = crop["fruit_light"]
    top_y = 380
    # Foliage above ground
    draw_stem_segment(draw, cx, base_y - 50, cx, top_y, 8, stem_c, stem_d, seed)
    # Bushy leaf cluster
    for i in range(5 + variant):
        angle = math.pi * 0.3 + i * math.pi * 0.12 + rng.uniform(-0.1, 0.1)
        leaf_len = 70 + variant * 8
        leaf_w = 18 + variant * 3
        draw_leaf(draw, cx, top_y + rng.randint(10, 60), leaf_len, leaf_w,
                  angle, leaf_c, leaf_d, seed + i + 20)
    # Root below ground (the actual vegetable)
    root_top = base_y - 40
    root_height = 150 + variant * 20
    # Carrot: tapered cone shape
    points = [
        (cx - 30 - variant * 5, root_top),
        (cx + 30 + variant * 5, root_top),
        (cx + 5, root_top + root_height),
        (cx - 5, root_top + root_height),
    ]
    fill_color = fruit_c + (255,) if len(fruit_c) == 3 else fruit_c
    draw.polygon(points, fill=fill_color)
    # Highlight stripe
    hl_color = fruit_l + (120,) if len(fruit_l) == 3 else fruit_l
    hl_points = [
        (cx - 10, root_top + 10),
        (cx + 5, root_top + 10),
        (cx + 2, root_top + root_height - 20),
        (cx - 5, root_top + root_height - 20),
    ]
    draw.polygon(hl_points, fill=hl_color)


def draw_mature_annual_berry(draw, cx, base_y, crop, variant, seed=0):
    """Stage 3: Berry plant with round fruit clusters."""
    rng = random.Random(seed)
    stem_c = crop["stem"]
    stem_d = crop["stem_dark"]
    leaf_c = crop["leaf"]
    leaf_d = crop["leaf_dark"]
    fruit_c = crop["fruit"]
    fruit_d = crop["fruit_dark"]
    fruit_l = crop["fruit_light"]
    top_y = 350
    # Main stem
    draw_stem_segment(draw, cx, base_y, cx, top_y, 10, stem_c, stem_d, seed)
    # Side branches with leaves
    for i, (bx, by) in enumerate([(-40, 150), (45, 100), (-30, 60)]):
        draw_leaf(draw, cx + bx, top_y + by, 65 + variant * 8, 28 + variant * 4,
                  math.pi * (0.55 if bx < 0 else 0.45), leaf_c, leaf_d, seed + i + 20)
    # Fruit clusters
    fruit_positions = [
        (cx - 25, top_y + 90, 22 + variant * 3),
        (cx + 30, top_y + 70, 20 + variant * 3),
        (cx + 5, top_y + 50, 18 + variant * 2),
        (cx - 15, top_y + 120, 16 + variant * 2),
    ]
    for i, (fx, fy, fr) in enumerate(fruit_positions):
        draw_fruit_sphere(draw, fx, fy, fr, fruit_c, fruit_d, fruit_l, seed + i * 5 + 30)


def draw_mature_annual_large(draw, cx, base_y, crop, variant, seed=0):
    """Stage 3: Large ground fruit (watermelon/pumpkin)."""
    rng = random.Random(seed)
    stem_c = crop["stem"]
    stem_d = crop["stem_dark"]
    leaf_c = crop["leaf"]
    leaf_d = crop["leaf_dark"]
    fruit_c = crop["fruit"]
    fruit_d = crop["fruit_dark"]
    fruit_l = crop["fruit_light"]
    # Spreading vine stems
    for vx in range(-100, 120, 60):
        draw_stem_segment(draw, cx + vx, base_y, cx + vx * 0.5, base_y - 120,
                         7, stem_c, stem_d, seed + vx)
    # Leaves along vine
    for i in range(4 + variant):
        lx = cx + rng.randint(-120, 120)
        ly = base_y - rng.randint(60, 150)
        draw_leaf(draw, lx, ly, 70 + variant * 10, 35 + variant * 5,
                  rng.uniform(0.2, 0.8) * math.pi, leaf_c, leaf_d, seed + i + 100)
    # Large fruit on ground
    fruit_cx = cx + rng.randint(-20, 20)
    fruit_cy = base_y - 60
    rx = 85 + variant * 12
    ry = 65 + variant * 8
    # Draw as an organic ellipse
    points = []
    for i in range(20):
        angle = 2 * math.pi * i / 20
        x = fruit_cx + rx * math.cos(angle) * (1 + rng.uniform(-0.05, 0.05))
        y = fruit_cy + ry * math.sin(angle) * (1 + rng.uniform(-0.05, 0.05))
        points.append((x, y))
    fill_color = fruit_c + (255,) if len(fruit_c) == 3 else fruit_c
    draw.polygon(points, fill=fill_color)
    # Highlight
    hl_color = fruit_l + (100,) if len(fruit_l) == 3 else fruit_l
    draw_organic_shape(draw, fruit_cx - rx * 0.2, fruit_cy - ry * 0.25,
                      min(rx, ry) * 0.3, hl_color[:3], 10, 0.2, 100, seed + 50)
    # Stripes for watermelon
    if crop["id"] == "watermelon":
        stripe_c = (35, 140, 35, 120)
        for sx in range(-2, 3):
            stripe_x = fruit_cx + sx * rx * 0.25
            draw.line([(stripe_x, fruit_cy - ry * 0.8), (stripe_x + 5, fruit_cy + ry * 0.8)],
                     fill=stripe_c, width=4)
    # Segments for pumpkin
    elif crop["id"] == "pumpkin":
        seg_c = fruit_d + (80,) if len(fruit_d) == 3 else fruit_d
        for sx in [-0.5, 0, 0.5]:
            stripe_x = fruit_cx + sx * rx
            draw.line([(stripe_x, fruit_cy - ry * 0.9), (stripe_x, fruit_cy + ry * 0.9)],
                     fill=seg_c, width=3)
        # Stem on top
        draw_stem_segment(draw, fruit_cx, fruit_cy - ry, fruit_cx + 5, fruit_cy - ry - 35,
                         6, stem_c, stem_d, seed + 60)


def draw_mature_bush(draw, cx, base_y, crop, variant, seed=0):
    """Stage 3: Low bush with berries."""
    rng = random.Random(seed)
    stem_c = crop["stem"]
    stem_d = crop["stem_dark"]
    leaf_c = crop["leaf"]
    leaf_d = crop["leaf_dark"]
    fruit_c = crop["fruit"]
    fruit_d = crop["fruit_dark"]
    fruit_l = crop["fruit_light"]
    # Multiple stems from base
    for i in range(3 + variant):
        sx = cx + (i - 1) * 40
        sway = rng.uniform(-15, 15)
        draw_stem_segment(draw, sx, base_y, sx + sway, base_y - 250 - variant * 20,
                         7, stem_c, stem_d, seed + i * 3)
    # Leaf canopy (multiple overlapping organic shapes)
    canopy_positions = [
        (cx, base_y - 350, 110 + variant * 10),
        (cx - 80, base_y - 300, 80 + variant * 8),
        (cx + 80, base_y - 310, 80 + variant * 8),
        (cx - 40, base_y - 380, 70 + variant * 6),
        (cx + 40, base_y - 370, 70 + variant * 6),
    ]
    for i, (lx, ly, lr) in enumerate(canopy_positions):
        draw_organic_shape(draw, lx, ly, lr, leaf_c, 14, 0.15, 255, seed + i * 11)
        # Darker inner shadow
        draw_organic_shape(draw, lx + 10, ly + 10, lr * 0.6, leaf_d, 10, 0.2, 100, seed + i * 11 + 1)
    # Berries scattered on bush
    berry_positions = [
        (cx - 60, base_y - 280, 12 + variant * 2),
        (cx + 55, base_y - 290, 11 + variant * 2),
        (cx - 20, base_y - 360, 13 + variant * 2),
        (cx + 30, base_y - 350, 10 + variant * 2),
        (cx, base_y - 320, 11 + variant * 2),
        (cx - 50, base_y - 340, 9 + variant * 1),
        (cx + 45, base_y - 310, 10 + variant * 2),
    ]
    for i, (bx, by, br) in enumerate(berry_positions):
        draw_fruit_sphere(draw, bx, by, br, fruit_c, fruit_d, fruit_l, seed + i * 7 + 50)


def draw_mature_tree(draw, cx, base_y, crop, variant, seed=0):
    """Stage 3: Full tree with trunk, canopy, and fruit."""
    rng = random.Random(seed)
    trunk_c = crop["stem"]
    trunk_d = crop["stem_dark"]
    leaf_c = crop["leaf"]
    leaf_d = crop["leaf_dark"]
    fruit_c = crop["fruit"]
    fruit_d = crop["fruit_dark"]
    fruit_l = crop["fruit_light"]
    trunk_top = base_y - 420 - variant * 15
    # Trunk (wider at base, tapered)
    trunk_base_w = 28 + variant * 3
    trunk_top_w = 16 + variant * 2
    trunk_points = [
        (cx - trunk_base_w, base_y),
        (cx + trunk_base_w, base_y),
        (cx + trunk_top_w, trunk_top),
        (cx - trunk_top_w, trunk_top),
    ]
    fill_color = trunk_c + (255,) if len(trunk_c) == 3 else trunk_c
    draw.polygon(trunk_points, fill=fill_color)
    # Bark texture lines
    for i in range(4):
        by = base_y - 80 * i - rng.randint(0, 30)
        draw.line([(cx - trunk_base_w + 5, by), (cx + trunk_base_w - 5, by + 15)],
                 fill=trunk_d + (80,), width=2)
    # Main branches
    branches = [
        (cx - trunk_top_w, trunk_top + 30, cx - 120 - variant * 10, trunk_top - 40),
        (cx + trunk_top_w, trunk_top + 20, cx + 130 + variant * 10, trunk_top - 50),
        (cx - trunk_top_w, trunk_top + 60, cx - 80, trunk_top + 20),
        (cx + trunk_top_w, trunk_top + 50, cx + 90, trunk_top + 10),
    ]
    for i, (bx0, by0, bx1, by1) in enumerate(branches):
        draw_stem_segment(draw, bx0, by0, bx1, by1, 10, trunk_c, trunk_d, seed + i * 5)
    # Canopy (large organic shapes)
    canopy_top = trunk_top - 100 - variant * 15
    canopy_positions = [
        (cx, canopy_top, 140 + variant * 12),
        (cx - 100, canopy_top + 60, 100 + variant * 10),
        (cx + 110, canopy_top + 50, 100 + variant * 10),
        (cx - 50, canopy_top - 40, 90 + variant * 8),
        (cx + 60, canopy_top - 30, 90 + variant * 8),
        (cx, canopy_top + 90, 110 + variant * 10),
    ]
    for i, (lx, ly, lr) in enumerate(canopy_positions):
        draw_organic_shape(draw, lx, ly, lr, leaf_c, 16, 0.12, 255, seed + i * 13)
        # Darker areas for depth
        draw_organic_shape(draw, lx + 15, ly + 20, lr * 0.5, leaf_d, 10, 0.2, 80, seed + i * 13 + 1)
    # Fruit hanging from branches
    fruit_positions = [
        (cx - 100, canopy_top + 100, 16 + variant * 2),
        (cx + 110, canopy_top + 90, 15 + variant * 2),
        (cx - 40, canopy_top + 70, 17 + variant * 2),
        (cx + 50, canopy_top + 60, 14 + variant * 2),
        (cx, canopy_top + 110, 16 + variant * 2),
        (cx - 70, canopy_top + 50, 13 + variant * 2),
    ]
    for i, (fx, fy, fr) in enumerate(fruit_positions):
        # Small stem connecting fruit to branch
        draw.line([(fx, fy - fr), (fx, fy - fr - 15)], fill=trunk_c + (180,), width=2)
        draw_fruit_sphere(draw, fx, fy, fr, fruit_c, fruit_d, fruit_l, seed + i * 9 + 70)


def draw_mature_vine(draw, cx, base_y, crop, variant, seed=0):
    """Stage 3: Grape vine with hanging fruit clusters."""
    rng = random.Random(seed)
    stem_c = crop["stem"]
    stem_d = crop["stem_dark"]
    leaf_c = crop["leaf"]
    leaf_d = crop["leaf_dark"]
    fruit_c = crop["fruit"]
    fruit_d = crop["fruit_dark"]
    fruit_l = crop["fruit_light"]
    # Horizontal support wire/branch
    wire_y = base_y - 550
    draw.line([(cx - 200, wire_y), (cx + 200, wire_y)], fill=(80, 60, 40, 200), width=5)
    # Main vine stems drooping from wire
    vine_drops = [cx - 100, cx - 30, cx + 40, cx + 110]
    for i, vx in enumerate(vine_drops):
        # Stem from wire downward with slight curve
        stem_end_y = wire_y + 80 + rng.randint(-10, 10)
        draw_stem_segment(draw, vx, wire_y, vx + rng.randint(-15, 15), stem_end_y,
                         6, stem_c, stem_d, seed + i * 7)
        # Leaf at stem end
        draw_leaf(draw, vx + rng.randint(-20, 20), stem_end_y, 55 + variant * 8, 30 + variant * 5,
                 rng.uniform(0.3, 0.7), leaf_c, leaf_d, seed + i * 7 + 3)
    # Hanging grape clusters
    cluster_positions = [cx - 80, cx - 10, cx + 60, cx + 130]
    for ci, cluster_x in enumerate(cluster_positions):
        cluster_top_y = wire_y + 40
        # Small stem to cluster
        draw.line([(cluster_x, wire_y), (cluster_x, cluster_top_y)],
                 fill=stem_c + (180,), width=2)
        # Triangular cluster of grapes
        grapes = []
        rows = 4 + variant
        for row in range(rows):
            count = row + 1
            for col in range(count):
                gx = cluster_x + (col - (count - 1) / 2) * (14 + variant)
                gy = cluster_top_y + row * (13 + variant)
                grapes.append((gx, gy, 9 + variant))
        for gi, (gx, gy, gr) in enumerate(grapes):
            draw_fruit_sphere(draw, int(gx), int(gy), gr, fruit_c, fruit_d, fruit_l,
                            seed + ci * 50 + gi * 3 + 100)


def draw_mature_flower_tall(draw, cx, base_y, crop, variant, seed=0):
    """Stage 3: Sunflower with large flower head."""
    rng = random.Random(seed)
    stem_c = crop["stem"]
    stem_d = crop["stem_dark"]
    leaf_c = crop["leaf"]
    leaf_d = crop["leaf_dark"]
    fruit_c = crop["fruit"]
    fruit_d = crop["fruit_dark"]
    fruit_l = crop["fruit_light"]
    top_y = base_y - 650 - variant * 15
    # Tall thick stem
    draw_stem_segment(draw, cx, base_y, cx + rng.uniform(-10, 10), top_y + 80,
                     12, stem_c, stem_d, seed)
    # Leaves along stem
    for i, (ly, side) in enumerate([(200, -1), (350, 1), (500, -1)]):
        draw_leaf(draw, cx + side * 40, base_y - ly, 80 + variant * 10, 35 + variant * 5,
                 math.pi * (0.6 if side < 0 else 0.4), leaf_c, leaf_d, seed + i + 20)
    # Large flower head
    head_cx = cx + rng.uniform(-5, 5)
    head_cy = top_y + 50
    head_r = 80 + variant * 8
    # Petals (radiating from center)
    petal_count = 14 + variant * 2
    for i in range(petal_count):
        angle = 2 * math.pi * i / petal_count + rng.uniform(-0.1, 0.1)
        petal_len = head_r + 30 + variant * 5
        px = head_cx + math.cos(angle) * petal_len
        py = head_cy + math.sin(angle) * petal_len
        # Draw each petal as an organic ellipse
        petal_w = 18 + variant * 2
        points = []
        for j in range(10):
            t = 2 * math.pi * j / 10
            ex = px + petal_w * 0.4 * math.cos(angle + t * 0.3) * math.cos(t)
            ey = py + petal_w * 0.4 * math.cos(angle + t * 0.3) * math.sin(t)
            # Elongate along the radial direction
            ex += math.cos(angle) * petal_w * 0.6 * math.cos(t)
            ey += math.sin(angle) * petal_w * 0.6 * math.cos(t)
            points.append((ex, ey))
        fill_color = fruit_c + (255,) if len(fruit_c) == 3 else fruit_c
        draw.polygon(points, fill=fill_color)
    # Dark center
    center_c = (60, 45, 25)
    center_cd = (40, 30, 15)
    draw_organic_shape(draw, head_cx, head_cy, head_r * 0.45, center_c, 14, 0.1, 255, seed + 80)
    # Seed pattern dots on center
    for i in range(20):
        dot_angle = rng.uniform(0, 2 * math.pi)
        dot_r = rng.uniform(5, head_r * 0.35)
        dx = head_cx + math.cos(dot_angle) * dot_r
        dy = head_cy + math.sin(dot_angle) * dot_r
        draw.ellipse([(dx - 3, dy - 3), (dx + 3, dy + 3)], fill=center_cd + (150,))


def draw_mature_flower_spike(draw, cx, base_y, crop, variant, seed=0):
    """Stage 3: Lavender with flower spikes."""
    rng = random.Random(seed)
    stem_c = crop["stem"]
    stem_d = crop["stem_dark"]
    leaf_c = crop["leaf"]
    leaf_d = crop["leaf_dark"]
    fruit_c = crop["fruit"]
    fruit_d = crop["fruit_dark"]
    fruit_l = crop["fruit_light"]
    # Multiple stems with flower spikes
    num_stems = 3 + variant
    for i in range(num_stems):
        sx = cx + (i - num_stems // 2) * 35
        sway = rng.uniform(-20, 20)
        top_y = base_y - 500 - variant * 20 - i * 30
        draw_stem_segment(draw, sx, base_y, sx + sway, top_y, 6, stem_c, stem_d, seed + i * 5)
        # Leaves
        for j in range(2):
            ly = base_y - 150 - j * 120
            side = -1 if j % 2 == 0 else 1
            draw_leaf(draw, sx + side * 25 + sway * 0.3, ly, 50 + variant * 8, 15 + variant * 3,
                     math.pi * (0.6 if side < 0 else 0.4), leaf_c, leaf_d, seed + i * 5 + j + 10)
        # Flower spike (cluster of small buds)
        spike_len = 100 + variant * 15
        for j in range(8 + variant * 2):
            by = top_y + 10 + j * (spike_len / (8 + variant * 2))
            br = 12 + variant * 2 + rng.uniform(-2, 2)
            draw_organic_shape(draw, sx + sway + rng.uniform(-5, 5), by, br,
                             fruit_c, 8, 0.2, 255, seed + i * 5 + j * 3 + 30)


def draw_mature_flower_round(draw, cx, base_y, crop, variant, seed=0):
    """Stage 3: Rose with layered petals."""
    rng = random.Random(seed)
    stem_c = crop["stem"]
    stem_d = crop["stem_dark"]
    leaf_c = crop["leaf"]
    leaf_d = crop["leaf_dark"]
    fruit_c = crop["fruit"]
    fruit_d = crop["fruit_dark"]
    fruit_l = crop["fruit_light"]
    top_y = base_y - 550 - variant * 15
    # Stem with thorns
    draw_stem_segment(draw, cx, base_y, cx + rng.uniform(-8, 8), top_y + 60,
                     8, stem_c, stem_d, seed)
    # Thorns
    for i in range(3):
        ty = base_y - 100 - i * 150
        side = 1 if i % 2 == 0 else -1
        draw.polygon([
            (cx + side * 4, ty),
            (cx + side * 18, ty - 8),
            (cx + side * 4, ty - 3),
        ], fill=stem_d + (200,))
    # Leaves
    for i, (ly, side) in enumerate([(180, -1), (350, 1)]):
        draw_leaf(draw, cx + side * 35, base_y - ly, 60 + variant * 8, 30 + variant * 4,
                 math.pi * (0.55 if side < 0 else 0.45), leaf_c, leaf_d, seed + i + 20)
    # Rose bloom - layered petals
    bloom_cx = cx + rng.uniform(-5, 5)
    bloom_cy = top_y + 45
    bloom_r = 55 + variant * 8
    # Outer petals (larger, slightly darker)
    for i in range(6):
        angle = 2 * math.pi * i / 6 + rng.uniform(-0.15, 0.15)
        px = bloom_cx + math.cos(angle) * bloom_r * 0.6
        py = bloom_cy + math.sin(angle) * bloom_r * 0.6
        draw_organic_shape(draw, px, py, bloom_r * 0.5, fruit_d, 10, 0.2, 230, seed + i * 7 + 40)
    # Inner petals (brighter)
    for i in range(5):
        angle = 2 * math.pi * i / 5 + math.pi / 5 + rng.uniform(-0.15, 0.15)
        px = bloom_cx + math.cos(angle) * bloom_r * 0.3
        py = bloom_cy + math.sin(angle) * bloom_r * 0.3
        draw_organic_shape(draw, px, py, bloom_r * 0.4, fruit_c, 8, 0.2, 255, seed + i * 7 + 50)
    # Center (lightest)
    draw_organic_shape(draw, bloom_cx, bloom_cy, bloom_r * 0.2, fruit_l, 6, 0.25, 255, seed + 60)


def draw_growing_tree(draw, cx, base_y, crop, variant, seed=0):
    """Stage 2: Young tree with small canopy."""
    rng = random.Random(seed)
    trunk_c = crop["stem"]
    trunk_d = crop["stem_dark"]
    leaf_c = crop["leaf"]
    leaf_d = crop["leaf_dark"]
    fruit_c = crop["fruit"]
    trunk_top = base_y - 320 - variant * 15
    # Thin trunk
    trunk_w = 14 + variant * 2
    trunk_points = [
        (cx - trunk_w, base_y),
        (cx + trunk_w, base_y),
        (cx + trunk_w * 0.6, trunk_top),
        (cx - trunk_w * 0.6, trunk_top),
    ]
    fill_color = trunk_c + (255,) if len(trunk_c) == 3 else trunk_c
    draw.polygon(trunk_points, fill=fill_color)
    # Small branches
    draw_stem_segment(draw, cx - trunk_w * 0.5, trunk_top + 30, cx - 60, trunk_top - 10,
                     6, trunk_c, trunk_d, seed + 1)
    draw_stem_segment(draw, cx + trunk_w * 0.5, trunk_top + 20, cx + 65, trunk_top - 15,
                     6, trunk_c, trunk_d, seed + 2)
    # Small canopy
    for lx, ly, lr in [(cx, trunk_top - 30, 80 + variant * 8), (cx - 50, trunk_top + 10, 55),
                        (cx + 55, trunk_top, 55), (cx, trunk_top - 60, 45)]:
        draw_organic_shape(draw, lx, ly, lr, leaf_c, 12, 0.15, 255, seed + lx)
    # Tiny fruit buds
    for i in range(2 + variant):
        fx = cx + rng.randint(-40, 40)
        fy = trunk_top + rng.randint(-30, 20)
        draw_organic_shape(draw, fx, fy, 8, fruit_c, 6, 0.3, 200, seed + i + 30)


def draw_growing_bush(draw, cx, base_y, crop, variant, seed=0):
    """Stage 2: Growing bush with some leaves."""
    rng = random.Random(seed)
    stem_c = crop["stem"]
    stem_d = crop["stem_dark"]
    leaf_c = crop["leaf"]
    leaf_d = crop["leaf_dark"]
    fruit_c = crop["fruit"]
    # Stems
    for i in range(2 + variant):
        sx = cx + (i - 1) * 30
        draw_stem_segment(draw, sx, base_y, sx + rng.uniform(-10, 10), base_y - 200 - variant * 15,
                         6, stem_c, stem_d, seed + i * 3)
    # Leaf clusters
    for lx, ly, lr in [(cx, base_y - 250, 70 + variant * 8), (cx - 50, base_y - 210, 50),
                        (cx + 55, base_y - 220, 50)]:
        draw_organic_shape(draw, lx, ly, lr, leaf_c, 10, 0.18, 255, seed + lx + 5)
    # Small fruit buds
    for i in range(2):
        fx = cx + rng.randint(-30, 30)
        fy = base_y - 200 + rng.randint(-20, 20)
        draw_organic_shape(draw, fx, fy, 8, fruit_c, 6, 0.3, 180, seed + i + 30)


def draw_growing_vine(draw, cx, base_y, crop, variant, seed=0):
    """Stage 2: Growing vine with tendrils."""
    rng = random.Random(seed)
    stem_c = crop["stem"]
    stem_d = crop["stem_dark"]
    leaf_c = crop["leaf"]
    leaf_d = crop["leaf_dark"]
    fruit_c = crop["fruit"]
    # Horizontal wire
    wire_y = base_y - 450
    draw.line([(cx - 150, wire_y), (cx + 150, wire_y)], fill=(80, 60, 40, 180), width=4)
    # Vine stems
    for vx in [cx - 60, cx + 60]:
        draw_stem_segment(draw, vx, wire_y, vx + rng.uniform(-15, 15), wire_y + 50,
                         5, stem_c, stem_d, seed + vx)
        draw_leaf(draw, vx, wire_y + 50, 45 + variant * 8, 25 + variant * 3,
                 rng.uniform(0.3, 0.7), leaf_c, leaf_d, seed + vx + 3)
    # Small fruit buds
    for i in range(2 + variant):
        fx = cx + rng.randint(-80, 80)
        fy = wire_y + 30 + rng.randint(-10, 20)
        draw_organic_shape(draw, fx, fy, 6, fruit_c, 6, 0.3, 150, seed + i + 40)


def draw_growing_flower(draw, cx, base_y, crop, variant, seed=0):
    """Stage 2: Growing flower with bud."""
    rng = random.Random(seed)
    stem_c = crop["stem"]
    stem_d = crop["stem_dark"]
    leaf_c = crop["leaf"]
    leaf_d = crop["leaf_dark"]
    fruit_c = crop["fruit"]
    top_y = base_y - 400 - variant * 15
    # Stem
    draw_stem_segment(draw, cx, base_y, cx + rng.uniform(-8, 8), top_y, 7, stem_c, stem_d, seed)
    # Leaves
    for i, (ly, side) in enumerate([(120, -1), (220, 1)]):
        draw_leaf(draw, cx + side * 30, base_y - ly, 55 + variant * 8, 25 + variant * 4,
                 math.pi * (0.55 if side < 0 else 0.45), leaf_c, leaf_d, seed + i + 10)
    # Flower bud (closed)
    bud_r = 25 + variant * 5
    draw_organic_shape(draw, cx, top_y, bud_r, fruit_c, 8, 0.2, 255, seed + 30)
    # Sepals (green outer leaves of bud)
    for i in range(3):
        angle = 2 * math.pi * i / 3 + rng.uniform(-0.1, 0.1)
        sx = cx + math.cos(angle) * bud_r * 0.8
        sy = top_y + bud_r * 0.5
        draw_leaf(draw, sx, sy, 20, 8, angle, leaf_c, leaf_d, seed + i + 40)


# Layer splitting: back = upper/rear portion, front = lower/front portion
# For side-view painted sprites, the back layer is what's behind the player,
# the front layer is what's in front. We split the image vertically.

def split_into_layers(img, split_y_ratio=0.6):
    """Split image into back and front layers.

    Back layer: top portion (behind player)
    Front layer: bottom portion (in front of player)
    The split point is at split_y_ratio of the image height.
    """
    w, h = img.size
    split_y = int(h * split_y_ratio)

    # Back layer: full image with bottom portion faded
    back = img.copy()
    back_arr = np.array(back)
    # Gradually fade bottom 30% of the image for smooth layering
    fade_start = split_y
    fade_end = h
    for y in range(fade_start, fade_end):
        alpha = max(0, int(255 * (1.0 - (y - fade_start) / max(1, fade_end - fade_start)) ** 0.8))
        back_arr[y, :, 3] = np.minimum(back_arr[y, :, 3], alpha)
    back = Image.fromarray(back_arr, 'RGBA')

    # Front layer: full image with top portion faded
    front = img.copy()
    front_arr = np.array(front)
    fade_end_front = split_y
    fade_start_front = max(0, fade_end_front - int(h * 0.15))
    for y in range(0, fade_end_front):
        if y < fade_start_front:
            front_arr[y, :, 3] = 0
        else:
            alpha = int(255 * ((y - fade_start_front) / max(1, fade_end_front - fade_start_front)) ** 0.8)
            front_arr[y, :, 3] = np.minimum(front_arr[y, :, 3], alpha)
    front = Image.fromarray(front_arr, 'RGBA')

    # Darken back layer slightly for depth
    back_arr = np.array(back, dtype=np.float32)
    back_arr[:, :, :3] *= 0.88
    back = Image.fromarray(back_arr.astype(np.uint8), 'RGBA')

    return back, front


def generate_full_image(crop, stage, variant, seed_offset):
    """Generate the complete crop image before splitting into layers."""
    random.seed(RNG_SEED + variant * 1000 + stage * 100 + seed_offset)
    img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    cx = 512  # center x
    base_y = 850  # ground level
    form = crop["form"]

    if stage == 0:
        # Seed stage: small seeds on ground
        cy = 750 + variant * 25
        draw_seed_cluster(draw, cx, cy, crop, variant, RNG_SEED + seed_offset)

    elif stage == 1:
        # Sprout stage: small green shoot
        top_y = 580 - variant * 20
        draw_sprout_common(draw, cx, base_y, top_y, crop, variant, RNG_SEED + seed_offset)

    elif stage == 2:
        # Growing stage: varies by form
        if form == "tree":
            draw_growing_tree(draw, cx, base_y, crop, variant, RNG_SEED + seed_offset)
        elif form == "bush":
            draw_growing_bush(draw, cx, base_y, crop, variant, RNG_SEED + seed_offset)
        elif form == "vine":
            draw_growing_vine(draw, cx, base_y, crop, variant, RNG_SEED + seed_offset)
        elif form.startswith("flower"):
            draw_growing_flower(draw, cx, base_y, crop, variant, RNG_SEED + seed_offset)
        else:
            # Annual growing
            top_y = 380 - variant * 15
            draw_growing_annual(draw, cx, base_y, top_y, crop, variant, RNG_SEED + seed_offset)
            # Add small fruit buds for berry/large types
            if form == "annual_berry":
                for i in range(2):
                    fx = cx + random.randint(-30, 30)
                    fy = 420 + random.randint(-20, 20)
                    draw_organic_shape(draw, fx, fy, 10, crop["fruit"], 6, 0.3, 180,
                                     RNG_SEED + seed_offset + i + 30)
            elif form == "annual_large":
                draw_organic_shape(draw, cx, base_y - 50, 25 + variant * 5, crop["fruit"],
                                 8, 0.2, 180, RNG_SEED + seed_offset + 30)

    elif stage == 3:
        # Mature stage: full grown, varies by form
        if form == "annual_root":
            draw_mature_annual_root(draw, cx, base_y, crop, variant, RNG_SEED + seed_offset)
        elif form == "annual_berry":
            draw_mature_annual_berry(draw, cx, base_y, crop, variant, RNG_SEED + seed_offset)
        elif form == "annual_large":
            draw_mature_annual_large(draw, cx, base_y, crop, variant, RNG_SEED + seed_offset)
        elif form == "bush":
            draw_mature_bush(draw, cx, base_y, crop, variant, RNG_SEED + seed_offset)
        elif form == "tree":
            draw_mature_tree(draw, cx, base_y, crop, variant, RNG_SEED + seed_offset)
        elif form == "vine":
            draw_mature_vine(draw, cx, base_y, crop, variant, RNG_SEED + seed_offset)
        elif form == "flower_tall":
            draw_mature_flower_tall(draw, cx, base_y, crop, variant, RNG_SEED + seed_offset)
        elif form == "flower_spike":
            draw_mature_flower_spike(draw, cx, base_y, crop, variant, RNG_SEED + seed_offset)
        elif form == "flower_round":
            draw_mature_flower_round(draw, cx, base_y, crop, variant, RNG_SEED + seed_offset)

    # Apply painterly noise texture
    img = apply_painterly_texture(img, intensity=0.06, seed=RNG_SEED + variant * 100 + stage * 10 + seed_offset)

    # Slight blur for soft painted edges
    img = img.filter(ImageFilter.SMOOTH)

    return img


def main():
    base_dir = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "crops")
    base_dir = os.path.normpath(base_dir)

    total = 0
    for crop in CROPS:
        crop_id = crop["id"]
        crop_seed = hash(crop_id) % 10000
        for stage in range(4):
            for variant in range(3):
                # Generate full image
                full_img = generate_full_image(crop, stage, variant, crop_seed)
                # Split into back and front layers
                back_img, front_img = split_into_layers(full_img)
                # Save both layers
                for layer_name, layer_img in [("back", back_img), ("front", front_img)]:
                    path = os.path.join(
                        base_dir, crop_id, "painted",
                        f"stage_{stage}", f"variant_{variant}_{layer_name}.png"
                    )
                    os.makedirs(os.path.dirname(path), exist_ok=True)
                    layer_img.save(path, 'PNG')
                    total += 1
        print(f"  Generated 24 textures for {crop_id} ({crop['name']})")

    print(f"\nDone! Generated {total} hand-painted style crop textures.")


if __name__ == "__main__":
    main()
