#!/usr/bin/env python3
"""Convert extracted card PNGs into 1-bit ZX Spectrum bitmaps.

Reads the cards produced by extract_cards.py and writes, per card:

    <name>.bin      packed bitmap, 1 bit per pixel, MSB = leftmost pixel,
                    width/8 bytes per row, rows top to bottom
    <name>.png      preview of exactly what the Spectrum would show
    <name>.asm      the same bytes as DEFB (only with --asm)

With --scr it instead writes a 6912 byte .scr: the card centred on a real
256x192 screen in Spectrum display order plus an attribute block, so it can be
loaded straight into an emulator.

The pipeline per card is: resize -> unsharp mask -> greyscale -> optional local
contrast -> level stretch -> gamma -> dither. Every stage is exposed as a flag
because the art varies a lot: the murky potion cards and the pale parchment
cards do not want the same settings.

Usage:
    python cards_to_zx.py                          # cards/*.png -> cards_zx/
    python cards_to_zx.py --size 96x136            # different target
    python cards_to_zx.py --dither bayer           # atkinson|bayer|floyd|none
    python cards_to_zx.py --scr cards/card1_04.png # full screen, emulator ready
    python cards_to_zx.py --sheet                  # contact sheet of previews
"""

import argparse
import glob
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

IN_DIR = "cards"
OUT_DIR = "cards_zx"

SCREEN_W, SCREEN_H = 256, 192

BAYER8 = np.array([
    [0, 32, 8, 40, 2, 34, 10, 42],
    [48, 16, 56, 24, 50, 18, 58, 26],
    [12, 44, 4, 36, 14, 46, 6, 38],
    [60, 28, 52, 20, 62, 30, 54, 22],
    [3, 35, 11, 43, 1, 33, 9, 41],
    [51, 19, 59, 27, 49, 17, 57, 25],
    [15, 47, 7, 39, 13, 45, 5, 37],
    [63, 31, 55, 23, 61, 29, 53, 21],
], dtype=np.float32) / 64.0


# --------------------------------------------------------------------------- #
# tone
# --------------------------------------------------------------------------- #
def to_gray(img):
    """Luma in 0..1. Rec.601 weights, which suit these saturated inks best."""
    a = np.asarray(img.convert("RGB"), dtype=np.float32) / 255.0
    return a @ np.array([0.299, 0.587, 0.114], dtype=np.float32)


def stretch(g, low_pct, high_pct):
    """Per-card level stretch, so dark art and parchment land on the same range."""
    lo, hi = np.percentile(g, [low_pct, high_pct])
    if hi - lo < 1e-3:
        return g
    return np.clip((g - lo) / (hi - lo), 0.0, 1.0)


def local_contrast(g, clip):
    """CLAHE. Pulls detail out of murky art, at the price of dithering areas of
    flat black that would otherwise stay solid, so it is off by default."""
    if clip <= 0:
        return g
    import cv2  # only needed for this option
    clahe = cv2.createCLAHE(clipLimit=clip, tileGridSize=(4, 4))
    return clahe.apply((g * 255).astype(np.uint8)).astype(np.float32) / 255.0


def sharpen(img, amount, radius):
    """Detail the dither would otherwise swallow has to be exaggerated first."""
    if amount <= 0:
        return img
    return img.filter(ImageFilter.UnsharpMask(radius=radius,
                                              percent=int(amount * 100),
                                              threshold=2))


