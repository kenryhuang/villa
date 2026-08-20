#!/usr/bin/env python3
"""Generate hand-painted crop textures for all 14 non-grain crops.

Produces 14 crops × 4 stages × 3 variants × 2 layers = 336 PNGs (1024×1024, RGBA).

Uses two modes:
  1. 'pil' (default): Enhanced PIL-based generation with brush simulation,
     natural lighting, organic shapes, and canvas texture. No API key needed.
  2. 'ai': AI image generation via image_gen.py + chroma-key removal.
     Requires OPENAI_API_KEY. Produces the highest quality matching grain style.

Usage:
    # PIL mode (no API key needed):
    python scripts/tools/generate_crop_assets.py pil

    # AI mode (requires OPENAI_API_KEY):
    python scripts/tools/generate_crop_assets.py ai
"""

import argparse
import json
import math
import os
import random
import subprocess
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFilter, ImageChops
    import numpy as np
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

# ── Paths ──────────────────────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parent.parent
ASSETS_DIR = PROJECT_DIR / "assets" / "crops"
TREE_REF = PROJECT_DIR / "assets" / "vegetation" / "tree-oak-large.png"
TMP_DIR = PROJECT_DIR / "tmp" / "crop_gen"
RAW_DIR = TMP_DIR / "raw"
BATCH_FILE = TMP_DIR / "crop_gen_batch.jsonl"

CODEX_HOME = Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex")))
IMAGE_GEN = CODEX_HOME / "skills" / ".system" / "imagegen" / "scripts" / "image_gen.py"
CHROMA_KEY = CODEX_HOME / "skills" / ".system" / "imagegen" / "scripts" / "remove_chroma_key.py"

SIZE = 1024
RNG_SEED = 42


# ═══════════════════════════════════════════════════════════════════════════
#  CROP DEFINITIONS
# ═══════════════════════════════════════════════════════════════════════════

CROPS = [
    {"id": "carrot",   "name_en": "carrot",   "name_zh": "胡萝卜",  "form": "annual_root"},
    {"id": "potato",   "name_en": "potato",   "name_zh": "土豆",    "form": "annual_root"},
    {"id": "tomato",   "name_en": "tomato",   "name_zh": "番茄",    "form": "annual_berry"},
    {"id": "watermelon","name_en":"watermelon","name_zh": "西瓜",    "form": "annual_large"},
    {"id": "pumpkin",  "name_en": "pumpkin",  "name_zh": "南瓜",    "form": "annual_large"},
    {"id": "strawberry","name_en": "strawberry","name_zh": "草莓",   "form": "bush"},
    {"id": "blueberry","name_en": "blueberry", "name_zh": "蓝莓",   "form": "bush"},
    {"id": "sunflower","name_en": "sunflower", "name_zh": "向日葵",  "form": "flower_tall"},
    {"id": "lavender", "name_en": "lavender",  "name_zh": "薰衣草",  "form": "flower_spike"},
    {"id": "rose",     "name_en": "rose",     "name_zh": "玫瑰",    "form": "flower_round"},
    {"id": "apple",    "name_en": "apple",    "name_zh": "苹果",    "form": "tree"},
    {"id": "peach",    "name_en": "peach",    "name_zh": "桃子",    "form": "tree"},
    {"id": "lemon",    "name_en": "lemon",    "name_zh": "柠檬",    "form": "tree"},
    {"id": "grape",    "name_en": "grape",    "name_zh": "葡萄",    "form": "vine"},
]

# Muted natural palettes per crop — never neon, always harmonized with tree art
PALETTES = {
    "carrot":      {"stem": (62,138,50),  "leaf": (52,148,42),  "fruit": (218,128,32), "seed": (138,88,42)},
    "potato":      {"stem": (68,142,55),  "leaf": (72,158,52),  "fruit": (182,148,88), "seed": (118,82,48)},
    "tomato":      {"stem": (58,132,48),  "leaf": (55,158,38),  "fruit": (198,52,38),  "seed": (155,145,125)},
    "watermelon":  {"stem": (48,122,38),  "leaf": (52,148,48),  "fruit": (38,125,38),  "seed": (48,38,18)},
    "pumpkin":     {"stem": (62,122,42),  "leaf": (72,152,48),  "fruit": (222,148,35), "seed": (175,155,118)},
    "strawberry":  {"stem": (55,132,48),  "leaf": (55,158,38),  "fruit": (198,42,52),  "seed": (175,165,135)},
    "blueberry":   {"stem": (55,102,62),  "leaf": (62,132,58),  "fruit": (72,58,135),  "seed": (155,145,118)},
    "sunflower":   {"stem": (62,122,42),  "leaf": (72,152,48),  "fruit": (238,195,35), "seed": (58,48,28)},
    "lavender":    {"stem": (82,112,68),  "leaf": (95,140,88),  "fruit": (148,102,178),"seed": (118,98,78)},
    "rose":        {"stem": (55,112,48),  "leaf": (58,142,38),  "fruit": (208,55,82),  "seed": (165,128,98)},
    "apple":       {"stem": (92,62,30),   "leaf": (55,142,48),  "fruit": (198,48,48),  "seed": (108,78,48)},
    "peach":       {"stem": (102,68,35),  "leaf": (62,152,58),  "fruit": (242,178,148),"seed": (128,88,52)},
    "lemon":       {"stem": (88,62,30),   "leaf": (62,142,42),  "fruit": (238,218,52), "seed": (118,98,38)},
    "grape":       {"stem": (72,92,52),   "leaf": (62,132,48),  "fruit": (122,52,158), "seed": (98,78,58)},
}


# ═══════════════════════════════════════════════════════════════════════════
#  HAND-PAINTED STYLE RENDERING ENGINE
# ═══════════════════════════════════════════════════════════════════════════

