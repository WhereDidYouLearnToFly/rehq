"""The scan with the parse drawn on it, and clicks turned into squares.

The canonical raster is 80 px to the square, which is why a click lands where
you think it does: the arithmetic here is a divide, not a calibration.
"""
import os

from PySide6 import QtCore, QtGui, QtWidgets

from .catalog import CAT
from .paths import DS, H, W

OUT_WASH = QtGui.QColor(10, 14, 40, 95)
COL = {
    "door": QtGui.QColor(255, 255, 255),
    "monster": QtGui.QColor(235, 40, 40),
    "mark": QtGui.QColor(250, 240, 60),
    "special": {"orange": QtGui.QColor(255, 150, 40),
                "deep_red": QtGui.QColor(150, 20, 45)},
    "furniture": QtGui.QColor(210, 150, 60),
    "arrow": QtGui.QColor(40, 230, 150),
    "opening": QtGui.QColor(205, 125, 255),
    "wall": QtGui.QColor(80, 190, 255, 150),
    "hand": QtGui.QColor(60, 220, 255),
}


def _layer_colour(layer):
    """A stable colour per catalogue layer, so a new one is legible at once.

    furniture keeps the colour it has had; anything else is placed around the
    hue circle by its name, which is arbitrary but never changes under you.
    """
    if layer == "furniture":
        return QtGui.QColor(COL["furniture"])
    hue = (sum(ord(c) * (i + 1) for i, c in enumerate(layer)) * 47) % 360
    return QtGui.QColor.fromHsv(hue, 170, 245)


def _abbr(t):
    """A few letters that tell the ten types apart at 20 px."""
    return {"dread_warrior": "DW", "dread_sorcerer": "DS", "abomination": "ABM",
            "skeleton": "SKL", "zombie": "ZMB", "mummy": "MUM", "goblin": "GOB",
            "orc": "ORC", "gargoyle": "GAR", "unknown": "???"}.get(t, t[:3].upper())


