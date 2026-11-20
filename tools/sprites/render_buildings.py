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
import inspect
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


def rail(length, width, thick, color, pivot, pitch=0, yaw=0):
    """Flat bar that starts at pivot and extends along its pitched/yawed +x."""
    return box((length, width, thick), color, _xf((length / 2, 0, 0), pitch, yaw, pivot),
               pitch=pitch, yaw=yaw)


def arch(r, length, color, pos, yaw=0, n=7, h=1.0):
    """Half-cylinder roof lying along local x, flat side down, centred on pos."""
    def ring(x):
        return [_xf((x, r * math.cos(math.pi * i / (n - 1)), h * r * math.sin(math.pi * i / (n - 1))),
                    0, yaw, pos) for i in range(n)]
    return _solid(ring(-length / 2), ring(length / 2), color)


def blob(r, color, pos, rot=0):
    """Low-poly ball."""
    x, y, z = pos
    return (prism(7, .001, r, z - r, z - .35 * r, color, at=(x, y), rot=rot)
            + prism(7, r, r, z - .35 * r, z + .35 * r, color, at=(x, y), rot=rot)
            + prism(7, r, .001, z + .35 * r, z + r, color, at=(x, y), rot=rot))


def _mix(a, b, t):
    ca, cb = _rgb(a), _rgb(b)
    return "#%02x%02x%02x" % tuple(int(round(v)) for v in ca + (cb - ca) * t)


DAMAGE_FIRE = True       # small flame at the hit point
DAMAGE_SMOKE = True      # smoke puffs rising from the hit point


def wreck(parts, hot, seed):
    """Generic damage pass: soot near the hit point, scorch marks and debris on
    the pad, plus optional fire and smoke. hot = (x, y, z) of the main hit."""
    rng = random.Random(seed)
    spots = [(hot, .5)]
    for _ in range(2):
        r, a = rng.uniform(.15, .45), rng.uniform(0, 2 * math.pi)
        spots.append(((r * math.cos(a), r * math.sin(a), rng.uniform(.15, .5)), .32))
    out = []
    for face, col in parts:
        if max(p[2] for p in face) > .06:
            c = [sum(p[i] for p in face) / len(face) for i in range(3)]
            amt = max(max(0.0, 1 - math.dist(c, sp) / rad) for sp, rad in spots)
            amt = max(amt, .12)
            col = _mix(col, "#24211f", min(.85, amt * 1.1))
        out.append((face, col))
    for sp, rad in spots:
        d = math.hypot(sp[0], sp[1])
        k = min(1, .45 / d) if d > 0 else 1
        out += prism(7, rad * .7, rad * .7, .121, .124, "#35322f",
                     at=(sp[0] * k, sp[1] * k), rot=rng.uniform(0, 50))
    greys = ["#5a5853", "#45433f", "#77756e", "#2f2e2b"]
    for _ in range(6):
        r, a = rng.uniform(.45, .66), rng.uniform(0, 2 * math.pi)
        sz = (rng.uniform(.07, .16), rng.uniform(.06, .13), rng.uniform(.04, .1))
        out += box(sz, rng.choice(greys), (r * math.cos(a), r * math.sin(a), .12 + sz[2] / 2),
                   pitch=rng.uniform(-15, 15), yaw=rng.uniform(0, 180))
    hx, hy, hz = hot
    if DAMAGE_FIRE:
        out += prism(6, .1, .001, hz, hz + .3, FLAME, at=(hx, hy))
        out += prism(5, .06, .001, hz, hz + .18, "#f2c230", at=(hx + .1, hy - .06))
        out += prism(5, .06, .001, hz, hz + .16, FLAME, at=(hx - .08, hy + .09))
    if DAMAGE_SMOKE:
        for i, g in enumerate(["#3f3f42", "#55555a", "#6c6c72"]):
            out += blob(.13 + .04 * i, g, (hx - .07 * i, hy + .05 * i, hz + .42 + .29 * i),
                        rot=rng.uniform(0, 50))
    return out


