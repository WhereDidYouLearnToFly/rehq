#!/usr/bin/env python3
"""Draw the four heroes as 1-bit contour art for the inventory screen.

Nothing is traced or scanned here: each figure is authored as vector shapes in
this file and rendered. Shapes are painted back to front, and every shape both
erases what is behind it and draws its own outline, so the picture reads as
contours -- a beard in front of a chest cuts the chest line, the way an inked
drawing does. Only the outline survives; the interiors stay paper.

Everything is drawn 4x oversized and boxed down to the target, which is what
keeps the diagonals from breaking up: a 4px band at 4x lands as one solid pixel.

Output per hero, into heroes_zx/:

    <name>.bin      packed bitmap, 1 bit per pixel, MSB = leftmost pixel,
                    width/8 bytes per row, rows top to bottom
    <name>.png      preview of exactly what the Spectrum would show
    <name>.asm      the same bytes as DEFB (only with --asm)

Usage:
    python heroes.py                        # all four -> heroes_zx/
    python heroes.py barbarian --zoom 4     # one, big preview
    python heroes.py --size 96x160          # different target
    python heroes.py --solid                # filled silhouettes, no contour
    python heroes.py --scr wizard           # full screen, emulator ready
    python heroes.py --sheet                # all four side by side
"""

import argparse
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

OUT_DIR = "heroes_zx"
SCREEN_W, SCREEN_H = 256, 192

W, H = 96, 160          # the canvas the figures are authored on
CX = W / 2              # mirror axis
SS = 4                  # supersample factor


# --------------------------------------------------------------------------- #
# authoring helpers
# --------------------------------------------------------------------------- #
def mir(pts):
    """The same shape, flipped about the mirror axis."""
    return [(2 * CX - x, y) for x, y in pts]


def sym(path):
    """Close a half-figure. Author the left side top to bottom, ending on the
    mirror axis; this returns the whole outline."""
    return list(path) + [(2 * CX - x, y) for x, y in reversed(path)]


def _circle(cx, cy, r, n=32):
    t = np.linspace(0, 2 * np.pi, n, endpoint=False)
    return list(zip(cx + r * np.cos(t), cy + r * np.sin(t)))


class Figure:
    """An ordered pile of shapes and strokes, painted back to front."""

    def __init__(self, name, title):
        self.name = name
        self.title = title
        self.ops = []

    def shape(self, pts):
        """A filled region: hides what is behind it, contributes its outline."""
        self.ops.append(("shape", list(pts)))
        return self

    def blot(self, pts):
        """A solid black region. Hair, boots and belts want mass, not outline."""
        self.ops.append(("blot", list(pts)))
        return self

    def cut(self, pts):
        """A hole punched back to paper -- a buckle inside a solid belt."""
        self.ops.append(("cut", list(pts)))
        return self

    def half(self, path):
        """A symmetric filled region, authored as its left half."""
        return self.shape(sym(path))

    def mshape(self, pts):
        """A shape and its mirror image -- the two legs, the two arms."""
        self.shape(pts)
        return self.shape(mir(pts))

    def mblot(self, pts):
        self.blot(pts)
        return self.blot(mir(pts))

    def mcut(self, pts):
        self.cut(pts)
        return self.cut(mir(pts))

    def ell(self, x0, y0, x1, y1, n=48):
        """An ellipse, as a shape."""
        rx, ry = (x1 - x0) / 2, (y1 - y0) / 2
        cx, cy = x0 + rx, y0 + ry
        t = np.linspace(0, 2 * np.pi, n, endpoint=False)
        return self.shape(zip(cx + rx * np.cos(t), cy + ry * np.sin(t)))

    def line(self, *pts, w=1):
        """A stroke that sits on top of whatever has been painted so far."""
        self.ops.append(("line", list(pts), w))
        return self

    def mline(self, *pts, w=1):
        """A stroke and its mirror image."""
        self.line(*pts, w=w)
        return self.line(*[(2 * CX - x, y) for x, y in pts], w=w)

    def dot(self, x, y, r=1):
        return self.ell(x - r, y - r, x + r, y + r, n=16)


# --------------------------------------------------------------------------- #
# rendering
# --------------------------------------------------------------------------- #
def _fill(pts, size):
    img = Image.new("L", size, 0)
    ImageDraw.Draw(img).polygon([(x * SS, y * SS) for x, y in pts], fill=255)
    return np.asarray(img) > 127


