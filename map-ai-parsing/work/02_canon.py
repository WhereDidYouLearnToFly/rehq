"""Step 2 - warp every map onto one canonical grid, and derive the bare board.

After this every quest is the same raster: square (x, y) is exactly the 80x80
block at (x*80, y*80). That is what makes template matching work - a door is
the same size in pixels in all ten maps.

The bare board falls out for free. All ten maps are the same printed board with
different overlays, so a high per-pixel percentile across the ten (bright wins)
keeps what is dark in every map - the rules and walls - and drops what is dark
in only a few - monsters, furniture, letters, the mauve shading. Subtracting
that plate's ink is how step 8 isolates furniture.

    in:  ds/qNN.png, work/frames.json
    out: ds/cNN.png    canonical 2080x1520 map
         ds/plate.png  the board with quest content voted away
"""
import json

import cv2
import numpy as np

CS, W, H = 80, 26, 19
CW, CH = W * CS, H * CS

F = json.load(open("work/frames.json"))
stack = []
for i in range(1, 11):
    q = "%02d" % i
    fr = F[q]
    im = cv2.imread("ds/q%s.png" % q)
    src = np.float32([[fr["x0"], fr["y0"]], [fr["x1"], fr["y0"]],
                      [fr["x1"], fr["y1"]], [fr["x0"], fr["y1"]]])
    dst = np.float32([[0, 0], [CW, 0], [CW, CH], [0, CH]])
    c = cv2.warpPerspective(im, cv2.getPerspectiveTransform(src, dst), (CW, CH),
                            flags=cv2.INTER_AREA)
    cv2.imwrite("ds/c%s.png" % q, c)
    stack.append(c.astype(np.float32))
    print("q%s -> ds/c%s.png" % (q, q))

cv2.imwrite("ds/plate.png", np.percentile(np.stack(stack), 80, axis=0).astype(np.uint8))
print("board plate -> ds/plate.png")
