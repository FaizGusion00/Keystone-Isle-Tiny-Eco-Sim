#!/usr/bin/env python3
"""Generates Keystone Isle's sprite atlas (original art, CC0 - made for this project).

Every sprite is authored as an SVG (vector, soft gradients) in *world pixels* with its
anchor at the tile's ground centre, rendered at SCALE x with CairoSVG, then shelf-packed into
assets/art/atlas.png. The packer also writes scripts/world/art_atlas.gd (regions + anchors).
Sprites listed in SWAY are packed in the first shelf so their top edge has UV.y == 0; the
world shader uses that to bend tree tops in the wind without redrawing any chunk.

Run:  python3 tools/art/make_atlas.py
"""
import io, math, os, random
import cairosvg
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCALE = 2
sprites = {}  # name -> (svg_body, w, h, ax, ay)


def P(X, Y, Z=0.0):
    """iso projection of a point in tile units (X,Y) and height Z (world px)."""
    return ((X - Y) * 32.0, (X + Y) * 16.0 - Z)


def poly(pts, fill, extra=""):
    d = " ".join(f"{x:.2f},{y:.2f}" for x, y in pts)
    return f'<polygon points="{d}" fill="{fill}" {extra}/>'


def shadow(rx, ry, cx=0.0, cy=0.0, a=0.28):
    return (f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="url(#sh)" opacity="{a}"/>')


DEFS = '''<defs>
<radialGradient id="sh"><stop offset="0" stop-color="#1d2a24" stop-opacity="1"/><stop offset="1" stop-color="#1d2a24" stop-opacity="0"/></radialGradient>
<radialGradient id="glow"><stop offset="0" stop-color="#ffd27a" stop-opacity=".9"/><stop offset="1" stop-color="#ff8a3d" stop-opacity="0"/></radialGradient>
</defs>'''


def add(name, body, w, h, ax, ay):
    sprites[name] = (body, w, h, ax, ay)


def svg_for(body, w, h, ax, ay):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w*SCALE}" height="{h*SCALE}" '
            f'viewBox="{-ax} {-ay} {w} {h}">{DEFS}{body}</svg>')


