"""Step 4 - find the doors.

A door is drawn as a white capsule straddling a wall, always the same size, so
on the canonical raster plain normalised template matching separates it cleanly:
real doors score 0.65..1.00 and everything else piles up at 0.60 and below. (On
the raw scans this does not work - the per-page scale differs by a percent or
two and the correlation collapses. Step 2 is what makes it work.)

Templates are taken from confirmed doors in quest 1, three vertical and two
horizontal, and each wall segment takes the best of them.

This finds a door drawn CLOSED - the white capsule - and nothing else. A door
the pack draws some other way does not score here at all, so step 9 checks
every room in play has a way in and manual.json carries the ones read by eye.

    in:  ds/cNN.png
    out: work/doors.json   {quest: [[x, y, "N"|"W", score]]}

A door is recorded as the NORTH or WEST wall of the square named, the same
convention data/quest_data.asm uses.
"""
import json

import cv2
import numpy as np

CS, W, H = 80, 26, 19
THRESH = 0.62
# px of slop allowed between the print and the ideal grid. 6 was too tight:
# the warp is linear and the printed board is not, so a wall can sit a dozen
# pixels off its ideal line. Quest 7's (12,15)W is the worst at 11 px, and at
# SEARCH = 6 it scored 0.09 - anti-correlated, nowhere near the 0.62 cut,
# because the template was landing on the wall beside the door rather than on
# it. 16 finds it and quest 3's (18,14)W and adds no false positive anywhere
# in the pack; the gap between lowest kept and highest dropped stays wide.
SEARCH = 16


def gray(q):
    return cv2.cvtColor(cv2.imread("ds/c%s.png" % q), cv2.COLOR_BGR2GRAY).astype(np.float32)


G1 = gray("01")
TPL_V = [G1[3 * CS + 3:4 * CS - 3, 80 - 24:80 + 24],          # W(1,3)
         G1[8 * CS + 3:9 * CS - 3, 80 - 24:80 + 24],          # W(1,8)
         G1[5 * CS + 3:6 * CS - 3, 21 * CS - 24:21 * CS + 24]]  # W(21,5)
TPL_H = [G1[9 * CS - 24:9 * CS + 24, 8 * CS + 3:9 * CS - 3],   # N(8,9)
         G1[CS - 24:CS + 24, 21 * CS + 3:22 * CS - 3]]         # N(21,1)


def scores(q):
    g = gray(q)
    res = {}
    for tpls, orient in ((TPL_V, "W"), (TPL_H, "N")):
        maps = [cv2.matchTemplate(g, t, cv2.TM_CCOEFF_NORMED) for t in tpls]
        th, tw = tpls[0].shape
        for y in range(H):
            for x in range(W + 1):
                if orient == "N" and (y == 0 or x >= W):
                    continue
                if orient == "W" and (x == 0 or x > W):
                    continue
                if orient == "W":
                    cx, cy = x * CS - tw // 2, y * CS + CS // 2 - th // 2
                else:
                    cx, cy = x * CS + CS // 2 - tw // 2, y * CS - th // 2
                best = -1
                for r in maps:
                    win = r[max(cy - SEARCH, 0):cy + SEARCH + 1,
                            max(cx - SEARCH, 0):cx + SEARCH + 1]
                    if win.size:
                        best = max(best, float(win.max()))
                res[(x, y, orient)] = best
    return res


if __name__ == "__main__":
    out = {}
    for i in range(1, 11):
        q = "%02d" % i
        s = scores(q)
        doors = sorted([(k[0], k[1], k[2], round(v, 2)) for k, v in s.items() if v >= THRESH],
                       key=lambda t: (t[1], t[0]))
        out[q] = doors
        ranked = sorted(s.values(), reverse=True)
        print("q%s doors=%2d  lowest kept %.2f  highest dropped %.2f"
              % (q, len(doors), ranked[len(doors) - 1], ranked[len(doors)]))
    json.dump(out, open("work/doors.json", "w"), indent=1)
