#!/usr/bin/env python3
"""Extract individual HeroQuest cards from flatbed scans.

Each scan (card0.png .. card3.png) holds several cards laid out sideways on the
glass, because the cards do not fit upright in the scanned area. This script
finds every card, deskews it, crops it out and stands it back up in portrait,
writing one PNG per card into ./cards/.

Cards were not all laid down facing the same way, so a card can come out upside
down. Those are fixed by name through cards/flips.json (see --flip); the file is
kept between runs, so a re-run reproduces the same result.

Usage:
    python extract_cards.py                     # card*.png -> cards/
    python extract_cards.py card2.png           # one scan only
    python extract_cards.py --sheet             # also write cards/_sheet.jpg
    python extract_cards.py --debug             # also write cards/_debug_*.jpg
    python extract_cards.py --flip card1_02 card1_03    # remember: turn these 180
    python extract_cards.py --unflip card1_02           # and undo that
"""

import argparse
import glob
import json
import os
import sys

import cv2
import numpy as np

OUT_DIR = "cards"
FLIP_FILE = os.path.join(OUT_DIR, "flips.json")

# A card is ~2.5" x 3.5" at 300 dpi. Sizes below are in pixels of the scan and
# are only used as a sanity filter plus as the grid pitch when cards touch.
CARD_SHORT = 740
CARD_LONG = 1050
MIN_CARD_AREA = 300_000
MIN_SIDE = 400
MAX_ASPECT = 2.0          # long/short of a single card sits around 1.4
TRIM = 6                  # px shaved off each side, kills the scanner halo
TRIM_SPLIT = 14           # extra px shaved where a card was cut from a neighbour
MAX_SKEW = 9.0            # how far off square a card is worth chasing, degrees
SKEW_TOL = 0.5            # below this it is not worth resampling the card


# --------------------------------------------------------------------------- #
# detection
# --------------------------------------------------------------------------- #
def card_mask(bgr):
    """White scanner background -> 0, card -> 255."""
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    sat, val = hsv[:, :, 1], hsv[:, :, 2]
    # A card is either coloured (saturated) or darker than the paper white.
    mask = ((sat > 45) | (val < 205)).astype(np.uint8) * 255
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((25, 25), np.uint8))
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((15, 15), np.uint8))
    # Fill interior holes so pale artwork does not break a card into pieces.
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    filled = np.zeros_like(mask)
    cv2.drawContours(filled, contours, -1, 255, cv2.FILLED)
    return filled


def find_blobs(mask):
    """minAreaRect of every blob big enough to be a card (or a clump of them)."""
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    rects = []
    for c in contours:
        if cv2.contourArea(c) < MIN_CARD_AREA:
            continue
        (cx, cy), (w, h), angle = cv2.minAreaRect(c)
        if min(w, h) < MIN_SIDE:
            continue
        # Keep the rectangle upright-ish so the grid maths below is predictable.
        if angle > 45:
            w, h, angle = h, w, angle - 90
        rects.append(((cx, cy), (w, h), angle))
    return rects


def grid_of(w, h):
    """How many cards sit in a w x h blob, as (cols, rows). (1, 1) if it is one card."""
    best, best_err = (1, 1), None
    for cw, ch in ((CARD_SHORT, CARD_LONG), (CARD_LONG, CARD_SHORT)):
        nx, ny = max(1, round(w / cw)), max(1, round(h / ch))
        # Overlapping cards make the clump smaller than nx*cw, hence the slack.
        err = abs(w - nx * cw) / cw + abs(h - ny * ch) / ch
        if err < 0.6 * (nx + ny) and (best_err is None or err < best_err):
            best, best_err = (nx, ny), err
    return best


def is_card_shaped(w, h):
    short, long_ = min(w, h), max(w, h)
    return short >= MIN_SIDE and long_ / short <= MAX_ASPECT


# --------------------------------------------------------------------------- #
# cropping
# --------------------------------------------------------------------------- #
def crop_rect(bgr, rect):
    """Rotate the scan so the blob is axis aligned, then cut it out."""
    (cx, cy), (w, h), angle = rect
    m = cv2.getRotationMatrix2D((cx, cy), angle, 1.0)
    rotated = cv2.warpAffine(
        bgr, m, (bgr.shape[1], bgr.shape[0]),
        flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE,
    )
    return cv2.getRectSubPix(rotated, (int(round(w)), int(round(h))), (cx, cy))