class BrushEngine:
    """Simulates hand-painted brush strokes with natural variation."""

    def __init__(self, img, rng_seed=0):
        self.img = img
        self.draw = ImageDraw.Draw(img)
        self.rng = random.Random(rng_seed)
        self.w, self.h = img.size
        # Pre-compute canvas noise for texture
        self._noise = self._make_canvas_noise()

    def _make_canvas_noise(self):
        """Subtle canvas/paper texture overlay."""
        small = np.random.RandomState(99).uniform(-1, 1, (self.h // 16, self.w // 16, 3)).astype(np.float32)
        noise_img = Image.fromarray(((small + 1) * 127.5).astype(np.uint8), 'RGB')
        noise_img = noise_img.resize((self.w, self.h), Image.BILINEAR)
        arr = np.array(noise_img, dtype=np.float32) / 255.0
        return (arr - 0.5) * 2  # -1..1

    def _vary_color(self, color, amount=15):
        """Add natural color variation to a base color."""
        r, g, b = color[:3]
        r = max(0, min(255, r + self.rng.randint(-amount, amount)))
        g = max(0, min(255, g + self.rng.randint(-amount, amount)))
        b = max(0, min(255, b + self.rng.randint(-amount, amount)))
        return (r, g, b)

    def _darken(self, color, factor=0.7):
        return tuple(max(0, int(c * factor)) for c in color[:3])

    def _lighten(self, color, amount=30):
        return tuple(min(255, c + amount) for c in color[:3])

    def brush_stroke(self, x0, y0, x1, y1, color, width=8, opacity=255, jitter=2):
        """Draw a single brush stroke from (x0,y0) to (x1,y1)."""
        dx = x1 - x0
        dy = y1 - y0
        length = math.sqrt(dx * dx + dy * dy)
        if length < 1:
            return
        steps = max(1, int(length / 2))
        for i in range(steps + 1):
            t = i / steps
            cx = x0 + dx * t + self.rng.gauss(0, jitter)
            cy = y0 + dy * t + self.rng.gauss(0, jitter)
            w = width * (1.0 - 0.3 * abs(t - 0.5)) + self.rng.gauss(0, width * 0.1)
            w = max(2, w)
            varied = self._vary_color(color, 12)
            fill = varied + (opacity,) if len(varied) == 3 else varied
            self.draw.ellipse([cx - w/2, cy - w/2, cx + w/2, cy + w/2], fill=fill)

    def paint_leaf(self, tip_x, tip_y, length, width, angle, color, seed=0):
        """Paint a leaf with brush-stroke fill and a visible midrib."""
        rng = random.Random(seed)
        base_x = tip_x - length * math.cos(angle)
        base_y = tip_y - length * math.sin(angle)
        mid_x = (base_x + tip_x) / 2
        mid_y = (base_y + tip_y) / 2
        perp = angle + math.pi / 2
        hw = width / 2

        # Outline points for leaf shape
        pts = [
            (base_x, base_y),
            (mid_x + hw * math.cos(perp) * (1 + rng.uniform(-0.08, 0.08)),
             mid_y + hw * math.sin(perp) * (1 + rng.uniform(-0.08, 0.08))),
            (tip_x + hw * 0.12 * math.cos(perp), tip_y + hw * 0.12 * math.sin(perp)),
            (tip_x, tip_y),
            (tip_x - hw * 0.12 * math.cos(perp), tip_y - hw * 0.12 * math.sin(perp)),
            (mid_x - hw * math.cos(perp) * (1 + rng.uniform(-0.08, 0.08)),
             mid_y - hw * math.sin(perp) * (1 + rng.uniform(-0.08, 0.08))),
        ]
        fill = color + (255,) if len(color) == 3 else color
        self.draw.polygon(pts, fill=fill)

        # Fill with parallel brush strokes for painterly texture
        num_strokes = max(3, int(width / 4))
        for s in range(num_strokes):
            t = (s + 0.5) / num_strokes
            # Interpolate from base to tip along the leaf
            sx = base_x + (tip_x - base_x) * t
            sy = base_y + (tip_y - base_y) * t
            # Width tapers at both ends, widest at middle
            w_t = 1.0 - abs(2 * t - 1) ** 0.8
            perp_off = (t - 0.5) * hw * 2 * 0.6
            px = sx + perp_off * math.cos(perp)
            py = sy + perp_off * math.sin(perp)
            stroke_color = self._vary_color(color, 15)
            self.draw.ellipse([px - width * 0.1, py - width * 0.15,
                               px + width * 0.1, py + width * 0.15],
                              fill=stroke_color + (80,) if len(stroke_color) == 3 else stroke_color)

        # Midrib (darker vein)
        rib_c = self._darken(color, 0.6)
        rib_w = max(2, int(width * 0.06))
        self.draw.line([(base_x, base_y), (tip_x, tip_y)], fill=rib_c + (220,), width=rib_w)

        # Highlight along upper-left edge (light source)
        hl_c = self._lighten(color, 25)
        hl_pts = []
        for i in range(3):
            t = 0.2 + i * 0.3
            hx = base_x + (tip_x - base_x) * t + hw * 0.3 * math.cos(perp)
            hy = base_y + (tip_y - base_y) * t + hw * 0.3 * math.sin(perp)
            hl_pts.append((hx, hy))
        if len(hl_pts) >= 2:
            for i in range(len(hl_pts) - 1):
                self.draw.line([hl_pts[i], hl_pts[i+1]], fill=hl_c + (60,), width=max(1, rib_w))

    def paint_stem(self, x0, y0, x1, y1, thickness, color, seed=0):
        """Paint a stem with brush strokes and highlight."""
        # Main stem body
        self.brush_stroke(x0, y0, x1, y1, color, width=thickness, jitter=1.5)
        # Darker edge on right/bottom (shadow side)
        shadow_c = self._darken(color, 0.65)
        dx = x1 - x0
        dy = y1 - y0
        length = math.sqrt(dx*dx + dy*dy) or 1
        nx = -dy / length
        ny = dx / length
        self.brush_stroke(x0 + nx * thickness * 0.2, y0 + ny * thickness * 0.2,
                          x1 + nx * thickness * 0.15, y1 + ny * thickness * 0.15,
                          shadow_c, width=thickness * 0.5, opacity=120, jitter=1)
        # Highlight on left/top (light side)
        hl_c = self._lighten(color, 22)
        self.brush_stroke(x0 - nx * thickness * 0.15, y0 - ny * thickness * 0.15,
                          x1 - nx * thickness * 0.1, y1 - ny * thickness * 0.1,
                          hl_c, width=thickness * 0.4, opacity=80, jitter=1)

    def paint_fruit(self, cx, cy, radius, color, seed=0):
        """Paint a round fruit with brush strokes, shadow, and highlight."""
        rng = random.Random(seed)
        # Base circle with organic variation
        for _ in range(3):
            ox = rng.gauss(0, radius * 0.05)
            oy = rng.gauss(0, radius * 0.05)
            r = radius * (1.0 + rng.uniform(-0.06, 0.06))
            varied = self._vary_color(color, 10)
            fill = varied + (255,) if len(varied) == 3 else varied
            self.draw.ellipse([cx + ox - r, cy + oy - r, cx + ox + r, cy + oy + r], fill=fill)

        # Shadow crescent (lower-right, away from upper-left light)
        shadow_c = self._darken(color, 0.55)
        sx = cx + radius * 0.2
        sy = cy + radius * 0.25
        sr = radius * 0.75
        self.draw.ellipse([sx - sr, sy - sr, sx + sr, sy + sr],
                          fill=shadow_c + (100,) if len(shadow_c) == 3 else shadow_c)

        # Re-draw main body to mask shadow overflow
        main_c = self._vary_color(color, 5)
        self.draw.ellipse([cx - radius, cy - radius, cx + radius, cy + radius],
                          fill=main_c + (255,) if len(main_c) == 3 else main_c)

        # Brush stroke texture across the fruit
        num = max(3, int(radius / 8))
        for i in range(num):
            t = (i + 0.5) / num
            stroke_y = cy - radius + 2 * radius * t
            stroke_x0 = cx - radius * 0.7 * math.sin(math.pi * t)
            stroke_x1 = cx + radius * 0.7 * math.sin(math.pi * t)
            stroke_c = self._vary_color(color, 12)
            self.brush_stroke(stroke_x0, stroke_y, stroke_x1, stroke_y,
                              stroke_c, width=3, opacity=40, jitter=0.5)

        # Specular highlight (upper-left)
        hl_c = self._lighten(color, 50)
        hx = cx - radius * 0.28
        hy = cy - radius * 0.32
        hr = radius * 0.3
        self.draw.ellipse([hx - hr, hy - hr, hx + hr, hy + hr],
                          fill=hl_c + (90,) if len(hl_c) == 3 else hl_c)

        # Secondary softer highlight
        hl2_c = self._lighten(color, 30)
        self.draw.ellipse([hx - hr * 1.5, hy - hr * 1.5, hx + hr * 1.5, hy + hr * 1.5],
                          fill=hl2_c + (35,) if len(hl2_c) == 3 else hl2_c)

    def paint_seed(self, cx, cy, radius, color, seed=0):
        """Paint a small seed with organic shape and highlight."""
        rng = random.Random(seed)
        varied = self._vary_color(color, 18)
        # Organic oval
        wobble = rng.uniform(0.85, 1.15)
        rx = radius * wobble
        ry = radius / wobble
        angle = rng.uniform(0, math.pi)
        pts = []
        for i in range(12):
            a = 2 * math.pi * i / 12
            r = 1.0 + rng.uniform(-0.15, 0.15)
            px = cx + rx * r * math.cos(a) * math.cos(angle) - ry * r * math.sin(a) * math.sin(angle)
            py = cy + rx * r * math.cos(a) * math.sin(angle) + ry * r * math.sin(a) * math.cos(angle)
            pts.append((px, py))
        fill = varied + (255,) if len(varied) == 3 else varied
        self.draw.polygon(pts, fill=fill)
        # Highlight
        hl = self._lighten(color, 35)
        hx = cx - radius * 0.2
        hy = cy - radius * 0.25
        self.draw.ellipse([hx - radius * 0.25, hy - radius * 0.25,
                           hx + radius * 0.25, hy + radius * 0.25],
                          fill=hl + (100,) if len(hl) == 3 else hl)

    def paint_contact_shadow(self, cx, cy, width, seed=0):
        """Paint a soft ground contact shadow below the plant base."""
        rng = random.Random(seed)
        sw = width * 0.8
        sh = width * 0.15
        for i in range(5):
            ox = rng.gauss(0, sw * 0.1)
            oy = rng.gauss(0, sh * 0.2)
            alpha = 40 - i * 7
            if alpha <= 0:
                break
            self.draw.ellipse([cx + ox - sw, cy + oy - sh, cx + ox + sw, cy + oy + sh],
                              fill=(40, 35, 30, alpha))

    def apply_canvas_texture(self, intensity=0.04):
        """Apply subtle canvas/paper texture to mimic painted surface."""
        arr = np.array(self.img, dtype=np.float32)
        mask = arr[:, :, 3] > 0
        for c in range(3):
            channel = arr[:, :, c].copy()
            channel[mask] = np.clip(channel[mask] + self._noise[:, :, c][mask] * 255 * intensity, 0, 255)
            arr[:, :, c] = channel
        self.img = Image.fromarray(arr.astype(np.uint8), 'RGBA')
        self.draw = ImageDraw.Draw(self.img)


# ═══════════════════════════════════════════════════════════════════════════
#  CROP FORM RENDERERS
# ═══════════════════════════════════════════════════════════════════════════

def render_seed_stage(eng, cx, base_y, palette, variant, seed):
    """Stage 0: Seeds on soil."""
    rng = random.Random(seed)
    sc = palette["seed"]
    count = 3 + variant
    for i in range(count):
        ox = rng.randint(-55, 55)
        oy = rng.randint(-15, 15)
        r = 18 + variant * 4 + rng.randint(-4, 4)
        eng.paint_seed(cx + ox, base_y + oy, r, sc, seed + i * 7)
    eng.paint_contact_shadow(cx, base_y + 10, 70 + variant * 10, seed + 100)


def render_sprout_stage(eng, cx, base_y, palette, variant, seed):
    """Stage 1: Small sprout with stem and tiny leaves."""
    rng = random.Random(seed)
    stem_c = palette["stem"]
    leaf_c = palette["leaf"]
    count = 3 + variant
    spread = 35 + variant * 10
    for i in range(count):
        ox = int(rng.uniform(-spread, spread))
        stem_h = 100 + variant * 20 + rng.randint(-15, 15)
        sway = rng.uniform(-12, 12)
        top_y = base_y - stem_h
        eng.paint_stem(cx + ox, base_y, cx + ox + sway, top_y, 6 + rng.randint(0, 2), stem_c, seed + i * 11)
        # Cotyledon leaves
        leaf_len = 40 + variant * 8
        leaf_w = 16 + variant * 3
        eng.paint_leaf(cx + ox + sway - 15, top_y + 25, leaf_len, leaf_w,
                       math.pi * 0.62, leaf_c, seed + i * 11 + 1)
        eng.paint_leaf(cx + ox + sway + 15, top_y + 35, leaf_len, leaf_w,
                       math.pi * 0.38, leaf_c, seed + i * 11 + 2)
    eng.paint_contact_shadow(cx, base_y + 8, 60 + variant * 10, seed + 200)


def render_annual_root_growing(eng, cx, base_y, palette, variant, seed):
    """Stage 2: Leafy tops with root shoulders."""
    rng = random.Random(seed)
    stem_c = palette["stem"]
    leaf_c = palette["leaf"]
    fruit_c = palette["fruit"]
    # Foliage
    count = 4 + variant
    for i in range(count):
        ox = rng.randint(-30, 30)
        stem_h = 160 + variant * 15 + rng.randint(-10, 10)
        top_y = base_y - stem_h
        eng.paint_stem(cx + ox, base_y - 30, cx + ox, top_y, 7, stem_c, seed + i * 13)
        for j in range(3 + variant):
            la = math.pi * 0.25 + j * math.pi * 0.15 + rng.uniform(-0.1, 0.1)
            ly = top_y + rng.randint(10, 50)
            ll = 55 + variant * 6
            lw = 16 + variant * 2
            eng.paint_leaf(cx + ox, ly, ll, lw, la, leaf_c, seed + i * 13 + j + 20)
    # Root shoulders visible
    rw = 25 + variant * 5
    rh = 20 + variant * 3
    eng.draw.ellipse([cx - rw, base_y - rh, cx + rw, base_y + rh * 0.3],
                     fill=fruit_c + (200,))
    eng.paint_contact_shadow(cx, base_y + 10, 80 + variant * 10, seed + 300)


def render_annual_root_mature(eng, cx, base_y, palette, variant, seed):
    """Stage 3: Full foliage above, visible root body at soil line."""
    rng = random.Random(seed)
    stem_c = palette["stem"]
    leaf_c = palette["leaf"]
    fruit_c = palette["fruit"]
    # Bushy leaf tops
    for i in range(5 + variant):
        ox = rng.randint(-35, 35)
        la = math.pi * 0.28 + i * math.pi * 0.11 + rng.uniform(-0.08, 0.08)
        ly = base_y - 80 - rng.randint(0, 80)
        ll = 60 + variant * 6
        lw = 15 + variant * 2
        eng.paint_leaf(cx + ox, ly, ll, lw, la, leaf_c, seed + i * 17 + 20)
    # Visible root body (conical)
    root_top = base_y - 35
    root_h = 120 + variant * 18
    rw_top = 28 + variant * 5
    pts = [(cx - rw_top, root_top), (cx + rw_top, root_top),
           (cx + 4, root_top + root_h), (cx - 4, root_top + root_h)]
    eng.draw.polygon(pts, fill=fruit_c + (255,))
    # Highlight stripe (upper-left lit)
    hl_c = eng._lighten(fruit_c, 28)
    hl_pts = [(cx - rw_top * 0.4, root_top + 8), (cx - rw_top * 0.1, root_top + 8),
              (cx - 2, root_top + root_h - 20), (cx - 8, root_top + root_h - 20)]
    eng.draw.polygon(hl_pts, fill=hl_c + (90,))
    # Shadow on right side
    sh_c = eng._darken(fruit_c, 0.6)
    sh_pts = [(cx + rw_top * 0.5, root_top + 5), (cx + rw_top, root_top),
              (cx + 3, root_top + root_h - 30), (cx + 1, root_top + root_h - 30)]
    eng.draw.polygon(sh_pts, fill=sh_c + (80,))
    eng.paint_contact_shadow(cx, base_y + root_h * 0.5 + 10, 60 + variant * 8, seed + 400)


def render_annual_berry_growing(eng, cx, base_y, palette, variant, seed):
    """Stage 2: Bush with small green fruits forming."""
    rng = random.Random(seed)
    stem_c = palette["stem"]
    leaf_c = palette["leaf"]
    top_y = base_y - (200 + variant * 20)
    # Main stems
    for i in range(2 + variant):
        ox = rng.randint(-20, 20)
        eng.paint_stem(cx + ox, base_y, cx + ox + rng.randint(-10, 10), top_y, 8, stem_c, seed + i * 19)
    # Leaves
    for i in range(6 + variant):
        lx = cx + rng.randint(-50, 50)
        ly = top_y + rng.randint(20, 120)
        ll = 50 + variant * 6
        lw = 22 + variant * 3
        la = math.pi * (0.35 + rng.uniform(0, 0.3))
        eng.paint_leaf(lx, ly, ll, lw, la, leaf_c, seed + i * 19 + 10)
    # Small green fruits
    green_fruit = eng._darken(palette["fruit"], 0.6)
    for i in range(2 + variant):
        fx = cx + rng.randint(-25, 25)
        fy = top_y + rng.randint(50, 100)
        eng.paint_fruit(fx, fy, 12 + variant * 2, green_fruit, seed + i * 31)
    eng.paint_contact_shadow(cx, base_y + 8, 70 + variant * 8, seed + 500)


def render_annual_berry_mature(eng, cx, base_y, palette, variant, seed):
    """Stage 3: Full bush with ripe fruits."""
    rng = random.Random(seed)
    stem_c = palette["stem"]
    leaf_c = palette["leaf"]
    fruit_c = palette["fruit"]
    top_y = base_y - (250 + variant * 15)
    # Main stems
    for i in range(3 + variant):
        ox = rng.randint(-25, 25)
        eng.paint_stem(cx + ox, base_y, cx + ox, top_y + rng.randint(-20, 20), 9, stem_c, seed + i * 23)
    # Leaves
    for i in range(8 + variant):
        lx = cx + rng.randint(-55, 55)
        ly = top_y + rng.randint(20, 150)
        ll = 55 + variant * 5
        lw = 24 + variant * 3
        la = math.pi * (0.3 + rng.uniform(0, 0.4))
        eng.paint_leaf(lx, ly, ll, lw, la, leaf_c, seed + i * 23 + 10)
    # Ripe fruits
    for i in range(4 + variant):
        fx = cx + rng.randint(-35, 35)
        fy = top_y + rng.randint(60, 140)
        fr = 16 + variant * 2 + rng.randint(-3, 3)
        eng.paint_fruit(fx, fy, fr, fruit_c, seed + i * 37)
    eng.paint_contact_shadow(cx, base_y + 8, 80 + variant * 8, seed + 600)


def render_annual_large_growing(eng, cx, base_y, palette, variant, seed):
    """Stage 2: Spreading vines with leaves and small fruits."""
    rng = random.Random(seed)
    stem_c = palette["stem"]
    leaf_c = palette["leaf"]
    # Vine stems spreading
    for i in range(3 + variant):
        angle = rng.uniform(-0.4, 0.4)
        vx = cx + rng.randint(-60, 60)
        vy = base_y - 20
        end_x = vx + int(120 * math.cos(angle)) * (1 if rng.random() > 0.5 else -1)
        end_y = vy - 30 - rng.randint(0, 20)
        eng.paint_stem(vx, vy, end_x, end_y, 7, stem_c, seed + i * 29)
    # Large leaves
    for i in range(5 + variant):
        lx = cx + rng.randint(-80, 80)
        ly = base_y - rng.randint(20, 80)
        ll = 65 + variant * 8
        lw = 55 + variant * 8
        la = math.pi * (0.4 + rng.uniform(-0.15, 0.15))
        eng.paint_leaf(lx, ly, ll, lw, la, leaf_c, seed + i * 29 + 10)
    # Small green fruit
    green_fruit = eng._darken(palette["fruit"], 0.6)
    for i in range(1 + variant):
        fx = cx + rng.randint(-30, 30)
        fy = base_y - rng.randint(15, 40)
        eng.paint_fruit(fx, fy, 18 + variant * 3, green_fruit, seed + i * 41)
    eng.paint_contact_shadow(cx, base_y + 8, 120 + variant * 15, seed + 700)


def render_annual_large_mature(eng, cx, base_y, palette, variant, seed):
    """Stage 3: Large fruits on sprawling vines."""
    rng = random.Random(seed)
    stem_c = palette["stem"]
    leaf_c = palette["leaf"]
    fruit_c = palette["fruit"]
    # Vine stems
    for i in range(4 + variant):
        vx = cx + rng.randint(-80, 80)
        vy = base_y - 15
        end_x = vx + rng.randint(-40, 40)
        end_y = vy - rng.randint(10, 30)
        eng.paint_stem(vx, vy, end_x, end_y, 8, stem_c, seed + i * 31)
    # Large leaves
    for i in range(6 + variant):
        lx = cx + rng.randint(-90, 90)
        ly = base_y - rng.randint(20, 90)
        ll = 70 + variant * 8
        lw = 60 + variant * 8
        la = math.pi * (0.4 + rng.uniform(-0.15, 0.15))
        eng.paint_leaf(lx, ly, ll, lw, la, leaf_c, seed + i * 31 + 10)
    # Large fruit
    for i in range(1 + (variant % 2)):
        fx = cx + rng.randint(-20, 20)
        fy = base_y - rng.randint(25, 50)
        fr = 35 + variant * 5
        eng.paint_fruit(fx, fy, fr, fruit_c, seed + i * 43)
    eng.paint_contact_shadow(cx, base_y + 8, 140 + variant * 15, seed + 800)


def render_bush_growing(eng, cx, base_y, palette, variant, seed):
    """Stage 2: Small bushy plant with flowers/buds."""
    rng = random.Random(seed)
    stem_c = palette["stem"]
    leaf_c = palette["leaf"]
    fruit_c = palette["fruit"]
    top_y = base_y - (120 + variant * 15)
    # Stems
    for i in range(3 + variant):
        ox = rng.randint(-20, 20)
        eng.paint_stem(cx + ox, base_y, cx + ox, top_y + rng.randint(0, 30), 6, stem_c, seed + i * 33)
    # Leaves
    for i in range(5 + variant):
        lx = cx + rng.randint(-40, 40)
        ly = top_y + rng.randint(15, 70)
        ll = 45 + variant * 5
        lw = 30 + variant * 4
        la = math.pi * (0.35 + rng.uniform(0, 0.3))
        eng.paint_leaf(lx, ly, ll, lw, la, leaf_c, seed + i * 33 + 10)
    # Small buds/flowers
    for i in range(2 + variant):
        fx = cx + rng.randint(-20, 20)
        fy = top_y + rng.randint(30, 60)
        eng.paint_fruit(fx, fy, 8 + variant, fruit_c, seed + i * 47)
    eng.paint_contact_shadow(cx, base_y + 8, 65 + variant * 8, seed + 900)


def render_bush_mature(eng, cx, base_y, palette, variant, seed):
    """Stage 3: Low bush with ripe berries."""
    rng = random.Random(seed)
    stem_c = palette["stem"]
    leaf_c = palette["leaf"]
    fruit_c = palette["fruit"]
    top_y = base_y - (150 + variant * 12)
    # Stems
    for i in range(4 + variant):
        ox = rng.randint(-25, 25)
        eng.paint_stem(cx + ox, base_y, cx + ox, top_y + rng.randint(0, 25), 6, stem_c, seed + i * 37)
    # Leaves
    for i in range(7 + variant):
        lx = cx + rng.randint(-50, 50)
        ly = top_y + rng.randint(10, 80)
        ll = 48 + variant * 5
        lw = 32 + variant * 4
        la = math.pi * (0.35 + rng.uniform(0, 0.3))
        eng.paint_leaf(lx, ly, ll, lw, la, leaf_c, seed + i * 37 + 10)
    # Ripe berries
    for i in range(5 + variant):
        fx = cx + rng.randint(-35, 35)
        fy = top_y + rng.randint(30, 70)
        fr = 10 + variant * 2
        eng.paint_fruit(fx, fy, fr, fruit_c, seed + i * 51)
    eng.paint_contact_shadow(cx, base_y + 8, 75 + variant * 10, seed + 1000)


def render_flower_tall_growing(eng, cx, base_y, palette, variant, seed):
    """Stage 2: Tall stem with leaves, small bud forming."""
    rng = random.Random(seed)
    stem_c = palette["stem"]
    leaf_c = palette["leaf"]
    fruit_c = palette["fruit"]
    top_y = base_y - (350 + variant * 20)
    # Tall stem
    sway = rng.uniform(-8, 8)
    eng.paint_stem(cx, base_y, cx + sway, top_y, 10, stem_c, seed)
    # Leaves along stem
    for i in range(4 + variant):
        ly = base_y - 80 - i * 60 + rng.randint(-10, 10)
        side = 1 if i % 2 == 0 else -1
        ll = 55 + variant * 5
        lw = 28 + variant * 3
        la = math.pi * (0.3 if side > 0 else 0.7) + rng.uniform(-0.08, 0.08)
        eng.paint_leaf(cx + sway + side * 15, ly, ll, lw, la, leaf_c, seed + i * 41 + 10)
    # Small green bud at top
    green_bud = eng._darken(fruit_c, 0.5)
    eng.paint_fruit(cx + sway, top_y + 10, 20 + variant * 3, green_bud, seed + 200)
    eng.paint_contact_shadow(cx, base_y + 8, 50 + variant * 5, seed + 1100)


def render_flower_tall_mature(eng, cx, base_y, palette, variant, seed):
    """Stage 3: Tall sunflower with full head."""
    rng = random.Random(seed)
    stem_c = palette["stem"]
    leaf_c = palette["leaf"]
    fruit_c = palette["fruit"]
    top_y = base_y - (420 + variant * 15)
    # Tall stem
    sway = rng.uniform(-6, 6)
    eng.paint_stem(cx, base_y, cx + sway, top_y + 40, 11, stem_c, seed)
    # Leaves
    for i in range(5 + variant):
        ly = base_y - 60 - i * 65 + rng.randint(-10, 10)
        side = 1 if i % 2 == 0 else -1
        ll = 60 + variant * 5
        lw = 30 + variant * 3
        la = math.pi * (0.3 if side > 0 else 0.7) + rng.uniform(-0.08, 0.08)
        eng.paint_leaf(cx + sway + side * 18, ly, ll, lw, la, leaf_c, seed + i * 43 + 10)
    # Sunflower head
    head_r = 45 + variant * 5
    # Petals
    petal_count = 12 + variant * 2
    for i in range(petal_count):
        angle = 2 * math.pi * i / petal_count
        px = cx + sway + head_r * 1.3 * math.cos(angle)
        py = top_y + 40 + head_r * 1.3 * math.sin(angle)
        pr = head_r * 0.35
        eng.paint_fruit(px, py, pr, fruit_c, seed + i * 53)
    # Dark center
    center_c = (80, 55, 25)
    eng.draw.ellipse([cx + sway - head_r * 0.6, top_y + 40 - head_r * 0.6,
                      cx + sway + head_r * 0.6, top_y + 40 + head_r * 0.6],
                     fill=center_c + (255,))
    eng.paint_contact_shadow(cx, base_y + 8, 55 + variant * 5, seed + 1200)


def render_flower_spike_growing(eng, cx, base_y, palette, variant, seed):
    """Stage 2: Multiple stems with small bud clusters."""
    rng = random.Random(seed)
    stem_c = palette["stem"]
    leaf_c = palette["leaf"]
    fruit_c = palette["fruit"]
    # Multiple stems
    for i in range(2 + variant):
        ox = rng.randint(-25, 25)
        top_y = base_y - (200 + variant * 15 + rng.randint(-15, 15))
        eng.paint_stem(cx + ox, base_y, cx + ox, top_y, 5, stem_c, seed + i * 47)
        # Narrow leaves
        for j in range(3 + variant):
            ly = base_y - 40 - j * 45
            side = 1 if j % 2 == 0 else -1
            ll = 40 + variant * 4
            lw = 8 + variant
            la = math.pi * (0.35 if side > 0 else 0.65)
            eng.paint_leaf(cx + ox + side * 10, ly, ll, lw, la, leaf_c, seed + i * 47 + j + 10)
        # Small bud cluster at top
        for k in range(3 + variant):
            bx = cx + ox + rng.randint(-5, 5)
            by = top_y + k * 8
            eng.paint_fruit(bx, by, 6 + variant, fruit_c, seed + i * 47 + k + 30)
    eng.paint_contact_shadow(cx, base_y + 8, 60 + variant * 8, seed + 1300)


def render_flower_spike_mature(eng, cx, base_y, palette, variant, seed):
    """Stage 3: Slender stems topped with purple flower spikes."""
    rng = random.Random(seed)
    stem_c = palette["stem"]
    leaf_c = palette["leaf"]
    fruit_c = palette["fruit"]
    for i in range(3 + variant):
        ox = rng.randint(-30, 30)
        top_y = base_y - (280 + variant * 12 + rng.randint(-10, 10))
        eng.paint_stem(cx + ox, base_y, cx + ox, top_y, 5, stem_c, seed + i * 51)
        # Narrow leaves
        for j in range(4 + variant):
            ly = base_y - 30 - j * 55
            side = 1 if j % 2 == 0 else -1
            ll = 42 + variant * 3
            lw = 8 + variant
            la = math.pi * (0.35 if side > 0 else 0.65)
            eng.paint_leaf(cx + ox + side * 8, ly, ll, lw, la, leaf_c, seed + i * 51 + j + 10)
        # Flower spike
        for k in range(8 + variant * 2):
            bx = cx + ox + rng.randint(-4, 4)
            by = top_y + k * 10
            br = 8 + variant * 2 - abs(k - 4) * 0.5
            eng.paint_fruit(bx, by, max(4, br), fruit_c, seed + i * 51 + k + 30)
    eng.paint_contact_shadow(cx, base_y + 8, 70 + variant * 8, seed + 1400)


def render_flower_round_growing(eng, cx, base_y, palette, variant, seed):
    """Stage 2: Leafy bush with pointed buds."""
    rng = random.Random(seed)
    stem_c = palette["stem"]
    leaf_c = palette["leaf"]
    fruit_c = palette["fruit"]
    top_y = base_y - (180 + variant * 15)
    # Thorny stems
    for i in range(3 + variant):
        ox = rng.randint(-20, 20)
        eng.paint_stem(cx + ox, base_y, cx + ox, top_y + rng.randint(0, 30), 6, stem_c, seed + i * 53)
    # Compound leaves
    for i in range(6 + variant):
        lx = cx + rng.randint(-45, 45)
        ly = top_y + rng.randint(15, 80)
        ll = 48 + variant * 5
        lw = 28 + variant * 3
        la = math.pi * (0.35 + rng.uniform(0, 0.3))
        eng.paint_leaf(lx, ly, ll, lw, la, leaf_c, seed + i * 53 + 10)
    # Pointed buds
    for i in range(2 + variant):
        bx = cx + rng.randint(-20, 20)
        by = top_y + rng.randint(30, 60)
        br = 10 + variant * 2
        eng.paint_fruit(bx, by, br, fruit_c, seed + i * 59)
    eng.paint_contact_shadow(cx, base_y + 8, 65 + variant * 8, seed + 1500)


def render_flower_round_mature(eng, cx, base_y, palette, variant, seed):
    """Stage 3: Open roses with compound leaves."""
    rng = random.Random(seed)
    stem_c = palette["stem"]
    leaf_c = palette["leaf"]
    fruit_c = palette["fruit"]
    top_y = base_y - (220 + variant * 12)
    # Stems
    for i in range(4 + variant):
        ox = rng.randint(-25, 25)
        eng.paint_stem(cx + ox, base_y, cx + ox, top_y + rng.randint(0, 25), 6, stem_c, seed + i * 57)
    # Leaves
    for i in range(8 + variant):
        lx = cx + rng.randint(-50, 50)
        ly = top_y + rng.randint(10, 80)
        ll = 50 + variant * 4
        lw = 28 + variant * 3
        la = math.pi * (0.35 + rng.uniform(0, 0.3))
        eng.paint_leaf(lx, ly, ll, lw, la, leaf_c, seed + i * 57 + 10)
    # Open roses
    for i in range(3 + variant):
        fx = cx + rng.randint(-30, 30)
        fy = top_y + rng.randint(30, 70)
        fr = 18 + variant * 3
        # Petals
        petal_count = 5 + variant
        for p in range(petal_count):
            pa = 2 * math.pi * p / petal_count + rng.uniform(-0.2, 0.2)
            px = fx + fr * 0.6 * math.cos(pa)
            py = fy + fr * 0.6 * math.sin(pa)
            pr = fr * 0.5
            eng.paint_fruit(px, py, pr, fruit_c, seed + i * 61 + p)
    eng.paint_contact_shadow(cx, base_y + 8, 80 + variant * 10, seed + 1600)


def render_tree_growing(eng, cx, base_y, palette, variant, seed):
    """Stage 2: Small tree with trunk and leafy canopy."""
    rng = random.Random(seed)
    stem_c = palette["stem"]
    leaf_c = palette["leaf"]
    # Trunk
    trunk_h = 180 + variant * 20
    trunk_w = 12 + variant * 2
    top_y = base_y - trunk_h
    eng.paint_stem(cx, base_y, cx, top_y, trunk_w, stem_c, seed)
    # Canopy (overlapping circles)
    canopy_r = 80 + variant * 10
    for i in range(6 + variant):
        ox = rng.randint(-int(canopy_r * 0.5), int(canopy_r * 0.5))
        oy = rng.randint(-int(canopy_r * 0.3), int(canopy_r * 0.3))
        cr = canopy_r * (0.6 + rng.uniform(0, 0.4))
        varied_leaf = eng._vary_color(leaf_c, 15)
        eng.draw.ellipse([cx + ox - cr, top_y - cr * 0.5 + oy,
                          cx + ox + cr, top_y + cr * 0.5 + oy],
                         fill=varied_leaf + (200,))
    eng.paint_contact_shadow(cx, base_y + 8, 100 + variant * 10, seed + 1700)


def render_tree_mature(eng, cx, base_y, palette, variant, seed):
    """Stage 3: Full tree with fruit among leaves."""
    rng = random.Random(seed)
    stem_c = palette["stem"]
    leaf_c = palette["leaf"]
    fruit_c = palette["fruit"]
    # Trunk
    trunk_h = 250 + variant * 15
    trunk_w = 16 + variant * 2
    top_y = base_y - trunk_h
    eng.paint_stem(cx, base_y, cx, top_y, trunk_w, stem_c, seed)
    # Canopy
    canopy_r = 110 + variant * 12
    for i in range(8 + variant):
        ox = rng.randint(-int(canopy_r * 0.5), int(canopy_r * 0.5))
        oy = rng.randint(-int(canopy_r * 0.3), int(canopy_r * 0.3))
        cr = canopy_r * (0.5 + rng.uniform(0, 0.5))
        varied_leaf = eng._vary_color(leaf_c, 15)
        eng.draw.ellipse([cx + ox - cr, top_y - cr * 0.5 + oy,
                          cx + ox + cr, top_y + cr * 0.5 + oy],
                         fill=varied_leaf + (220,))
    # Fruits in canopy
    for i in range(4 + variant):
        fx = cx + rng.randint(-int(canopy_r * 0.6), int(canopy_r * 0.6))
        fy = top_y + rng.randint(-int(canopy_r * 0.2), int(canopy_r * 0.3))
        fr = 14 + variant * 2
        eng.paint_fruit(fx, fy, fr, fruit_c, seed + i * 67)
    eng.paint_contact_shadow(cx, base_y + 8, 120 + variant * 10, seed + 1800)


def render_vine_growing(eng, cx, base_y, palette, variant, seed):
    """Stage 2: Spreading vine with lobed leaves."""
    rng = random.Random(seed)
    stem_c = palette["stem"]
    leaf_c = palette["leaf"]
    fruit_c = palette["fruit"]
    # Vine stems
    for i in range(3 + variant):
        sx = cx + rng.randint(-40, 40)
        ex = sx + rng.randint(-60, 60)
        ey = base_y - 40 - rng.randint(0, 30)
        eng.paint_stem(sx, base_y, ex, ey, 6, stem_c, seed + i * 71)
    # Lobed leaves
    for i in range(5 + variant):
        lx = cx + rng.randint(-70, 70)
        ly = base_y - rng.randint(20, 70)
        ll = 55 + variant * 5
        lw = 50 + variant * 6
        la = math.pi * (0.4 + rng.uniform(-0.1, 0.1))
        eng.paint_leaf(lx, ly, ll, lw, la, leaf_c, seed + i * 71 + 10)
    # Tiny green clusters
    green_fruit = eng._darken(fruit_c, 0.5)
    for i in range(2):
        gx = cx + rng.randint(-30, 30)
        gy = base_y - rng.randint(25, 50)
        for j in range(4 + variant):
            eng.paint_fruit(gx + rng.randint(-8, 8), gy + rng.randint(-8, 8), 5, green_fruit, seed + i * 73 + j)
    eng.paint_contact_shadow(cx, base_y + 8, 100 + variant * 10, seed + 1900)


def render_vine_mature(eng, cx, base_y, palette, variant, seed):
    """Stage 3: Vine with hanging grape clusters."""
    rng = random.Random(seed)
    stem_c = palette["stem"]
    leaf_c = palette["leaf"]
    fruit_c = palette["fruit"]
    # Vine stems
    for i in range(4 + variant):
        sx = cx + rng.randint(-50, 50)
        ex = sx + rng.randint(-70, 70)
        ey = base_y - 50 - rng.randint(0, 40)
        eng.paint_stem(sx, base_y, ex, ey, 7, stem_c, seed + i * 73)
    # Lobed leaves
    for i in range(7 + variant):
        lx = cx + rng.randint(-80, 80)
        ly = base_y - rng.randint(20, 80)
        ll = 60 + variant * 5
        lw = 55 + variant * 6
        la = math.pi * (0.4 + rng.uniform(-0.1, 0.1))
        eng.paint_leaf(lx, ly, ll, lw, la, leaf_c, seed + i * 73 + 10)
    # Grape clusters
    for i in range(3 + variant):
        gx = cx + rng.randint(-40, 40)
        gy = base_y - rng.randint(40, 80)
        for j in range(8 + variant * 2):
            gr = 7 + variant + rng.randint(-2, 2)
            eng.paint_fruit(gx + rng.randint(-12, 12), gy + j * 9, gr, fruit_c, seed + i * 79 + j)
    eng.paint_contact_shadow(cx, base_y + 8, 120 + variant * 10, seed + 2000)


# Stage dispatch table per form
FORM_RENDERERS = {
    "annual_root": [render_seed_stage, render_sprout_stage,
                    render_annual_root_growing, render_annual_root_mature],
    "annual_berry": [render_seed_stage, render_sprout_stage,
                     render_annual_berry_growing, render_annual_berry_mature],
    "annual_large": [render_seed_stage, render_sprout_stage,
                     render_annual_large_growing, render_annual_large_mature],
    "bush": [render_seed_stage, render_sprout_stage,
             render_bush_growing, render_bush_mature],
    "flower_tall": [render_seed_stage, render_sprout_stage,
                    render_flower_tall_growing, render_flower_tall_mature],
    "flower_spike": [render_seed_stage, render_sprout_stage,
                     render_flower_spike_growing, render_flower_spike_mature],
    "flower_round": [render_seed_stage, render_sprout_stage,
                     render_flower_round_growing, render_flower_round_mature],
    "tree": [render_seed_stage, render_sprout_stage,
             render_tree_growing, render_tree_mature],
    "vine": [render_seed_stage, render_sprout_stage,
             render_vine_growing, render_vine_mature],
}


# ═══════════════════════════════════════════════════════════════════════════
#  LAYER SPLITTING
# ═══════════════════════════════════════════════════════════════════════════

def split_into_layers(img):
    """Split the full image into back (upper, slightly darker) and front (lower) layers."""
    w, h = img.size
    arr = np.array(img)

    # Back layer: upper 65% of the plant (taller, further from camera)
    back = arr.copy()
    # Fade out the bottom 35% to transparent
    cutoff = int(h * 0.65)
    fade_zone = int(h * 0.15)
    for y in range(cutoff, h):
        if y < cutoff + fade_zone:
            alpha_factor = 1.0 - (y - cutoff) / fade_zone
        else:
            alpha_factor = 0.0
        back[y, :, 3] = (back[y, :, 3] * alpha_factor).astype(np.uint8)

    # Front layer: lower 55% of the plant (shorter, closer to camera)
    front = arr.copy()
    # Fade out the top 45%
    front_cutoff = int(h * 0.45)
    front_fade = int(h * 0.12)
    for y in range(0, front_cutoff + front_fade):
        if y < front_cutoff - front_fade:
            alpha_factor = 0.0
        elif y < front_cutoff:
            alpha_factor = (y - (front_cutoff - front_fade)) / (front_fade * 2)
        else:
            alpha_factor = min(1.0, (y - front_cutoff + front_fade) / front_fade)
        front[y, :, 3] = (front[y, :, 3] * alpha_factor).astype(np.uint8)

    back_img = Image.fromarray(back, 'RGBA')
    front_img = Image.fromarray(front, 'RGBA')

    # Slightly darken back layer (further from camera)
    back_arr = np.array(back_img, dtype=np.float32)
    mask = back_arr[:, :, 3] > 0
    for c in range(3):
        back_arr[:, :, c][mask] *= 0.9
    back_img = Image.fromarray(back_arr.astype(np.uint8), 'RGBA')

    return back_img, front_img


# ═══════════════════════════════════════════════════════════════════════════
#  FULL IMAGE GENERATION
# ═══════════════════════════════════════════════════════════════════════════

def generate_full_image(crop, stage, variant, rng_seed):
    """Generate a complete crop image for one stage/variant."""
    rng = random.Random(rng_seed + variant * 1000 + stage * 100)
    crop_id = crop["id"]
    palette = PALETTES[crop_id]
    form = crop["form"]

    img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    eng = BrushEngine(img, rng_seed=rng_seed + variant * 1000 + stage * 100)

    # Root anchor at 82% canvas height (matching grain style)
    base_y = int(SIZE * 0.82)
    cx = SIZE // 2

    # Render the crop at this stage
    renderer = FORM_RENDERERS[form][stage]
    renderer(eng, cx, base_y, palette, variant, rng_seed + variant * 1000 + stage * 100)

    # Apply canvas texture for painterly feel
    eng.apply_canvas_texture(intensity=0.045)

    # Soft blur for painted edges
    img = eng.img.filter(ImageFilter.SMOOTH)

    return img


# ═══════════════════════════════════════════════════════════════════════════
#  AI GENERATION PIPELINE (for when OPENAI_API_KEY is available)
# ═══════════════════════════════════════════════════════════════════════════

FORM_STAGES = {
    "annual_root": [
        "three to five small ochre-brown seeds, partly buried in soil, close to the ground",
        "five to seven tender yellow-green shoots, about 30 percent of mature height, small cotyledon leaves",
        "leafy green tops with developing root shoulders barely visible at soil line, about 70 percent of mature height",
        "bushy green feathery leaf tops above visible orange root bodies at soil line, full mature height",
    ],
    "annual_berry": [
        "three to five small flat seeds on the soil surface, close to the ground",
        "five to seven tender green seedlings with first true leaves, about 30 percent of mature height",
        "leafy green bush with small green fruits just beginning to form, about 70 percent of mature height",
        "full bush with ripe red fruits hanging from stems among green leaves, mature height",
    ],
    "annual_large": [
        "three to five flat seeds on soil surface, close to the ground",
        "three to five low spreading vines with first true leaves, about 25 percent of mature spread",
        "spreading vines with large leaves and small green fruits forming, about 60 percent of mature spread",
        "large mature fruits resting on sprawling vines among broad leaves, full size",
    ],
    "bush": [
        "tiny seeds scattered on soil surface, close to the ground",
        "low green seedlings with first trifoliate leaves, about 30 percent of mature size",
        "small bushy plant with a few flowers and small green berries forming, about 70 percent of mature size",
        "low bush with ripe berries among green leaves, full mature size",
    ],
    "flower_tall": [
        "dark striped seeds on soil surface, close to the ground",
        "sturdy green seedling with a thick stem and first leaves, about 25 percent of mature height",
        "tall stem with broad leaves and a small green bud forming at the top, about 70 percent of mature height",
        "tall stem with a full golden-yellow flower head facing the viewer, broad leaves along the stem, mature height",
    ],
    "flower_spike": [
        "tiny dark seeds on soil surface, close to the ground",
        "low gray-green seedling with narrow leaves, about 30 percent of mature height",
        "multiple slender stems with leaf growth and small flower bud clusters forming, about 70 percent of mature height",
        "slender silvery-green stems topped with dense purple flower spikes, full mature height",
    ],
    "flower_round": [
        "small dark seeds on soil surface, close to the ground",
        "green seedling with a thorny stem and first compound leaves, about 30 percent of mature height",
        "leafy bush with pointed flower buds just beginning to open, about 70 percent of mature height",
        "bush with open roses and compound green leaves on thorny stems, full mature height",
    ],
    "tree": [
        "small brown seed or pit on soil surface, close to the ground",
        "tiny sapling with a thin trunk and a few small leaves, about 20 percent of mature height",
        "small tree with a visible trunk and a leafy canopy, about 60 percent of mature height",
        "full tree with ripe fruit visible among green leaves in the canopy, mature height",
    ],
    "vine": [
        "small dark seeds on soil surface, close to the ground",
        "thin climbing vine with first lobed leaves, about 25 percent of mature spread",
        "spreading vine with large lobed leaves and tiny green grape clusters forming, about 65 percent of mature spread",
        "vine with large lobed leaves and hanging clusters of purple grapes, full mature spread",
    ],
}

AI_PALETTES = {
    "carrot": "muted orange roots, natural green feathery tops, ochre soil",
    "potato": "earthy tan-brown tubers, natural green leafy tops, brown soil",
    "tomato": "muted red ripe fruits, natural green stems and leaves, no neon",
    "watermelon": "dark green striped rind, pale green inner flesh hint, natural vine greens",
    "pumpkin": "muted ochre-orange pumpkins, natural green vine leaves, brown stems",
    "strawberry": "muted red berries with tiny seeds, natural green trifoliate leaves",
    "blueberry": "muted dusky blue-purple berries, natural gray-green leaves",
    "sunflower": "muted golden-yellow petals, dark brown center disc, natural green stalk and leaves",
    "lavender": "muted soft purple flower spikes, silvery-gray-green narrow leaves and stems",
    "rose": "muted crimson-pink rose petals, natural green compound leaves, thorny stems",
    "apple": "muted red apples, natural green canopy leaves, brown bark trunk",
    "peach": "soft pinkish-orange peach skin, natural green leaves, brown bark",
    "lemon": "muted yellow lemons, natural green glossy leaves, brown bark",
    "grape": "muted deep purple grape clusters, natural green lobed vine leaves, brown vine",
}


def write_ai_batch(batch_path):
    """Write JSONL batch file for AI image generation."""
    batch_path.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    with open(batch_path, "w", encoding="utf-8") as f:
        for crop in CROPS:
            form = crop["form"]
            palette = AI_PALETTES[crop["id"]]
            for stage in range(4):
                stage_desc = FORM_STAGES[form][stage]
                for variant in range(3):
                    for layer in ["back", "front"]:
                        if layer == "back":
                            prompt = f"hand-painted semi-realistic {crop['name_en']} crop cluster, growth stage {stage_desc}, variation {variant}"
                            subject = "only the taller rear plants; natural height, bend, and spacing differences; include a subtle painted soil contact shadow at the roots"
                            constraints = "opaque crop artwork, crisp soft-painted edges, no front plants, no square soil tile, no text, no watermark"
                        else:
                            prompt = f"complementary shorter foreground plants for the same {crop['name_en']} cluster, growth stage {stage_desc}, variation {variant}"
                            subject = "only the shorter front plants; leave open gaps so the back plants remain visible; no cast or contact shadow"
                            constraints = "match the back layer's brushwork, lighting, scale, and natural muted palette; no duplicated rear plants, no text, no watermark"

                        job = {
                            "prompt": prompt,
                            "use_case": "stylized-concept",
                            "style": "hand-painted semi-realistic; brushwork, palette, outline, and upper-left lighting matching tree-oak-large.png style reference",
                            "subject": subject,
                            "composition": "centered on a square canvas, shared root anchor at 82% canvas height, generous transparent padding, game camera sees the plants from an elevated three-quarter view",
                            "lighting": "upper-left warm directional light with soft ambient fill",
                            "palette": palette,
                            "materials": "painted on canvas texture with visible soft brush strokes and natural edge variation",
                            "constraints": constraints,
                            "negative": "photorealism, plastic 3D rendering, black outlines, scenery, sky, horizon, pots, tools, characters, neon colors",
                            "_meta": {"crop_id": crop["id"], "stage": stage, "variant": variant, "layer": layer},
                        }
                        f.write(json.dumps(job, ensure_ascii=False) + "\n")
                        count += 1
    return count


# ═══════════════════════════════════════════════════════════════════════════
#  COMMANDS
# ═══════════════════════════════════════════════════════════════════════════

def cmd_pil(args):
    """Generate textures using enhanced PIL-based rendering."""
    if not HAS_PIL:
        print("Error: PIL/Pillow and numpy are required for PIL mode.")
        sys.exit(1)

    base_dir = ASSETS_DIR
    total = 0
    for crop in CROPS:
        crop_id = crop["id"]
        crop_seed = hash(crop_id) % 10000
        for stage in range(4):
            for variant in range(3):
                full_img = generate_full_image(crop, stage, variant, crop_seed)
                back_img, front_img = split_into_layers(full_img)
                for layer_name, layer_img in [("back", back_img), ("front", front_img)]:
                    path = base_dir / crop_id / "painted" / f"stage_{stage}" / f"variant_{variant}_{layer_name}.png"
                    path.parent.mkdir(parents=True, exist_ok=True)
                    layer_img.save(str(path), 'PNG')
                    total += 1
        print(f"  Generated 24 textures for {crop_id} ({crop['name_zh']})")

    print(f"\nDone! Generated {total} hand-painted style crop textures.")


def cmd_ai(args):
    """Generate textures using AI image generation pipeline."""
    # Step 1: Prepare batch
    print("Step 1: Preparing batch file...")
    count = write_ai_batch(BATCH_FILE)
    print(f"  {count} jobs written to {BATCH_FILE}")

    # Step 2: Run image generation
    print("\nStep 2: Running AI image generation...")
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    gen_cmd = [
        sys.executable, str(IMAGE_GEN), "generate-batch",
        "--input", str(BATCH_FILE),
        "--size", "1024x1024",
        "--quality", "medium",
        "--background", "opaque",
        "--concurrency", "5",
        "--out-dir", str(RAW_DIR),
        "--force",
    ]
    result = subprocess.run(gen_cmd)
    if result.returncode != 0:
        print(f"  Image generation failed (exit code {result.returncode})")
        print("  You can run the batch manually:")
        print(f'  python "{IMAGE_GEN}" generate-batch --input "{BATCH_FILE}" --size 1024x1024 --quality medium --background opaque --concurrency 5 --out-dir "{RAW_DIR}" --force')
        return

    # Step 3: Chroma-key removal + resize
    print("\nStep 3: Post-processing...")
    expected = []
    for crop in CROPS:
        for stage in range(4):
            for variant in range(3):
                expected.append((crop["id"], stage, variant, "back"))
                expected.append((crop["id"], stage, variant, "front"))

    raw_files = sorted(RAW_DIR.glob("output_*.png")) if RAW_DIR.exists() else []
    success = 0
    for i, (crop_id, stage, variant, layer) in enumerate(expected):
        if i >= len(raw_files):
            break
        raw_path = raw_files[i]
        final_path = ASSETS_DIR / crop_id / "painted" / f"stage_{stage}" / f"variant_{variant}_{layer}.png"
        final_path.parent.mkdir(parents=True, exist_ok=True)
        cmd = [sys.executable, str(CHROMA_KEY),
               "--input", str(raw_path), "--out", str(final_path),
               "--auto-key", "border", "--soft-matte",
               "--transparent-threshold", "12", "--opaque-threshold", "220",
               "--despill", "--force"]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            # Retry with edge contraction
            cmd.append("--edge-contract")
            cmd.append("1")
            r2 = subprocess.run(cmd, capture_output=True, text=True)
            if r2.returncode != 0:
                print(f"  FAILED: {crop_id} stage {stage} variant {variant} {layer}")
                continue
        # Resize to 1024x1024 if needed
        if HAS_PIL:
            img = Image.open(final_path)
            if img.size != (1024, 1024):
                img = img.resize((1024, 1024), Image.LANCZOS)
                img.save(str(final_path), 'PNG')
        success += 1

    print(f"  {success}/{len(expected)} textures processed successfully.")
    print("\nDone! Run 'python scripts/tools/generate_crop_assets.py validate' to check.")


def cmd_validate(args):
    """Validate all generated textures."""
    if not HAS_PIL:
        print("PIL/Pillow required for validation.")
        return
    missing = 0
    bad_alpha = 0
    bad_size = 0
    for crop in CROPS:
        for stage in range(4):
            for variant in range(3):
                for layer in ["back", "front"]:
                    path = ASSETS_DIR / crop["id"] / "painted" / f"stage_{stage}" / f"variant_{variant}_{layer}.png"
                    if not path.exists():
                        missing += 1
                        continue
                    img = Image.open(path)
                    if img.mode != "RGBA":
                        bad_alpha += 1
                    elif img.getpixel((0, 0))[3] != 0:
                        bad_alpha += 1
                    if img.size != (1024, 1024):
                        bad_size += 1
    total = 14 * 4 * 3 * 2
    ok = total - missing - bad_alpha - bad_size
    print(f"Validation: {ok}/{total} textures OK, {missing} missing, {bad_alpha} bad alpha, {bad_size} wrong size")
    if ok == total:
        print("PASS: all textures valid!")
    else:
        print("FAIL: some textures need attention.")


def cmd_prepare_batch(args):
    """Write JSONL batch file for AI generation without running it."""
    count = write_ai_batch(BATCH_FILE)
    print(f"Generated batch file with {count} jobs: {BATCH_FILE}")
    print()
    print("Run image generation with:")
    print(f'  python "{IMAGE_GEN}" generate-batch \\')
    print(f'    --input "{BATCH_FILE}" \\')
    print(f'    --size 1024x1024 \\')
    print(f'    --quality medium \\')
    print(f'    --background opaque \\')
    print(f'    --concurrency 5 \\')
    print(f'    --out-dir "{RAW_DIR}" \\')
    print(f'    --force')


def main():
    parser = argparse.ArgumentParser(
        description="Generate hand-painted crop textures matching grain art style"
    )
    sub = parser.add_subparsers(dest="command")

    sub.add_parser("pil", help="Generate textures using enhanced PIL rendering (no API key needed)")
    sub.add_parser("ai", help="Generate textures using AI image generation (requires OPENAI_API_KEY)")
    sub.add_parser("validate", help="Validate all generated textures")
    sub.add_parser("prepare-batch", help="Write JSONL batch file for AI generation")

    args = parser.parse_args()

    if args.command == "pil":
        cmd_pil(args)
    elif args.command == "ai":
        cmd_ai(args)
    elif args.command == "validate":
        cmd_validate(args)
    elif args.command == "prepare-batch":
        cmd_prepare_batch(args)
    else:
        parser.print_help()
        print("\nQuick start (no API key needed):")
        print("  python scripts/tools/generate_crop_assets.py pil")
        print("\nFor AI-generated textures (higher quality, requires OPENAI_API_KEY):")
        print("  python scripts/tools/generate_crop_assets.py ai")


if __name__ == "__main__":
    main()
