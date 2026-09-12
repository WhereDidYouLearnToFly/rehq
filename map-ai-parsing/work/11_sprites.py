"""Step 11 - cut the printed symbols off the maps, one image per symbol.

The parse says a goblin stands on square (3,1). This step is what makes that
look like a goblin: it cuts the actual printed icons out of the canonical
rasters and writes them as transparent PNGs the .hip puts back on the board,
so the scene shows the quest as drawn rather than as coloured rectangles.

One image per SYMBOL, not per placement - ten quests draw the same goblin
seventy times and the scene wants one goblin. Which instance to cut is the
whole question, and it is a different answer per kind:

  monsters   A type is not one drawing. Step 5 lands ~88 clusters on ~10
             types, so an "orc" is nine or so poses, and a median across all
             of them is mush. The sharp answer is the median of the type's
             LARGEST cluster - the pose it is drawn in most often - so this
             step reuses step 5's clustering rather than re-deriving one.
  marks      A, B .. F and X are one fixed glyph each, so the median across
             every placement is both sharp and the most representative.
  doors      One graphic, two orientations, straddling a wall - so the crop
             is centred on the wall and not on a square.
  furniture  No two pieces alike and no clustering to lean on. A kind is cut
             from one real instance: the modal footprint for that kind, and
             within that the drawing with the most ink on it, which is the
             one least likely to be clipped or overlapped.
  arrows     The escape arrows, by orientation. Only N, S and W are printed.

Alpha starts from the reason step 2's plate exists: the plate is the board
with every quest's overlay voted away, so "what this quest added to this
square" is the pixels that differ from it. Two things have to be done to that
difference before it is a usable cutout:

  - Board ink has to come off it. The warp is good to a pixel, not to
    nothing, so every printed grid line leaves a hairline of difference along
    its edge. Step 8 already answers this - subtract the plate's own dilated
    ink - and the same subtraction is used here, for every kind but the
    doors, which are drawn ON a wall and would be subtracted away with it.

  - Holes have to be filled, for the kinds that are solid. A monster icon is
    a disc, and the pale crown of a goblin's head is almost exactly the
    colour of the beige floor, so a pure difference punches a hole straight
    through the top of its skull. Flood-filling from outside the silhouette
    puts it back.

Furniture and the escape arrows skip the cutout entirely and stay opaque,
background and all. Cutting out is right for a thing with a silhouette - a
monster disc, a bold letter, a door - but a table is a dozen thin strokes,
and reduced to just those it reads as scratches floating on whatever colour
the room happens to be. It was drawn on a patch of printed floor and it looks
like the map when it keeps it.

Placements that sit on an orange or deep-red special square are skipped: the
fill changes the whole background, so the difference from the plate is the
whole square rather than the symbol on it.

Specials are not cut. An orange or deep-red square is a flat fill, not a
symbol - there is no art to lift, and the .hip already draws it as a colour.

    in:  ds/cNN.png, ds/plate.png, work/ctypes.json,
         ../assets/quests/quests_data.json
    out: ../assets/quests/sprites/<kind>/<name>.png   the symbols, RGBA
         ../assets/quests/sprites/index.json          what the .hip reads
         work/sprites.png                             contact sheet - LOOK AT
                                                      THIS, it is the check
"""
import importlib.util
import json
import os
from collections import Counter

import cv2
import numpy as np

CS, W, H = 80, 26, 19
OUT = "../assets/quests/sprites"
DATA = json.load(open("../assets/quests/quests_data.json"))["quests"]

# Alpha ramp on the distance from the plate. Below LO is the board showing
# through unchanged; above HI is solidly the symbol. The gap is what keeps a
# pencil edge from turning into a staircase.
A_LO, A_HI = 26.0, 68.0

# Slack cut around a solid symbol so its silhouette can be closed - see
# median_stack. Trimmed off again before the sprite is written.
PAD = 12

PLATE = cv2.imread("ds/plate.png")
MAPS = {"%02d" % i: cv2.imread("ds/c%02d.png" % i) for i in range(1, 11)}


def ink(im):
    """The printed reddish-brown line, the same test step 8 uses."""
    b, g, r = [im[:, :, i].astype(int) for i in range(3)]
    return (((r - g) > 28) & (g < 155)).astype(np.uint8)


