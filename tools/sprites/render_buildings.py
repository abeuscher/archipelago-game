#!/usr/bin/env python3
"""Archipelago building sprite renderer.

Builds each installation from simple 3D primitives and renders it from the six
map rotations into transparent PNG sprite sheets (6 frames per sheet, left to
right = view 0..5).

    python render_buildings.py                      # 52px-wide hexes -> ./out
    python render_buildings.py --hex-width 104      # 2x art
    python render_buildings.py --only radar bank    # just some buildings
    python render_buildings.py --frames             # also one PNG per frame

Requires: numpy, pillow.

Conventions
  * World: x/y ground plane, z up. One unit = hex circumradius (centre to
    vertex). Hexes are pointy-top on screen.
  * Weapons face +x. In view 0, +x is screen-right. --facing rotates that.
  * View k = the scene turned k * 60 degrees counter-clockwise seen from above.
    If your in-game rotate buttons go the other way, pass --reverse.
  * --squash is (hex row spacing) / (0.75 * unsquashed hex height); i.e. how
    much the ground plane is flattened vertically. Match it to the map.
  * Light is fixed to the camera so every view is lit the same way.

To add a building: write a function returning a list of parts and register it
in BUILDINGS at the bottom.
"""
import argparse
import json
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

# ---------------------------------------------------------------- palette --
PAD_RIM = "#1b1c20"      # black base rim (red/yellow/orange are reserved for hex outlines)
PAD_TOP = "#a9a79d"
STEEL = "#5b5e63"
STEEL_LT = "#6c7076"
STEEL_DK = "#3b3f45"
GUNMETAL = "#2f3338"
CONCRETE = "#8b897f"
CONCRETE_LT = "#d9d7cf"
WHITE = "#e8e6df"
RED = "#d83a34"
RED_DK = "#8f1d1d"
GREEN = "#3f8f4f"
PURPLE = "#8a5fc7"
BLUE = "#5fa8d8"
GOLD = "#d4a72c"
RUST = "#b06a35"
FLAME = "#e8742a"
WOOD = "#b08a55"
TARP = "#8fa3ad"

BUILDING_SCALE = 0.8     # building units -> tile units (pad ends up ~2/3 of the tile)


# ------------------------------------------------------------- primitives --
def _xf(p, pitch, yaw, pos):
    """Pitch (raise +x end) about y, then yaw about z, then translate."""
    a, b = math.radians(pitch), math.radians(yaw)
    x = p[0] * math.cos(a) - p[2] * math.sin(a)
    z = p[0] * math.sin(a) + p[2] * math.cos(a)
    y = p[1]
    return (x * math.cos(b) - y * math.sin(b) + pos[0],
            x * math.sin(b) + y * math.cos(b) + pos[1],
            z + pos[2])


def _solid(r0, r1, color, caps=(True, True)):
    n = len(r0)
    faces = [[r0[i], r0[(i + 1) % n], r1[(i + 1) % n], r1[i]] for i in range(n)]
    if caps[0]:
        faces.append(list(r0))
    if caps[1]:
        faces.append(list(r1))
    return [(f, color) for f in faces]


def prism(n, r0, r1, z0, z1, color, at=(0, 0), rot=0, caps=(True, True)):
    """Vertical n-gon frustum: radius r0 at height z0, r1 at z1."""
    def ring(r, z):
        return [(at[0] + r * math.cos(math.radians(rot) + i * 2 * math.pi / n),
                 at[1] + r * math.sin(math.radians(rot) + i * 2 * math.pi / n), z)
                for i in range(n)]
    return _solid(ring(r0, z0), ring(r1, z1), color, caps)


def tube(n, r0, r1, length, color, pos, pitch=0, yaw=0, x0=0, lift=0, off=0,
         sy=1, sz=1, caps=(True, True)):
    """n-gon frustum along local +x (from x0 to x0+length), then pitched/yawed.
    lift offsets it along local z before the pitch; sy/sz squash the section."""
    def ring(r, x):
        return [_xf((x, sy * r * math.cos(math.radians(off) + i * 2 * math.pi / n),
                     lift + sz * r * math.sin(math.radians(off) + i * 2 * math.pi / n)),
                    pitch, yaw, pos) for i in range(n)]
    return _solid(ring(r0, x0), ring(r1, x0 + length), color, caps)


def box(size, color, pos, pitch=0, yaw=0):
    """Box of size (x, y, z) centred on pos, pitched/yawed about its centre."""
    sx, sy, sz = size
    c = [(sy / 2, sz / 2), (-sy / 2, sz / 2), (-sy / 2, -sz / 2), (sy / 2, -sz / 2)]
    r0 = [_xf((-sx / 2, y, z), pitch, yaw, pos) for y, z in c]
    r1 = [_xf((sx / 2, y, z), pitch, yaw, pos) for y, z in c]
    return _solid(r0, r1, color)


