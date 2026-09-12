"""Step 0 - pull the ten quest maps out of the scanned quest pack.

The PDF is a flat scan: 16 pages, no text layer, one quest per page from page
index 2 on (map on the top half, quest notes below). We only need the map half,
rendered big enough that a board square is ~80px after warping.

    out: hi/qNN.png      the map half of quest NN at 300 dpi
"""
import os
import pymupdf

PDF = r"E:/github/rehq/assets/scans/crypt_of_eternal_darkness.pdf"
FIRST_QUEST_PAGE = 2          # page index of quest 1
MAP_RECT = pymupdf.Rect(0, 0, 595, 470)     # top half of an A4 page

os.makedirs("hi", exist_ok=True)
doc = pymupdf.open(PDF)
for i in range(10):
    page = doc[FIRST_QUEST_PAGE + i]
    pix = page.get_pixmap(dpi=300, clip=MAP_RECT)
    pix.save("hi/q%02d.png" % (i + 1))
    print("q%02d %dx%d" % (i + 1, pix.width, pix.height))
