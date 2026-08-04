#!/usr/bin/env python3
"""Convert a picture to a full colour Spectrum screen.

cards_to_zx.py throws colour away and keeps one attribute for the whole image,
which is right for ink drawings on parchment and useless for a dark painting:
turn a green dragon on a green ruin into luma and the dragon disappears, because
what separated them was hue, not brightness.

So this one uses the attributes. Each 8x8 cell gets its own ink and paper,
chosen together with the bright flag by trying all 128 legal combinations and
keeping whichever reproduces that cell's 64 pixels with the least error. Pixels
are then assigned to whichever of the two colours they are nearer.

The catch is the hardware's, not the code's: two colours per cell, and bright
applies to both at once. Fine detail inside a cell that spans three colours will
still be lost -- that is attribute clash, and no converter avoids it.

Output is a 6912 byte .scr plus a PNG of exactly what the machine will show.

Usage:
    python png_to_scr.py dragon.png                  # -> dragon.scr
    python png_to_scr.py dragon.png --contrast 4     # lift a flat, dark source
    python png_to_scr.py dragon.png --crop 0.19,0.02,0.81,0.92
    python png_to_scr.py dragon.png --dither floyd   # none|bayer|floyd
    python png_to_scr.py dragon.png --fill           # crop to fill, not letterbox
"""

import argparse
import os

import numpy as np
from PIL import Image

SCREEN_W, SCREEN_H = 256, 192
NORMAL, BRIGHT = 215, 255

BAYER8 = np.array([
    [0, 32, 8, 40, 2, 34, 10, 42], [48, 16, 56, 24, 50, 18, 58, 26],
    [12, 44, 4, 36, 14, 46, 6, 38], [60, 28, 52, 20, 62, 30, 54, 22],
    [3, 35, 11, 43, 1, 33, 9, 41], [51, 19, 59, 27, 49, 17, 57, 25],
    [15, 47, 7, 39, 13, 45, 5, 37], [63, 31, 55, 23, 61, 29, 53, 21],
], dtype=np.float32) / 64.0


def palette():
    """The 16 Spectrum colours as RGB. Index is bright * 8 + colour."""
    out = []
    for level in (NORMAL, BRIGHT):
        for c in range(8):
            out.append(((c >> 1 & 1) * level, (c >> 2 & 1) * level, (c & 1) * level))
    return np.array(out, dtype=np.float32)


PALETTE = palette()


def local_contrast(rgb, clip):
    """CLAHE on lightness only, so hue survives. Flat dark art needs this."""
    if clip <= 0:
        return rgb
    import cv2
    lab = cv2.cvtColor(rgb.astype(np.uint8), cv2.COLOR_RGB2LAB)
    lab[:, :, 0] = cv2.createCLAHE(clip, (8, 8)).apply(lab[:, :, 0])
    return cv2.cvtColor(lab, cv2.COLOR_LAB2RGB).astype(np.float32)