def beam(p, q, thick, color):
    """Square beam between two points in the same horizontal plane or not."""
    dx, dy, dz = q[0] - p[0], q[1] - p[1], q[2] - p[2]
    length = math.sqrt(dx * dx + dy * dy + dz * dz)
    yaw = math.degrees(math.atan2(dy, dx))
    pitch = math.degrees(math.atan2(dz, math.hypot(dx, dy)))
    mid = ((p[0] + q[0]) / 2, (p[1] + q[1]) / 2, (p[2] + q[2]) / 2)
    return box((length, thick, thick), color, mid, pitch=pitch, yaw=yaw)


def pad():
    return (prism(6, .84, .84, 0, .05, PAD_RIM, rot=90)
            + prism(6, .78, .78, .05, .12, PAD_TOP, rot=90))


# ---------------------------------------------------------------- models --
def missile_launcher(loaded=True):
    pivot = (-.3, 0, .25)
    m = pad()
    m += prism(12, .42, .42, .12, .2, STEEL, at=(-.05, 0))
    m += box((.1, .22, .42), STEEL_LT, (.16, 0, .41))
    m += box((1.1, .16, .06), "#474b52", (.121, 0, .604), pitch=40)
    if loaded:
        m += tube(4, .15, .085, .16, "#8d9197", pivot, pitch=40, x0=.04, lift=.13, off=45)
        m += tube(10, .085, .085, .82, WHITE, pivot, pitch=40, x0=.1, lift=.13)
        m += tube(10, .085, .001, .28, RED, pivot, pitch=40, x0=.92, lift=.13)
    m += box((.06, .62, .42), STEEL_DK, (-.62, 0, .33), pitch=-18)
    m += box((.4, .26, .22), CONCRETE, (-.1, .5, .23))
    m += box((.44, .3, .04), RED, (-.1, .5, .36))
    return m


def ballistic_launcher(loaded=True):
    m = pad()
    m += prism(8, .5, .45, .12, .22, STEEL)
    if loaded:
        m += box((.52, .04, .2), GUNMETAL, (.08, 0, .32))
        m += box((.52, .04, .2), GUNMETAL, (.08, 0, .32), yaw=90)
        m += prism(12, .14, .14, .22, 1.15, WHITE, at=(.08, 0))
        m += prism(12, .147, .147, .58, .7, GUNMETAL, at=(.08, 0))
        m += prism(12, .14, .001, 1.15, 1.5, RED_DK, at=(.08, 0))
        m += box((.3, .06, .05), "#59677a", (-.2, 0, .95))
        m += box((.3, .06, .05), "#59677a", (-.2, 0, .6))
    m += box((.16, .16, 1.15), "#59677a", (-.42, 0, .8))
    m += box((.22, .22, .05), STEEL_DK, (-.42, 0, 1.4))
    m += box((.34, .26, .2), CONCRETE, (.1, -.52, .22))
    m += box((.38, .3, .04), RED_DK, (.1, -.52, .34))
    return m


def anti_air():
    m = pad()
    m += prism(12, .5, .45, .12, .24, STEEL)
    m += prism(8, .3, .26, .24, .48, GREEN)
    m += box((.3, .52, .18), "#4a4f55", (.02, 0, .54))
    for y in (-.15, .15):
        m += tube(8, .05, .05, .78, GUNMETAL, (0, y, .54), pitch=50, x0=.05)
        m += tube(8, .07, .07, .12, "#16181b", (0, y, .54), pitch=50, x0=.78)
    m += box((.22, .2, .14), GREEN, (-.38, .3, .19))
    m += box((.22, .2, .14), "#4a4f55", (-.38, -.3, .19))
    return m


def radar():
    hub = (0, 0, .72)
    m = pad()
    m += prism(8, .4, .34, .12, .3, STEEL)
    m += prism(8, .385, .365, .18, .25, PURPLE)
    m += prism(8, .09, .09, .3, .66, STEEL_LT)
    m += box((.16, .16, .14), STEEL_DK, hub)
    m += tube(16, .07, .56, .2, WHITE, hub, pitch=35, x0=.06, caps=(True, False))
    m += tube(6, .02, .02, .42, GUNMETAL, hub, pitch=35, x0=.06)
    m += tube(8, .06, .06, .09, PURPLE, hub, pitch=35, x0=.46)
    m += box((.26, .22, .16), CONCRETE, (-.42, -.28, .2))
    return m


