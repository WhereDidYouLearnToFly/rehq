"""Step 10 - draw the parsed data back out, over the scan it came from.

Nothing here feeds the pipeline; it exists so the parse can be checked by eye.
Each sheet is the reconstruction on top and the scan underneath, same scale.

    out: work/verNN.png, copied to assets/quests/verify/qNN.png
"""
import json
import os
import shutil

import cv2
import numpy as np

CS, W, H = 46, 26, 19
D = json.load(open("work/quests.json"))
COL = {"orc": (60, 150, 60), "goblin": (90, 190, 90), "skeleton": (220, 220, 220),
       "zombie": (120, 160, 190), "mummy": (150, 200, 230), "dread_warrior": (60, 60, 200),
       "abomination": (180, 140, 60), "gargoyle": (140, 60, 180),
       "dread_sorcerer": (200, 60, 200), "unknown": (0, 0, 0)}
INI = {"orc": "O", "goblin": "g", "skeleton": "S", "zombie": "Z", "mummy": "M",
       "dread_warrior": "D", "abomination": "A", "gargoyle": "G",
       "dread_sorcerer": "W", "unknown": "?"}

OUTDIR = "E:/github/rehq/assets/quests/verify"
os.makedirs(OUTDIR, exist_ok=True)
for q in sorted(D):
    d = D[q]
    img = np.full((H * CS, W * CS, 3), 245, np.uint8)
    for y in range(H):
        for x in range(W):
            c = (250, 245, 235) if d["grid"][y][x] == "o" else (170, 175, 205)
            cv2.rectangle(img, (x * CS, y * CS), ((x + 1) * CS - 1, (y + 1) * CS - 1), c, -1)
            cv2.rectangle(img, (x * CS, y * CS), ((x + 1) * CS, (y + 1) * CS), (215, 210, 205), 1)
    for x0, y0, x1, y1, k in d["furniture"]:
        cv2.rectangle(img, (x0 * CS + 3, y0 * CS + 3), ((x1 + 1) * CS - 4, (y1 + 1) * CS - 4),
                      (40, 120, 190), 2)
        cv2.putText(img, k[:6], (x0 * CS + 4, y0 * CS + 16), cv2.FONT_HERSHEY_SIMPLEX,
                    0.32, (40, 120, 190), 1)
    for x, y, o in d["doors"]:
        p1, p2 = (((x * CS - 6, y * CS + 8), (x * CS + 6, (y + 1) * CS - 8)) if o == "W"
                  else ((x * CS + 8, y * CS - 6), ((x + 1) * CS - 8, y * CS + 6)))
        cv2.rectangle(img, p1, p2, (255, 255, 255), -1)
        cv2.rectangle(img, p1, p2, (30, 30, 30), 2)
    for x, y, t in d["monsters"]:
        cv2.circle(img, (x * CS + CS // 2, y * CS + CS // 2), CS // 3, COL.get(t, (0, 0, 0)), -1)
        cv2.putText(img, INI.get(t, "?"), (x * CS + CS // 2 - 7, y * CS + CS // 2 + 7),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 2)
    for x, y, t in d["special"]:
        cv2.rectangle(img, (x * CS + 2, y * CS + 2), ((x + 1) * CS - 3, (y + 1) * CS - 3),
                      (0, 140, 255) if t == "orange" else (0, 0, 160), 2)
    for x, y, L in d["marks"]:
        cv2.putText(img, L, (x * CS + 10, y * CS + CS - 10), cv2.FONT_HERSHEY_SIMPLEX,
                    0.9, (0, 0, 190), 3)
    for a in d["arrows"]:
        cv2.putText(img, ">" + a[2], (a[0] * CS + 4, a[1] * CS + CS - 12),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (200, 0, 120), 2)
    bar = np.full((34, W * CS, 3), 255, np.uint8)
    cv2.putText(bar, "Quest %d  %s   (wandering: %s)" % (d["n"], d["title"], d["wandering"]),
                (6, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.62, (0, 0, 0), 2)
    scan = cv2.resize(cv2.imread("ds/c%s.png" % q), (W * CS, H * CS))
    sheet = np.vstack([bar, img, np.full((8, W * CS, 3), 120, np.uint8), scan])
    cv2.imwrite("work/ver%s.png" % q, sheet)
    shutil.copy("work/ver%s.png" % q, os.path.join(OUTDIR, "q%s.png" % q))
    print("q%s -> assets/quests/verify/q%s.png" % (q, q))