def residual_skew(card, limit=MAX_SKEW, step=0.25):
    """How far this one card is still off square, in degrees.

    crop_rect can only use one angle per blob, so a card that was touching a
    neighbour lying at a different angle comes out of the clump still tilted.
    The dark frame around the art gives long straight runs, so the angle that
    makes the gradient profiles spikiest is the angle that squares the card up.
    """
    gray = cv2.cvtColor(card, cv2.COLOR_BGR2GRAY)
    scale = 320 / max(gray.shape)
    gray = cv2.resize(gray, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)
    gx = np.abs(cv2.Sobel(gray, cv2.CV_32F, 1, 0, ksize=3))
    gy = np.abs(cv2.Sobel(gray, cv2.CV_32F, 0, 1, ksize=3))
    h, w = gray.shape
    centre = (w / 2, h / 2)
    best, best_score = 0.0, None
    for angle in np.arange(-limit, limit + 1e-9, step):
        m = cv2.getRotationMatrix2D(centre, angle, 1.0)
        cols = cv2.warpAffine(gx, m, (w, h)).sum(axis=0).var()
        rows = cv2.warpAffine(gy, m, (w, h)).sum(axis=1).var()
        if best_score is None or cols + rows > best_score:
            best, best_score = float(angle), cols + rows
    return best


def square_up(card):
    """Straighten a card that came out of its blob still tilted."""
    angle = residual_skew(card)
    if abs(angle) < SKEW_TOL:
        return card
    h, w = card.shape[:2]
    m = cv2.getRotationMatrix2D((w / 2, h / 2), angle, 1.0)
    rotated = cv2.warpAffine(card, m, (w, h), flags=cv2.INTER_CUBIC,
                             borderMode=cv2.BORDER_CONSTANT,
                             borderValue=(255, 255, 255))
    # The turn swings the corners out of frame and leaves white wedges behind;
    # cut back to the card itself.
    contours, _ = cv2.findContours(card_mask(rotated), cv2.RETR_EXTERNAL,
                                   cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return rotated
    x, y, bw, bh = cv2.boundingRect(max(contours, key=cv2.contourArea))
    return rotated[y:y + bh, x:x + bw]


def seam_positions(img, count, axis):
    """Where to cut a clump into `count` pieces along `axis` (1 = vertical cuts).

    Starts from an even split and slides each cut onto the nearest strong edge,
    which is the rim (or its shadow) of the card lying on top.
    """
    span = img.shape[1] if axis == 1 else img.shape[0]
    step = span / count
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    grad = np.abs(cv2.Sobel(gray, cv2.CV_32F, 1 if axis == 1 else 0,
                            0 if axis == 1 else 1, ksize=3))
    energy = grad.sum(axis=0 if axis == 1 else 1)
    window = max(8, int(0.05 * step))
    cuts = []
    for i in range(1, count):
        nominal = int(round(i * step))
        lo, hi = max(1, nominal - window), min(span - 1, nominal + window)
        cuts.append(lo + int(np.argmax(energy[lo:hi])) if hi > lo else nominal)
    return cuts


def split_clump(img, cols, rows):
    """Cut a clump of touching cards into single cards, top-to-bottom then l-to-r."""
    xs = [0] + seam_positions(img, cols, axis=1) + [img.shape[1]]
    ys = [0] + seam_positions(img, rows, axis=0) + [img.shape[0]]
    out = []
    for r in range(rows):
        for c in range(cols):
            x0, x1, y0, y1 = xs[c], xs[c + 1], ys[r], ys[r + 1]
            # Pull back from cuts that ran through a neighbouring card.
            x0 += TRIM_SPLIT if c else 0
            x1 -= TRIM_SPLIT if c < cols - 1 else 0
            y0 += TRIM_SPLIT if r else 0
            y1 -= TRIM_SPLIT if r < rows - 1 else 0
            cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
            out.append((img[y0:y1, x0:x1], cx, cy))
    return out


def trim(card):
    if min(card.shape[:2]) > 4 * TRIM:
        card = card[TRIM:-TRIM, TRIM:-TRIM]
    return card


def to_portrait(card, upside_down):
    """Cards lie on their side on the glass; stand them back up."""
    if card.shape[1] > card.shape[0]:
        # Most titles read bottom-to-top on the scan, so a clockwise quarter
        # turn puts them upright; the rest are corrected by the flip list.
        card = cv2.rotate(card, cv2.ROTATE_90_CLOCKWISE)
    if upside_down:
        card = cv2.rotate(card, cv2.ROTATE_180)
    return card


# --------------------------------------------------------------------------- #
# per scan
# --------------------------------------------------------------------------- #
def process(path, flips, debug=False):
    stem = os.path.splitext(os.path.basename(path))[0]
    bgr = cv2.imread(path, cv2.IMREAD_COLOR)
    if bgr is None:
        print(f"!! cannot read {path}")
        return []

    found = []            # (image, centre x, centre y) in scan coordinates
    clumps = 0
    for rect in find_blobs(card_mask(bgr)):
        (cx, cy), (w, h), _ = rect
        cols, rows = grid_of(w, h)
        piece = crop_rect(bgr, rect)
        if cols * rows == 1:
            if not is_card_shaped(w, h):
                continue
            found.append((trim(square_up(piece)), cx, cy))
            continue
        clumps += 1
        ox, oy = cx - w / 2, cy - h / 2
        for sub, sx, sy in split_clump(piece, cols, rows):
            found.append((trim(square_up(sub)), ox + sx, oy + sy))

    # Reading order: rows top to bottom, left to right inside a row. Centres are
    # snapped to a coarse grid so a slightly tilted row keeps its order.
    found.sort(key=lambda f: (round(f[2] / 500), f[1]))

    written = []
    for i, (card, _, _) in enumerate(found, start=1):
        name = f"{stem}_{i:02d}"
        out = os.path.join(OUT_DIR, name + ".png")
        cv2.imwrite(out, to_portrait(card, flips.get(name, False)))
        written.append(out)

    if debug:
        write_debug(bgr, stem)
    note = f"  ({clumps} clump(s) split - cards were touching)" if clumps else ""
    print(f"{path}: {len(written)} cards{note}")
    return written


def write_debug(bgr, stem):
    mask = card_mask(bgr)
    vis = bgr.copy()
    vis[mask == 0] = (255, 255, 255)
    for rect in find_blobs(mask):
        box = np.int32(cv2.boxPoints(rect))
        cv2.drawContours(vis, [box], 0, (0, 0, 255), 8)
    scale = 900 / vis.shape[0]
    vis = cv2.resize(vis, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)
    cv2.imwrite(os.path.join(OUT_DIR, f"_debug_{stem}.jpg"), vis,
                [cv2.IMWRITE_JPEG_QUALITY, 85])


def write_sheet(paths, per_row=7):
    """Contact sheet of everything written, for checking orientation at a glance."""
    thumbs = []
    for p in paths:
        im = cv2.resize(cv2.imread(p), (180, 255))
        label = os.path.splitext(os.path.basename(p))[0]
        cv2.putText(im, label, (4, 20), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 255), 2)
        thumbs.append(im)
    rows = []
    for i in range(0, len(thumbs), per_row):
        row = thumbs[i:i + per_row]
        row += [np.full_like(thumbs[0], 255)] * (per_row - len(row))
        rows.append(np.hstack(row))
    sheet = os.path.join(OUT_DIR, "_sheet.jpg")
    cv2.imwrite(sheet, np.vstack(rows), [cv2.IMWRITE_JPEG_QUALITY, 85])
    print(f"contact sheet: {sheet}")