class Board(QtWidgets.QWidget):
    """The scan with the parse drawn on it, and clicks turned into squares."""

    clicked = QtCore.Signal(int, int, float, float, int, int)
    dragged = QtCore.Signal(int, int, int, int)
    hovered = QtCore.Signal(int, int)

    def __init__(self):
        super(Board, self).__init__()
        self.model = None
        self.q = "01"
        self.show_scan = True
        self.show_parse = True
        self.show_walls = True
        self.drag_kind = False
        self._img = {}
        self._scaled = None
        self._down = None
        self._downf = None
        self._hover = None
        self.setMouseTracking(True)
        self.setMinimumSize(520, 380)
        self.setFocusPolicy(QtCore.Qt.StrongFocus)

    def set_quest(self, q):
        self.q = q
        self._scaled = None
        self.update()

    def image(self):
        if self.q not in self._img:
            p = os.path.join(DS, "c%s.png" % self.q)
            self._img[self.q] = QtGui.QImage(p) if os.path.exists(p) else QtGui.QImage()
        return self._img[self.q]

    def board_rect(self):
        """The 26x19 board inside the widget, aspect kept."""
        w, h = self.width(), self.height()
        s = min(w / float(W), h / float(H))
        bw, bh = s * W, s * H
        return QtCore.QRectF((w - bw) / 2.0, (h - bh) / 2.0, bw, bh)

    def cell_at(self, pos):
        r = self.board_rect()
        cs = r.width() / W
        fx = (pos.x() - r.left()) / cs
        fy = (pos.y() - r.top()) / cs
        x, y = int(fx), int(fy)
        if not (0 <= x < W and 0 <= y < H):
            return None
        return x, y, fx - x, fy - y

    # -- paint -----------------------------------------------------------

    def paintEvent(self, ev):
        p = QtGui.QPainter(self)
        p.fillRect(self.rect(), QtGui.QColor(24, 24, 28))
        r = self.board_rect()
        cs = r.width() / W
        img = self.image()
        if self.show_scan and not img.isNull():
            if self._scaled is None or self._scaled.width() != int(r.width()):
                self._scaled = QtGui.QPixmap.fromImage(
                    img.scaled(int(r.width()), int(r.height()),
                               QtCore.Qt.IgnoreAspectRatio,
                               QtCore.Qt.SmoothTransformation))
            p.drawPixmap(r.topLeft(), self._scaled)
        else:
            p.fillRect(r, QtGui.QColor(200, 195, 180))
        if self.model is None:
            return
        p.setRenderHint(QtGui.QPainter.Antialiasing, True)
        if self.show_parse:
            self._paint_parse(p, r, cs)
        self._paint_grid(p, r, cs)

    def _cell(self, r, cs, x, y):
        return QtCore.QRectF(r.left() + x * cs, r.top() + y * cs, cs, cs)

    def _paint_parse(self, p, r, cs):
        m, q = self.model, self.q
        grid = m.grid(q)
        hand_sq = m.hand_squares(q)
        for y in range(H):
            for x in range(W):
                if grid[y][x] != "o":
                    p.fillRect(self._cell(r, cs, x, y), OUT_WASH)
                if (x, y) in hand_sq:
                    self._hand_mark(p, self._cell(r, cs, x, y))

        if self.show_walls:
            pen = QtGui.QPen(COL["wall"], max(1.5, cs * 0.06))
            pen.setCapStyle(QtCore.Qt.FlatCap)
            p.setPen(pen)
            p.setBrush(QtCore.Qt.NoBrush)
            for x, y, o in m.walls(q, grid):
                c = self._cell(r, cs, x, y)
                p.drawLine(c.topLeft(),
                           c.bottomLeft() if o == "W" else c.topRight())
            p.drawRect(r)                       # the board's own edge

        for row, hand in m.rows(q, "special"):
            x, y, kind = row
            c = QtGui.QColor(COL["special"].get(kind, QtGui.QColor(255, 0, 255)))
            c.setAlpha(110)
            p.fillRect(self._cell(r, cs, x, y).adjusted(2, 2, -2, -2), c)
            if hand:
                self._hand_mark(p, self._cell(r, cs, x, y))

        p.setBrush(QtCore.Qt.NoBrush)
        for x0, y0, x1, y1, kind in m.furniture(q):
            rect = QtCore.QRectF(r.left() + x0 * cs, r.top() + y0 * cs,
                                 (x1 - x0 + 1) * cs,
                                 (y1 - y0 + 1) * cs).adjusted(2, 2, -2, -2)
            p.setPen(QtGui.QPen(COL["furniture"], 2.0))
            p.drawRect(rect)
            self._label(p, rect.adjusted(3, 1, -3, 0), kind, COL["furniture"],
                        QtCore.Qt.AlignLeft | QtCore.Qt.AlignTop, cs * 0.20)

        for row, hand in m.rows(q, "doors"):
            x, y, o = row
            c = self._cell(r, cs, x, y)
            t = max(3.0, cs * 0.16)
            bar = (QtCore.QRectF(c.left() - t / 2, c.top() + cs * 0.15, t, cs * 0.70)
                   if o == "W" else
                   QtCore.QRectF(c.left() + cs * 0.15, c.top() - t / 2, cs * 0.70, t))
            p.setPen(QtGui.QPen(QtGui.QColor(20, 20, 20), 1.0))
            p.setBrush(COL["hand"] if hand else COL["door"])
            p.drawRect(bar)
            p.setBrush(QtCore.Qt.NoBrush)

        # An opening is drawn as the opposite of a door: the wall's two ends
        # left standing and the middle of it gone, which is what a doorway
        # looks like on a floor plan and what the cardboard overlay does.
        stub = QtGui.QPen(COL["opening"], max(2.5, cs * 0.11))
        stub.setCapStyle(QtCore.Qt.FlatCap)
        gap = QtGui.QPen(COL["opening"], 1.0, QtCore.Qt.DotLine)
        for x, y, o in m.openings(q):
            c = self._cell(r, cs, x, y)
            e = cs * 0.24
            if o == "W":
                ends = [(c.topLeft(), QtCore.QPointF(c.left(), c.top() + e)),
                        (QtCore.QPointF(c.left(), c.bottom() - e), c.bottomLeft())]
                middle = (QtCore.QPointF(c.left(), c.top() + e),
                          QtCore.QPointF(c.left(), c.bottom() - e))
            else:
                ends = [(c.topLeft(), QtCore.QPointF(c.left() + e, c.top())),
                        (QtCore.QPointF(c.right() - e, c.top()), c.topRight())]
                middle = (QtCore.QPointF(c.left() + e, c.top()),
                          QtCore.QPointF(c.right() - e, c.top()))
            p.setPen(stub)
            for a, b in ends:
                p.drawLine(a, b)
            p.setPen(gap)
            p.drawLine(*middle)

        for row, hand in m.rows(q, "monsters"):
            x, y, t = row
            c = self._cell(r, cs, x, y)
            d = cs * 0.62
            disc = QtCore.QRectF(c.center().x() - d / 2, c.center().y() - d / 2, d, d)
            p.setPen(QtGui.QPen(COL["hand"] if hand else QtGui.QColor(20, 20, 20), 2.0))
            col = QtGui.QColor(COL["monster"])
            col.setAlpha(120)
            p.setBrush(col)
            p.drawEllipse(disc)
            p.setBrush(QtCore.Qt.NoBrush)
            self._label(p, c, _abbr(t), QtGui.QColor(255, 255, 255),
                        QtCore.Qt.AlignCenter, cs * 0.28)

        for row, hand in m.rows(q, "marks"):
            x, y, L = row
            c = self._cell(r, cs, x, y).adjusted(cs * 0.24, cs * 0.24,
                                                 -cs * 0.24, -cs * 0.24)
            p.setPen(QtGui.QPen(COL["hand"] if hand else QtGui.QColor(20, 20, 20), 1.5))
            col = QtGui.QColor(COL["mark"])
            col.setAlpha(150)
            p.setBrush(col)
            p.drawRect(c)
            p.setBrush(QtCore.Qt.NoBrush)
            self._label(p, c, L, QtGui.QColor(30, 30, 10),
                        QtCore.Qt.AlignCenter, cs * 0.30)

        for x, y, o in m.arrows(q):
            c = self._cell(r, cs, x, y)
            glyph = {"N": "↑", "S": "↓", "W": "←", "E": "→"}
            self._label(p, c, glyph.get(o, o), COL["arrow"],
                        QtCore.Qt.AlignCenter, cs * 0.5)

    def _hand_mark(self, p, rect):
        p.setPen(QtGui.QPen(COL["hand"], 1.5, QtCore.Qt.DotLine))
        p.setBrush(QtCore.Qt.NoBrush)
        p.drawRect(rect.adjusted(1, 1, -1, -1))

    def _label(self, p, rect, text, colour, align, px):
        f = p.font()
        f.setPixelSize(max(7, int(px)))
        f.setBold(True)
        p.setFont(f)
        p.setPen(QtGui.QPen(QtGui.QColor(0, 0, 0, 190), 1))
        p.drawText(rect.adjusted(1, 1, 1, 1), align, text)
        p.setPen(QtGui.QPen(colour, 1))
        p.drawText(rect, align, text)

    def _paint_grid(self, p, r, cs):
        p.setBrush(QtCore.Qt.NoBrush)
        for x in range(W + 1):
            p.setPen(QtGui.QPen(QtGui.QColor(255, 255, 255, 70 if x % 5 else 130), 1))
            p.drawLine(QtCore.QPointF(r.left() + x * cs, r.top()),
                       QtCore.QPointF(r.left() + x * cs, r.bottom()))
        for y in range(H + 1):
            p.setPen(QtGui.QPen(QtGui.QColor(255, 255, 255, 70 if y % 5 else 130), 1))
            p.drawLine(QtCore.QPointF(r.left(), r.top() + y * cs),
                       QtCore.QPointF(r.right(), r.top() + y * cs))
        if self._hover:
            x, y = self._hover
            p.setPen(QtGui.QPen(QtGui.QColor(70, 255, 210), 2))
            p.drawRect(self._cell(r, cs, x, y).adjusted(1, 1, -1, -1))
        if self._down and self.drag_kind:
            x0, y0 = self._down
            x1, y1 = self._hover or self._down
            rect = QtCore.QRectF(r.left() + min(x0, x1) * cs,
                                 r.top() + min(y0, y1) * cs,
                                 (abs(x1 - x0) + 1) * cs, (abs(y1 - y0) + 1) * cs)
            p.setPen(QtGui.QPen(COL["furniture"], 2, QtCore.Qt.DashLine))
            p.drawRect(rect)

    # -- mouse -----------------------------------------------------------

    def resizeEvent(self, ev):
        self._scaled = None

    def mouseMoveEvent(self, ev):
        c = self.cell_at(ev.position())
        h = (c[0], c[1]) if c else None
        if h != self._hover:
            self._hover = h
            if h:
                self.hovered.emit(h[0], h[1])
            self.update()

    def mousePressEvent(self, ev):
        c = self.cell_at(ev.position())
        if not c:
            return
        self._down = (c[0], c[1])
        self._downf = c

    def mouseReleaseEvent(self, ev):
        if not self._down:
            return
        c = self.cell_at(ev.position())
        x0, y0 = self._down
        d = self._downf
        self._down = None
        if (c and self.drag_kind and ev.button() == QtCore.Qt.LeftButton
                and (c[0], c[1]) != (x0, y0)):
            self.dragged.emit(min(x0, c[0]), min(y0, c[1]),
                              max(x0, c[0]), max(y0, c[1]))
        else:
            self.clicked.emit(d[0], d[1], d[2], d[3],
                              int(ev.button().value), int(ev.modifiers().value))
        self.update()

    def leaveEvent(self, ev):
        self._hover = None
        self.update()


def _wall(x, y, fx, fy, forced):
    """Which wall a click at (fx, fy) inside square (x, y) meant.

    Doors are recorded as the north or the west wall of a square, so the east
    and south edges of this square are the west and north walls of the next
    one - and clicking the edge you can see is the whole point of doing this
    on the map rather than in the file.
    """
    if forced in ("N", "W"):
        return x, y, forced
    cand = [(fx, (x, y, "W")), (fy, (x, y, "N")),
            (1 - fx, (x + 1, y, "W")), (1 - fy, (x, y + 1, "N"))]
    for _d, (cx, cy, o) in sorted(cand, key=lambda c: c[0]):
        if 0 <= cx < W and 0 <= cy < H:
            return cx, cy, o
    return x, y, "W"