def _stroke(pts, width, size):
    img = Image.new("L", size, 0)
    ImageDraw.Draw(img).line([(x * SS, y * SS) for x, y in pts],
                             fill=255, width=max(1, int(width * SS)), joint="curve")
    return np.asarray(img) > 127


def _edge(mask):
    """The inward border of a mask, SS pixels thick, so it survives boxing down."""
    eroded = mask.copy()
    for _ in range(SS):
        e = eroded
        e = e & np.pad(e, ((1, 0), (0, 0)))[:-1] & np.pad(e, ((0, 1), (0, 0)))[1:]
        e = e & np.pad(e, ((0, 0), (1, 0)))[:, :-1] & np.pad(e, ((0, 0), (0, 1)))[:, 1:]
        eroded = e
    return mask & ~eroded


def render(fig, size=(W, H), solid=False):
    """Paint the figure and box it down to 1 bit per pixel."""
    w, h = size
    big = (w * SS, h * SS)
    ink = np.zeros((h * SS, w * SS), dtype=bool)
    body = np.zeros_like(ink)

    for op in fig.ops:
        if op[0] == "line":
            _, pts, width = op
            ink |= _stroke(pts, width, big)
            continue
        mask = _fill(op[1], big)
        ink &= ~mask                        # anything painted hides what is behind
        if op[0] == "shape":
            ink |= _edge(mask)
            body |= mask
        elif op[0] == "blot":
            ink |= mask
            body |= mask

    out = body if solid else ink
    # box filter down: a run of SS lit pixels becomes one lit pixel
    cov = out.reshape(h, SS, w, SS).mean(axis=(1, 3))
    return cov >= 0.42


# --------------------------------------------------------------------------- #
# the heroes
# --------------------------------------------------------------------------- #
def barbarian():
    f = Figure("barbarian", "BARBARIAN")

    # mane: solid, and wide enough to frame the face once the head cuts into it
    f.blot(sym([(48, 4), (37, 6), (31, 14), (30, 26), (32, 38), (28, 50),
                (35, 52), (39, 42), (40, 28), (40, 13), (44, 7)]))

    # body
    f.half([(48, 9), (41, 11), (38, 17), (38, 24), (41, 30), (44, 33), (43, 36),
            (32, 37), (25, 42), (22, 50), (20, 62), (20, 73), (22, 83), (25, 91),
            (31, 95), (35, 90), (33, 78), (32, 64), (35, 50), (34, 61), (33, 71),
            (36, 80), (38, 87), (36, 101), (35, 115), (36, 129), (37, 141),
            (35, 150), (28, 155), (28, 158), (45, 158), (45, 147), (46, 129),
            (47, 111), (47, 100), (48, 95)])

    # face
    f.mline((40, 19), (45, 21), w=1)                                  # brow
    f.mline((42, 23), (45, 23), w=1)                                  # eye
    f.line((48, 21), (46, 26), (50, 26), w=1)                         # nose
    f.line((44, 29), (52, 29), w=1)                                   # mouth

    # chest, stomach, shoulder seam
    f.mline((36, 46), (40, 54), (47, 56), w=1)
    f.line((48, 56), (48, 67), w=1)
    f.mline((42, 60), (47, 60), w=1)
    f.mline((42, 65), (47, 65), w=1)
    f.mline((25, 43), (35, 48), w=1)
    f.mline((20, 58), (32, 60), w=1)                                  # arm band

    # belt with a punched buckle, then the loincloth under it
    f.shape([(37, 77), (59, 77), (57, 97), (48, 102), (39, 97)])
    f.line((48, 79), (48, 99), w=1)
    f.blot([(33, 68), (63, 68), (63, 78), (33, 78)])
    f.cut([(45, 70), (51, 70), (51, 76), (45, 76)])

    # broadsword, held out from the body so the blade reads clear of the arm
    f.shape([(63, 86), (71, 89), (88, 28), (86, 19), (80, 26)])       # blade
    f.line((84, 27), (68, 84), w=1)                                   # fuller
    f.blot([(58, 84), (76, 90), (75, 94), (57, 88)])                  # crossguard
    f.shape([(63, 92), (70, 94), (66, 106), (60, 104)])               # grip
    f.blot(_circle(62, 107, 4))                                       # pommel

    # boots
    f.blot([(35, 134), (44, 134), (45, 147), (45, 158), (28, 158), (28, 155),
            (34, 150)])
    f.blot([(52, 134), (61, 134), (62, 150), (68, 155), (68, 158), (51, 158),
            (51, 147)])
    f.cut([(36, 138), (44, 138), (44, 141), (36, 141)])
    f.cut([(52, 138), (60, 138), (60, 141), (52, 141)])
    return f