def pad():
    return (prism(6, .84, .84, 0, .05, PAD_RIM, rot=90)
            + prism(6, .78, .78, .05, .12, PAD_TOP, rot=90))


# ---------------------------------------------------------------- models --
def missile_launcher(loaded=True, damaged=False):
    pivot = (-.3, 0, .25)
    m = pad()
    m += prism(12, .42, .42, .12, .2, STEEL, at=(-.05, 0))
    if damaged:
        m += box((.1, .22, .16), STEEL_LT, (.16, 0, .28))
        m += rail(1.1, .16, .06, "#474b52", pivot, pitch=7, yaw=24)
        m += box((.42, .62, .06), STEEL_DK, (-.6, .05, .16), pitch=6, yaw=12)
        m += box((.4, .26, .22), CONCRETE, (-.1, .5, .23))
        m += box((.44, .3, .04), RED, (-.02, .56, .36), pitch=14, yaw=25)
        return wreck(m, (.12, 0, .26), 1)
    m += box((.1, .22, .42), STEEL_LT, (.16, 0, .41))
    m += rail(1.1, .16, .06, "#474b52", pivot, pitch=40)
    if loaded:
        m += tube(4, .15, .085, .16, "#8d9197", pivot, pitch=40, x0=.04, lift=.13, off=45)
        m += tube(10, .085, .085, .82, WHITE, pivot, pitch=40, x0=.1, lift=.13)
        m += tube(10, .085, .001, .28, RED, pivot, pitch=40, x0=.92, lift=.13)
    m += box((.06, .62, .42), STEEL_DK, (-.62, 0, .33), pitch=-18)
    m += box((.4, .26, .22), CONCRETE, (-.1, .5, .23))
    m += box((.44, .3, .04), RED, (-.1, .5, .36))
    return m


def ballistic_launcher(loaded=True, damaged=False):
    m = pad()
    m += prism(8, .5, .45, .12, .22, STEEL)
    if damaged:
        m += box((.52, .04, .12), GUNMETAL, (.08, 0, .28))
        m += prism(12, .14, .12, .22, .42, WHITE, at=(.08, 0))
        m += tube(4, .113, .113, 1.15, "#59677a", (-.42, 0, .22), pitch=58, yaw=-22, off=45)
        m += box((.34, .26, .2), CONCRETE, (.1, -.52, .22))
        m += box((.38, .3, .04), RED_DK, (.16, -.5, .34), pitch=-12, yaw=18)
        return wreck(m, (.08, 0, .42), 2)
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


def anti_air(damaged=False):
    m = pad()
    m += prism(12, .5, .45, .12, .24, STEEL)
    m += prism(8, .3, .26, .24, .48, GREEN)
    if damaged:
        m += box((.3, .52, .18), "#4a4f55", (.02, 0, .54), pitch=8, yaw=20)
        m += tube(8, .05, .05, .78, GUNMETAL, (0, -.15, .54), pitch=4, yaw=-28, x0=.05)
        m += tube(8, .07, .07, .12, "#16181b", (0, -.15, .54), pitch=4, yaw=-28, x0=.78)
        m += tube(8, .05, .05, .36, GUNMETAL, (0, .15, .54), pitch=50, yaw=20, x0=.05)
        m += box((.22, .2, .14), GREEN, (-.38, .3, .19))
        return wreck(m, (.05, .1, .6), 3)
    m += box((.3, .52, .18), "#4a4f55", (.02, 0, .54))
    for y in (-.15, .15):
        m += tube(8, .05, .05, .78, GUNMETAL, (0, y, .54), pitch=50, x0=.05)
        m += tube(8, .07, .07, .12, "#16181b", (0, y, .54), pitch=50, x0=.78)
    m += box((.22, .2, .14), GREEN, (-.38, .3, .19))
    m += box((.22, .2, .14), "#4a4f55", (-.38, -.3, .19))
    return m