def frame(img, fill):
    """Fit to 256x192, either letterboxed or cropped to fill."""
    w, h = img.size
    scale = max if fill else min
    f = scale(SCREEN_W / w, SCREEN_H / h)
    img = img.resize((max(1, round(w * f)), max(1, round(h * f))), Image.LANCZOS)
    out = Image.new("RGB", (SCREEN_W, SCREEN_H), (0, 0, 0))
    out.paste(img, ((SCREEN_W - img.width) // 2, (SCREEN_H - img.height) // 2))
    return out


def choose_attributes(rgb):
    """Per cell, the (bright, ink, paper) that reproduces it best.

    All 128 combinations are scored against every pixel in the cell, which is
    cheap enough at 768 cells and avoids the guesswork of picking colours from
    a cell average.
    """
    cells = rgb.reshape(24, 8, 32, 8, 3).transpose(0, 2, 1, 3, 4).reshape(768, 64, 3)
    # squared distance from every pixel to every palette entry
    dist = ((cells[:, :, None, :] - PALETTE[None, None, :, :]) ** 2).sum(axis=3)

    best_err = np.full(768, np.inf, dtype=np.float32)
    best = np.zeros((768, 3), dtype=np.int32)
    for bright in (0, 1):
        base = bright * 8
        for ink in range(8):
            di = dist[:, :, base + ink]
            for paper in range(8):
                err = np.minimum(di, dist[:, :, base + paper]).sum(axis=1)
                better = err < best_err
                if better.any():
                    best_err = np.where(better, err, best_err)
                    best[better] = (bright, ink, paper)
    return best


def draw(rgb, attrs, mode):
    """Decide ink or paper for every pixel, optionally dithering between them."""
    cells = rgb.reshape(24, 8, 32, 8, 3).transpose(0, 2, 1, 3, 4).reshape(768, 64, 3)
    ink = PALETTE[attrs[:, 0] * 8 + attrs[:, 1]]
    paper = PALETTE[attrs[:, 0] * 8 + attrs[:, 2]]

    axis = ink - paper
    length = (axis ** 2).sum(axis=1)
    length[length == 0] = 1.0
    # how far along the paper->ink line each pixel sits, 0..1
    t = (((cells - paper[:, None, :]) * axis[:, None, :]).sum(axis=2)
         / length[:, None])
    t = np.clip(t, 0.0, 1.0)

    grid = t.reshape(24, 32, 8, 8).transpose(0, 2, 1, 3).reshape(SCREEN_H, SCREEN_W)
    if mode == "bayer":
        bits = grid > np.tile(BAYER8, (24, 32))
    elif mode == "floyd":
        bits = np.zeros_like(grid, dtype=bool)
        work = grid.copy()
        for y in range(SCREEN_H):
            for x in range(SCREEN_W):
                old = work[y, x]
                new = 1.0 if old >= 0.5 else 0.0
                bits[y, x] = new > 0.5
                e = old - new
                if x + 1 < SCREEN_W:
                    work[y, x + 1] += e * 7 / 16
                if y + 1 < SCREEN_H:
                    if x:
                        work[y + 1, x - 1] += e * 3 / 16
                    work[y + 1, x] += e * 5 / 16
                    if x + 1 < SCREEN_W:
                        work[y + 1, x + 1] += e * 1 / 16
    else:
        bits = grid >= 0.5
    return bits


def scr_offset(y):
    """Spectrum display file: third / pixel row / character row."""
    return ((y >> 6) * 2048) + ((y & 7) * 256) + (((y >> 3) & 7) * 32)


def to_scr(bits, attrs):
    packed = np.packbits(bits.astype(np.uint8), axis=1)
    screen = bytearray(6912)
    for y in range(SCREEN_H):
        screen[scr_offset(y):scr_offset(y) + 32] = packed[y].tobytes()
    bright, ink, paper = attrs[:, 0], attrs[:, 1], attrs[:, 2]
    screen[6144:] = bytes((bright * 64 + paper * 8 + ink).astype(np.uint8))
    return bytes(screen)


def render(bits, attrs):
    """What the machine will actually show."""
    ink = PALETTE[attrs[:, 0] * 8 + attrs[:, 1]].reshape(24, 32, 3)
    paper = PALETTE[attrs[:, 0] * 8 + attrs[:, 2]].reshape(24, 32, 3)
    ink = np.repeat(np.repeat(ink, 8, axis=0), 8, axis=1)
    paper = np.repeat(np.repeat(paper, 8, axis=0), 8, axis=1)
    return np.where(bits[:, :, None], ink, paper).astype(np.uint8)


def parse_crop(text):
    l, t, r, b = (float(v) for v in text.split(","))
    return l, t, r, b


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("images", nargs="+")
    ap.add_argument("--crop", type=parse_crop, metavar="L,T,R,B",
                    help="cut a region first, as fractions of the image")
    ap.add_argument("--contrast", type=float, default=0.0,
                    help="CLAHE clip on lightness; try 3-5 for dark flat art (0)")
    ap.add_argument("--dither", default="floyd", choices=("none", "bayer", "floyd"))
    ap.add_argument("--fill", action="store_true",
                    help="crop to fill the screen instead of letterboxing")
    ap.add_argument("--zoom", type=int, default=1, help="preview magnification")
    ap.add_argument("--out", default=".", help="output directory")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    for path in args.images:
        name = os.path.splitext(os.path.basename(path))[0]
        img = Image.open(path).convert("RGB")
        if args.crop:
            w, h = img.size
            l, t, r, b = args.crop
            img = img.crop((int(l * w), int(t * h), int(r * w), int(b * h)))

        rgb = np.asarray(frame(img, args.fill), dtype=np.float32)
        rgb = local_contrast(rgb, args.contrast)

        attrs = choose_attributes(rgb)
        bits = draw(rgb, attrs, args.dither)

        out = os.path.join(args.out, name)
        open(out + ".scr", "wb").write(to_scr(bits, attrs))
        shown = Image.fromarray(render(bits, attrs))
        if args.zoom > 1:
            shown = shown.resize((SCREEN_W * args.zoom, SCREEN_H * args.zoom),
                                 Image.NEAREST)
        shown.save(out + "_scr.png")
        used = len(set(map(tuple, attrs.tolist())))
        print(f"{out}.scr  6912 bytes  {used} distinct attribute pairs")


if __name__ == "__main__":
    main()