def dwarf():
    f = Figure("dwarf", "DWARF")

    # body: wide and low shouldered, but the arms hang clear of the barrel so
    # the whole thing does not read as one egg
    f.half([(48, 32), (40, 33), (36, 39), (36, 47), (39, 53), (42, 56), (41, 59),
            (31, 61), (24, 68), (21, 80), (22, 92), (25, 101), (30, 107),
            (35, 104), (33, 92), (32, 80), (35, 69), (33, 82), (32, 96),
            (34, 106), (35, 112), (33, 124), (32, 136), (33, 146),
            (30, 152), (25, 156), (25, 159), (44, 159), (44, 148), (45, 133),
            (46, 120), (48, 114)])
    f.mline((31, 62), (35, 70), w=1)                                  # shoulder seam
    f.mline((22, 86), (33, 88), w=1)                                  # cuff

    # helm: solid dome, paper nose guard cut back out of it
    f.blot(sym([(48, 17), (40, 19), (34, 26), (32, 35), (29, 41), (34, 44),
                (38, 39), (40, 30), (44, 22)]))
    f.cut([(45, 38), (51, 38), (51, 53), (45, 53)])
    f.line((45, 38), (45, 53), w=1)
    f.line((51, 38), (51, 53), w=1)
    f.mline((37, 46), (43, 47), w=1)                                  # eye

    # beard, over the chest, narrow enough to leave the arms free
    f.shape([(39, 52), (44, 57), (52, 57), (57, 52), (59, 68), (57, 84),
             (51, 97), (48, 101), (45, 97), (39, 84), (37, 68)])
    f.mline((44, 62), (42, 79), (46, 93), w=1)
    f.line((48, 64), (48, 97), w=1)

    # belt and buckle
    f.blot([(30, 101), (66, 101), (66, 111), (30, 111)])
    f.cut([(43, 103), (53, 103), (53, 109), (43, 109)])

    # boots
    f.blot([(30, 138), (44, 138), (44, 159), (25, 159), (25, 156), (31, 152)])
    f.blot([(52, 138), (66, 138), (65, 152), (71, 156), (71, 159), (52, 159)])
    f.cut([(31, 142), (43, 142), (43, 145), (31, 145)])
    f.cut([(53, 142), (65, 142), (65, 145), (53, 145)])

    # battleaxe, stood beside him, clear of the body. One big bit reads better
    # at this size than two small ones.
    f.shape([(76, 26), (81, 26), (81, 154), (76, 154)])
    f.blot([(81, 26), (88, 28), (94, 38), (94, 50), (88, 60), (81, 62),
            (84, 50), (84, 38)])
    f.shape([(76, 34), (70, 32), (68, 42), (72, 50), (76, 48)])       # back spike
    f.line((78, 64), (78, 150), w=1)
    return f


