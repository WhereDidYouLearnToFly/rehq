"""Step 3 - which squares are in play.

A square that is not part of a quest is filled mauve on its map. Mauve is a
specific flat colour, so classify by how much of the square is mauve rather
than by how dark it is - darkness alone calls a square blocked when a big
piece of furniture is drawn on it, which is what the tavern tile in quest 1
does to half a dozen squares.

What identifies mauve is its HUE - R-B and R-G - not how dark it is. The
absolute channel bounds only keep the beige floor out, and the hue tests
exclude the beige on their own anyway (it runs R-G 10, R-B 25, nowhere near
the cut). So the blue ceiling wants to be loose, and at 170 it was not: the
bottom row of quest 2 is scanned lighter than the rest of that map, mean blue
168 against 150 a row up, and square (3,18) came out 0.44 mauve where its
neighbours were 0.68 and 0.83. That put one square in play, alone, with no
in-play square touching it, on a map where it is plainly shaded.

Both numbers sit on a plateau rather than on an edge, which is the only
reason to trust either of them:

  THRESH  0.45..0.65   reproduces the hand-built /obj/quest_0's 352 squares
                       exactly, with no square either way
  B_MAX   175..200     every quest identical across the range, and no square
                       anywhere left stranded from the rest of its play area

That last one is worth keeping as a test. The play area is where the heroes
walk, so it is connected by definition, and a square cut off from all the
others is a parse error every time - it is what found this one.

    in:  ds/cNN.png
    out: work/grids.json   {quest: 19 strings of 26 chars, 'o' in play, '.' out}
"""
import json

import cv2
import numpy as np

CS, W, H = 80, 26, 19
THRESH = 0.55
B_MAX = 185         # hue is what says mauve; brightness must not veto it


def mauve_frac(q):
    im = cv2.imread("ds/c%s.png" % q).astype(int)
    f = np.zeros((H, W))
    for y in range(H):
        for x in range(W):
            p = im[y * CS + 14:(y + 1) * CS - 14, x * CS + 14:(x + 1) * CS - 14].reshape(-1, 3)
            B, G, R = p[:, 0], p[:, 1], p[:, 2]
            m = ((R > 160) & (R < 235) & (G > 120) & (G < 195) & (B > 90) & (B < B_MAX)
                 & (R - B > 40) & (R - B < 95) & (R - G > 20))
            f[y, x] = m.mean()
    return f


def stranded(grid):
    """Squares in play that no other square in play touches.

    The play area is where the heroes walk, so it is one connected area and
    anything cut off from it is a misread square, not a feature.
    """
    from collections import deque

    seen, areas = set(), []
    for y in range(H):
        for x in range(W):
            if grid[y][x] != "o" or (x, y) in seen:
                continue
            area, q = [], deque([(x, y)])
            seen.add((x, y))
            while q:
                cx, cy = q.popleft()
                area.append((cx, cy))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = cx + dx, cy + dy
                    if (0 <= nx < W and 0 <= ny < H and grid[ny][nx] == "o"
                            and (nx, ny) not in seen):
                        seen.add((nx, ny))
                        q.append((nx, ny))
            areas.append(sorted(area))
    areas.sort(key=len, reverse=True)
    return [s for a in areas[1:] for s in a]        # everything but the board


if __name__ == "__main__":
    out = {}
    for i in range(1, 11):
        q = "%02d" % i
        f = mauve_frac(q)
        out[q] = ["".join("." if f[y, x] > THRESH else "o" for x in range(W)) for y in range(H)]
        loose = stranded(out[q])
        print("q%s squares in play: %d%s"
              % (q, sum(r.count("o") for r in out[q]),
                 "   STRANDED %s - see the docstring" % loose if loose else ""))
    json.dump(out, open("work/grids.json", "w"), indent=1)
