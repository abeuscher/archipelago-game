#!/usr/bin/env python3
"""Archipelago troop unit sprite renderer.

Renders platoons, parachutists, the air transport, the landing craft, the
spy's helicopter and the spy in two colourways (player, enemy), using the same primitives, lighting and outline as
render_buildings.py (which must sit next to this file).

    python render_units.py --out ../../assets/units
    python render_units.py --out ../../assets/units --only helicopter spy

Art is drawn at 2x: a hex is 104 px wide on the sheet. Writes one PNG per
sheet, units.json (frame size, anchor, rows, columns) and _units_preview.png.

Screen directions (sheet rows for platoon and boat), as world yaw in degrees:
    0 E   0     1 SE -60     2 SW -120     3 W 180     4 NW 120     5 NE 60
"""
import argparse
import json
import math
import os
import random

from PIL import Image, ImageDraw

from render_buildings import Camera, _xf, beam, blob, box, prism, tube

HEX_WIDTH = 104
SQUASH = 0.58
DIRECTIONS = [("E", 0), ("SE", -60), ("SW", -120), ("W", 180), ("NW", 120), ("NE", 60)]

SIDES = {
    "player": dict(uniform="#8a9c48", dark="#4a5528", helmet="#39431f", trim="#8c9a55",
                   hull="#66733a", hull_dk="#4c572b", canopy="#dfe3c8"),
    "enemy": dict(uniform="#565a63", dark="#2b2d33", helmet="#c2a878", trim="#c2a878",
                  hull="#4a4d55", hull_dk="#35383f", canopy="#e3d6b8"),
}
SKIN = "#d9a47a"
GUN = "#1b1c1f"
BOOT = "#26221f"
FLASH = "#f6d23c"
FOAM = "#e6f0f5"


def place(parts, pos=(0, 0, 0), yaw=0, pitch=0):
    """Rotate parts (pitch, then yaw) about the origin, then move them to pos."""
    return [([_xf(p, pitch, yaw, pos) for p in face], col) for face, col in parts]


# ---------------------------------------------------------------- soldier --
def soldier(c, pose="stand", phase=0, flash=False):
    """One soldier about 0.45 tile units tall, feet at the origin, facing +x.
    pose: stand | walk (phase 0..3) | fight | drop (arms up) | crouch | down."""
    if pose == "down":
        m = box((.17, .15, .07), c["uniform"], (0, 0, .035))
        m += beam((-.08, .04, .03), (-.25, .07, .03), .05, c["dark"])
        m += beam((-.08, -.04, .03), (-.24, -.09, .03), .05, c["dark"])
        m += beam((.02, .09, .03), (.12, .17, .03), .04, c["uniform"])
        m += blob(.05, SKIN, (.13, 0, .05))
        m += prism(8, .058, .04, .0, .05, c["helmet"], at=(.2, -.1))
        m += beam((-.05, -.16, .015), (.15, -.2, .015), .025, GUN)
        return m
    swing = [1, 0, -1, 0][phase % 4] if pose == "walk" else 0
    bob = [0, .012, 0, .012][phase % 4] if pose == "walk" else 0
    stance = .05 if pose == "fight" else 0
    hip = .18
    if pose == "crouch":
        hip, bob = .13, -.05
    m = []
    for side, s in ((1, 1), (-1, -1)):
        fx = .08 * swing * s + stance * s
        y = .038 * side
        if pose == "crouch":
            m += beam((0, y, hip), (.07, y, .07), .05, c["dark"])
            m += beam((.07, y, .07), (.0, y, .0), .05, c["dark"])
        else:
            m += beam((0, y, hip + bob), (fx, y, .02), .05, c["dark"])
        m += box((.075, .05, .035), BOOT, (fx + .012, y, .018))
    m += box((.09, .15, .16), c["uniform"], (0, 0, .26 + bob))
    m += box((.03, .11, .1), c["dark"], (-.055, 0, .27 + bob))          # pack
    m += blob(.05, SKIN, (.005, 0, .385 + bob))
    m += prism(8, .054, .036, .405 + bob, .45 + bob, c["helmet"])
    sh = .32 + bob
    if pose == "fight":
        m += beam((0, .09, sh), (.12, .0, .33), .04, c["uniform"])
        m += beam((0, -.09, sh), (.06, -.05, .32), .04, c["uniform"])
        m += beam((.0, -.05, .335), (.24, -.05, .335), .028, GUN)
        if flash:
            m += tube(5, .045, .001, .11, FLASH, (.24, -.05, .335))
    elif pose == "drop":
        m += beam((0, .09, sh), (0, .13, sh + .14), .04, c["uniform"])
        m += beam((0, -.09, sh), (0, -.13, sh + .14), .04, c["uniform"])
        m += beam((-.06, .0, .34), (-.06, .0, .16), .028, GUN)
    else:
        m += beam((0, .09, sh), (-.05 * swing + .01, .095, .2 + bob), .04, c["uniform"])
        m += beam((0, -.09, sh), (.07, -.07, .25 + bob), .04, c["uniform"])
        m += beam((-.04, -.1, .21 + bob), (.15, -.1, .31 + bob), .028, GUN)
    return m