def elf():
    f = Figure("elf", "ELF")

    # cloak: hangs behind, and only really opens out below the belt, so it
    # frames the figure instead of swallowing it
    f.shape(sym([(48, 34), (36, 37), (32, 56), (30, 78), (27, 104), (23, 128),
                 (26, 136), (32, 130), (37, 136), (43, 130), (48, 136)]))
    f.mline((32, 60), (29, 100), (27, 130), w=1)                      # cloak fold

    # hair, cut at the shoulder
    f.blot(sym([(48, 7), (40, 9), (36, 16), (35, 26), (34, 36), (33, 46),
                (38, 48), (40, 38), (41, 26), (43, 12)]))

    # body: narrow, long limbed
    f.half([(48, 11), (42, 13), (39, 19), (39, 26), (42, 32), (45, 35), (44, 38),
            (36, 39), (30, 44), (28, 54), (27, 66), (28, 78), (30, 88), (33, 95),
            (37, 91), (35, 79), (34, 66), (37, 52), (36, 63), (35, 73),
            (37, 82), (39, 89), (38, 103), (37, 117), (38, 131), (39, 143),
            (37, 151), (31, 156), (31, 159), (46, 159), (46, 148), (47, 130),
            (47, 112), (48, 100)])

    # face, with the ear pushed up through the hair
    f.mline((41, 21), (45, 22), w=1)
    f.mline((42, 24), (45, 24), w=1)
    f.line((48, 22), (46, 26), (50, 26), w=1)
    f.line((45, 30), (51, 30), w=1)
    f.shape([(39, 25), (36, 14), (34, 22), (36, 27)])                 # pointed ear

    # tunic with a laced collar, and a quiver strap across it
    f.shape([(36, 39), (60, 39), (63, 58), (61, 76), (57, 86), (48, 89),
             (39, 86), (35, 76), (33, 58)])
    f.line((41, 41), (48, 50), (55, 41), w=1)                         # collar
    f.mline((44, 52), (48, 55), w=1)
    f.mline((44, 58), (48, 61), w=1)
    f.line((37, 48), (59, 72), w=1)
    f.line((39, 46), (61, 70), w=1)

    # belt, hip sword, boots
    f.blot([(34, 76), (62, 76), (62, 85), (34, 85)])
    f.cut([(44, 78), (52, 78), (52, 83), (44, 83)])
    f.shape([(60, 82), (66, 85), (71, 120), (67, 121), (61, 88)])
    f.blot([(37, 130), (46, 130), (46, 159), (31, 159), (31, 156), (36, 152)])
    f.blot([(50, 130), (59, 130), (60, 152), (65, 156), (65, 159), (50, 159)])
    f.cut([(38, 134), (46, 134), (46, 137), (38, 137)])
    f.cut([(50, 134), (58, 134), (58, 137), (50, 137)])

    # longbow, held clear of the cloak: a thin limb and a straight string
    f.blot([(14, 50), (17, 54), (20, 84), (17, 114), (14, 118), (17, 84)])
    f.line((15, 52), (15, 116), w=1)                                  # string
    return f


def wizard():
    f = Figure("wizard", "WIZARD")

    # robe: one long triangle, the silhouette that says wizard, but with real
    # shoulders on it so the head is not sitting on a cone
    f.half([(48, 42), (40, 43), (34, 48), (31, 58), (26, 82), (20, 112),
            (14, 142), (15, 153), (48, 156)])

    # head
    f.half([(48, 26), (42, 27), (40, 32), (40, 38), (43, 43), (46, 45), (48, 46)])
    f.mline((41, 33), (44, 34), w=1)
    f.line((48, 33), (46, 37), (50, 37), w=1)

    # hat: solid, brim first so the point sits on top of it
    f.blot([(31, 23), (65, 23), (67, 29), (29, 29)])
    f.blot([(35, 26), (61, 26), (57, 13), (51, 5), (43, 8), (37, 16)])
    f.cut([(37, 19), (59, 19), (59, 22), (37, 22)])                   # hat band
    f.cut(_circle(50, 12, 3))                                         # star on the hat

    # beard, from the cheeks to the waist
    f.shape([(40, 40), (44, 46), (52, 46), (56, 40), (58, 56), (55, 76),
             (48, 92), (41, 76), (38, 56)])
    f.mline((44, 52), (43, 70), (46, 86), w=1)
    f.line((48, 50), (48, 90), w=1)

    # sleeves, flaring from the shoulder down to a cuff the hand comes out of
    f.shape([(38, 46), (30, 58), (24, 80), (23, 97), (36, 101), (40, 92),
             (34, 80), (35, 60)])
    f.shape([(58, 46), (66, 58), (72, 80), (73, 97), (60, 101), (56, 92),
             (62, 80), (61, 60)])
    f.mline((23, 95), (36, 99), w=1)                                  # cuff

    # rope belt with a knot and two tails
    f.blot([(38, 90), (58, 90), (58, 95), (38, 95)])
    f.line((44, 95), (43, 112), w=1)
    f.line((52, 95), (53, 112), w=1)

    # staff, gripped in the right hand, taller than he is
    f.shape([(69, 30), (75, 30), (75, 156), (69, 156)])
    f.blot(_circle(72, 22, 9))
    f.cut(_circle(72, 22, 4))
    f.shape([(60, 96), (77, 94), (79, 102), (77, 109), (60, 107)])    # hand on it
    f.shape([(22, 97), (34, 95), (37, 102), (34, 110), (22, 108)])    # open hand
    f.mline((26, 99), (26, 107), w=1)                                 # fingers
    f.mline((30, 98), (30, 108), w=1)

    # robe folds and hem
    f.mline((41, 104), (36, 128), (32, 150), w=1)
    f.mline((46, 106), (45, 128), (44, 150), w=1)
    f.line((16, 146), (80, 146), w=1)
    return f


HEROES = {f.name: f for f in (barbarian(), dwarf(), elf(), wizard())}