def radar(damaged=False):
    hub = (0, 0, .72)
    m = pad()
    m += prism(8, .4, .34, .12, .3, STEEL)
    m += prism(8, .385, .365, .18, .25, PURPLE)
    if damaged:
        m += prism(8, .09, .09, .3, .5, STEEL_LT)
        m += tube(16, .07, .56, .2, WHITE, (.12, .1, .5), pitch=-38, yaw=50, x0=.06,
                  caps=(True, False))
        m += box((.26, .22, .16), CONCRETE, (-.42, -.28, .2))
        return wreck(m, (-.05, -.05, .5), 4)
    m += prism(8, .09, .09, .3, .66, STEEL_LT)
    m += box((.16, .16, .14), STEEL_DK, hub)
    m += tube(16, .07, .56, .2, WHITE, hub, pitch=35, x0=.06, caps=(True, False))
    m += tube(6, .02, .02, .42, GUNMETAL, hub, pitch=35, x0=.06)
    m += tube(8, .06, .06, .09, PURPLE, hub, pitch=35, x0=.46)
    m += box((.26, .22, .16), CONCRETE, (-.42, -.28, .2))
    return m


BANK_FLAG = "#1f5a36"
BANK_SIGN = "#9be8a8"


def bank(damaged=False, cam_yaw=0):
    """Six-sided pillared building with a dollar-sign flag. cam_yaw (degrees) is
    the camera yaw of the view being rendered; the flag is turned to face it."""
    stone = "#f2f0e8"
    m = pad()
    m += prism(6, .74, .74, .12, .17, "#cfccc0", rot=90)
    m += prism(6, .67, .67, .17, .22, "#dedbd0", rot=90)
    m += prism(6, .42, .42, .22, .76, "#e6e3d9", rot=90)
    m += box((.03, .16, .32), GUNMETAL, (.37, 0, .38))
    corners = [(.57 * math.cos(math.radians(90 + 60 * i)),
                .57 * math.sin(math.radians(90 + 60 * i))) for i in range(6)]
    for i, at in enumerate(corners):
        if damaged and i == 1:
            m += prism(8, .065, .06, .22, .4, "#ffffff", at=at)
        elif damaged and i == 4:
            m += tube(8, .06, .055, .5, "#ffffff", (at[0] * .75, at[1] * .75, .28), yaw=200)
        else:
            m += prism(8, .065, .055, .22, .76, "#ffffff", at=at)
    m += prism(6, .68, .68, .76, .82, stone, rot=90)
    flag = prism(4, .02, .02, 0, .53, GUNMETAL)
    flag += box((.42, .02, .28), BANK_FLAG, (.23, 0, .38))
    for z in (.085, 0, -.085):
        flag += box((.14, .012, .034), BANK_SIGN, (.23, -.016, .38 + z))
    flag += box((.036, .012, .1), BANK_SIGN, (.178, -.016, .4225))
    flag += box((.036, .012, .1), BANK_SIGN, (.282, -.016, .3375))
    flag += box((.03, .012, .25), BANK_SIGN, (.23, -.016, .38))

    def mount(pos, tilt):
        return [([_xf(p, tilt, -cam_yaw, pos) for p in face], col) for face, col in flag]

    if damaged:
        m += prism(6, .64, .46, .82, .88, "#cfccc0", rot=90)
        m += prism(6, .46, .46, .88, .885, "#1d1b1a", rot=90)
        m += box((.4, .34, .05), "#cfccc0", (-.12, .1, .93), pitch=22, yaw=35)
        out = wreck(m, (-.05, -.05, .88), 5)
        return out + mount((.12, 0, .86), -24)
    m += prism(6, .64, .3, .82, .93, "#cfccc0", rot=90)
    m += prism(6, .3, .24, .93, .97, stone, rot=90)
    return m + mount((0, 0, .97), 0)


def refinery(damaged=False):
    m = pad()
    if damaged:
        m += prism(12, .26, .26, .12, .5, "#c8c4b8", at=(-.3, .3))
        m += prism(12, .22, .22, .5, .505, "#1d1b1a", at=(-.3, .3))
        m += prism(12, .2, .2, .12, .4, "#c8c4b8", at=(-.36, -.3))
        m += prism(12, .2, .06, .4, .48, "#b4b0a4", at=(-.36, -.3))
        m += tube(8, .11, .11, .66, RUST, (.22, .38, .2), pitch=22, yaw=250)
        m += prism(8, .09, .075, .12, .55, STEEL_LT, at=(.36, -.12))
        m += beam((-.36, -.3, .26), (.36, -.12, .26), .05, "#8a5a32")
        return wreck(m, (-.3, .3, .5), 6)
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


