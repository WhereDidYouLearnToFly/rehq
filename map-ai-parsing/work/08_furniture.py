"""Step 8 - cut the furniture out of the maps for reading by eye.

There is no way around looking at these: a table, a tomb, an altar and a forge
are all just line art, and there is no fixed template to match. What this step
does is find them and crop them, so the reading is a few contact sheets instead
of a hunt across ten scans.

Isolating them: take the quest's ink, subtract the board plate's ink (step 2),
drop the squares that are out of play, drop the squares holding a monster, drop
the door footprints. What is left is furniture, note letters and the odd bit of
board decoration, which connected components turn into croppable boxes.

The reading itself lands in assets/quests/manual.json, by hand, as
[x0, y0, x1, y1, kind] - the ink footprint of each piece.

    in:  ds/cNN.png, ds/plate.png, work/grids.json, work/monsters.json, work/doors.json
    out: work/fmNN.png       contact sheet per quest, each crop labelled x0,y0-x1,y1
         work/furn_raw.json  the component boxes behind those sheets
"""
import json

import cv2
import numpy as np

CS, W, H = 80, 26, 19
MIN_AREA = 1200

grids = json.load(open("work/grids.json"))
monsters = json.load(open("work/monsters.json"))
doors = json.load(open("work/doors.json"))


def ink(im):
    b, g, r = [im[:, :, i].astype(int) for i in range(3)]
    return (((r - g) > 28) & (g < 155)).astype(np.uint8)


PLATE = cv2.dilate(ink(cv2.imread("ds/plate.png")), np.ones((5, 5), np.uint8))


def comps(q):
    im = cv2.imread("ds/c%s.png" % q)
    keep = (ink(im) & (1 - PLATE)).astype(np.uint8)
    mon = {(m[0], m[1]) for m in monsters[q]}
    for y in range(H):
        for x in range(W):
            if (x, y) in mon or grids[q][y][x] == ".":
                keep[y * CS:(y + 1) * CS, x * CS:(x + 1) * CS] = 0
    for x, y, o, s in doors[q]:
        if o == "W":
            keep[y * CS:(y + 1) * CS, max(x * CS - 32, 0):x * CS + 32] = 0
        else:
            keep[max(y * CS - 32, 0):y * CS + 32, x * CS:(x + 1) * CS] = 0
    k = cv2.dilate(keep, np.ones((13, 13), np.uint8))
    n, lab, stats, _ = cv2.connectedComponentsWithStats(k, 8)
    out = []
    for i in range(1, n):
        x, y, w, h, a = stats[i]
        if a >= MIN_AREA:
            out.append(dict(px=int(x), py=int(y), pw=int(w), ph=int(h), area=int(a),
                            x0=x / CS, y0=y / CS, x1=(x + w) / CS, y1=(y + h) / CS))
    return out, im


if __name__ == "__main__":
    allc = {}
    for i in range(1, 11):
        q = "%02d" % i
        cs, im = comps(q)
        allc[q] = cs
        tiles = []
        for j, c in enumerate(cs):
            pad = 8
            crop = im[max(c["py"] - pad, 0):c["py"] + c["ph"] + pad,
                      max(c["px"] - pad, 0):c["px"] + c["pw"] + pad]
            sc = min(180 / crop.shape[1], 180 / crop.shape[0], 2.2)
            crop = cv2.resize(crop, None, fx=sc, fy=sc)
            canvas = np.full((205, 200, 3), 255, np.uint8)
            canvas[:min(crop.shape[0], 190), :min(crop.shape[1], 200)] = crop[:190, :200]
            label = "%d: %d,%d-%d,%d" % (j, int(round(c["x0"])), int(round(c["y0"])),
                                         int(round(c["x1"])) - 1, int(round(c["y1"])) - 1)
            cv2.putText(canvas, label, (3, 202), cv2.FONT_HERSHEY_SIMPLEX, 0.52, (255, 0, 0), 1)
            tiles.append(canvas)
        while len(tiles) % 7:
            tiles.append(np.full((205, 200, 3), 255, np.uint8))
        cv2.imwrite("work/fm%s.png" % q,
                    np.vstack([np.hstack(tiles[r:r + 7]) for r in range(0, len(tiles), 7)]))
        print("q%s components=%d -> work/fm%s.png" % (q, len(cs), q))
    json.dump(allc, open("work/furn_raw.json", "w"), indent=1)