def fit(size, box):
    """Largest w x h inside box keeping aspect, width snapped to a byte."""
    bw, bh = box
    w, h = size
    scale = min(bw / w, bh / h)
    out_w = max(8, int(round(w * scale)) // 8 * 8)
    out_h = max(1, min(bh, int(round(h * scale))))
    return out_w, out_h


# --------------------------------------------------------------------------- #
# dithering. 1 = ink (black on screen), 0 = paper.
# --------------------------------------------------------------------------- #
def dither_bayer(g):
    h, w = g.shape
    t = np.tile(BAYER8, (h // 8 + 1, w // 8 + 1))[:h, :w]
    return (g < t).astype(np.uint8)


def dither_error(g, kernel, divisor):
    """Serpentine error diffusion; serpentine avoids the diagonal worming."""
    g = g.astype(np.float32).copy()
    h, w = g.shape
    out = np.zeros((h, w), dtype=np.uint8)
    for y in range(h):
        rng = range(w) if y % 2 == 0 else range(w - 1, -1, -1)
        flip = 1 if y % 2 == 0 else -1
        for x in rng:
            old = g[y, x]
            new = 1.0 if old >= 0.5 else 0.0
            out[y, x] = 0 if new else 1
            err = old - new
            for dx, dy, weight in kernel:
                nx, ny = x + dx * flip, y + dy
                if 0 <= nx < w and 0 <= ny < h:
                    g[ny, nx] += err * weight / divisor
    return out


FLOYD = ([(1, 0, 7), (-1, 1, 3), (0, 1, 5), (1, 1, 1)], 16)
# Atkinson only passes on 3/4 of the error, which keeps 1-bit art crisp.
ATKINSON = ([(1, 0, 1), (2, 0, 1), (-1, 1, 1), (0, 1, 1), (1, 1, 1), (0, 2, 1)], 8)


def dither(g, mode):
    if mode == "bayer":
        return dither_bayer(g)
    if mode == "floyd":
        return dither_error(g, *FLOYD)
    if mode == "atkinson":
        return dither_error(g, *ATKINSON)
    if mode == "none":
        return (g < 0.5).astype(np.uint8)
    raise ValueError(f"unknown dither mode: {mode}")


# --------------------------------------------------------------------------- #
# packing
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
    """Centre the bitmap on a 256x192 screen and add the attribute block."""
    canvas = np.zeros((SCREEN_H, SCREEN_W), dtype=np.uint8)
    h, w = bits.shape
    x0 = ((SCREEN_W - w) // 2) // 8 * 8
    y0 = (SCREEN_H - h) // 2
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


# --------------------------------------------------------------------------- #
def convert(path, args, out_dir):
    name = os.path.splitext(os.path.basename(path))[0]
    src = Image.open(path)

    if args.crop:
        src = src.crop(crop_box(src.size, args.crop))

    box = (SCREEN_W, SCREEN_H) if args.scr else args.size
    img = src.resize(fit(src.size, box), Image.LANCZOS)
    img = sharpen(img, args.sharpen, args.sharpen_radius)

    g = local_contrast(to_gray(img), args.local_contrast)
    g = stretch(g, args.black_point, args.white_point)
    if args.gamma != 1.0:
        g = np.power(g, args.gamma)
    if args.invert:
        g = 1.0 - g
    bits = dither(g, args.dither)

    out = os.path.join(out_dir, name)
    if args.scr:
        data = to_scr(bits, args.attr)
        open(out + ".scr", "wb").write(data)
        kind = f"{out}.scr  6912 bytes"
    else:
        data = pack(bits)
        open(out + ".bin", "wb").write(data)
        row_bytes = (bits.shape[1] + 7) // 8
        if args.asm:
            write_asm(out + ".asm", data, name, row_bytes)
        kind = f"{out}.bin  {bits.shape[1]}x{bits.shape[0]}px  {len(data)} bytes"

    prev = preview(bits, args.zoom)
    prev.save(out + ".png")
    print(kind)
    return prev, name


def write_sheet(previews, out_dir, per_row=7):
    if not previews:
        return
    tw = max(p.width for p, _ in previews) + 8
    th = max(p.height for p, _ in previews) + 8
    rows = (len(previews) + per_row - 1) // per_row
    sheet = Image.new("L", (tw * per_row, th * rows), 255)
    for i, (p, _) in enumerate(previews):
        sheet.paste(p, ((i % per_row) * tw + 4, (i // per_row) * th + 4))
    path = os.path.join(out_dir, "_sheet.png")
    sheet.save(path)
    print(f"contact sheet: {path}")


def parse_size(text):
    w, _, h = text.lower().partition("x")
    return int(w), int(h)


def parse_crop(text):
    """left,top,right,bottom as fractions of the card, e.g. 0.04,0.15,0.96,0.69."""
    parts = [float(v) for v in text.split(",")]
    if len(parts) != 4:
        raise argparse.ArgumentTypeError("--crop wants four comma separated numbers")
    l, t, r, b = parts
    if not (0 <= l < r <= 1 and 0 <= t < b <= 1):
        raise argparse.ArgumentTypeError("--crop wants 0 <= left < right <= 1 (same for top/bottom)")
    return l, t, r, b


def crop_box(size, frac):
    """Fractions to a pixel box, for cropping the art out of a card."""
    w, h = size
    l, t, r, b = frac
    return int(round(l * w)), int(round(t * h)), int(round(r * w)), int(round(b * h))


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cards", nargs="*", help=f"card PNGs (default: {IN_DIR}/card*.png)")
    ap.add_argument("--size", type=parse_size, default=(128, 176),
                    metavar="WxH", help="target box, width snaps to a byte (128x176)")
    ap.add_argument("--scr", action="store_true",
                    help="write a full 256x192 .scr instead of a raw bitmap")
    ap.add_argument("--crop", type=parse_crop, metavar="L,T,R,B",
                    help="cut a region out of each card first, as fractions "
                         "(the figure on a character card is 0.04,0.15,0.96,0.69)")
    ap.add_argument("--attr", type=lambda s: int(s, 0), default=0x47,
                    help="attribute byte for --scr (default 0x47: bright white on black)")
    ap.add_argument("--dither", default="atkinson",
                    choices=["atkinson", "bayer", "floyd", "none"],
                    help="atkinson keeps the most contrast on this art (default)")
    ap.add_argument("--black-point", type=float, default=2.0,
                    help="percentile mapped to black (2)")
    ap.add_argument("--white-point", type=float, default=98.0,
                    help="percentile mapped to white (98)")
    ap.add_argument("--local-contrast", type=float, default=0.0, metavar="CLIP",
                    help="CLAHE clip limit; 2-3 rescues murky art, 0 = off (default)")
    ap.add_argument("--gamma", type=float, default=1.0,
                    help=">1 darkens midtones, <1 lifts them")
    ap.add_argument("--sharpen", type=float, default=1.2,
                    help="unsharp amount, 0 disables (1.2)")
    ap.add_argument("--sharpen-radius", type=float, default=1.5)
    ap.add_argument("--invert", action="store_true", help="swap ink and paper")
    ap.add_argument("--zoom", type=int, default=1, help="preview magnification")
    ap.add_argument("--asm", action="store_true", help="also emit DEFB source")
    ap.add_argument("--sheet", action="store_true", help="write cards_zx/_sheet.png")
    ap.add_argument("--out", default=OUT_DIR, help=f"output directory ({OUT_DIR})")
    args = ap.parse_args()

    cards = args.cards or sorted(glob.glob(os.path.join(IN_DIR, "card*.png")))
    if not cards:
        print(f"no cards found (expected {IN_DIR}/card*.png)")
        return 1

    out_dir = args.out
    os.makedirs(out_dir, exist_ok=True)

    previews = [convert(p, args, out_dir) for p in cards]
    print(f"total: {len(previews)} cards -> {out_dir}/")
    if args.sheet:
        write_sheet(previews, out_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