# --------------------------------------------------------------------------- #
# output
# --------------------------------------------------------------------------- #
def pack(bits):
    """Rows of 1bpp bytes, MSB = leftmost pixel."""
    h, w = bits.shape
    if w % 8:
        bits = np.pad(bits, ((0, 0), (0, 8 - w % 8)))
    return np.packbits(bits, axis=1).tobytes()


def scr_offset(y):
    """Spectrum display file is stored third / pixel row / character row."""
    return ((y >> 6) * 2048) + ((y & 7) * 256) + (((y >> 3) & 7) * 32)


def to_scr(bits, attr):
    canvas = np.zeros((SCREEN_H, SCREEN_W), dtype=np.uint8)
    h, w = bits.shape
    x0 = ((SCREEN_W - w) // 2) // 8 * 8
    y0 = max(0, (SCREEN_H - h) // 2)
    canvas[y0:y0 + h, x0:x0 + w] = bits[:min(h, SCREEN_H - y0), :min(w, SCREEN_W - x0)]
    packed = np.packbits(canvas, axis=1)
    screen = bytearray(6912)
    for y in range(SCREEN_H):
        screen[scr_offset(y):scr_offset(y) + 32] = packed[y].tobytes()
    screen[6144:] = bytes([attr]) * 768
    return bytes(screen)


def preview(bits, zoom):
    img = Image.fromarray(np.where(bits, 0, 255).astype(np.uint8), mode="L")
    if zoom > 1:
        img = img.resize((img.width * zoom, img.height * zoom), Image.NEAREST)
    return img


def write_asm(path, data, label, row_bytes):
    with open(path, "w") as fh:
        fh.write(f"; {label}: {len(data)} bytes, {row_bytes} bytes per row\n")
        fh.write(f"{label}:\n")
        for i in range(0, len(data), row_bytes):
            row = ", ".join(f"${b:02X}" for b in data[i:i + row_bytes])
            fh.write(f"        defb {row}\n")


def write_sheet(previews, out_dir):
    if not previews:
        return
    tw = max(p.width for p, _ in previews) + 8
    th = max(p.height for p, _ in previews) + 8
    sheet = Image.new("L", (tw * len(previews), th), 255)
    for i, (p, _) in enumerate(previews):
        sheet.paste(p, (i * tw + 4, 4))
    path = os.path.join(out_dir, "_sheet.png")
    sheet.save(path)
    print(f"contact sheet: {path}")


def parse_size(text):
    w, _, h = text.lower().partition("x")
    return int(w), int(h)


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("heroes", nargs="*", help="which heroes (default: all four)")
    ap.add_argument("--size", type=parse_size, default=(W, H),
                    help=f"target size, WxH ({W}x{H})")
    ap.add_argument("--solid", action="store_true",
                    help="filled silhouettes instead of contours")
    ap.add_argument("--scr", action="store_true", help="write a 6912 byte .scr")
    ap.add_argument("--attr", type=lambda s: int(s, 0), default=0x47,
                    help="attribute byte for --scr (0x47)")
    ap.add_argument("--asm", action="store_true", help="also write DEFB source")
    ap.add_argument("--zoom", type=int, default=1, help="preview magnification")
    ap.add_argument("--sheet", action="store_true", help="write _sheet.png")
    ap.add_argument("--out", default=OUT_DIR, help=f"output directory ({OUT_DIR})")
    args = ap.parse_args()

    names = args.heroes or list(HEROES)
    unknown = [n for n in names if n not in HEROES]
    if unknown:
        sys.exit(f"unknown hero(es): {', '.join(unknown)}\n"
                 f"known: {', '.join(HEROES)}")

    os.makedirs(args.out, exist_ok=True)
    previews = []
    for name in names:
        bits = render(HEROES[name], args.size, args.solid)
        out = os.path.join(args.out, name)
        if args.scr:
            open(out + ".scr", "wb").write(to_scr(bits, args.attr))
            print(f"{out}.scr  6912 bytes")
        else:
            data = pack(bits)
            open(out + ".bin", "wb").write(data)
            row_bytes = (bits.shape[1] + 7) // 8
            if args.asm:
                write_asm(out + ".asm", data, name, row_bytes)
            print(f"{out}.bin  {bits.shape[1]}x{bits.shape[0]}px  {len(data)} bytes")
        p = preview(bits, args.zoom)
        p.save(out + ".png")
        previews.append((p, name))

    if args.sheet:
        write_sheet(previews, args.out)


if __name__ == "__main__":
    main()
