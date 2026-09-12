"""Step 1 - deskew each map and find the printed board frame.

The board is 26x19 squares inside a double-ruled frame. Finding the inner frame
line on each side is what pins the grid; everything downstream is indexed off it.

Method: mask the dark red printing, take the median angle of the long straight
lines to deskew, then look for rows/columns that are >80% covered by that mask -
those are the frame and the room walls. The frame is the outermost such line on
each side, chosen so the resulting cell is ~81.9 x 82.45 px (the print is
regular, so a candidate pair that disagrees with that is the wrong pair).

    in:  hi/qNN.png
    out: ds/qNN.png      deskewed map
         work/frames.json  {quest: {ang, x0, y0, x1, y1, cw, ch}}
"""
import glob
import json
import os

import cv2
import numpy as np

CELL_W, CELL_H = 81.9, 82.45          # measured, and consistent across all ten scans
W, H = 26, 19


def linemask(im):
    """The dark red printing: rules, walls, furniture outlines. Not the mauve fill."""
    b, g, r = [im[:, :, i].astype(int) for i in range(3)]
    return (((r - g) > 30) & (g < 140)).astype(np.uint8)


def deskew(im):
    m = linemask(im)
    small = cv2.resize(m * 255, (m.shape[1] // 2, m.shape[0] // 2))
    lines = cv2.HoughLinesP(small, 1, np.pi / 1800, threshold=200,
                            minLineLength=small.shape[1] // 3, maxLineGap=10)
    angs = []
    if lines is not None:
        for x1, y1, x2, y2 in lines[:, 0]:
            a = np.degrees(np.arctan2(y2 - y1, x2 - x1))
            if abs(a) < 5:
                angs.append(a)
    ang = float(np.median(angs)) if angs else 0.0
    h, w = im.shape[:2]
    M = cv2.getRotationMatrix2D((w / 2, h / 2), ang, 1.0)
    return cv2.warpAffine(im, M, (w, h), flags=cv2.INTER_LINEAR,
                          borderMode=cv2.BORDER_REPLICATE), ang


def runs(cov, thr, lo, hi):
    """Centres of the runs where coverage is over thr, ignoring the page edges."""
    on = cov > thr
    out, i = [], 0
    while i < len(on):
        if on[i]:
            j = i
            while j < len(on) and on[j]:
                j += 1
            if i > lo and j - 1 < hi:
                out.append((i + j - 1) / 2.0)
            i = j
        else:
            i += 1
    return out


def frame(im):
    m = linemask(im)
    h, w = m.shape
    cr = m[:, int(w * 0.2):int(w * 0.8)].mean(axis=1)
    cc = m[int(h * 0.2):int(h * 0.8), :].mean(axis=0)
    R = runs(cr, 0.8, 45, h - 45)
    C = runs(cc, 0.8, 45, w - 45)

    def pick(cands, n, target):
        best = None
        for a in cands[:3]:
            for b in cands[-3:]:
                e = abs((b - a) / n - target)
                if best is None or e < best[0]:
                    best = (e, a, b)
        return best[1], best[2]

    x0, x1 = pick(C, W, CELL_W)
    y0, y1 = pick(R, H, CELL_H)
    return x0, y0, x1, y1


if __name__ == "__main__":
    os.makedirs("ds", exist_ok=True)
    os.makedirs("work", exist_ok=True)
    info = {}
    for f in sorted(glob.glob("hi/q*.png")):
        q = os.path.basename(f)[1:3]
        im, ang = deskew(cv2.imread(f))
        cv2.imwrite("ds/q%s.png" % q, im)
        x0, y0, x1, y1 = frame(im)
        info[q] = dict(ang=ang, x0=x0, y0=y0, x1=x1, y1=y1,
                       cw=(x1 - x0) / W, ch=(y1 - y0) / H)
        print("q%s ang %+.2f  x %.1f..%.1f  y %.1f..%.1f  cell %.2f x %.2f"
              % (q, ang, x0, x1, y0, y1, info[q]["cw"], info[q]["ch"]))
    json.dump(info, open("work/frames.json", "w"), indent=1)
