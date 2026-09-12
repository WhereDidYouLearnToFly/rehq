"""Quest editor - correct the parse by clicking on the scan.

map-ai-parsing reads the ten quest maps off the scans, and everything it
finds can be wrong. The channel for saying so is map-ai-parsing/work/
manual.json: a per-quest "fix" block of add and del rows that 09_assemble.py
applies over the detectors, and a hand-written furniture and arrows list that
has no detector behind it at all. All of that is correct and none of it is
convenient - it is JSON typed by hand against a square you counted off a
picture, which is how a wrong coordinate gets in.

This is the same channel with a map in front of it. It draws the canonical
scan (map-ai-parsing/ds/cNN.png, 80 px to the square, which is why a click
lands where you think it does), draws the parse over it, and turns a click
into the fix row that says what you just said.

    left click    put the selected thing on this square
    right click   take whatever this layer has on this square off it
    drag          a furniture footprint, when the furniture layer is up

WHAT IT WRITES, AND WHY IT CANCELS RATHER THAN STACKS

09_assemble.py stops the run on a del that matches nothing or an add that is
already there - deliberately, so that a detector improving cannot leave a
patch behind quietly misrepresenting the scan. An editor that only appended
would walk straight into that: delete a monster, put it back, and the file
now holds a del and an add for the same square, the del stale the moment the
add lands.

So every edit is resolved against what the detectors actually found:

    delete a row the detectors found         ->  add it to "del"
    delete a row that is only there as "add" ->  drop that add
    add a row that "del" is hiding           ->  drop that del
    add a row the detectors never had        ->  append to "add"

which is the minimal fix for the state on screen, and never a stale one.
Furniture and arrows skip all of it: those lists are the source, so an edit
there is an edit to the list.

THE FILE IT WRITES

manual.json is hand-made and hand-read, and a formatter that reflowed the
whole thing on every save would bury one changed row in a file-sized diff.
Only the quests actually edited are rewritten; every other quest keeps its
bytes exactly.

APPLY

Apply saves manual.json, runs step 9 in this process (it is pure json - no
cv2, no numpy) and shows what it printed, including the room and sealed-room
checks, then rebuilds the scene through build_quests_hou.py. That script is
the only thing in the tree that knows how a quest becomes nodes, and this
does not learn a second version of it.

Nothing downstream of quests_data.json is run - the verify overlays, the
sprites and assets/quests_to_asm.py are the README's chain and stay a
deliberate step.

    import quest_editor; quest_editor.show()
"""
import io
import json
import os
import contextlib
import runpy
import traceback

import hou
from PySide6 import QtCore, QtGui, QtWidgets

HIP = hou.expandString("$HIP")                       # assets/quests
ROOT = os.path.dirname(os.path.dirname(HIP))
PARSE = os.path.join(ROOT, "map-ai-parsing")
WORK = os.path.join(PARSE, "work")
DS = os.path.join(PARSE, "ds")
MANUAL = os.path.join(WORK, "manual.json")
ASSEMBLE = os.path.join(WORK, "09_assemble.py")
BUILD = os.path.join(HIP, "build_quests_hou.py")

W, H = 26, 19
QUESTS = ["%02d" % i for i in range(1, 11)]

# How many of a row's leading values name the thing, the same keylen
# 09_assemble.py applies add and del with: 2 for a square, 3 for a door,
# because one square can carry both a north and a west one.
KEYLEN = {"doors": 3, "monsters": 2, "marks": 2, "special": 2}

SPECIALS = ["orange", "deep_red"]
LETTERS = ["A", "B", "C", "D", "E", "F", "X"]


def _sprite_names(kind, fallback):
    """The names step 11 has cut a symbol for, so the pickers offer what the
    scene can actually draw. A kind with no sprite yet is still legal - the
    furniture picker is editable and step 11 will cut one for a new name."""
    try:
        idx = json.load(open(os.path.join(HIP, "sprites", "index.json")))
        return sorted(idx["sprites"].get(kind, {})) or fallback
    except Exception:
        return fallback


# ============================================================================
# the data
# ============================================================================