def lab(damaged=False):
    c = (.12, .1)
    m = pad()
    m += box((.5, .4, .24), CONCRETE_LT, (-.34, -.3, .24))
    m += box((.54, .44, .03), STEEL_DK, (-.34, -.3, .375))
    m += prism(10, .5, .5, .12, .2, CONCRETE_LT, at=c)
    m += prism(10, .48, .44, .2, .36, BLUE, at=c)
    m += prism(10, .44, .32, .36, .52, BLUE, at=c)
    if damaged:
        m += prism(10, .3, .3, .52, .525, "#16202b", at=c)
        m += tube(4, .018, .018, .56, GUNMETAL, (-.48, -.36, .39), pitch=35, yaw=140)
        return wreck(m, (c[0], c[1], .5), 7)
    m += prism(10, .32, .14, .52, .62, BLUE, at=c)
    m += prism(10, .14, .001, .62, .66, WHITE, at=c)
    m += prism(4, .018, .018, .39, .95, GUNMETAL, at=(-.48, -.36))
    m += prism(6, .045, .045, .93, 1.0, RED, at=(-.48, -.36))
    return m


def base(flag=WHITE, damaged=False, wall=CONCRETE_LT, upper="#efede6", band="#2a3340",
         roof="#4a4f55"):
    m = pad()
    m += prism(6, .66, .56, .12, .42, wall, rot=90)
    m += prism(6, .4, .34, .42, .66, upper, rot=90)
    m += prism(6, .39, .375, .5, .56, band, rot=90)
    if damaged:
        m += prism(6, .3, .3, .66, .665, "#1d1b1a", rot=90)
        m += box((.06, .22, .2), GUNMETAL, (.53, 0, .22))
        m += tube(4, .02, .02, .5, GUNMETAL, (.1, .1, .66), pitch=28, yaw=35)
        m += box((.3, .025, .17), flag, _xf((.34, 0, -.1), 28, 35, (.1, .1, .66)), pitch=28, yaw=35)
        m += box((.3, .26, .05), roof, (-.3, -.25, .46), pitch=20, yaw=40)
        return wreck(m, (-.05, -.05, .66), 8)
    m += prism(6, .37, .37, .66, .7, roof, rot=90)
    m += box((.06, .22, .2), GUNMETAL, (.53, 0, .22))
    m += prism(4, .02, .02, .7, 1.2, GUNMETAL)
    m += box((.3, .025, .17), flag, (.17, 0, 1.1))
    return m


def decoy(damaged=False):
    """The base in sandy tan instead of cool grey; same geometry and flag."""
    return base(damaged=damaged, wall="#cdbf9f", upper="#e0d2b0", band="#3a3326", roof="#5a5140")


def stronghold(damaged=False):
    """Base variant: steel dome on the lower tier with a twin anti-air gun on top."""
    dome = "#8996a3"
    m = pad()
    m += prism(6, .66, .56, .12, .42, CONCRETE_LT, rot=90)
    m += box((.06, .22, .2), GUNMETAL, (.53, 0, .22))
    m += prism(12, .45, .45, .42, .5, "#efede6")
    m += prism(12, .455, .455, .44, .48, "#2a3340")
    m += prism(12, .45, .4, .5, .63, dome)
    if damaged:
        m += prism(12, .4, .33, .63, .7, dome)
        m += prism(12, .33, .33, .7, .705, "#1d1b1a")
        m += box((.3, .26, .04), dome, (-.2, .12, .72), pitch=24, yaw=30)
        m += box((.16, .26, .1), GREEN, (.2, -.12, .7), pitch=-22, yaw=-25)
        m += tube(8, .032, .032, .44, GUNMETAL, (.2, -.2, .7), pitch=-6, yaw=-40, x0=.02)
        m += tube(8, .032, .032, .26, GUNMETAL, (.2, -.04, .72), pitch=30, yaw=-10, x0=.02)
        return wreck(m, (-.02, .02, .7), 15)
    m += prism(12, .4, .29, .63, .75, dome)
    m += prism(12, .29, .15, .75, .82, dome)
    m += prism(8, .17, .15, .82, .87, STEEL_DK)
    m += box((.16, .26, .1), GREEN, (0, 0, .92))
    for y in (-.08, .08):
        m += tube(8, .032, .032, .44, GUNMETAL, (0, y, .93), pitch=50, x0=.02)
        m += tube(8, .045, .045, .07, "#16181b", (0, y, .93), pitch=50, x0=.44)
    return m


