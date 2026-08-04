#!/usr/bin/env python3
"""Lift the hero figures off the parchment, as pictures and as drawing data.

The character cards paint a figure on a mottled parchment ground. Modelling
that ground by colour does not work -- the barbarian's skin is the same tan as
the paper -- so the split is done with GrabCut, seeded with a rectangle just
inside the crop. What comes back is a silhouette, and everything else is
derived from it.

Two ways to keep a figure, and the whole point of the exercise is that the
second one is an order of magnitude smaller than the first:

    bitmap    <name>_solid/_line/_ink .bin   filled, outline, outline+detail
    drawing   <name>_poly.asm                corner points to fill at runtime
              <name>_spans.asm               one run per row, exact and fast

A 248x192 silhouette costs 5952 bytes as a bitmap. The same shape as polygon
corners is a few hundred, and as row spans it is exact and still far smaller,
at the price of a fill routine in the engine instead of a straight blit.

Crops are per card because the poses are not framed alike. They are fractions,
so they survive a re-scan at a different resolution.

Usage:
    python figure_lines.py                       # all four -> figures_zx/
    python figure_lines.py barbarian --zoom 3
    python figure_lines.py --height 120          # smaller, for a side panel
    python figure_lines.py --simplify 1.2        # coarser polygons, fewer points
    python figure_lines.py --sheet
"""

import argparse
import os
import sys

import cv2
import numpy as np
from PIL import Image, ImageFilter

CARD_DIR = os.path.join("original_cards", "cards")
OUT_DIR = "figures_zx"

# card file, and the part of it the figure occupies (left, top, right, bottom)
HEROES = {
    "barbarian": ("card0_07", (0.05, 0.18, 0.97, 0.685)),
    "dwarf":     ("card0_06", (0.05, 0.18, 0.97, 0.685)),
    "elf":       ("card0_03", (0.27, 0.155, 0.81, 0.70)),
    "wizard":    ("card0_01", (0.25, 0.150, 0.80, 0.70)),
}

SS = 2                    # cut the figure at this multiple of the target size


# --------------------------------------------------------------------------- #
# figure against ground
# --------------------------------------------------------------------------- #
def _u8(m):
    return m.astype(np.uint8) * 255


def largest_blob(m):
    """Keep the biggest connected run, drop specks of parchment."""
    count, label, stats, _ = cv2.connectedComponentsWithStats(_u8(m), 8)
    if count < 2:
        return m
    return label == 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))


def fill_holes(m):
    """Flood the outside in; whatever the flood cannot reach is figure."""
    h, w = m.shape
    flood = _u8(m).copy()
    cv2.floodFill(flood, np.zeros((h + 2, w + 2), np.uint8), (0, 0), 128)
    return flood != 128


def figure_mask(rgb, margin, iters):
    """GrabCut, seeded with a rectangle inset from the edge of the crop.

    The crop is already tight around the figure, so the inset band is reliably
    parchment and the middle is reliably paint. That is all GrabCut needs.
    """
    bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
    h, w = bgr.shape[:2]
    mx, my = max(1, int(w * margin)), max(1, int(h * margin))
    mask = np.zeros((h, w), np.uint8)
    cv2.grabCut(bgr, mask, (mx, my, w - 2 * mx, h - 2 * my),
                np.zeros((1, 65), np.float64), np.zeros((1, 65), np.float64),
                iters, cv2.GC_INIT_WITH_RECT)
    m = (mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD)
    k = np.ones((3, 3), np.uint8)
    m = cv2.morphologyEx(_u8(m), cv2.MORPH_CLOSE, k, iterations=2) > 127
    m = cv2.morphologyEx(_u8(m), cv2.MORPH_OPEN, k, iterations=2) > 127
    return fill_holes(largest_blob(m))


# --------------------------------------------------------------------------- #
# pictures
# --------------------------------------------------------------------------- #
def box_down(mask, size):
    w, h = size
    a = Image.fromarray(_u8(mask)).resize((w, h), Image.BOX)
    return np.asarray(a, dtype=np.float32) / 255.0