class Model(object):
    """The detectors, the hand file, and the merge of the two.

    The merge here is 09_assemble.py's, repeated rather than imported because
    that script is a program and not a module - it reads, merges and writes
    the moment it is touched. Repeating it is what lets a click show its
    result before anything is saved; Apply then runs the real one, and the
    two disagreeing would show up there as a different board.
    """

    def __init__(self):
        self.reload()

    def reload(self):
        def j(name):
            return json.load(open(os.path.join(WORK, name)))
        doors, mons = j("doors.json"), j("monsters.json")
        lets, spec = j("letters.json"), j("special.json")
        self.grids = j("grids.json")
        # Step 4 keeps its match score on the row and step 6 its own; the row
        # the fix channel speaks in is the leading values only.
        self.base = {q: {"doors": [list(d[:3]) for d in doors[q]],
                         "monsters": [list(m) for m in mons[q]],
                         "marks": [[x, y, L] for x, y, L, _s in lets[q]],
                         "special": [list(s) for s in spec[q]]} for q in QUESTS}
        self.manual = json.load(open(MANUAL))
        self.undo = []
        self.dirty = set()

    # -- the fix block ---------------------------------------------------

    def _fix(self, q, layer, create=False):
        fix = self.manual[q].get("fix")
        if fix is None:
            if not create:
                return {}
            fix = self.manual[q]["fix"] = {}
        d = fix.get(layer)
        if d is None:
            if not create:
                return {}
            d = fix[layer] = {}
        return d

    def _tidy(self, q):
        """Drop the empties. An "add": [] left lying about is not wrong, but
        it reads as a correction that is not there."""
        fix = self.manual[q].get("fix", {})
        for layer in list(fix):
            for k in list(fix[layer]):
                if not fix[layer][k]:
                    del fix[layer][k]
            if not fix[layer]:
                del fix[layer]
        if not fix and "fix" in self.manual[q]:
            del self.manual[q]["fix"]

    def snapshot(self):
        self.undo.append((json.dumps(self.manual), set(self.dirty)))
        del self.undo[:-40]

    def undo_last(self):
        if not self.undo:
            return False
        man, dirty = self.undo.pop()
        self.manual, self.dirty = json.loads(man), dirty
        return True

    # -- what is on the board --------------------------------------------

    def rows(self, q, layer):
        """[(row, by_hand)] - the detectors with this quest's fix applied."""
        n = KEYLEN[layer]
        fix = self._fix(q, layer)
        dels = [list(d) for d in fix.get("del", [])]
        out = [(list(r), False) for r in self.base[q][layer]
               if list(r[:n]) not in dels]
        out += [(list(a), True) for a in fix.get("add", [])]
        return out

    def find(self, q, layer, key):
        n = KEYLEN[layer]
        for row, hand in self.rows(q, layer):
            if row[:n] == list(key):
                return row, hand
        return None, False

    def furniture(self, q):
        return self.manual[q].setdefault("furniture", [])

    def arrows(self, q):
        return self.manual[q].setdefault("arrows", [])

    def grid(self, q):
        """19 rows of 26, the way step 9 settles them: the shading, then every
        square carrying something forced in, then the hand's in and out."""
        g = [list(r) for r in self.grids[q]]
        for layer in ("monsters", "marks", "special"):
            for row, _h in self.rows(q, layer):
                g[row[1]][row[0]] = "o"
        for x0, y0, x1, y1, _k in self.furniture(q):
            for xx in range(x0, x1 + 1):
                for yy in range(y0, y1 + 1):
                    if 0 <= xx < W and 0 <= yy < H:
                        g[yy][xx] = "o"
        sq = self.manual[q].get("fix", {}).get("squares", {})
        for x, y in sq.get("in", []):
            g[y][x] = "o"
        for x, y in sq.get("out", []):
            g[y][x] = "."
        return ["".join(r) for r in g]

    def hand_squares(self, q):
        sq = self.manual[q].get("fix", {}).get("squares", {})
        return ({tuple(c) for c in sq.get("in", [])} |
                {tuple(c) for c in sq.get("out", [])})

    # -- editing ---------------------------------------------------------

    def add(self, q, layer, row):
        """Put `row` on the board, as the minimal fix that says so."""
        n = KEYLEN[layer]
        row, key = list(row), list(row[:n])
        self.snapshot()
        cur, _hand = self.find(q, layer, key)
        if cur == row:
            return "already there"
        if cur is not None:
            # Retyping a square - a goblin where an orc was. Take the old one
            # off first so the two edits resolve separately.
            self.delete(q, layer, key, _chain=True)
        fix = self._fix(q, layer, create=True)
        dels = fix.get("del", [])
        base = [list(r) for r in self.base[q][layer]]
        if key in [list(d) for d in dels]:
            hidden = [r for r in base if r[:n] == key]
            if hidden and hidden[0] == row:
                dels.remove([d for d in dels if list(d) == key][0])
                self._tidy(q)
                self.dirty.add(q)
                return "restored, del dropped"
        fix.setdefault("add", []).append(row)
        self.dirty.add(q)
        return "added"

    def delete(self, q, layer, key, _chain=False):
        n = KEYLEN[layer]
        key = list(key)
        if not _chain:
            self.snapshot()
        fix = self._fix(q, layer, create=True)
        adds = fix.get("add", [])
        mine = [a for a in adds if list(a[:n]) == key]
        if mine:
            for a in mine:
                adds.remove(a)
            self._tidy(q)
            self.dirty.add(q)
            return "add dropped"
        if any(list(r[:n]) == key for r in self.base[q][layer]):
            fix.setdefault("del", []).append(key)
            self._tidy(q)
            self.dirty.add(q)
            return "deleted"
        self._tidy(q)
        return "nothing there"

    def set_square(self, q, x, y, want_in):
        """Force a square in or out of play, or stop forcing it when the
        shading already says what you want."""
        self.snapshot()
        sq = self._fix(q, "squares", create=True)
        for k in ("in", "out"):
            for c in [c for c in sq.get(k, []) if list(c) == [x, y]]:
                sq[k].remove(c)
        base_in = self.grids[q][y][x] == "o"
        if want_in != base_in:
            sq.setdefault("in" if want_in else "out", []).append([x, y])
            msg = "forced %s" % ("in" if want_in else "out")
        else:
            msg = "back to the scan"
        self._tidy(q)
        self.dirty.add(q)
        return msg

    def add_furniture(self, q, x0, y0, x1, y1, kind):
        self.snapshot()
        self.furniture(q).append([x0, y0, x1, y1, kind])
        self.dirty.add(q)
        return "%s %dx%d" % (kind, x1 - x0 + 1, y1 - y0 + 1)

    def del_furniture(self, q, x, y):
        self.snapshot()
        f = self.furniture(q)
        hit = [p for p in f if p[0] <= x <= p[2] and p[1] <= y <= p[3]]
        if not hit:
            return "nothing there"
        f.remove(hit[-1])
        self.dirty.add(q)
        return "removed %s" % hit[-1][4]

    def add_arrow(self, q, x, y, o):
        self.snapshot()
        a = self.arrows(q)
        for old in [r for r in a if list(r[:2]) == [x, y]]:
            a.remove(old)
        a.append([x, y, o])
        self.dirty.add(q)
        return "escape %s" % o

    def del_arrow(self, q, x, y):
        self.snapshot()
        a = self.arrows(q)
        hit = [r for r in a if list(r[:2]) == [x, y]]
        if not hit:
            return "nothing there"
        for r in hit:
            a.remove(r)
        self.dirty.add(q)
        return "removed"

    # -- writing ---------------------------------------------------------

    def save(self):
        """Rewrite only the quests that changed, in the file's own style."""
        text = open(MANUAL).read()
        for q in sorted(self.dirty):
            text = _splice(text, q, _block(q, self.manual[q]))
        open(MANUAL, "w").write(text)
        done, self.dirty = sorted(self.dirty), set()
        return done