# ---- troop buildings (airport, bunker, docks, coastal cannon) ------------
ASPHALT = "#3a3d42"
NAVY = "#4d5a6b"
NAVY_DK = "#3d4856"
TEAL = "#3f7f9a"
DARK = "#1d1f22"


def airport(damaged=False):
    m = pad()
    m += box((1.3, .34, .02), ASPHALT, (0, -.2, .13))
    for x in (-.45, -.15, .15, .45):
        m += box((.14, .03, .006), WHITE, (x, -.2, .142))
    m += box((.44, .48, .1), CONCRETE_LT, (-.2, .22, .17))
    if damaged:
        m += box((.4, .44, .01), DARK, (-.2, .22, .224))
        m += arch(.24, .16, "#7d8a96", (-.34, .22, .22))
        m += box((.3, .3, .03), "#7d8a96", (-.08, .2, .26), pitch=-24, yaw=15)
        m += prism(6, .07, .07, .12, .26, CONCRETE_LT, at=(.36, .3))
        m += tube(6, .07, .07, .3, CONCRETE_LT, (.33, .26, .2), pitch=10, yaw=205)
        m += tube(8, .045, .045, .3, WHITE, (.05, -.26, .19), yaw=28)
        m += box((.09, .24, .015), WHITE, (.2, -.07, .17), pitch=12, yaw=40)
        m += box((.07, .012, .07), BLUE, (.08, -.25, .245), yaw=28)
        return wreck(m, (-.18, .2, .26), 11)
    m += arch(.24, .44, "#7d8a96", (-.2, .22, .22))
    m += box((.012, .36, .17), "#1d2228", (.022, .22, .205))
    m += prism(6, .07, .07, .12, .5, CONCRETE_LT, at=(.36, .3))
    m += prism(6, .1, .1, .5, .6, "#2a3340", at=(.36, .3))
    m += prism(6, .11, .11, .6, .63, STEEL_DK, at=(.36, .3))
    m += prism(4, .02, .02, .63, .71, RED, at=(.36, .3))
    m += tube(8, .045, .045, .3, WHITE, (.05, -.2, .19))
    m += tube(8, .045, .012, .08, WHITE, (.05, -.2, .19), x0=.3)
    m += box((.09, .42, .015), WHITE, (.2, -.2, .2))
    m += box((.05, .16, .012), WHITE, (.07, -.2, .2))
    m += box((.07, .012, .07), BLUE, (.07, -.2, .245))
    return m


def bunker(damaged=False):
    m = pad()
    m += prism(8, .62, .56, .12, .38, "#9a988f", rot=22.5)
    m += prism(8, .6, .588, .25, .31, DARK, rot=22.5)
    m += box((.03, .2, .2), "#2a2c30", (-.585, 0, .22))
    if damaged:
        m += prism(8, .5, .5, .38, .385, DARK, rot=22.5)
        m += box((.62, .5, .08), "#7d7b73", (-.14, .1, .45), pitch=13, yaw=22)
        m += box((.26, .22, .08), "#7d7b73", (.34, -.26, .4), pitch=-20, yaw=-30)
        m += tube(6, .03, .03, .22, GUNMETAL, (.55, 0, .28), pitch=-25, yaw=-20)
        return wreck(m, (.15, -.08, .4), 12)
    m += prism(8, .6, .48, .38, .47, "#7d7b73", rot=22.5)
    m += prism(6, .1, .08, .47, .52, STEEL_DK)
    m += tube(6, .03, .03, .22, GUNMETAL, (.55, 0, .28))
    return m