# --------------------------------------------------------------------------- #
def load_flips():
    if os.path.exists(FLIP_FILE):
        with open(FLIP_FILE) as fh:
            return json.load(fh)
    return {}


def save_flips(flips):
    with open(FLIP_FILE, "w") as fh:
        json.dump(flips, fh, indent=2, sort_keys=True)


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("scans", nargs="*", help="scan files (default: card*.png)")
    ap.add_argument("--flip", nargs="+", metavar="NAME", default=[],
                    help="card names (e.g. card1_02) to turn 180 degrees")
    ap.add_argument("--unflip", nargs="+", metavar="NAME", default=[],
                    help="card names to stop turning")
    ap.add_argument("--sheet", action="store_true", help="write cards/_sheet.jpg")
    ap.add_argument("--debug", action="store_true", help="write detection overlays")
    args = ap.parse_args()

    scans = args.scans or sorted(glob.glob("card*.png"))
    if not scans:
        print("no scans found (expected card*.png in the current directory)")
        return 1

    os.makedirs(OUT_DIR, exist_ok=True)
    flips = load_flips()
    for name in args.flip:
        flips[name] = True
    for name in args.unflip:
        flips.pop(name, None)
    if args.flip or args.unflip:
        save_flips(flips)

    written = []
    for path in scans:
        written += process(path, flips, args.debug)
    print(f"total: {len(written)} cards -> {OUT_DIR}/")
    if args.sheet and written:
        write_sheet(written)
    return 0


if __name__ == "__main__":
    sys.exit(main())