def bank():
    m = pad()
    m += box((1.0, .84, .06), "#c9c5b8", (0, 0, .15))
    m += box((.74, .6, .36), "#e3dfd2", (-.06, 0, .36))
    for y in (-.27, -.09, .09, .27):
        m += prism(8, .04, .04, .18, .54, WHITE, at=(.4, y))
    m += box((.96, .78, .04), "#c9c5b8", (0, 0, .56))
    m += tube(3, 1, 1, .96, GOLD, (-.48, 0, 0), lift=.655, off=90, sy=.45, sz=.15)
    m += box((.04, .14, .22), GUNMETAL, (.315, 0, .29))
    return m


def refinery():
    m = pad()
    m += prism(12, .26, .26, .12, .5, "#c8c4b8", at=(-.3, .3))
    m += prism(12, .26, .08, .5, .6, "#b4b0a4", at=(-.3, .3))
    m += prism(12, .2, .2, .12, .4, "#c8c4b8", at=(-.36, -.3))
    m += prism(12, .2, .06, .4, .48, "#b4b0a4", at=(-.36, -.3))
    m += prism(8, .11, .11, .12, .78, RUST, at=(.22, .38))
    m += prism(8, .13, .13, .5, .55, STEEL_DK, at=(.22, .38))
    m += prism(8, .09, .06, .12, 1.0, STEEL_LT, at=(.36, -.12))
    m += prism(8, .07, .07, .82, .9, WHITE, at=(.36, -.12))
    m += prism(8, .07, .001, 1.0, 1.18, FLAME, at=(.36, -.12))
    m += beam((-.3, .3, .3), (.22, .38, .3), .05, "#8a5a32")
    m += beam((-.36, -.3, .26), (.36, -.12, .26), .05, "#8a5a32")
    m += beam((.22, .38, .6), (.36, -.12, .6), .04, "#8a5a32")
    return m


def lab():
    c = (.12, .1)
    m = pad()
    m += box((.5, .4, .24), CONCRETE_LT, (-.34, -.3, .24))
    m += box((.54, .44, .03), STEEL_DK, (-.34, -.3, .375))
    m += prism(10, .5, .5, .12, .2, CONCRETE_LT, at=c)
    m += prism(10, .48, .44, .2, .36, BLUE, at=c)
    m += prism(10, .44, .32, .36, .52, BLUE, at=c)
    m += prism(10, .32, .14, .52, .62, BLUE, at=c)
    m += prism(10, .14, .001, .62, .66, WHITE, at=c)
    m += prism(4, .018, .018, .39, .95, GUNMETAL, at=(-.48, -.36))
    m += prism(6, .045, .045, .93, 1.0, RED, at=(-.48, -.36))
    return m


def base(flag=WHITE):
    m = pad()
    m += prism(6, .66, .56, .12, .42, CONCRETE_LT, rot=90)
    m += prism(6, .4, .34, .42, .66, "#efede6", rot=90)
    m += prism(6, .39, .375, .5, .56, "#2a3340", rot=90)
    m += prism(6, .37, .37, .66, .7, "#4a4f55", rot=90)
    m += box((.06, .22, .2), GUNMETAL, (.53, 0, .22))
    m += prism(4, .02, .02, .7, 1.2, GUNMETAL)
    m += box((.3, .025, .17), flag, (.17, 0, 1.1))
    return m


def decoy():
    return base(flag="#6c7076")


def repair():
    m = pad()
    m += box((.62, .62, .52), TARP, (0, 0, .38))
    poles = [(.6 * math.cos(math.radians(30 + 60 * i)),
              .6 * math.sin(math.radians(30 + 60 * i))) for i in range(6)]
    for x, y in poles:
        m += prism(4, .028, .028, .12, 1.0, "#c8ccd0", at=(x, y))
    for i in range(6):
        (x0, y0), (x1, y1) = poles[i], poles[(i + 1) % 6]
        m += beam((x0, y0, .5), (x1, y1, .5), .06, WOOD)
        m += beam((x0, y0, .92), (x1, y1, .92), .06, WOOD)
        if i % 2 == 0:
            m += beam((x0, y0, .5), (x1, y1, .92), .03, "#c8ccd0")
    return m