FORMATION = [(.28, -.3), (.28, 0), (.28, .3), (0, -.16), (0, .16), (-.28, -.3), (-.28, 0), (-.28, .3)]


def platoon(c, column):
    """column: 0 stand, 1-4 walk, 5-6 fight, 7 wiped out."""
    rng = random.Random(3)
    m = []
    for i, (x, y) in enumerate(FORMATION):
        x, y = x + rng.uniform(-.03, .03), y + rng.uniform(-.03, .03)
        turn = rng.uniform(-8, 8)
        if column == 0:
            s = soldier(c, "stand")
        elif column <= 4:
            s = soldier(c, "walk", phase=(column - 1) + 2 * (i % 2))
        elif column <= 6:
            s = soldier(c, "fight", flash=(i % 2 == column - 5))
        else:
            s, turn = soldier(c, "down"), rng.uniform(0, 360)
        m += place(s, (x, y, 0), yaw=turn)
    return m


# ------------------------------------------------------------ parachutist --
def canopy(c, r, z0, z1, at=(0, 0)):
    n, mid = 10, z0 + (z1 - z0) * .55
    parts = (prism(n, r, r * .8, z0, mid, c["canopy"], at=at, caps=(False, False))
             + prism(n, r * .8, r * .25, mid, z1, c["canopy"], at=at, caps=(False, True)))
    out = []
    for i, (face, col) in enumerate(parts):
        out.append((face, c["uniform"] if (i % n) % 2 == 0 and i < 2 * n else col))
    return out


def parachutist(c, frame):
    """frame: 0 opening, 1 sway left, 2 sway right, 3 landing."""
    if frame == 3:
        m = place(soldier(c, "crouch"), yaw=-60)
        m += place(canopy(c, .24, 0, .16), (-.08, .1, .38), pitch=-28)
        m += beam((0, .05, .3), (-.1, .16, .4), .014, GUN)
        m += beam((0, -.05, .3), (-.02, .0, .4), .014, GUN)
        return m
    m = place(soldier(c, "drop"), yaw=-60)
    if frame == 0:
        m += canopy(c, .11, .8, 1.16)
        rim, top = .1, .8
    else:
        m += canopy(c, .3, .86, 1.14)
        rim, top = .28, .86
    for a in (30, 150, 210, 330):
        m += beam((.0, .11 * math.copysign(1, math.sin(math.radians(a))), .47),
                  (rim * math.cos(math.radians(a)), rim * math.sin(math.radians(a)), top), .014, GUN)
    if frame in (1, 2):
        tilt = 8 if frame == 1 else -8
        m = place(place(m, (0, 0, -.6)), (0, 0, .6), pitch=tilt)
    return m