def outline_of(mask, size, thickness=1):
    inner = cv2.erode(_u8(mask), np.ones((3, 3), np.uint8),
                      iterations=max(1, SS * thickness)) > 127
    return box_down(mask & ~inner, size) >= 0.35


def interior_ink(rgb, mask, size, strength):
    """The strongest edges inside the figure: a face, a belt, a blade."""
    grey = Image.fromarray(rgb).convert("L")
    edges = np.asarray(grey.filter(ImageFilter.FIND_EDGES), dtype=np.float32)
    inner = cv2.erode(_u8(mask), np.ones((3, 3), np.uint8), iterations=SS + 1) > 127
    edges = np.where(inner, edges, 0.0)
    if not inner.any():
        return np.zeros(size[::-1], dtype=bool)
    cut = np.percentile(edges[inner], 100 - strength)
    return box_down(edges > max(cut, 8.0), size) >= 0.25


# --------------------------------------------------------------------------- #
# drawing data
# --------------------------------------------------------------------------- #
def polygons(bits, simplify):
    """Corner points of the silhouette, ready for a polygon fill."""
    found, _ = cv2.findContours(_u8(bits), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    total = max(1, int(bits.sum()))
    out = []
    for c in found:
        if cv2.contourArea(c) < 0.02 * total:      # ignore crumbs
            continue
        eps = simplify * cv2.arcLength(c, True) / 100.0
        out.append(cv2.approxPolyDP(c, eps, True).reshape(-1, 2))
    return out


def spans(bits):
    """One or more (x0, x1) runs per row. Exact, and trivial to draw."""
    rows = []
    for y in range(bits.shape[0]):
        xs = np.flatnonzero(bits[y])
        if xs.size == 0:
            rows.append([])
            continue
        cuts = np.flatnonzero(np.diff(xs) > 1)
        starts = np.concatenate(([xs[0]], xs[cuts + 1]))
        ends = np.concatenate((xs[cuts], [xs[-1]]))
        rows.append(list(zip(starts.tolist(), ends.tolist())))
    return rows


def raster_polygons(polys, shape):
    img = np.zeros(shape, np.uint8)
    if polys:
        cv2.fillPoly(img, [p.astype(np.int32) for p in polys], 255)
    return img > 127


def write_poly_asm(path, polys, label):
    n = sum(len(p) for p in polys)
    with open(path, "w") as fh:
        fh.write(f"; {label}: {len(polys)} outline(s), {n} points, "
                 f"{2 * n + 2 * len(polys) + 1} bytes\n")
        fh.write("; layout: count, then per outline: point count, then x,y pairs\n")
        fh.write(f"{label}:\n        defb {len(polys)}\n")
        for i, p in enumerate(polys):
            fh.write(f"        defb {len(p)}          ; outline {i}\n")
            for j in range(0, len(p), 8):
                chunk = ", ".join(f"{int(x)},{int(y)}" for x, y in p[j:j + 8])
                fh.write(f"        defb {chunk}\n")
    return 2 * n + len(polys) + 1


def write_spans_asm(path, rows, label):
    size = 1 + sum(1 + 2 * len(r) for r in rows)
    with open(path, "w") as fh:
        fh.write(f"; {label}: {len(rows)} rows, "
                 f"{sum(len(r) for r in rows)} runs, {size} bytes\n")
        fh.write("; layout: row count, then per row: run count, then x0,x1 pairs\n")
        fh.write(f"{label}:\n        defb {len(rows)}\n")
        for y, r in enumerate(rows):
            runs = "".join(f", {a},{b}" for a, b in r)
            fh.write(f"        defb {len(r)}{runs}\n")
    return size


# --------------------------------------------------------------------------- #
# output
# --------------------------------------------------------------------------- #
def pack(bits):
    """Rows of 1bpp bytes, MSB = leftmost pixel."""
    h, w = bits.shape
    if w % 8:
        bits = np.pad(bits, ((0, 0), (0, 8 - w % 8)))
    return np.packbits(bits, axis=1).tobytes()


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


def emit_bitmap(bits, out, label, args):
    data = pack(bits)
    open(out + ".bin", "wb").write(data)
    if args.asm:
        write_asm(out + ".asm", data, label, (bits.shape[1] + 7) // 8)
    preview(bits, args.zoom).save(out + ".png")
    return len(data)


def convert(name, args):
    card, frac = HEROES[name]
    src = Image.open(os.path.join(args.cards, card + ".png")).convert("RGB")
    w, h = src.size
    l, t, r, b = frac
    src = src.crop((int(l * w), int(t * h), int(r * w), int(b * h)))

    tw = max(8, int(round(args.height * src.width / src.height)) // 8 * 8)
    size = (tw, args.height)
    big = np.asarray(src.resize((tw * SS, args.height * SS), Image.LANCZOS))

    mask = figure_mask(big, args.margin, args.iters)
    solid = box_down(mask, size) >= 0.5
    line = outline_of(mask, size, args.thickness)
    ink = line | interior_ink(big, mask, size, args.detail)

    out = os.path.join(args.out, name)
    bmp = emit_bitmap(solid, out + "_solid", name + "_solid", args)
    emit_bitmap(line, out + "_line", name + "_line", args)
    emit_bitmap(ink, out + "_ink", name + "_ink", args)

    polys = polygons(solid, args.simplify)
    poly_bytes = write_poly_asm(out + "_poly.asm", polys, name + "_poly")
    span_bytes = write_spans_asm(out + "_spans.asm", spans(solid), name + "_spans")

    redrawn = raster_polygons(polys, solid.shape)
    agree = 100.0 * (redrawn == solid).mean()
    preview(redrawn, args.zoom).save(out + "_poly.png")

    print(f"{name:10s} {tw}x{args.height}  bitmap {bmp}B   "
          f"poly {poly_bytes}B ({sum(len(p) for p in polys)} pts, {agree:.1f}% match)   "
          f"spans {span_bytes}B (exact)")
    return [preview(b, args.zoom) for b in (solid, redrawn, line, ink)]


def write_sheet(rows, out_dir):
    if not rows:
        return
    pad = 8
    cw = max(im.width for row in rows for im in row) + pad
    ch = max(im.height for row in rows for im in row) + pad
    sheet = Image.new("L", (cw * len(rows) + pad, ch * len(rows[0]) + pad), 255)
    for c, row in enumerate(rows):
        for r, im in enumerate(row):
            sheet.paste(im, (pad + c * cw, pad + r * ch))
    path = os.path.join(out_dir, "_sheet.png")
    sheet.save(path)
    print(f"contact sheet: {path}")


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("heroes", nargs="*", help="which heroes (default: all four)")
    ap.add_argument("--height", type=int, default=192,
                    help="target height in pixels (192, a full screen)")
    ap.add_argument("--margin", type=float, default=0.04,
                    help="inset of the GrabCut seed rectangle (0.04)")
    ap.add_argument("--iters", type=int, default=6, help="GrabCut iterations (6)")
    ap.add_argument("--simplify", type=float, default=0.6,
                    help="polygon tolerance, percent of outline length (0.6)")
    ap.add_argument("--thickness", type=int, default=1, help="outline width (1)")
    ap.add_argument("--detail", type=float, default=10.0,
                    help="percent of the figure that becomes interior ink (10)")
    ap.add_argument("--cards", default=CARD_DIR, help=f"card directory ({CARD_DIR})")
    ap.add_argument("--out", default=OUT_DIR, help=f"output directory ({OUT_DIR})")
    ap.add_argument("--asm", action="store_true", help="also write bitmap DEFB source")
    ap.add_argument("--zoom", type=int, default=1, help="preview magnification")
    ap.add_argument("--sheet", action="store_true", help="write _sheet.png")
    args = ap.parse_args()

    names = args.heroes or list(HEROES)
    unknown = [n for n in names if n not in HEROES]
    if unknown:
        sys.exit(f"unknown hero(es): {', '.join(unknown)}\nknown: {', '.join(HEROES)}")

    os.makedirs(args.out, exist_ok=True)
    rows = [convert(n, args) for n in names]
    if args.sheet:
        write_sheet(rows, args.out)


if __name__ == "__main__":
    main()
