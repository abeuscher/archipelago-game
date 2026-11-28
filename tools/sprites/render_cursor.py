"""Renders the pointing-hand cursor: a gloved hand in the game's outlined
cartoon style, index finger up, its tip the click point.

Writes four PNGs to assets/ui/: cursor_hand.png and cursor_hand_pressed.png
(32 px, the design size) and the same at 64 px with _2x (for screens where
the interface is drawn at double size). The pressed hand is the same glove
squeezed down a little, the fingertip staying on the click point.

    python tools/sprites/render_cursor.py

The hotspot (fingertip) is at HOTSPOT in 32 px units; game/cursors.gd uses
the same value.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

SS = 8                 # supersampling for smooth edges
HOTSPOT = (12, 1)      # fingertip, in 32 px units

INK = (41, 38, 31, 255)
GLOVE = (214, 196, 150, 255)
GLOVE_SHADE = (178, 158, 112, 255)
GLOVE_LIGHT = (236, 224, 188, 255)
CUFF = (112, 114, 72, 255)
CUFF_SHADE = (86, 88, 54, 255)


def _shapes(drop):
    """The glove's parts as (kind, box, radius) in 32 px units. drop: how
    far the palm, thumb and cuff sit lower than the fingertip's row is
    pulled up (the pressed hand squeezes the finger shorter)."""
    d = drop
    finger = ("rr", (9.5, 1.0, 14.5, 17.0 - d), 2.5)
    folded = [
        ("rr", (13.5, 11.0 - d, 18.0, 18.5 - d), 2.2),
        ("rr", (17.0, 12.0 - d, 21.5, 19.5 - d), 2.2),
        ("rr", (20.5, 13.5 - d, 24.5, 20.0 - d), 2.0),
    ]
    palm = ("rr", (8.0, 14.0 - d, 25.0, 26.0 - d), 4.5)
    thumb = ("rr", (4.5, 15.5 - d, 11.0, 21.5 - d), 3.0)
    cuff = ("rr", (9.0, 24.5 - d, 24.5, 30.5 - d), 1.5)
    return finger, folded, palm, thumb, cuff


def _box(b, s):
    return [round(b[0] * s), round(b[1] * s), round(b[2] * s), round(b[3] * s)]


def render(size, pressed):
    s = size / 32.0 * SS
    w = size * SS
    finger, folded, palm, thumb, cuff = _shapes(1.5 if pressed else 0.0)
    parts = [thumb, palm] + folded + [finger, cuff]

    # Silhouette, then a dark outline round it.
    mask = Image.new("L", (w, w), 0)
    md = ImageDraw.Draw(mask)
    for _, b, r in parts:
        md.rounded_rectangle(_box(b, s), radius=r * s, fill=255)
    grow = int(round(1.6 * s)) | 1   # odd filter size
    outline = mask.filter(ImageFilter.MaxFilter(grow))

    img = Image.new("RGBA", (w, w), (0, 0, 0, 0))
    img.paste(INK, (0, 0), outline)
    d = ImageDraw.Draw(img)

    def fill(part, colour, shrink=0.0):
        _, b, r = part
        bb = (b[0] + shrink, b[1] + shrink, b[2] - shrink, b[3] - shrink)
        d.rounded_rectangle(_box(bb, s), radius=max(0.5, r - shrink) * s, fill=colour)

    # Back to front, each part outlined so the fingers read separately.
    line = max(1, round(0.9 * s))
    for part in [thumb, palm] + folded:
        d.rounded_rectangle(_box(part[1], s), radius=part[2] * s, fill=GLOVE, outline=INK, width=line)
    # The palm's lower half in shade, under the folded fingers.
    _, pb, pr = palm
    d.rounded_rectangle(_box((pb[0] + 1.0, pb[1] + 6.0, pb[2] - 1.0, pb[3] - 1.0), s), radius=(pr - 1.5) * s, fill=GLOVE_SHADE)
    for part in folded:
        d.rounded_rectangle(_box(part[1], s), radius=part[2] * s, fill=GLOVE, outline=INK, width=line)
    d.rounded_rectangle(_box(finger[1], s), radius=finger[2] * s, fill=GLOVE, outline=INK, width=line)
    # A highlight down the raised finger.
    _, fb, _ = finger
    d.rounded_rectangle(_box((fb[0] + 1.2, fb[1] + 1.4, fb[0] + 2.4, fb[3] - 3.0), s), radius=0.6 * s, fill=GLOVE_LIGHT)
    # The cuff, with a stitched band.
    d.rounded_rectangle(_box(cuff[1], s), radius=cuff[2] * s, fill=CUFF, outline=INK, width=line)
    _, cb, _ = cuff
    d.rectangle(_box((cb[0] + 1.0, cb[3] - 2.4, cb[2] - 1.0, cb[3] - 1.2), s), fill=CUFF_SHADE)

    return img.resize((size, size), Image.LANCZOS)


def main():
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
    out = os.path.normpath(os.path.join(root, "assets", "ui"))
    if len(sys.argv) > 1:
        out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for pressed in (False, True):
        for size, tag in ((32, ""), (64, "_2x")):
            name = "cursor_hand%s%s.png" % ("_pressed" if pressed else "", tag)
            render(size, pressed).save(os.path.join(out, name))
            print("wrote", os.path.join(out, name))


if __name__ == "__main__":
    main()