# ------------------------------------------------------------------ trees (sway shelf)
def lerp_hex(a, b, t):
    a = [int(a[i:i+2], 16) for i in (1, 3, 5)]
    b = [int(b[i:i+2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(x + (y - x) * t):02x}" for x, y in zip(a, b))


def pine(name, height, width, tiers, dark, light, seed):
    r = random.Random(seed)
    b = shadow(width * 0.55, width * 0.26, 2, 1)
    b += f'<rect x="-1.6" y="{-8}" width="3.2" height="9" rx="1" fill="#6b4a33"/>'
    base = 5.0
    for k in range(tiers):
        t = k / max(1, tiers - 1)
        y0 = -base - k * (height - base) / (tiers + 0.6)
        wd = width * (1.0 - 0.62 * t) * 0.5
        top = y0 - (height - base) / tiers * 1.55
        col = lerp_hex(dark, light, 0.15 * k)
        b += poly([(-wd, y0), (wd, y0), (0.4, top)], col)
        # lit left half
        b += poly([(-wd, y0), (-wd * 0.15, y0 + 0.5), (0.4, top)], lerp_hex(col, light, 0.45))
        b += poly([(-wd, y0), (wd, y0), (wd*0.7, y0 + 1.6), (-wd*0.7, y0 + 1.6)], lerp_hex(dark, "#203528", 0.4), 'opacity=".55"')
    add(name, b, width + 8, height + 6, (width + 8) / 2, height + 2)


def round_tree(name, height, width, dark, mid, light, seed):
    r = random.Random(seed)
    b = shadow(width * 0.55, width * 0.27, 2, 1)
    b += f'<path d="M-1.8 1 L-1.2 {-height*0.42} L1.2 {-height*0.42} L1.8 1 Z" fill="#6e4d35"/>'
    cy = -height * 0.58
    blobs = []
    for _ in range(7):
        a = r.uniform(0, math.tau)
        d = r.uniform(0.0, 0.45)
        blobs.append((math.cos(a) * width * d * 0.5, cy + math.sin(a) * height * d * 0.32, r.uniform(0.28, 0.4) * width))
    blobs.sort(key=lambda t: t[1])
    for x, y, rad in blobs:
        b += f'<circle cx="{x:.2f}" cy="{y + 1.5:.2f}" r="{rad:.2f}" fill="{dark}"/>'
    for x, y, rad in blobs:
        b += f'<circle cx="{x:.2f}" cy="{y:.2f}" r="{rad*0.92:.2f}" fill="{mid}"/>'
    for x, y, rad in blobs[:4]:
        b += f'<circle cx="{x - rad*0.25:.2f}" cy="{y - rad*0.3:.2f}" r="{rad*0.5:.2f}" fill="{light}" opacity=".8"/>'
    add(name, b, width + 10, height + 6, (width + 10) / 2, height + 2)


pine("pine_a", 40, 22, 4, "#2f5a43", "#6c9a66", 1)
pine("pine_b", 50, 20, 5, "#2b5340", "#5f8f5f", 2)
pine("pine_c", 32, 18, 3, "#35634a", "#77a46c", 3)
round_tree("oak_a", 36, 28, "#3f6a3a", "#5f8c48", "#8db564", 4)
round_tree("oak_b", 30, 24, "#4a6d34", "#728f42", "#a2b866", 5)
round_tree("oak_c", 40, 30, "#3b6539", "#56854a", "#84b06a", 6)
round_tree("bush", 14, 16, "#466c3a", "#6a9450", "#97bd72", 7)
# sapling: small stake + 3 leaves
b = shadow(6, 3, 1, 1) + '<rect x="2.5" y="-14" width="1.2" height="15" fill="#8a6a48"/>'
b += '<path d="M0 1 L0 -9" stroke="#6b4a33" stroke-width="1.4"/>'
for x, y, rr in [(-3, -10, 3.4), (3, -11, 3.2), (0, -14, 3.6)]:
    b += f'<circle cx="{x}" cy="{y}" r="{rr}" fill="#6f9e52"/><circle cx="{x-1}" cy="{y-1}" r="{rr*0.5}" fill="#a3c97a"/>'
add("sapling", b, 16, 22, 8, 19)
# burnt snag
b = shadow(7, 3, 1, 1, 0.22)
b += '<path d="M-1.5 1 L-1 -22 L1 -22 L1.6 1 Z" fill="#3a302b"/>'
b += '<path d="M0 -14 L-7 -20 M0 -10 L6 -17 M0 -18 L4 -25" stroke="#3a302b" stroke-width="1.6" stroke-linecap="round"/>'
add("snag", b, 18, 30, 9, 27)
# grass tuft + flowers (also sway)
b = ""
for k, (x, h) in enumerate([(-3, 6), (-1, 8), (1, 7), (3, 5), (0, 9)]):
    b += f'<path d="M{x} 0 Q{x + 0.6} {-h*0.5} {x + (1 if k % 2 else -1)} {-h}" stroke="#5f8a45" stroke-width="1.2" fill="none" stroke-linecap="round"/>'
add("tuft", b, 10, 11, 5, 10)
b = ""
for x, y, c in [(-3, -5, "#f2e6c8"), (2, -6, "#e8b6c4"), (0, -3, "#f6d27a")]:
    b += f'<path d="M{x} 0 L{x} {y}" stroke="#5f8a45" stroke-width="1"/><circle cx="{x}" cy="{y}" r="1.5" fill="{c}"/>'
add("flowers", b, 10, 9, 5, 8)
# reeds by the water
b = ""
for x, h in [(-4, 10), (-1, 13), (2, 11), (4, 8)]:
    b += f'<path d="M{x} 0 L{x+0.5} {-h}" stroke="#7f8f4a" stroke-width="1.1"/><rect x="{x-0.3}" y="{-h+1}" width="1.6" height="3.5" rx=".8" fill="#7a5638"/>'
add("reeds", b, 12, 15, 6, 14)
# crops (sway): one plant cluster, drawn in rows by the renderer
for name, col, h, hi in [("crop_sprout", "#8fbf5e", 4, "#b8dc85"), ("crop_green", "#5f9a45", 8, "#8cc163"),
                         ("crop_ripe", "#d9b44a", 9, "#f1d77e"), ("crop_dry", "#a88f52", 6, "#c4ad70")]:
    b = ""
    for x in (-2.5, 0, 2.5):
        b += f'<path d="M{x} 0 Q{x+0.5} {-h*0.6} {x+0.3} {-h}" stroke="{col}" stroke-width="1.5" fill="none" stroke-linecap="round"/>'
        if name in ("crop_ripe",):
            b += f'<ellipse cx="{x+0.3}" cy="{-h+1}" rx="1" ry="2" fill="{hi}"/>'
        elif name != "crop_sprout":
            b += f'<ellipse cx="{x-0.8}" cy="{-h*0.55}" rx="1.4" ry=".8" fill="{hi}"/>'
    add(name, b, 10, h + 3, 5, h + 2)
SWAY = [n for n in sprites]

# ------------------------------------------------------------------ structures


def box(x0, x1, y0, y1, z0, z1, top, left, right):
    """axis-aligned box; returns svg for the 3 visible faces (top, +Y face, +X face)."""
    s = poly([P(x0, y1, z0), P(x1, y1, z0), P(x1, y1, z1), P(x0, y1, z1)], left)
    s += poly([P(x1, y0, z0), P(x1, y1, z0), P(x1, y1, z1), P(x1, y0, z1)], right)
    s += poly([P(x0, y0, z1), P(x1, y0, z1), P(x1, y1, z1), P(x0, y1, z1)], top)
    return s


def house(x0, x1, y0, y1, wall_h, roof_h, wall, roof, roof_dark, door=True, chimney=False, windows=1):
    wl, wr = wall, lerp_hex(wall, "#6b6152", 0.32)
    s = box(x0, x1, y0, y1, 0, wall_h, wall, wl, wr)
    ym = (y0 + y1) / 2
    ov = 0.06
    # roof ridge along X
    s += poly([P(x0 - ov, y1 + ov, wall_h - 1), P(x1 + ov, y1 + ov, wall_h - 1), P(x1 + ov, ym, wall_h + roof_h), P(x0 - ov, ym, wall_h + roof_h)], roof)
    s += poly([P(x1 + ov, y1 + ov, wall_h - 1), P(x1 + ov, y0 - ov, wall_h - 1), P(x1 + ov, ym, wall_h + roof_h)], lerp_hex(wr, "#000000", 0.05))
    s += poly([P(x1, y1, wall_h), P(x1, y0, wall_h), P(x1, ym, wall_h + roof_h - 1.5)], wr)
    # ridge highlight + eave shadow
    a, c = P(x0 - ov, ym, wall_h + roof_h), P(x1 + ov, ym, wall_h + roof_h)
    s += f'<line x1="{a[0]:.2f}" y1="{a[1]:.2f}" x2="{c[0]:.2f}" y2="{c[1]:.2f}" stroke="{lerp_hex(roof, "#ffffff", 0.3)}" stroke-width="1"/>'
    s += poly([P(x0, y1, wall_h - 1), P(x1, y1, wall_h - 1), P(x1, y1, wall_h - 3), P(x0, y1, wall_h - 3)], "#000000", 'opacity=".12"')
    if door:
        dx = x0 + (x1 - x0) * 0.62
        s += poly([P(dx, y1, 0), P(dx + 0.12, y1, 0), P(dx + 0.12, y1, 7), P(dx, y1, 7)], "#6b4a33")
    for k in range(windows):
        wx = x0 + (x1 - x0) * (0.18 + 0.0 * k)
        s += poly([P(wx, y1, 4), P(wx + 0.11, y1, 4), P(wx + 0.11, y1, 8), P(wx, y1, 8)], "#f3d68f")
        s += poly([P(x1, y0 + (y1 - y0) * 0.35, 4), P(x1, y0 + (y1 - y0) * 0.35 + 0.1, 4), P(x1, y0 + (y1 - y0) * 0.35 + 0.1, 8), P(x1, y0 + (y1 - y0) * 0.35, 8)], "#d9bd7c")
    if chimney:
        cx = x0 + (x1 - x0) * 0.25
        s += box(cx, cx + 0.08, ym - 0.12, ym - 0.04, wall_h, wall_h + roof_h + 4, "#9a8f84", "#8a7f74", "#6f665d")
    return s


def struct(name, body, sh=(20, 9), w=64, h=64, ay=48):
    add(name, shadow(sh[0], sh[1], 2, 2, 0.3) + body, w, h, w / 2, ay)


struct("cottage", house(-0.2, 0.16, -0.14, 0.14, 9, 7, "#efe4cf", "#c4664c", "#a14f3b"), (16, 8), 48, 40, 30)
struct("cottage_b", house(-0.2, 0.16, -0.14, 0.14, 9, 7, "#e9dcc4", "#5f7489", "#4a5d70", chimney=True), (16, 8), 48, 40, 30)
struct("cottage_c", house(-0.2, 0.16, -0.14, 0.14, 9, 6, "#efe6d3", "#c9a35e", "#a8853f"), (16, 8), 48, 40, 30)
struct("house_big", house(-0.26, 0.22, -0.18, 0.18, 15, 9, "#f1e7d4", "#b85c45", "#984a37", chimney=True, windows=2), (22, 10), 64, 56, 44)
struct("hall", house(-0.3, 0.3, -0.2, 0.2, 13, 11, "#ece0c6", "#7d6a9a", "#665681", chimney=True, windows=2), (26, 12), 72, 60, 46)
# well
b = box(-0.08, 0.08, -0.08, 0.08, 0, 5, "#5e88a6", "#a59c90", "#857c71")
b += f'<rect x="-6" y="-17" width="1.4" height="12" fill="#6b4a33"/><rect x="4.6" y="-17" width="1.4" height="12" fill="#6b4a33"/>'
b += poly([(-8, -16), (8, -16), (0, -22)], "#b35f47")
struct("well", b, (9, 4), 24, 28, 22)
# market stall
b = box(-0.12, 0.12, -0.1, 0.1, 0, 4, "#c69a6a", "#a88058", "#8c6a48")
b += poly([P(-0.16, 0.14, 10), P(0.16, 0.14, 10), P(0.16, -0.14, 12), P(-0.16, -0.14, 12)], "#e6c35c")
b += poly([P(-0.16, 0.14, 10), P(0.0, 0.14, 10), P(0.0, -0.14, 12), P(-0.16, -0.14, 12)], "#f2efe6")
struct("stall", b, (10, 5), 28, 28, 22)
# dams: wall across the tile, two orientations
for nm, (x0, x1, y0, y1) in {"dam_x": (-0.12, 0.12, -0.46, 0.46), "dam_y": (-0.46, 0.46, -0.12, 0.12)}.items():
    b = box(x0, x1, y0, y1, 0, 9, "#b9b0a0", "#958b7b", "#7c7366")
    # stone courses
    for z in (3, 6):
        a, c = P(x0, y1, z), P(x1, y1, z)
        a2, c2 = P(x1, y0, z), P(x1, y1, z)
        b += f'<line x1="{a[0]:.1f}" y1="{a[1]:.1f}" x2="{c[0]:.1f}" y2="{c[1]:.1f}" stroke="#7a705f" stroke-width=".7"/>'
        b += f'<line x1="{a2[0]:.1f}" y1="{a2[1]:.1f}" x2="{c2[0]:.1f}" y2="{c2[1]:.1f}" stroke="#665e52" stroke-width=".7"/>'
    # timber cap
    b += box(x0 - 0.02, x1 + 0.02, y0 - 0.02, y1 + 0.02, 9, 11, "#a07a52", "#86643f", "#6e5234")
    struct(nm, b, (22, 10), 72, 48, 30)
# goat
b = shadow(5, 2, 0, 1, 0.25)
b += '<ellipse cx="0" cy="-4" rx="4.2" ry="2.6" fill="#f2efe8"/><ellipse cx="0.5" cy="-3.2" rx="3.6" ry="1.6" fill="#d8d3c8"/>'
b += '<rect x="-3" y="-2.4" width=".9" height="3" fill="#6a5e52"/><rect x="2" y="-2.4" width=".9" height="3" fill="#6a5e52"/>'
b += '<ellipse cx="-4.4" cy="-6" rx="1.6" ry="1.3" fill="#e9e4da"/><path d="M-4.6 -7 L-5.5 -8.8" stroke="#8a7f70" stroke-width=".7"/>'
add("goat", b, 14, 12, 7, 10)
b = shadow(5, 2, 0, 1, 0.25)
b += '<ellipse cx="0" cy="-4" rx="4.2" ry="2.6" fill="#7a6250"/><ellipse cx="0.5" cy="-3.2" rx="3.6" ry="1.6" fill="#62503f"/>'
b += '<rect x="-3" y="-2.4" width=".9" height="3" fill="#3e342c"/><rect x="2" y="-2.4" width=".9" height="3" fill="#3e342c"/>'
b += '<ellipse cx="4.4" cy="-6" rx="1.6" ry="1.3" fill="#86705c"/><path d="M4.6 -7 L5.5 -8.8" stroke="#5a4e40" stroke-width=".7"/>'
add("goat_b", b, 14, 12, 7, 10)
# fish leaping
b = '<path d="M-6 0 Q-3 -2 0 0 Q3 2 6 0" stroke="#e8f4f6" stroke-width="1" fill="none" opacity=".8"/>'
b += '<path d="M-3 -2 Q0 -9 4 -5 L5 -3 Q1 -6 -2 -1 Z" fill="#c9dbe0"/><path d="M4 -5 L7 -7 L6 -3 Z" fill="#a9c2ca"/>'
add("fish", b, 16, 12, 8, 9)
# boat
b = '<path d="M-9 -2 L9 -2 L6 2 L-6 2 Z" fill="#8a5d3b"/><path d="M-9 -2 L9 -2 L8 -1 L-8 -1 Z" fill="#a8774f"/>'
b += '<path d="M0 -2 L0 -16" stroke="#6b4a33" stroke-width="1"/><path d="M0.6 -15 L8 -4 L0.6 -4 Z" fill="#f2ead9"/>'
add("boat", b, 22, 22, 11, 18)
# rocks
for nm, pts, col in [("rock_a", [(-7, 1), (-5, -5), (0, -7), (6, -3), (7, 1)], "#a39a8c"),
                     ("rock_b", [(-5, 1), (-3, -4), (2, -5), (5, 1)], "#9b9384")]:
    b = shadow(8, 3, 1, 1, 0.22) + poly(pts, col)
    b += poly([pts[0], pts[1], pts[2], (pts[2][0] - 1, pts[2][1] + 3)], lerp_hex(col, "#ffffff", 0.25))
    add(nm, b, 18, 12, 9, 9)
# fire (flicker shelf handled by colour marker, not UVs)
for nm, s in [("fire_a", 1.0), ("fire_b", 0.85)]:
    b = '<ellipse cx="0" cy="-6" rx="12" ry="9" fill="url(#glow)"/>'
    b += f'<path d="M-6 0 Q-8 {-9*s} -2 {-18*s} Q-1 {-11*s} 1 {-10*s} Q2 {-17*s} 5 {-20*s} Q9 {-9*s} 6 0 Z" fill="#f08a3c"/>'
    b += f'<path d="M-3 0 Q-4 {-6*s} 0 {-12*s} Q1 {-7*s} 2 {-7*s} Q4 {-10*s} 4 {-12*s} Q6 {-6*s} 3 0 Z" fill="#ffd66b"/>'
    add(nm, b, 28, 26, 14, 22)
# smoke puff
b = '<circle cx="0" cy="-6" r="5" fill="#8d8a86" opacity=".55"/><circle cx="4" cy="-9" r="4" fill="#a19e99" opacity=".45"/>'
add("smoke", b, 16, 16, 7, 12)


# ------------------------------------------------------------------ pack
def render(name):
    body, w, h, ax, ay = sprites[name]
    png = cairosvg.svg2png(bytestring=svg_for(body, w, h, ax, ay).encode())
    return Image.open(io.BytesIO(png)).convert("RGBA")


ATLAS_W = 1024
images = {n: render(n) for n in sprites}
order = SWAY + sorted([n for n in sprites if n not in SWAY], key=lambda n: -images[n].height)
PAD = 4
x = PAD
y = 0  # sway shelf starts exactly at the top edge (UV.y == 0 marks tree tops)
shelf_h = 0
regions = {}
first_shelf = True
for n in order:
    im = images[n]
    if n not in SWAY and first_shelf:
        first_shelf = False
        x, y, shelf_h = PAD, y + shelf_h + PAD, 0
    if x + im.width + PAD > ATLAS_W:
        assert not (n in SWAY), "sway sprites must fit in one shelf"
        x, y, shelf_h = PAD, y + shelf_h + PAD, 0
    regions[n] = (x, y, im.width, im.height)
    x += im.width + PAD
    shelf_h = max(shelf_h, im.height)
H = 1
while H < y + shelf_h + PAD:
    H *= 2
atlas = Image.new("RGBA", (ATLAS_W, H), (0, 0, 0, 0))
for n, (rx, ry, rw, rh) in regions.items():
    atlas.paste(images[n], (rx, ry))
# Bleed: copy edge colours into transparent padding (keeps alpha 0) to avoid dark fringes.
rgb = atlas.copy()
blur = atlas.filter(ImageFilter.MaxFilter(5))
px_a, px_b = rgb.load(), blur.load()
for yy in range(H):
    for xx in range(ATLAS_W):
        r, g, b_, a = px_a[xx, yy]
        if a == 0:
            r2, g2, b2, a2 = px_b[xx, yy]
            if a2 > 0:
                px_a[xx, yy] = (r2, g2, b2, 0)
rgb.save(os.path.join(ROOT, "assets/art/atlas.png"))

sway_h = max(regions[n][3] for n in SWAY)
lines = ["class_name ArtAtlas", "extends RefCounted",
         "## GENERATED by tools/art/make_atlas.py - do not edit by hand.",
         "## name -> [x, y, w, h, anchor_x, anchor_y] in atlas pixels (SCALE px per world px).",
         "", f"const SCALE := {SCALE}.0", f"const SWAY_SHELF_H := {sway_h}",
         "const TEXTURE := preload(\"res://assets/art/atlas.png\")", "", "const R := {"]
for n in sorted(regions):
    rx, ry, rw, rh = regions[n]
    ax, ay = sprites[n][3] * SCALE, sprites[n][4] * SCALE
    lines.append(f'\t"{n}": [{rx}, {ry}, {rw}, {rh}, {ax:g}, {ay:g}],')
lines.append("}")
open(os.path.join(ROOT, "scripts/world/art_atlas.gd"), "w").write("\n".join(lines) + "\n")

# ------------------------------------------------------------------ loose textures
def soft_blob(path, w, h, blobs, blur):
    im = Image.new("L", (w, h), 0)
    from PIL import ImageDraw
    d = ImageDraw.Draw(im)
    for cx, cy, rx, ry in blobs:
        d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=255)
    im = im.filter(ImageFilter.GaussianBlur(blur))
    out = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    out.putalpha(im)
    out.save(path)


soft_blob(os.path.join(ROOT, "assets/art/cloud.png"), 256, 128,
          [(80, 74, 48, 30), (128, 58, 56, 40), (180, 76, 46, 28), (130, 86, 80, 24)], 9)
soft_blob(os.path.join(ROOT, "assets/art/soft_dot.png"), 32, 32, [(16, 16, 9, 9)], 4)
drop = Image.new("RGBA", (4, 24), (255, 255, 255, 0))
for yy in range(24):
    a = int(200 * (yy / 23.0))
    for xx in (1, 2):
        drop.putpixel((xx, yy), (220, 232, 245, a))
drop.save(os.path.join(ROOT, "assets/art/raindrop.png"))
print("atlas", ATLAS_W, "x", H, len(regions), "sprites")
