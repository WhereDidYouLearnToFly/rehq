"""The detectors, the hand file, and the merge of the two."""
import json
import os

from .catalog import CAT
from .manualfile import _block, _splice
from .paths import H, KEYLEN, MANUAL, QUESTS, W, WORK


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
        rooms = j("rooms.json")
        # Square to room id, -1 for the corridor. The same table 09_assemble.py
        # builds, and with the same one bad square: (17,13) is claimed by both
        # room17's rectangle and room21's, so they go down lowest id first and
        # the higher one wins - deterministically, rather than by dict order.
        self.room_at = [[-1] * W for _ in range(H)]
        for name in sorted(rooms, key=lambda n: int(n[4:])):
            r = rooms[name]
            for dy in range(r["h"]):
                for dx in range(r["w"]):
                    self.room_at[r["y"] + dy][r["x"] + dx] = int(name[4:])
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

    def items(self, q, layer):
        """A catalogue layer's placed rows: [x0, y0, x1, y1, name]."""
        return self.manual[q].setdefault(layer, [])

    def all_items(self, q):
        """[(layer, row)] over every catalogue layer, in catalogue order."""
        return [(layer, row) for layer in CAT.layers
                for row in self.items(q, layer)]

    def furniture(self, q):
        return self.items(q, "furniture")

    def arrows(self, q):
        return self.manual[q].setdefault("arrows", [])

    def openings(self, q):
        return self.manual[q].setdefault("openings", [])

    def walls(self, q, grid=None):
        """The board's walls, as [x, y, "N"|"W"] segments.

        Nothing stores them. Two adjacent squares are walled apart when their
        room ids differ - the rule game/quest_structures.i states, and the
        reason there is no wall list in the game either. So this is not a
        lookup, it is the rule run over the board, which is exactly what you
        want to see on the map: what the DATA thinks the walls are, next to
        the ones the scan has printed on it.

        A segment this quest has opened is not a wall - that is what opening
        it means - so it is left out and the gap shows.

        Only segments with a square in play on one side: a wall between two
        squares the quest never uses is noise on top of a picture.
        """
        grid = grid or self.grid(q)
        gone = {tuple(o) for o in self.openings(q)}
        out = []
        for y in range(H):
            for x in range(W):
                for o, nx, ny in (("W", x - 1, y), ("N", x, y - 1)):
                    if nx < 0 or ny < 0:
                        continue
                    if self.room_at[y][x] == self.room_at[ny][nx]:
                        continue
                    if grid[y][x] != "o" and grid[ny][nx] != "o":
                        continue
                    if (x, y, o) not in gone:
                        out.append([x, y, o])
        return out

    def grid(self, q):
        """19 rows of 26, the way step 9 settles them: the shading, then every
        square carrying something forced in, then the hand's in and out."""
        g = [list(r) for r in self.grids[q]]
        for layer in ("monsters", "marks", "special"):
            for row, _h in self.rows(q, layer):
                g[row[1]][row[0]] = "o"
        for _layer, (x0, y0, x1, y1, _k) in self.all_items(q):
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

    def clear_square(self, q, x, y):
        """Right click: one step away from this square.

        Everything standing on it first, all of it in one go, and only when
        there is nothing left does the square itself go out of play. The order
        matters: a click that cleared the square AND shaded it would need two
        undos to get back what one click took, and a click that shaded a
        square with a monster still on it would be overruled by step 9, which
        forces any square carrying something back in.

        What is there is read before anything is touched, so a click that
        finds nothing to do takes no undo slot with it - Ctrl+Z then undoes
        the last edit you actually made and not the shrug before it.

        Doors and openings are not on a square, they are on one of its walls,
        and which wall you meant is a question only those two layers ask. They
        are left alone.
        """
        carried = []
        for layer in ("monsters", "marks", "special"):
            row, _hand = self.find(q, layer, [x, y])
            if row is not None:
                carried.append((layer, row))
        pieces = [(layer, r) for layer, r in self.all_items(q)
                  if r[0] <= x <= r[2] and r[1] <= y <= r[3]]
        arrows = [r for r in self.arrows(q) if list(r[:2]) == [x, y]]

        if not (carried or pieces or arrows):
            if self.grid(q)[y][x] != "o":
                return ("already nothing - left click on the squares layer "
                        "puts it back")
            return self.set_square(q, x, y, False)

        self.snapshot()
        gone = []
        for layer, row in carried:
            self.delete(q, layer, [x, y], _chain=True)
            gone.append("%s %s" % (layer[:-1], row[2]))
        a = self.arrows(q)
        for layer, piece in pieces:
            self.items(q, layer).remove(piece)
            gone.append("%s %s" % (layer, piece[4]))
        for arrow in arrows:
            a.remove(arrow)
            gone.append("arrow %s" % arrow[2])
        self.dirty.add(q)
        return "cleared " + ", ".join(gone)

    def kinds(self):
        """Every furniture name in use, whether or not step 11 has cut it.

        The picker offers these on top of the sprites, so a name you gave a
        piece last week is one you can pick today rather than retype - and a
        name with no sprite yet is still legal, step 11 cuts one for it the
        next time it runs.
        """
        return sorted({row[4] for q in QUESTS
                       for _layer, row in self.all_items(q)})

    def where(self, kind):
        """[(quest, layer, box)] - every placement of a name, all ten quests."""
        return [(q, layer, tuple(row[:4])) for q in QUESTS
                for layer, row in self.all_items(q) if row[4] == kind]

    def rename_kind(self, old, new):
        """Rename a furniture kind everywhere, in one undo step.

        The thing this tool could not do until now. A name given to a whole
        class of piece is a guess about what the drawing IS, and a guess that
        turns out wrong is wrong in every quest at once - which is nine or ten
        clicks spread over ten maps you have to find first, or this.
        """
        hits = self.where(old)
        if not hits:
            return "no piece is called %r" % old
        if old == new:
            return "same name"
        self.snapshot()
        for q in {h[0] for h in hits}:
            for layer in CAT.layers:
                for row in self.items(q, layer):
                    if row[4] == old:
                        row[4] = new
            self.dirty.add(q)
        qs = sorted({h[0] for h in hits})
        return "%s -> %s: %d piece%s in q%s" % (
            old, new, len(hits), "" if len(hits) == 1 else "s", ", q".join(qs))

    def at(self, q, layer, x, y):
        """The piece of `layer` under this square, or None."""
        hit = [r for r in self.items(q, layer)
               if r[0] <= x <= r[2] and r[1] <= y <= r[3]]
        return hit[-1] if hit else None

    def name_item(self, q, layer, x, y, kind):
        """Left click on a catalogue layer: name what is here, or place it.

        A piece already under the pointer keeps its footprint and takes the
        new name. Renaming by deleting and replacing would lose the footprint
        a drag set, and getting a 3x2 back by hand is the thing this tool
        exists to avoid.

        Nothing here yet lays the item down at the size the catalogue gives
        it, so a 3x2 is one click and not a drag you have to aim.
        """
        piece = self.at(q, layer, x, y)
        if piece is None:
            w, h = CAT.size(kind)
            return self.place_item(q, layer, x, y, x + w - 1, y + h - 1, kind)
        if piece[4] == kind:
            return "already %s" % kind
        self.snapshot()
        was, piece[4] = piece[4], kind
        self.dirty.add(q)
        return "%s -> %s, kept %dx%d" % (was, kind, piece[2] - piece[0] + 1,
                                         piece[3] - piece[1] + 1)

    def move_placements(self, kind, layer):
        """Move every placement of a name into another layer's list.

        The catalogue and the maps have to agree: an item offered by one layer
        whose pieces sit in another is a piece you cannot click on the layer
        that claims it.
        """
        hits = self.where(kind)
        moved = 0
        for q in {h[0] for h in hits}:
            self.dirty.add(q)
            for old in CAT.layers:
                if old == layer:
                    continue
                for row in [r for r in self.items(q, old) if r[4] == kind]:
                    self.items(q, old).remove(row)
                    self.items(q, layer).append(row)
                    moved += 1
            self.items(q, layer).sort(key=lambda r: (r[1], r[0]))
        return moved

    def place_item(self, q, layer, x0, y0, x1, y1, kind):
        self.snapshot()
        x1, y1 = min(x1, W - 1), min(y1, H - 1)
        self.items(q, layer).append([x0, y0, x1, y1, kind])
        self.dirty.add(q)
        return "%s %dx%d" % (kind, x1 - x0 + 1, y1 - y0 + 1)

    def add_arrow(self, q, x, y, o):
        self.snapshot()
        a = self.arrows(q)
        for old in [r for r in a if list(r[:2]) == [x, y]]:
            a.remove(old)
        a.append([x, y, o])
        self.dirty.add(q)
        return "escape %s" % o

    def add_opening(self, q, x, y, o):
        """Take the wall on one side of a square away for this quest.

        Whether there is a wall there at all is step 9's to answer - it has
        the room rectangles and it stops the run on an opening that removes
        nothing. Here it is only worth saying, because the message lands in
        the panel while you are still looking at the map.
        """
        self.snapshot()
        a = self.openings(q)
        if [x, y, o] in [list(r) for r in a]:
            return "already open"
        a.append([x, y, o])
        a.sort(key=lambda r: (r[1], r[0], r[2]))
        self.dirty.add(q)
        if self.find(q, "doors", [x, y, o])[0] is not None:
            return "wall opened - but a door is on this segment, step 9 "                   "will refuse it"
        return "wall opened"

    def del_opening(self, q, x, y, o):
        self.snapshot()
        a = self.openings(q)
        hit = [r for r in a if list(r) == [x, y, o]]
        if not hit:
            return "nothing there"
        for r in hit:
            a.remove(r)
        self.dirty.add(q)
        return "wall back"

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