def docks(damaged=False):
    m = pad()
    for x in (-.5, -.17, .17, .5):
        for y in (-.32, -.02):
            m += prism(6, .035, .035, .12, .22, "#5a4630", at=(x, y))
    m += box((.18, .18, .08), STEEL, (-.3, .3, .16))
    m += prism(8, .05, .05, .27, .39, TEAL, at=(-.45, -.08))
    if damaged:
        m += box((.56, .4, .05), WOOD, (-.31, -.17, .23), pitch=-9)
        m += box((.5, .4, .05), WOOD, (.33, -.17, .2), pitch=14, yaw=6)
        m += box((.1, .1, .3), TEAL, (-.3, .3, .34))
        m += beam((-.3, .3, .46), (.38, -.2, .3), .05, TEAL)
        m += box((.18, .16, .12), TEAL, (-.1, .42, .19), pitch=20, yaw=40)
        m += box((.36, .3, .2), CONCRETE_LT, (.26, .33, .22))
        m += box((.4, .34, .04), "#3f6f8a", (.3, .3, .35), pitch=-14, yaw=14)
        m += box((.14, .14, .12), "#8a6a3c", (.5, -.3, .19), yaw=30)
        return wreck(m, (0, -.15, .26), 13)
    m += box((1.2, .4, .05), WOOD, (0, -.17, .245))
    for x in (-.5, .5):
        m += prism(6, .03, .03, .27, .33, GUNMETAL, at=(x, -.33))
    m += box((.14, .14, .12), "#8a6a3c", (.3, -.1, .33))
    m += box((.12, .12, .1), "#a37f4a", (.43, -.22, .32))
    m += box((.36, .3, .2), CONCRETE_LT, (.26, .33, .22))
    m += box((.4, .34, .04), "#3f6f8a", (.26, .33, .34))
    m += box((.1, .1, .62), TEAL, (-.3, .3, .5))
    m += box((.18, .16, .12), TEAL, (-.28, .3, .84))
    m += beam((-.3, .3, .9), (.3, -.1, 1.02), .05, TEAL)
    m += beam((-.3, .3, .9), (-.5, .43, .86), .05, TEAL)
    m += beam((.2, -.033, .99), (.2, -.033, .52), .014, GUNMETAL)
    m += box((.12, .12, .1), "#8a6a3c", (.2, -.033, .47))
    return m


def coastal_cannon(damaged=False):
    gun = (.2, 0, .62)
    m = pad()
    m += prism(12, .55, .5, .12, .26, STEEL)
    m += prism(8, .36, .31, .26, .5, NAVY)
    m += box((.2, .18, .12), NAVY, (-.4, -.3, .18))
    if damaged:
        m += box((.34, .54, .3), NAVY_DK, (.06, .03, .58), pitch=-10, yaw=22)
        m += tube(10, .11, .11, .2, STEEL_LT, gun, pitch=-9, yaw=-32)
        m += tube(10, .085, .07, .8, GUNMETAL, gun, pitch=-9, yaw=-32)
        m += tube(10, .1, .1, .12, "#16181b", gun, pitch=-9, yaw=-32, x0=.8)
        return wreck(m, (.02, .08, .62), 14)
    m += box((.34, .54, .3), NAVY_DK, (.08, 0, .6))
    m += box((.08, .7, .06), STEEL_DK, (-.02, 0, .78))
    m += tube(10, .11, .11, .2, STEEL_LT, gun, pitch=12)
    m += tube(10, .085, .07, .8, GUNMETAL, gun, pitch=12)
    m += tube(10, .1, .1, .12, "#16181b", gun, pitch=12, x0=.8)
    return m
# ---- end troop buildings --------------------------------------------------


# ---- nuclear silo ---------------------------------------------------------
RUSTY = "#5c4a42"
RUSTY_DK = "#43352f"
HAZARD = "#e8c22e"
INK = "#17181b"