# ============================================================================
# manual.json, written the way it is read
# ============================================================================

WRAP = 114


def _c(o):
    return json.dumps(o, separators=(",", ":"))


def _rows(rows, col):
    """Rows one after another, wrapped, continuations under the first one."""
    lines, cur = [], ""
    for r in rows:
        s = _c(r)
        if cur and len(cur) + 1 + len(s) > WRAP - col:
            lines.append(cur + ",")
            cur = s
        else:
            cur = (cur + "," + s) if cur else s
    lines.append(cur)
    pad = " " * col
    return "[" + ("\n" + pad).join(lines) + "]"


def _block(q, d):
    """One quest, as the lines it occupies in manual.json."""
    out = ['"%s": {"title":%s,"wandering":%s,'
           % (q, _c(d["title"]), _c(d["wandering"]))]
    fix = d.get("fix")
    if fix:
        parts = ["%s:%s" % (_c(k), _c(v)) for k, v in sorted(fix.items())]
        one = '  "fix":{%s},' % ",".join(parts)
        if len(one) <= WRAP:
            out.append(one)
        else:
            pad = " " * len('  "fix":{')
            out.append('  "fix":{' + (",\n" + pad).join(parts) + "},")
    out.append('  "furniture":' + _rows(d.get("furniture", []),
                                        len('  "furniture":[')))
    if d.get("arrows"):
        out[-1] += ","
        out.append('  "arrows":' + _rows(d["arrows"], len('  "arrows":[')))
    out[-1] += "}"
    return out