# -------------------------------------------------------------- transport --
def transport(c, frame):
    """Top-down plane, nose toward +x. frame: 0/1 propeller positions, 2 door open."""
    m = tube(10, .05, .12, .3, c["hull"], (-.85, 0, .12))
    m += tube(10, .12, .12, .95, c["hull"], (-.55, 0, .12))
    m += tube(10, .12, .05, .25, c["hull"], (.4, 0, .12))
    m += box((.14, .16, .04), "#1d2733", (.44, 0, .2))                  # cockpit glass
    m += box((.36, 1.36, .035), c["hull_dk"], (.08, 0, .25))            # wing
    m += box((.36, .1, .037), c["trim"], (.08, .5, .25))
    m += box((.36, .1, .037), c["trim"], (.08, -.5, .25))
    m += box((.2, .52, .03), c["hull_dk"], (-.72, 0, .2))               # tailplane
    m += box((.26, .035, .2), c["trim"], (-.7, 0, .3))                  # fin
    for y in (-.32, .32):
        m += tube(8, .06, .06, .3, "#2a2c30", (.02, y, .2))
        m += tube(8, .03, .03, .04, "#b8bcc2", (.32, y, .2))
        ang = math.radians(15 if frame != 1 else 75)
        dy, dz = .17 * math.cos(ang), .17 * math.sin(ang)
        m += beam((.35, y - dy, .2 - dz), (.35, y + dy, .2 + dz), .022, "#d5d8dc")
        m += beam((.35, y - dz * .5, .2 + dy * .5), (.35, y + dz * .5, .2 - dy * .5), .022, "#9a9ea4")
    if frame == 2:
        m += box((.3, .16, .02), "#14161a", (-.38, 0, .245))
    return m


# ------------------------------------------------------------- helicopter --
def helicopter(c, frame):
    """The spy's helicopter, top-down, nose toward +x. frame: 0/1 rotor positions."""
    m = blob(.25, c["hull"], (.1, 0, .22))                                  # cabin
    m += tube(10, .21, .12, .36, c["hull"], (-.3, 0, .22))
    m += blob(.16, "#1d2733", (.26, 0, .28))                                # bubble canopy
    m += tube(8, .06, .03, .62, c["hull_dk"], (-.74, 0, .24))              # tail boom
    m += box((.16, .03, .14), c["trim"], (-.72, .02, .3))                  # tail fin
    m += box((.03, .22, .02), "#9a9ea4", (-.72, .06, .34), yaw=frame * 60)  # tail rotor
    for y in (-.17, .17):                                                   # skids
        m += box((.62, .02, .02), "#2a2c30", (.05, y, .01))
        m += beam((-.12, y, .03), (-.1, y * .6, .12), .025, "#2a2c30")
        m += beam((.22, y, .03), (.2, y * .6, .12), .025, "#2a2c30")
    m += tube(8, .04, .04, .06, "#2a2c30", (.02, 0, .4), pitch=-90)        # mast
    m += blob(.045, "#2a2c30", (.02, 0, .46))
    for k in range(2):                                                      # main rotor
        a = math.radians((30 if frame == 0 else 75) + 90 * k)
        dx, dy = .66 * math.cos(a), .66 * math.sin(a)
        m += beam((.02 - dx, -dy, .47), (.02 + dx, dy, .47), .035, "#3a3d42")
    return m


def _scaled(parts, k):
    return [([(x * k, y * k, z * k) for x, y, z in face], col) for face, col in parts]


# -------------------------------------------------------------------- spy --
TUX = "#1b1c21"
LAPEL = "#2c2f37"        # satin lapels, a shade off the cloth: black against the white V
SHIRT = "#ffffff"
SHOE = "#050506"


