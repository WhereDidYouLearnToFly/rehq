#!/usr/bin/env python3
"""Cut the illustration out of a card and size it to whole character cells.

Every item and spell card frames its picture in a thick dark box. That box is
found here rather than assumed, because the title above it runs to one or two
lines and pushes the frame up and down between cards. What comes out is the
inside of the frame, resized to an exact multiple of 8 in both directions so it
lands on the Spectrum character grid with nothing left over.

Character and monster cards have no frame -- their art bleeds to the edge -- so
they are reported as skipped rather than guessed at.

The output is a PNG at the final pixel size, ready for cards_to_zx.py, which
will then convert it 1:1 with no further resampling:

    python card_art.py                       # -> art/
    python cards_to_zx.py art/*.png --out art_zx --asm

Usage:
    python card_art.py                       # every card in original_cards/cards
    python card_art.py --size 128x96         # a different cell size
    python card_art.py --inset 3             # shave more of the black frame
    python card_art.py --sheet               # contact sheet of what was found
"""

import argparse
import glob
import os
import sys

import cv2
import numpy as np

IN_DIR = os.path.join("original_cards", "cards")
OUT_DIR = "art"

# The frame is very dark against parchment; these bound where it can sit and
# how big it can be, as fractions of the card.
DARK = 110
MIN_WIDTH = 0.45          # a real panel spans most of the card
MAX_BOTTOM = 0.70         # and lives in the upper part of it
EDGE = 0.03               # ignore anything touching the card's own border


def find_panel(bgr):
    """Bounding box of the illustration frame, or None if the card has none."""
    h, w = bgr.shape[:2]
    grey = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    dark = (grey < DARK).astype(np.uint8) * 255
    dark = cv2.morphologyEx(dark, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    contours, _ = cv2.findContours(dark, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)

    best = None
    for c in contours:
        x, y, cw, ch = cv2.boundingRect(c)
        if cw < MIN_WIDTH * w or ch < 0.15 * h:
            continue
        if x < EDGE * w or y < EDGE * h or x + cw > (1 - EDGE) * w:
            continue                       # that is the card's own dark border
        if (y + ch) > MAX_BOTTOM * h:
            continue                       # that is the body text block
        area = cw * ch
        if best is None or area > best[0]:
            best = (area, (x, y, cw, ch))
    return best[1] if best else None


def cut(bgr, box, inset, size, square=False):
    """Inside of the frame, resized to exactly the target.

    The panels are all 4:3, so --square is a real crop, not a rescale: it keeps
    the full height and takes the middle of the width, where the subject is.
    """
    x, y, w, h = box
    x, y = x + inset, y + inset
    w, h = max(1, w - 2 * inset), max(1, h - 2 * inset)
    if square and w > h:
        x, w = x + (w - h) // 2, h
    art = bgr[y:y + h, x:x + w]
    return cv2.resize(art, size, interpolation=cv2.INTER_AREA)


def on_canvas(art, canvas, top):
    """Drop the art on a bigger tile, sitting near the top rather than centred.

    Leaves the space underneath free for a name or a price, and makes a row of
    items line up on their heads instead of on their middles.
    """
    cw, ch = canvas
    h, w = art.shape[:2]
    tile = np.full((ch, cw, 3), 255, np.uint8)
    x = max(0, (cw - w) // 2)
    y = max(0, min(top, ch - h))
    tile[y:y + h, x:x + w] = art[:min(h, ch - y), :min(w, cw - x)]
    return tile


def parse_size(text):
    w, _, h = text.lower().partition("x")
    w, h = int(w), int(h)
    if w % 8 or h % 8:
        raise argparse.ArgumentTypeError("--size wants both sides divisible by 8")
    return w, h


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cards", nargs="*", help=f"card PNGs (default: {IN_DIR}/card*.png)")
    ap.add_argument("--size", type=parse_size, default=(128, 96),
                    help="output size, both sides divisible by 8 (128x96)")
    ap.add_argument("--inset", type=int, default=8,
                    help="px shaved inside the frame, drops the black rule (8)")
    ap.add_argument("--in-dir", default=IN_DIR, help=f"card directory ({IN_DIR})")
    ap.add_argument("--out", default=OUT_DIR, help=f"output directory ({OUT_DIR})")
    ap.add_argument("--canvas", type=parse_size, metavar="WxH",
                    help="pad onto a tile this big, art near its top")
    ap.add_argument("--top", type=int, default=4,
                    help="gap above the art on the canvas (4)")
    ap.add_argument("--square", action="store_true",
                    help="centre crop the 4:3 panel to a square first")
    ap.add_argument("--sheet", action="store_true", help="write art/_sheet.jpg")
    args = ap.parse_args()

    cards = args.cards or sorted(glob.glob(os.path.join(args.in_dir, "card*.png")))
    if not cards:
        sys.exit(f"no cards found in {args.in_dir}/")
    os.makedirs(args.out, exist_ok=True)

    done, skipped = [], []
    for path in cards:
        name = os.path.splitext(os.path.basename(path))[0]
        bgr = cv2.imread(path, cv2.IMREAD_COLOR)
        if bgr is None:
            skipped.append((name, "unreadable"))
            continue
        box = find_panel(bgr)
        if box is None:
            skipped.append((name, "no framed panel"))
            continue
        art = cut(bgr, box, args.inset, args.size, args.square)
        if args.canvas:
            art = on_canvas(art, args.canvas, args.top)
        out = os.path.join(args.out, name + ".png")
        cv2.imwrite(out, art)
        done.append((name, art))

    w, h = args.canvas or args.size
    print(f"{len(done)} illustrations at {w}x{h} ({w // 8}x{h // 8} cells) -> {args.out}/")
    if skipped:
        print(f"{len(skipped)} skipped: " + ", ".join(n for n, _ in skipped))

    if args.sheet and done:
        per_row = 8
        rows = (len(done) + per_row - 1) // per_row
        sheet = np.full(((h + 6) * rows + 6, (w + 6) * per_row + 6, 3), 255, np.uint8)
        for i, (_, art) in enumerate(done):
            r, c = divmod(i, per_row)
            y, x = 6 + r * (h + 6), 6 + c * (w + 6)
            sheet[y:y + h, x:x + w] = art
        path = os.path.join(args.out, "_sheet.jpg")
        cv2.imwrite(path, sheet, [cv2.IMWRITE_JPEG_QUALITY, 90])
        print(f"contact sheet: {path}")


if __name__ == "__main__":
    main()
