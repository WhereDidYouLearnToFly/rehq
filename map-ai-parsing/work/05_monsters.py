"""Step 5 - find the monsters and name them.

Finding them is easy: a monster icon is the only green thing on the map.

Naming them is the interesting half. Reading 280 small icons one at a time is
slow and inconsistent, so instead they are clustered by normalised correlation
(0.74 on a 40x40 grey patch), which lands them in ~88 tight clusters, and the
cluster medians are labelled once by eye against the reference icons printed on
the manual's own "Wandering Monster in this Quest" lines. Every icon then
inherits its cluster's label. work/ctypes.json is that hand-made labelling.

    in:  ds/cNN.png, work/ctypes.json
    out: work/monsters.json  {quest: [[x, y, type]]}
         work/clusters.png   cluster medians, ids matching ctypes.json - look at
                             this if a type ever needs re-checking
"""
import json
from collections import Counter

import cv2
import numpy as np

CS, W, H = 80, 26, 19
GREEN = 0.12        # fraction of green pixels that makes a square a monster
SIM = 0.74          # correlation that keeps two icons in one cluster


def monster_cells(q):
    im = cv2.imread("ds/c%s.png" % q).astype(int)
    out = []
    for y in range(H):
        for x in range(W):
            p = im[y * CS + 14:(y + 1) * CS - 14, x * CS + 14:(x + 1) * CS - 14].reshape(-1, 3)
            B, G, R = p[:, 0], p[:, 1], p[:, 2]
            if ((G > R + 10) & (G > B + 10)).mean() > GREEN:
                out.append((x, y))
    return out


def vec(crop, s=40):
    g = cv2.resize(cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY), (s, s)).astype(np.float32).ravel()
    return (g - g.mean()) / (g.std() + 1e-6)


def cluster_icons():
    """Every monster icon in the pack, and the cluster each one fell in.

    Returns (keys, crops, lab, n): keys[i] is (quest, x, y), crops[i] the
    80x80 icon, lab[i] its cluster id, n the number of clusters.

    This is a function rather than a run of statements only so step 11 can cut
    its sprites off the same clustering this step reads types from. One
    clustering, two callers, no way for the two to disagree about what cluster
    7 is - and ctypes.json is keyed to those ids, so they have to be stable.
    """
    keys, crops = [], []
    for i in range(1, 11):
        q = "%02d" % i
        im = cv2.imread("ds/c%s.png" % q)
        for x, y in monster_cells(q):
            keys.append((q, x, y))
            crops.append(im[y * CS:(y + 1) * CS, x * CS:(x + 1) * CS])
    V = np.stack([vec(c) for c in crops])
    S = V @ V.T / V.shape[1]
    lab = -np.ones(len(crops), int)
    n = 0
    for i in np.argsort(-S.sum(1)):                 # densest icon first
        if lab[i] >= 0:
            continue
        lab[np.where((S[i] > SIM) & (lab < 0))[0]] = n
        n += 1
    return keys, crops, lab, n


if __name__ == "__main__":
    keys, crops, lab, n = cluster_icons()
    print("%d icons -> %d clusters" % (len(crops), n))

    ct = json.load(open("work/ctypes.json"))
    c2t = {c: t for t, ids in ct.items() for c in ids}
    unlabelled = sorted(set(lab.tolist()) - set(c2t))
    if unlabelled:
        print("WARNING unlabelled clusters (see work/clusters.png):", unlabelled)

    out = {}
    for (q, x, y), c in zip(keys, lab):
        out.setdefault(q, []).append([x, y, c2t.get(int(c), "?")])
    json.dump(out, open("work/monsters.json", "w"), indent=1)
    for q in sorted(out):
        print("q%s" % q, dict(Counter(m[2] for m in out[q])))

    rows, strip = [], []
    sizes = [(int((lab == k).sum()), k) for k in range(n)]
    for _, k in sorted(sizes, reverse=True):
        med = np.median(np.stack([cv2.resize(crops[i], (150, 150))
                                  for i in np.where(lab == k)[0]]), axis=0).astype(np.uint8)
        cv2.rectangle(med, (0, 0), (62, 22), (255, 255, 255), -1)
        cv2.putText(med, str(k), (3, 18), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (200, 0, 0), 2)
        strip.append(med)
        if len(strip) == 8:
            rows.append(np.hstack(strip)); strip = []
    if strip:
        strip += [np.full((150, 150, 3), 255, np.uint8)] * (8 - len(strip))
        rows.append(np.hstack(strip))
    cv2.imwrite("work/clusters.png", np.vstack(rows))