def annulus(n, rin, rout, z, color, at=(0, 0)):
    """Flat ring at height z."""
    return prism(n, rin, rout, z, z, color, at=at, caps=(False, False))


def trefoil(r, place):
    """Radiation symbol of radius r. place maps a flat (x, y, height) point into the scene."""
    out = []

    def disc(rad, col, h, n=20):
        out.append(([place((rad * math.cos(2 * math.pi * i / n), rad * math.sin(2 * math.pi * i / n), h))
                     for i in range(n)], col))
    disc(r, HAZARD, 0)
    for k in range(3):
        for j in range(3):                                # each blade = three convex slices
            a0 = math.radians(90 + 120 * k - 30 + 20 * j)
            a1 = a0 + math.radians(20)
            pts = [(.28 * r * math.cos(a0), .28 * r * math.sin(a0)), (.86 * r * math.cos(a0), .86 * r * math.sin(a0)),
                   (.86 * r * math.cos(a1), .86 * r * math.sin(a1)), (.28 * r * math.cos(a1), .28 * r * math.sin(a1))]
            out.append(([place((x, y, .004)) for x, y in pts], INK))
    disc(.16 * r, INK, .004, 12)
    return out


def nuclear_silo(state="closed"):
    """state: closed (armed) | open (build phase, empty shaft) | open_loaded | damaged."""
    n = 20
    m = pad()
    m += prism(n, .62, .6, .12, .3, RUSTY, caps=(False, False))
    m += annulus(n, .47, .6, .3, RUSTY)
    for i in range(12):
        a = math.radians(15 + 30 * i)
        m += box((.07, .05, .1), RUSTY_DK, (.63 * math.cos(a), .63 * math.sin(a), .17), yaw=math.degrees(a))
    m += box((.16, .34, .12), RUSTY_DK, (-.6, 0, .3))
    if state == "closed":
        m += prism(n, .5, .47, .3, .38, RUSTY_DK)
        m += trefoil(.36, lambda p: (p[0], p[1], .381 + p[2]))
        for y in (-.1, .1):
            m += beam((-.6, y, .36), (-.4, y, .4), .06, GUNMETAL)
        return m
    m += prism(n, .47, .47, .26, .3, RUSTY_DK, caps=(False, False))
    m += annulus(n, .35, .47, .26, "#b9b6aa")
    m += prism(n, .35, .35, .125, .26, "#77756c", caps=(False, False))
    m += prism(n, .35, .35, .124, .126, "#14161a")
    if state == "damaged":                                # lid blown askew, half off the shaft
        lid = (.16, .1, .3)
        m += tube(n, .5, .47, .08, RUSTY_DK, lid, pitch=74, yaw=25)
        m += trefoil(.36, lambda p: _xf((.081 + p[2], p[1], p[0]), 74, 25, lid))
        m += beam((-.6, .1, .36), (-.42, .2, .3), .06, GUNMETAL)
        m += beam((-.6, -.1, .36), (-.5, -.28, .5), .06, GUNMETAL)
        return wreck(m, (-.22, -.12, .3), 16)
    if state == "open_loaded":
        m += prism(14, .19, .19, .126, .3, "#c9ccd2")
        m += prism(14, .19, .1, .3, .5, "#dfe2e6")
        m += prism(14, .1, .03, .5, .58, "#3a3d42")
    lid = (-.82, 0, .7)
    for y in (-.1, .1):
        m += beam((-.56, y, .32), (-.74, y, .62), .06, GUNMETAL)
    m += tube(n, .47, .5, .09, RUSTY_DK, lid, pitch=24)
    m += tube(n, .3, .3, .03, RUSTY, lid, pitch=24, x0=.09)
    m += trefoil(.36, lambda p: _xf((-.003 - p[2], p[1], p[0]), 24, 0, lid))
    return m


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
    "missile_launcher_damaged": lambda: missile_launcher(damaged=True),
    "ballistic_launcher_damaged": lambda: ballistic_launcher(damaged=True),
    "anti_air_damaged": lambda: anti_air(damaged=True),
    "radar_damaged": lambda: radar(damaged=True),
    "bank_damaged": lambda cam_yaw=0: bank(damaged=True, cam_yaw=cam_yaw),
    "refinery_damaged": lambda: refinery(damaged=True),
    "lab_damaged": lambda: lab(damaged=True),
    "base_damaged": lambda: base(damaged=True),
    "decoy_damaged": lambda: decoy(damaged=True),
    "airport": airport,
    "airport_damaged": lambda: airport(damaged=True),
    "bunker": bunker,
    "bunker_damaged": lambda: bunker(damaged=True),
    "docks": docks,
    "docks_damaged": lambda: docks(damaged=True),
    "coastal_cannon": coastal_cannon,
    "coastal_cannon_damaged": lambda: coastal_cannon(damaged=True),
    "stronghold": stronghold,
    "stronghold_damaged": lambda: stronghold(damaged=True),
    "nuclear_silo": nuclear_silo,
    "nuclear_silo_open": lambda: nuclear_silo("open"),
    "nuclear_silo_open_loaded": lambda: nuclear_silo("open_loaded"),
    "nuclear_silo_damaged": lambda: nuclear_silo("damaged"),
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
        self.fw = int(round(self.scale * 2.2 / 2) * 2)
        self.fh = int(round(self.scale * 3.3 / 2) * 2)
        self.ax = self.fw / 2
        self.ay = round(self.fh - self.scale * 0.8)

    def yaw(self, view):
        return self.facing + self.dir * view * math.pi / 3

    def render(self, parts, view=0, outline=True, yaw=None, frame=None, anchor=None,
               model_scale=BUILDING_SCALE):
        """yaw (degrees CCW from above) overrides view; frame=(w, h) and
        anchor=(x, y) override the building frame; model_scale converts model
        units to tile units."""
        fw, fh = frame or (self.fw, self.fh)
        ax, ay = anchor or (self.ax, self.ay)
        ang = self.yaw(view) if yaw is None else math.radians(yaw)
        ss, W, H = self.ss, fw * self.ss, fh * self.ss
        color = np.zeros((H, W, 3))
        alpha = np.zeros((H, W), dtype=bool)
        zbuf = np.full((H, W), np.inf)
        c, s = math.cos(ang), math.sin(ang)
        rot = np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])
        view_vec = np.array([0, self.cp, -self.sp])
        k = self.scale * ss
        for face, col in parts:
            p = (np.array(face) * model_scale) @ rot.T
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
            X = ax * ss + p[:, 0] * k
            Y = ay * ss - (p[:, 1] * self.sp + p[:, 2] * self.cp) * k
            D = p[:, 1] * self.cp - p[:, 2] * self.sp
            for i in range(1, len(p) - 1):
                self._tri(color, alpha, zbuf, rgb,
                          (X[0], Y[0], D[0]), (X[i], Y[i], D[i]), (X[i + 1], Y[i + 1], D[i + 1]))
        a = alpha.reshape(fh, ss, fw, ss).mean(axis=(1, 3))
        rgbsum = (color * alpha[..., None]).reshape(fh, ss, fw, ss, 3).mean(axis=(1, 3))
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
    ap.add_argument("--no-fire", action="store_true", help="damaged sheets without flames")
    ap.add_argument("--no-smoke", action="store_true", help="damaged sheets without smoke")
    ap.add_argument("--preview-zoom", type=int, default=3)
    args = ap.parse_args()

    global DAMAGE_FIRE, DAMAGE_SMOKE
    DAMAGE_FIRE, DAMAGE_SMOKE = not args.no_fire, not args.no_smoke
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
        model = BUILDINGS[name]
        faces_camera = "cam_yaw" in inspect.signature(model).parameters
        parts = None if faces_camera else model()
        sheet = Image.new("RGBA", (cam.fw * 6, cam.fh), (0, 0, 0, 0))
        for v in range(6):
            if faces_camera:      # models with a camera-facing part are rebuilt per view
                parts = model(cam_yaw=math.degrees(cam.yaw(v)))
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