def _splice(text, q, block):
    """Put `block` where quest q's lines are now, and leave the rest alone.

    A quest block is the line starting `"NN": {` and every line under it
    until the next one starts at column 0 - which is the file's own shape,
    not a guess: every key is at column 0 and every continuation is indented.
    """
    lines = text.split("\n")
    head = '"%s": {' % q
    start = next(i for i, l in enumerate(lines) if l.startswith(head))
    end = start
    while end + 1 < len(lines) and lines[end + 1].startswith(" "):
        end += 1
    if lines[end].rstrip().endswith(","):
        block = list(block)
        block[-1] += ","
    return "\n".join(lines[:start] + list(block) + lines[end + 1:])


# ============================================================================
# the board
# ============================================================================

OUT_WASH = QtGui.QColor(10, 14, 40, 95)
COL = {
    "door": QtGui.QColor(255, 255, 255),
    "monster": QtGui.QColor(235, 40, 40),
    "mark": QtGui.QColor(250, 240, 60),
    "special": {"orange": QtGui.QColor(255, 150, 40),
                "deep_red": QtGui.QColor(150, 20, 45)},
    "furniture": QtGui.QColor(210, 150, 60),
    "arrow": QtGui.QColor(40, 230, 150),
    "hand": QtGui.QColor(60, 220, 255),
}


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


def _abbr(t):
    """A few letters that tell the ten types apart at 20 px."""
    return {"dread_warrior": "DW", "dread_sorcerer": "DS", "abomination": "ABM",
            "skeleton": "SKL", "zombie": "ZMB", "mummy": "MUM", "goblin": "GOB",
            "orc": "ORC", "gargoyle": "GAR", "unknown": "???"}.get(t, t[:3].upper())


# ============================================================================
# the panel
# ============================================================================

LAYERS = ["doors", "monsters", "marks", "special", "squares", "furniture", "arrows"]


