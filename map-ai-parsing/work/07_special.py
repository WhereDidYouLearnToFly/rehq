"""Step 7 - squares printed in a colour of their own.

Orange squares mark quest-specific things (the doors marked A in quest 8, the
vine traps in quest 3, a treasure chest); deep red ones are the staircase and
the pools. Both are flat fills, so a square counts only if most of it is that
colour - that is what keeps furniture ink from reading as a special square.

    in:  ds/cNN.png
    out: work/special.json  {quest: [[x, y, "orange"|"deep_red"]]}
"""
import json

import cv2

CS, W, H = 80, 26, 19

out = {}
for i in range(1, 11):
    q = "%02d" % i
    im = cv2.imread("ds/c%s.png" % q).astype(int)
    res = []
    for y in range(H):
        for x in range(W):
            p = im[y * CS + 16:(y + 1) * CS - 16, x * CS + 16:(x + 1) * CS - 16].reshape(-1, 3)
            B, G, R = p[:, 0], p[:, 1], p[:, 2]
            orange = ((R > 150) & (G > 60) & (G < 150) & (B < 115) & (R - B > 70)).mean()
            deep = ((R < 170) & (G < 95) & (R > G + 30)).mean()
            if orange > 0.55:
                res.append([x, y, "orange"])
            elif deep > 0.65:
                res.append([x, y, "deep_red"])
    out[q] = res
    print("q%s specials=%d" % (q, len(res)))
json.dump(out, open("work/special.json", "w"), indent=1)