def rubble():
    rng = random.Random(7)
    m = pad()
    m += prism(6, .62, .62, .12, .125, "#3a3836", rot=90)
    greys = ["#5a5853", "#77756e", "#45433f", "#8b897f", "#2f2e2b"]
    for _ in range(11):
        r, a = rng.uniform(0, .45), rng.uniform(0, 2 * math.pi)
        s = (rng.uniform(.12, .3), rng.uniform(.1, .24), rng.uniform(.06, .2))
        m += box(s, rng.choice(greys), (r * math.cos(a), r * math.sin(a), .12 + s[2] / 2),
                 pitch=rng.uniform(-18, 18), yaw=rng.uniform(0, 180))
    m += beam((-.3, .1, .16), (.2, -.15, .5), .05, GUNMETAL)
    m += beam((.1, .3, .16), (.3, .05, .38), .04, GUNMETAL)
    return m


# name -> model function. Sheet files are <name>.png
BUILDINGS = {
    "missile_launcher": lambda: missile_launcher(True),
    "missile_launcher_empty": lambda: missile_launcher(False),
    "ballistic_launcher": lambda: ballistic_launcher(True),
    "ballistic_launcher_empty": lambda: ballistic_launcher(False),
    "anti_air": anti_air,
    "radar": radar,
    "bank": bank,
    "refinery": refinery,
    "lab": lab,
    "base": base,
    "decoy": decoy,
    "repair": repair,
    "rubble": rubble,
}


# --------------------------------------------------------------- renderer --
LIGHT = np.array([-0.45, -0.55, 0.7])
LIGHT /= np.linalg.norm(LIGHT)
AMBIENT = 0.5


def _rgb(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], dtype=float)