def spy(c, frame):
    """A man in a tuxedo, feet at the origin, facing +x. frame: 0 stand, 1 step,
    2 hand to ear (reporting). Built to read at a few dozen pixels: a white
    V of shirt framed by pale satin lapels, a bow tie (red for the enemy),
    white cuffs and pocket square, and coat tails behind."""
    swing = [0, 1, 0][frame]
    m = []
    for side in (1, -1):
        fx = .06 * swing * side
        y = .036 * side
        m += beam((0, y, .18), (fx, y, .02), .048, TUX)                  # trousers
        m += box((.075, .048, .03), SHOE, (fx + .012, y, .016))
    m += box((.085, .15, .17), TUX, (0, 0, .265))                        # jacket
    for side in (1, -1):                                                 # tails
        m += box((.03, .05, .13), TUX, (-.052, .035 * side, .15), pitch=-12)
    # Shirt front narrowing down to the waist, lapels along both edges.
    for w, z, h in ((.09, .322, .05), (.06, .282, .036), (.03, .25, .03)):
        m += box((.02, w, h), SHIRT, (.05, 0, z))
        for side in (1, -1):
            m += box((.02, .018, h), LAPEL, (.048, (w / 2 + .009) * side, z))
    tie = "#9b1424" if c is SIDES["enemy"] else "#08080a"
    m += box((.012, .044, .018), tie, (.062, 0, .336))                   # bow tie
    m += box((.012, .012, .022), tie, (.062, 0, .336))
    m += box((.014, .016, .014), SHIRT, (.046, -.066, .3))               # pocket square
    m += blob(.048, SKIN, (.004, 0, .39))
    m += prism(8, .05, .04, .405, .44, "#2a1d14", at=(-.008, 0))         # slicked hair
    sh = .33
    hands = [(.01, .1, .2)]
    m += beam((0, .09, sh), hands[0], .04, TUX)
    if frame == 2:
        hands.append((.02, -.07, .4))
    else:
        hands.append((-.01 * swing, -.1, .2))
    m += beam((0, -.09, sh), hands[1], .04, TUX)
    for hx, hy, hz in hands:                                             # cuffs and hands
        down = -.018 if hz < .3 else .018
        m += blob(.022, SHIRT, (hx, hy, hz))
        m += blob(.018, SKIN, (hx, hy, hz + down))
    return _scaled(m, 1.75)   # well over a soldier's size, so the suit reads at play zoom


# ------------------------------------------------------------------- boat --
def boat(c, frame):
    """Landing craft, bow toward +x, waterline at z=0. frame 0/1: bob + bow wave."""
    lift, tip = (0, 0) if frame == 0 else (.02, 3)
    m = box((1.3, .56, .1), c["hull_dk"], (0, 0, .05))
    m += box((1.3, .05, .22), c["hull"], (0, .28, .13))
    m += box((1.3, .05, .22), c["hull"], (0, -.28, .13))
    m += box((.05, .56, .22), c["hull"], (-.65, 0, .13))
    m += box((.05, .52, .3), c["trim"], (.69, 0, .17), pitch=-22)       # bow ramp
    m += box((.3, .42, .24), c["hull"], (-.46, 0, .34))                 # wheelhouse
    m += box((.31, .43, .07), "#1d2733", (-.46, 0, .38))
    m += box((.34, .46, .03), c["hull_dk"], (-.46, 0, .475))
    m += prism(4, .012, .012, .49, .66, GUN, at=(-.56, .12))
    m += box((.1, .012, .07), c["trim"], (-.5, .12, .62))
    for x in (-.15, .08, .31):
        for y in (-.12, .12):
            m += prism(8, .05, .035, .15, .2, c["helmet"], at=(x, y))
    m = place(m, (0, 0, lift), pitch=tip)
    spread = .26 if frame == 0 else .34
    for side in (1, -1):                                             # bow wave
        m += box((spread + .1, .1, .012), FOAM, (.66 - spread / 2, (.36 + spread * .12) * side, .006),
                 yaw=-14 * side)
    m += box((.16 + spread * .5, .44, .012), FOAM, (-.76 - spread * .25, 0, .006))   # wake
    return m