class Editor(QtWidgets.QWidget):

    def __init__(self):
        super(Editor, self).__init__()
        self.setWindowTitle("Quest editor")
        self.resize(1500, 900)
        self.model = Model()

        self.board = Board()
        self.board.model = self.model
        self.board.clicked.connect(self.on_click)
        self.board.dragged.connect(self.on_drag)
        self.board.hovered.connect(self.on_hover)

        self.quest = QtWidgets.QComboBox()
        for q in QUESTS:
            self.quest.addItem("%s  %s" % (q, self.model.manual[q]["title"]), q)
        self.quest.currentIndexChanged.connect(self.on_quest)

        self.layer = QtWidgets.QComboBox()
        self.layer.addItems(LAYERS)
        self.layer.currentIndexChanged.connect(self.on_layer)

        self.value = QtWidgets.QComboBox()

        self.scan = QtWidgets.QCheckBox("scan")
        self.scan.setChecked(True)
        self.scan.toggled.connect(self.on_show)
        self.parse = QtWidgets.QCheckBox("parse")
        self.parse.setChecked(True)
        self.parse.toggled.connect(self.on_show)

        self.fixview = QtWidgets.QPlainTextEdit()
        self.fixview.setReadOnly(True)
        self.fixview.setMaximumHeight(150)
        self.log = QtWidgets.QPlainTextEdit()
        self.log.setReadOnly(True)
        for w in (self.fixview, self.log):
            w.setFont(QtGui.QFont("Consolas", 8))
            w.setLineWrapMode(QtWidgets.QPlainTextEdit.NoWrap)

        self.status = QtWidgets.QLabel("ready")

        b_apply = QtWidgets.QPushButton("Apply")
        b_apply.setToolTip("save manual.json, run step 9, rebuild the scene")
        b_apply.clicked.connect(self.apply)
        b_undo = QtWidgets.QPushButton("Undo")
        b_undo.clicked.connect(self.undo)
        b_revert = QtWidgets.QPushButton("Revert")
        b_revert.clicked.connect(self.revert)

        side = QtWidgets.QVBoxLayout()
        form = QtWidgets.QFormLayout()
        form.addRow("quest", self.quest)
        form.addRow("layer", self.layer)
        form.addRow("place", self.value)
        side.addLayout(form)
        row = QtWidgets.QHBoxLayout()
        row.addWidget(self.scan)
        row.addWidget(self.parse)
        row.addStretch(1)
        side.addLayout(row)
        tip = QtWidgets.QLabel(
            "Left click places, right click removes. Furniture drags out a "
            "footprint. Cyan means the hand put it there, not a detector. "
            "Ctrl+Z undoes; nothing reaches disk until Apply.")
        tip.setWordWrap(True)
        side.addWidget(tip)
        side.addWidget(QtWidgets.QLabel("this quest's fix"))
        side.addWidget(self.fixview)
        side.addWidget(b_undo)
        side.addWidget(b_revert)
        side.addWidget(b_apply)
        side.addWidget(QtWidgets.QLabel("log"))
        side.addWidget(self.log, 1)
        panel = QtWidgets.QWidget()
        panel.setLayout(side)
        # Not a fixed width: Houdini runs at whatever UI scale the display
        # asks for, and a panel sized in pixels clips its own buttons there.
        panel.setMinimumWidth(360)
        panel.setMaximumWidth(460)
        panel.setSizePolicy(QtWidgets.QSizePolicy.Preferred,
                            QtWidgets.QSizePolicy.Preferred)

        main = QtWidgets.QVBoxLayout(self)
        body = QtWidgets.QHBoxLayout()
        body.addWidget(self.board, 1)
        body.addWidget(panel, 0)
        main.addLayout(body, 1)
        main.addWidget(self.status)

        QtGui.QShortcut(QtGui.QKeySequence("Ctrl+Z"), self, self.undo)
        self.on_layer()
        self.refresh()

    # -- state -----------------------------------------------------------

    @property
    def q(self):
        return self.quest.currentData()

    def on_show(self):
        self.board.show_scan = self.scan.isChecked()
        self.board.show_parse = self.parse.isChecked()
        self.board.update()

    def on_quest(self):
        self.board.set_quest(self.q)
        self.refresh()

    def on_layer(self):
        layer = self.layer.currentText()
        opts = {"doors": ["auto (nearest wall)", "N", "W"],
                "monsters": _sprite_names("monster", ["orc"]),
                "marks": LETTERS,
                "special": SPECIALS,
                "squares": ["in (right click puts it out)"],
                "furniture": _sprite_names("furniture", ["table"]),
                "arrows": ["N", "S", "W", "E"]}[layer]
        self.value.clear()
        self.value.addItems(opts)
        self.value.setEditable(layer == "furniture")
        self.board.drag_kind = (layer == "furniture")
        self.board.update()

    def refresh(self):
        fix = self.model.manual[self.q].get("fix", {})
        self.fixview.setPlainText(json.dumps(fix, indent=1) if fix else "(none)")
        dirty = ", ".join(sorted(self.model.dirty))
        self.setWindowTitle("Quest editor%s"
                            % ("   unsaved: " + dirty if dirty else ""))
        self.board.update()

    def say(self, msg):
        self.status.setText(msg)

    def note(self, msg):
        self.log.appendPlainText(msg)
        bar = self.log.verticalScrollBar()
        bar.setValue(bar.maximum())

    def on_hover(self, x, y):
        m, q = self.model, self.q
        bits = []
        for layer in ("doors", "monsters", "marks", "special"):
            for row, hand in m.rows(q, layer):
                if row[0] == x and row[1] == y:
                    bits.append("%s %s%s" % (layer[:-1], row[2],
                                             " (hand)" if hand else ""))
        for f in m.furniture(q):
            if f[0] <= x <= f[2] and f[1] <= y <= f[3]:
                bits.append("furniture %s" % f[4])
        self.say("(%d,%d) %s   %s"
                 % (x, y, "in play" if m.grid(q)[y][x] == "o" else "SHADED OUT",
                    "   ".join(bits)))

    # -- clicks ----------------------------------------------------------

    def on_click(self, x, y, fx, fy, button, mods):
        right = button == int(QtCore.Qt.RightButton.value)
        layer = self.layer.currentText()
        v = self.value.currentText().strip()
        m, q = self.model, self.q
        try:
            if layer == "doors":
                dx, dy, o = _wall(x, y, fx, fy, v if v in ("N", "W") else None)
                msg = "door (%d,%d)%s: %s" % (
                    dx, dy, o, m.delete(q, "doors", [dx, dy, o]) if right
                    else m.add(q, "doors", [dx, dy, o]))
            elif layer in ("monsters", "marks", "special"):
                msg = "%s (%d,%d) %s: %s" % (
                    layer[:-1], x, y, "" if right else v,
                    m.delete(q, layer, [x, y]) if right
                    else m.add(q, layer, [x, y, v]))
            elif layer == "squares":
                msg = "square (%d,%d): %s" % (x, y, m.set_square(q, x, y, not right))
            elif layer == "furniture":
                msg = "furniture (%d,%d): %s" % (
                    x, y, m.del_furniture(q, x, y) if right
                    else m.add_furniture(q, x, y, x, y, v))
            elif layer == "arrows":
                msg = "arrow (%d,%d): %s" % (
                    x, y, m.del_arrow(q, x, y) if right else m.add_arrow(q, x, y, v))
        except Exception:
            self.note(traceback.format_exc())
            return
        self.note(msg)
        self.say(msg)
        self.refresh()

    def on_drag(self, x0, y0, x1, y1):
        v = self.value.currentText().strip()
        msg = self.model.add_furniture(self.q, x0, y0, x1, y1, v)
        self.note("furniture (%d,%d)-(%d,%d): %s" % (x0, y0, x1, y1, msg))
        self.refresh()

    # -- the buttons -----------------------------------------------------

    def undo(self):
        self.note("undo" if self.model.undo_last() else "nothing to undo")
        self.refresh()

    def revert(self):
        if self.model.dirty:
            ask = QtWidgets.QMessageBox.question(
                self, "Revert", "Throw away the unsaved edits to %s?"
                % ", ".join(sorted(self.model.dirty)))
            if ask != QtWidgets.QMessageBox.Yes:
                return
        self.model.reload()
        self.board.model = self.model
        self.note("reloaded manual.json")
        self.refresh()

    def apply(self):
        m = self.model
        if not m.dirty:
            self.note("nothing to save")
            return
        done = m.save()
        self.note("manual.json: rewrote %s" % ", ".join(done))
        out, ok = _run(ASSEMBLE, PARSE)
        self.note(out)
        if not ok:
            self.note("*** step 9 refused it - manual.json is saved, the data is "
                      "not. Fix what it says and Apply again.")
            self.say("step 9 refused it")
            return
        out, ok = _run(BUILD, HIP)
        self.note(out)
        self.say("applied" if ok else "step 9 ran, the scene rebuild did not")
        m.reload()
        self.board.model = m
        self.refresh()


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


def _run(path, cwd):
    """A pipeline script, in this process, with what it printed captured.

    SystemExit is how 09_assemble.py says no - a stale fix, a row off the
    board - and its message is the useful half of this whole tool, so it is
    caught and shown rather than allowed to take the panel with it.
    """
    buf = io.StringIO()
    here = os.getcwd()
    try:
        os.chdir(cwd)
        with contextlib.redirect_stdout(buf):
            runpy.run_path(path, run_name="__main__")
        return buf.getvalue().rstrip(), True
    except SystemExit as e:
        return (buf.getvalue() + "\n" + str(e)).strip(), False
    except Exception:
        return (buf.getvalue() + "\n" + traceback.format_exc()).strip(), False
    finally:
        os.chdir(here)


_WIN = None


def show():
    global _WIN
    if _WIN is not None:
        _WIN.close()
    _WIN = Editor()
    _WIN.setParent(hou.qt.mainWindow(), QtCore.Qt.Window)
    _WIN.show()
    return _WIN