# The board's own ink, dilated to cover the hairline the warp leaves along
# every grid line. Anything here is print that was already on the board.
PLATE_INK = cv2.dilate(ink(PLATE), np.ones((5, 5), np.uint8))

# Squares with an orange or deep-red fill on them - not usable as a source
# for any symbol, because the fill is the difference, not the symbol.
SPECIAL = {q: {(x, y) for x, y, _ in DATA[q]["special"]} for q in DATA}


def _step5():
    """Import work/05_monsters.py, whose name is not an identifier."""
    spec = importlib.util.spec_from_file_location("step5", "work/05_monsters.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def window(img, px, py, pw, ph):
    """img[py:py+ph, px:px+pw], with the edge repeated where it runs off.

    A symbol on the top or left row of the board - quest 10's unknown icon is
    one - has no room for the padding median_stack wants. Repeating the edge
    costs nothing there, because the padding is trimmed off again anyway.
    """
    ih, iw = img.shape[:2]
    x0, y0, x1, y1 = max(px, 0), max(py, 0), min(px + pw, iw), min(py + ph, ih)
    sub = img[y0:y1, x0:x1]
    t, l, b, r = y0 - py, x0 - px, (py + ph) - y1, (px + pw) - x1
    if t or l or b or r:
        sub = cv2.copyMakeBorder(sub, t, b, l, r, cv2.BORDER_REPLICATE)
    return sub


def cut(q, px, py, pw, ph, drop_board=True):
    """RGBA of one pixel box: the map's colour, and alpha off the plate.

    drop_board is off only for the doors, which are printed on a wall - the
    board ink under a door is the thing the door replaced, and taking it out
    takes the door with it.
    """
    im = window(MAPS[q], px, py, pw, ph).astype(np.float32)
    pl = window(PLATE, px, py, pw, ph).astype(np.float32)
    d = np.abs(im - pl).max(axis=2)
    a = np.clip((d - A_LO) / (A_HI - A_LO), 0, 1)
    if drop_board:
        a = a * (1 - window(PLATE_INK, px, py, pw, ph))
    return im, a


def fill_holes(m):
    """m, with every run of 0 that the outside cannot reach turned to 1.

    Padding first is what makes it safe: flooding from a corner of the real
    image would do nothing at all if the symbol happened to touch it.
    """
    p = cv2.copyMakeBorder(m, 1, 1, 1, 1, cv2.BORDER_CONSTANT, value=0)
    outside = (1 - p).astype(np.uint8)
    cv2.floodFill(outside, np.zeros((outside.shape[0] + 2,
                                     outside.shape[1] + 2), np.uint8), (0, 0), 0)
    return (p | outside)[1:-1, 1:-1]


def finish(rgb, a, solid=False, opaque=False):
    """Clean the alpha up and pack to an 8-bit RGBA image.

    The close fills the speckle inside a hatched drawing - line art is mostly
    holes, and every one of them would otherwise be a see-through pixel.
    solid goes further and fills the enclosed ones too, for the kinds that
    are a filled shape rather than an outline.

    opaque skips all of it and keeps the printed background. A monster is a
    disc and a letter is a glyph, and both want cutting out; a table is a
    dozen thin strokes, and cutting those out leaves lines floating on
    whatever colour the room happens to be. The piece was drawn on a patch of
    floor, and it reads as the map when it keeps the patch.
    """
    if opaque:
        return np.dstack([rgb, np.full(a.shape, 255.0)]).astype(np.uint8)
    m = (a > 0.35).astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8))
    if solid:
        m = cv2.morphologyEx(fill_holes(m), cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
    a = np.maximum(a, m.astype(np.float32) * 0.92)
    a = cv2.GaussianBlur(a, (3, 3), 0)
    return np.dstack([rgb, a * 255]).astype(np.uint8)


def usable(boxes):
    """Drop placements sitting on a special fill, unless that leaves none."""
    clean = [b for b in boxes if not (SPECIAL[b[0]] & b[5])]
    return clean or boxes


def median_stack(boxes, solid=False, drop_board=True, pad=0, opaque=False):
    """Median RGB and median alpha over several placements of one symbol.

    pad cuts a wider box and trims it off at the end, and the solid kinds
    need it. A monster disc very nearly fills its square, so it overlaps the
    printed grid line at the bottom of it - which drop_board then rubs out,
    leaving a gap in the silhouette exactly at the edge of the crop. Filling
    holes through that gap floods the whole disc. There is nothing to close
    the gap against inside an 80x80 crop; a few pixels of the next square is
    all it takes, and the median has already voted away whatever was drawn
    there.
    """
    rgbs, alphas = [], []
    for q, px, py, pw, ph, _ in boxes:
        rgb, a = cut(q, px - pad, py - pad, pw + 2 * pad, ph + 2 * pad, drop_board)
        rgbs.append(rgb); alphas.append(a)
    if not rgbs:
        return None
    img = finish(np.median(np.stack(rgbs), axis=0),
                 np.median(np.stack(alphas), axis=0), solid, opaque)
    return img[pad:pad + ph, pad:pad + pw] if pad else img


def monsters(index, sheet):
    """One sprite per monster type, off the largest cluster of that type.

    Off the clustering rather than off the data, because the data records
    where a monster stands and this wants every drawing of it. A type the
    data no longer carries is skipped: a fix in manual.json can delete the
    last of a type - quest 10's phantom `unknown` at (4,0) is exactly that -
    and cutting a sprite nothing references would leave the index lying.
    """
    keys, crops, lab, _ = _step5().cluster_icons()
    c2t = {c: t for t, ids in json.load(open("work/ctypes.json")).items() for c in ids}
    in_play = {m[2] for d in DATA.values() for m in d["monsters"]}

    by_type = {}
    for (q, x, y), c in zip(keys, lab):
        by_type.setdefault(c2t.get(int(c), "unknown"), {}).setdefault(int(c), []).append((q, x, y))

    for t in sorted(by_type):
        if t not in in_play:
            print("  %-10s %-16s no quest carries one any more - not cut" % ("monster", t))
            continue
        best = max(by_type[t].values(), key=len)        # the commonest pose
        boxes = usable([(q, x * CS, y * CS, CS, CS, {(x, y)}) for q, x, y in best])
        write(index, sheet, "monster", t, median_stack(boxes, solid=True, pad=PAD), 1, 1,
              "%d of %d icons" % (len(best), sum(len(v) for v in by_type[t].values())))


def marks(index, sheet):
    """One sprite per note letter, median of every placement of it."""
    at = {}
    for q in sorted(DATA):
        for x, y, L in DATA[q]["marks"]:
            at.setdefault(L, []).append((q, x * CS, y * CS, CS, CS, {(x, y)}))
    for L in sorted(at):
        boxes = usable(at[L])
        write(index, sheet, "mark", L, median_stack(boxes), 1, 1,
              "%d of %d placements" % (len(boxes), len(at[L])))


def doors(index, sheet):
    """One sprite per orientation. A door straddles a wall, so the crop is
    centred on the wall it is in and half of it lies in the next square."""
    at = {}
    for q in sorted(DATA):
        for x, y, o in DATA[q]["doors"]:
            if o == "W":
                box = (q, x * CS - CS // 2, y * CS, CS, CS, {(x, y), (x - 1, y)})
            else:
                box = (q, x * CS, y * CS - CS // 2, CS, CS, {(x, y), (x, y - 1)})
            if box[1] >= 0 and box[2] >= 0:
                at.setdefault(o, []).append(box)
    for o in sorted(at):
        boxes = usable(at[o])
        write(index, sheet, "door", o,
              median_stack(boxes, solid=True, drop_board=False, pad=PAD), 1, 1,
              "%d of %d placements" % (len(boxes), len(at[o])))


def arrows(index, sheet):
    at = {}
    for q in sorted(DATA):
        for x, y, o in DATA[q]["arrows"]:
            at.setdefault(o, []).append((q, x * CS, y * CS, CS, CS, {(x, y)}))
    for o in sorted(at):
        boxes = usable(at[o])
        write(index, sheet, "arrow", o, median_stack(boxes, opaque=True), 1, 1,
              "%d of %d placements" % (len(boxes), len(at[o])))


def furniture(index, sheet):
    """One sprite per kind, cut from a single real instance.

    There is nothing to average here - two tombs are two drawings - so the
    job is picking which one. Modal footprint first, so the sprite has the
    aspect ratio the kind usually has; then most ink, which is the instance
    least likely to be half under a monster or clipped by the shading.
    """
    at = {}
    for q in sorted(DATA):
        for x0, y0, x1, y1, kind in DATA[q]["furniture"]:
            cells = {(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)}
            at.setdefault(kind, []).append(
                (q, x0 * CS, y0 * CS, (x1 - x0 + 1) * CS, (y1 - y0 + 1) * CS, cells))

    for kind in sorted(at):
        # Shape first, off every instance, and only then prefer the clean
        # ones. Filtering first loses it: a stairway is drawn on a deep-red
        # square in most quests, so the clean instances are the odd-sized
        # ones and the kind would take its shape from an outlier.
        shapes = Counter((pw, ph) for _, _, _, pw, ph, _ in at[kind])
        pw, ph = shapes.most_common(1)[0][0]
        w, h = pw // CS, ph // CS
        boxes = usable([b for b in at[kind] if (b[3], b[4]) == (pw, ph)])
        best, best_ink = None, -1
        for q, px, py, cw, ch, _ in boxes:
            rgb, a = cut(q, px, py, pw, ph)
            if rgb.shape[:2] != (ph, pw):
                continue
            if a.sum() > best_ink:
                best, best_ink = (rgb, a), a.sum()
        if best is None:
            print("  no clean instance for furniture %r" % kind)
            continue
        write(index, sheet, "furniture", kind, finish(*best, opaque=True), w, h,
              "%dx%d, %d of %d that shape"
              % (w, h, shapes[(pw, ph)], len(at[kind])))


def write(index, sheet, kind, name, img, w, h, note):
    if img is None:
        print("  nothing to cut for %s/%s" % (kind, name))
        return
    d = os.path.join(OUT, kind)
    os.makedirs(d, exist_ok=True)
    rel = "%s/%s.png" % (kind, name)
    cv2.imwrite(os.path.join(OUT, rel), img)
    index.setdefault(kind, {})[name] = dict(file=rel, w=w, h=h)
    sheet.append((kind, name, img, note))
    print("  %-10s %-16s %-28s %s" % (kind, name, note, rel))


def contact(sheet):
    """One sheet of everything cut, on a checker so the alpha is visible."""
    tiles = []
    for kind, name, img, _ in sheet:
        sc = min(150.0 / img.shape[1], 150.0 / img.shape[0])
        im = cv2.resize(img, None, fx=sc, fy=sc, interpolation=cv2.INTER_AREA)
        canvas = np.zeros((180, 165, 3), np.uint8)
        yy, xx = np.mgrid[0:180, 0:165]
        canvas[:] = np.where((((yy // 8) + (xx // 8)) % 2)[..., None], 210, 165)
        y0, x0 = (155 - im.shape[0]) // 2, (165 - im.shape[1]) // 2
        a = im[:, :, 3:4].astype(np.float32) / 255.0
        roi = canvas[y0:y0 + im.shape[0], x0:x0 + im.shape[1]]
        canvas[y0:y0 + im.shape[0], x0:x0 + im.shape[1]] = (
            im[:, :, :3] * a + roi * (1 - a)).astype(np.uint8)
        cv2.putText(canvas, "%s/%s" % (kind[:4], name), (3, 174),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.4, (0, 0, 160), 1)
        tiles.append(canvas)
    while len(tiles) % 8:
        tiles.append(np.full((180, 165, 3), 255, np.uint8))
    cv2.imwrite("work/sprites.png",
                np.vstack([np.hstack(tiles[r:r + 8]) for r in range(0, len(tiles), 8)]))


if __name__ == "__main__":
    index, sheet = {}, []
    for fn in (monsters, marks, doors, arrows, furniture):
        print("%s:" % fn.__name__)
        fn(index, sheet)
    os.makedirs(OUT, exist_ok=True)
    json.dump(dict(_note="cut by map-ai-parsing/work/11_sprites.py from the "
                         "canonical rasters; w/h are the sprite's footprint "
                         "in board squares", sprites=index),
              open(os.path.join(OUT, "index.json"), "w"), indent=1, sort_keys=True)
    contact(sheet)
    print("\n%d symbols -> %s, contact sheet -> work/sprites.png"
          % (len(sheet), OUT))