# ----------------------------------------------------------------- sheets --
def build(out, supersample, only=None):
    iso = Camera(HEX_WIDTH, SQUASH, 0, False, supersample)
    top = Camera(HEX_WIDTH, 1.0, 0, False, supersample)      # straight down, for the transport
    yaws = [yaw for _, yaw in DIRECTIONS]
    specs = {
        "platoon": dict(frame=(104, 80), anchor=(52, 56), cam=iso, rows=yaws, model=platoon,
                        columns=["stand", "walk_1", "walk_2", "walk_3", "walk_4",
                                 "fight_1", "fight_2", "wiped_out"]),
        "parachutist": dict(frame=(48, 64), anchor=(24, 60), cam=iso, rows=[0], model=parachutist,
                            columns=["opening", "sway_left", "sway_right", "landing"]),
        "transport": dict(frame=(120, 90), anchor=(60, 45), cam=top, rows=[0], model=transport,
                          columns=["prop_1", "prop_2", "door_open"]),
        "boat": dict(frame=(120, 90), anchor=(60, 56), cam=iso, rows=yaws, model=boat,
                     columns=["bob_1", "bob_2"]),
        "helicopter": dict(frame=(120, 90), anchor=(60, 45), cam=top, rows=[0], model=helicopter,
                           columns=["rotor_1", "rotor_2"]),
        "spy": dict(frame=(48, 64), anchor=(24, 60), cam=iso, rows=[-60], model=spy,
                    columns=["stand", "step", "report"]),
    }
    if only:
        specs = {k: v for k, v in specs.items() if k in only}
    os.makedirs(out, exist_ok=True)
    meta, sheets = {}, []
    for unit, sp in specs.items():
        fw, fh = sp["frame"]
        for side, colours in SIDES.items():
            name = "%s_%s" % (unit, side)
            sheet = Image.new("RGBA", (fw * len(sp["columns"]), fh * len(sp["rows"])), (0, 0, 0, 0))
            for col in range(len(sp["columns"])):
                parts = sp["model"](colours, col)
                for row, yaw in enumerate(sp["rows"]):
                    img = sp["cam"].render(parts, yaw=yaw, frame=sp["frame"], anchor=sp["anchor"],
                                           model_scale=1.0)
                    sheet.paste(img, (col * fw, row * fh))
            sheet.save(os.path.join(out, name + ".png"))
            sheets.append((name, sheet, unit))
            meta[name] = {
                "file": name + ".png", "frame_width": fw, "frame_height": fh,
                "anchor": list(sp["anchor"]), "columns": sp["columns"],
                "rows": [d for d, _ in DIRECTIONS] if len(sp["rows"]) == 6 else ["single"],
            }
            print("rendered", name)
    path = os.path.join(out, "units.json")
    if only and os.path.exists(path):
        with open(path) as f:
            kept = json.load(f)["sheets"]
        kept.update(meta)
        meta = kept
    with open(path, "w") as f:
        json.dump({"hex_width": HEX_WIDTH, "squash": SQUASH, "sheets": meta}, f, indent=2)

    backdrop = {"platoon": (111, 145, 80), "parachutist": (120, 160, 200),
                "transport": (111, 145, 80), "boat": (52, 92, 140),
                "helicopter": (111, 145, 80), "spy": (111, 145, 80)}
    width = max(s.width for _, s, _ in sheets) + 20
    height = sum(s.height + 26 for _, s, _ in sheets) + 10
    prev = Image.new("RGBA", (width, height), (28, 36, 51, 255))
    d, y = ImageDraw.Draw(prev), 6
    for name, sheet, unit in sheets:
        d.text((10, y), name, fill=(220, 220, 220, 255))
        d.rectangle([10, y + 14, 10 + sheet.width - 1, y + 14 + sheet.height - 1], fill=backdrop[unit] + (255,))
        prev.alpha_composite(sheet, (10, y + 14))
        y += sheet.height + 26
    prev.save(os.path.join(out, "_units_preview.png"))
    print("wrote %d sheets, units.json and _units_preview.png to %s/" % (len(sheets), out))


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", default="out_units")
    ap.add_argument("--supersample", type=int, default=6)
    ap.add_argument("--only", nargs="*", help="render just these units (units.json keeps the others)")
    args = ap.parse_args()
    build(args.out, args.supersample, args.only)
