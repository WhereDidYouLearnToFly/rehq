"""Step 6 - the note letters printed on the maps.

Each quest's notes are keyed to bold letters (A..F, X) drawn on squares. Same
fixed glyphs on the same canonical raster, so template matching again. Glyph
templates come from quest 2, which happens to print six of the seven cleanly.

Matches below 0.7 are dropped - the corner masonry on the board can score in
the 0.6s against 'F'.

    in:  ds/cNN.png
    out: work/letters.json  {quest: [[x, y, letter, score]]}
"""
import json

import cv2
import numpy as np

CS, W, H = 80, 26, 19
THRESH = 0.7
SRC = [("A", "02", 22, 2), ("B", "02", 19, 3), ("C", "02", 18, 7), ("D", "02", 21, 17),
       ("E", "02", 2, 13), ("X", "02", 3, 4), ("F", "05", 6, 5)]


def gray(q):
    return cv2.cvtColor(cv2.imread("ds/c%s.png" % q), cv2.COLOR_BGR2GRAY).astype(np.float32)


TPL = {L: gray(q)[y * CS + 12:(y + 1) * CS - 12, x * CS + 12:(x + 1) * CS - 12]
       for L, q, x, y in SRC}


def find(q):
    g = gray(q)
    best = {}
    for L, t in TPL.items():
        r = cv2.matchTemplate(g, t, cv2.TM_CCOEFF_NORMED)
        for y in range(H):
            for x in range(W):
                cy, cx = y * CS + 12, x * CS + 12
                win = r[max(cy - 8, 0):cy + 9, max(cx - 8, 0):cx + 9]
                if win.size and win.max() >= THRESH:
                    s = float(win.max())
                    if (x, y) not in best or s > best[(x, y)][1]:
                        best[(x, y)] = (L, s)
    return sorted([(x, y, L, round(s, 2)) for (x, y), (L, s) in best.items()],
                  key=lambda t: (t[1], t[0]))


if __name__ == "__main__":
    out = {}
    for i in range(1, 11):
        q = "%02d" % i
        out[q] = find(q)
        print("q%s" % q, [(t[2], t[0], t[1]) for t in out[q]])
    json.dump(out, open("work/letters.json", "w"), indent=1)