class Camera:
    def __init__(self, hex_width, squash, facing, reverse, supersample):
        self.scale = hex_width / math.sqrt(3)          # px per tile unit
        self.sp = squash
        self.cp = math.sqrt(1 - squash * squash)
        self.facing = math.radians(facing)
        self.dir = -1 if reverse else 1
        self.ss = supersample
        self.fw = int(math.ceil(self.scale * 2.2 / 2) * 2)
        self.fh = int(math.ceil(self.scale * 3.3 / 2) * 2)
        self.ax = self.fw / 2
        self.ay = round(self.fh - self.scale * 0.8)

    def yaw(self, view):
        return self.facing + self.dir * view * math.pi / 3

    def render(self, parts, view, outline=True):
        ss, W, H = self.ss, self.fw * self.ss, self.fh * self.ss
        color = np.zeros((H, W, 3))
        alpha = np.zeros((H, W), dtype=bool)
        zbuf = np.full((H, W), np.inf)
        c, s = math.cos(self.yaw(view)), math.sin(self.yaw(view))
        rot = np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])
        view_vec = np.array([0, self.cp, -self.sp])
        k = self.scale * ss
        for face, col in parts:
            p = (np.array(face) * BUILDING_SCALE) @ rot.T
            q = np.roll(p, -1, axis=0)
            n = np.array([((p[:, 1] - q[:, 1]) * (p[:, 2] + q[:, 2])).sum(),
                          ((p[:, 2] - q[:, 2]) * (p[:, 0] + q[:, 0])).sum(),
                          ((p[:, 0] - q[:, 0]) * (p[:, 1] + q[:, 1])).sum()])
            ln = np.linalg.norm(n)
            if ln < 1e-9:
                continue
            n /= ln
            if n @ view_vec > 0:
                n = -n
            shade = AMBIENT + (1 - AMBIENT) * max(0.0, float(n @ LIGHT))
            rgb = np.clip(_rgb(col) * shade, 0, 255)
            X = self.ax * ss + p[:, 0] * k
            Y = self.ay * ss - (p[:, 1] * self.sp + p[:, 2] * self.cp) * k
            D = p[:, 1] * self.cp - p[:, 2] * self.sp
            for i in range(1, len(p) - 1):
                self._tri(color, alpha, zbuf, rgb,
                          (X[0], Y[0], D[0]), (X[i], Y[i], D[i]), (X[i + 1], Y[i + 1], D[i + 1]))
        a = alpha.reshape(self.fh, ss, self.fw, ss).mean(axis=(1, 3))
        rgbsum = (color * alpha[..., None]).reshape(self.fh, ss, self.fw, ss, 3).mean(axis=(1, 3))
        rgb = np.where(a[..., None] > 0, rgbsum / np.maximum(a[..., None], 1e-9), 0)
        img = Image.fromarray(np.dstack([rgb, a * 255]).round().astype(np.uint8), "RGBA")
        if outline:
            grown = img.getchannel("A").filter(ImageFilter.MaxFilter(3))
            edge = Image.new("RGBA", img.size, (16, 18, 22, 0))
            edge.putalpha(grown)
            img = Image.alpha_composite(edge, img)
        return img

    @staticmethod
    def _tri(color, alpha, zbuf, rgb, a, b, c):
        H, W = zbuf.shape
        x0 = max(int(math.floor(min(a[0], b[0], c[0]))), 0)
        x1 = min(int(math.ceil(max(a[0], b[0], c[0]))), W)
        y0 = max(int(math.floor(min(a[1], b[1], c[1]))), 0)
        y1 = min(int(math.ceil(max(a[1], b[1], c[1]))), H)
        if x0 >= x1 or y0 >= y1:
            return
        area = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
        if abs(area) < 1e-9:
            return
        px, py = np.meshgrid(np.arange(x0, x1) + .5, np.arange(y0, y1) + .5)
        w0 = ((b[0] - px) * (c[1] - py) - (b[1] - py) * (c[0] - px)) / area
        w1 = ((c[0] - px) * (a[1] - py) - (c[1] - py) * (a[0] - px)) / area
        w2 = 1 - w0 - w1
        d = w0 * a[2] + w1 * b[2] + w2 * c[2]
        zs = zbuf[y0:y1, x0:x1]
        m = (w0 >= 0) & (w1 >= 0) & (w2 >= 0) & (d < zs - 1e-6)
        zs[m] = d[m]
        color[y0:y1, x0:x1][m] = rgb
        alpha[y0:y1, x0:x1][m] = True

    def tile_polygon(self, ox, oy):
        """Screen outline of the ground hex, for previews."""
        return [(ox + self.ax + self.scale * math.cos(math.radians(90 + 60 * i)),
                 oy + self.ay - self.scale * math.sin(math.radians(90 + 60 * i)) * self.sp)
                for i in range(6)]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default="out")
    ap.add_argument("--hex-width", type=float, default=52, help="on-screen hex width in px")
    ap.add_argument("--squash", type=float, default=0.58, help="vertical flattening of the ground plane")
    ap.add_argument("--facing", type=float, default=0, help="degrees CCW that weapons point in view 0 (0 = screen-right)")
    ap.add_argument("--reverse", action="store_true", help="views advance clockwise instead")
    ap.add_argument("--supersample", type=int, default=6)
    ap.add_argument("--no-outline", action="store_true")
    ap.add_argument("--frames", action="store_true", help="also write one PNG per frame")
    ap.add_argument("--only", nargs="*", help="building names to render")
    ap.add_argument("--preview-zoom", type=int, default=3)
    args = ap.parse_args()

    names = args.only or list(BUILDINGS)
    unknown = [n for n in names if n not in BUILDINGS]
    if unknown:
        ap.error("unknown building(s): %s. Known: %s" % (", ".join(unknown), ", ".join(BUILDINGS)))

    cam = Camera(args.hex_width, args.squash, args.facing, args.reverse, args.supersample)
    os.makedirs(args.out, exist_ok=True)
    label_w = 150
    contact = Image.new("RGBA", (label_w + cam.fw * 6, cam.fh * len(names)), (28, 36, 51, 255))
    draw = ImageDraw.Draw(contact)
    for row, name in enumerate(names):
        parts = BUILDINGS[name]()
        sheet = Image.new("RGBA", (cam.fw * 6, cam.fh), (0, 0, 0, 0))
        for v in range(6):
            frame = cam.render(parts, v, outline=not args.no_outline)
            sheet.paste(frame, (v * cam.fw, 0))
            if args.frames:
                frame.save(os.path.join(args.out, "%s_%d.png" % (name, v)))
            ox, oy = label_w + v * cam.fw, row * cam.fh
            draw.polygon(cam.tile_polygon(ox, oy), fill=(111, 145, 80, 255))
            contact.alpha_composite(frame, (ox, oy))
        sheet.save(os.path.join(args.out, name + ".png"))
        draw.text((6, row * cam.fh + cam.fh // 2), name, fill=(220, 220, 220, 255))
        print("rendered", name)

    meta = {
        "frame_width": cam.fw, "frame_height": cam.fh, "frames_per_sheet": 6,
        "anchor": [cam.ax, cam.ay],
        "anchor_note": "pixel in each frame that sits on the centre of the hex top face",
        "hex_width": args.hex_width, "squash": args.squash,
        "facing": args.facing, "reverse": args.reverse,
        "sheets": {n: n + ".png" for n in names},
    }
    with open(os.path.join(args.out, "sprites.json"), "w") as f:
        json.dump(meta, f, indent=2)
    contact.save(os.path.join(args.out, "_contact_sheet.png"))
    z = max(1, args.preview_zoom)
    contact.resize((contact.width * z, contact.height * z), Image.NEAREST).save(
        os.path.join(args.out, "_contact_sheet_%dx.png" % z))
    print("wrote %d sheets, sprites.json and contact sheets to %s/" % (len(names), args.out))


if __name__ == "__main__":
    main()
