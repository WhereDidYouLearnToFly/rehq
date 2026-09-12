"""Quest editor - correct the parse by clicking on the scan.

map-ai-parsing reads the ten quest maps off the scans, and everything it
finds can be wrong. The channel for saying so is map-ai-parsing/work/
manual.json: a per-quest "fix" block of add and del rows that 09_assemble.py
applies over the detectors, and hand-written furniture, arrows and openings
lists that have no detector behind them at all. All of that is correct and none of it is
convenient - it is JSON typed by hand against a square you counted off a
picture, which is how a wrong coordinate gets in.

This is the same channel with a map in front of it. It draws the canonical
scan (map-ai-parsing/ds/cNN.png, 80 px to the square, which is why a click
lands where you think it does), draws the parse over it, and turns a click
into the fix row that says what you just said.

    left click    put the selected thing on this square
    right click   clear the square: what is on it, then the square itself
    drag          a furniture footprint, when the furniture layer is up

On the furniture layer a left click on a piece that is already there RENAMES
it and keeps its footprint, so a 3x2 stays a 3x2. The picker is editable and
offers every name already in the file as well as every one step 11 has cut a
sprite for, so a name of your own is a name you type once.

A right click is not layer work. Whatever layer is up, it takes one step away
from the square under the pointer: everything standing on it first - monster,
letter, special fill, furniture, arrow - and once nothing is left on it, the
square itself, out of play. Two clicks from a full square to a shaded one, and
the second never quietly undoes the first.

The doors and openings layers get first refusal on the nearest WALL, since
that is the thing they are for - move the pointer towards the edge you mean.
But only when there is a door or an opening on that edge to take: when there
is not, the click falls through to the square like everywhere else, so a right
click is never a shrug.

WHAT IT WRITES, AND WHY IT CANCELS RATHER THAN STACKS

09_assemble.py stops the run on a del that matches nothing or an add that is
already there - deliberately, so that a detector improving cannot leave a
patch behind quietly misrepresenting the scan. An editor that only appended
would walk straight into that: delete a monster, put it back, and the file
now holds a del and an add for the same square, the del stale the moment the
add lands.

OPENINGS

The board has no wall list: two squares are walled apart when their room ids
differ, which is the rule the game uses too. A door is the hole a quest puts
in one of those walls; an opening is the wall taken away entirely, so the two
rooms are one hall for this quest - what the pack does with a cardboard
overlay, as in quest 1's tavern and quest 10's dragon lair.

Click the wall between two rooms with the openings layer up and it is gone.
Which rooms that joins is worked out in 09_assemble.py and written to
quests_data.json as "halls"; it is never typed, so it cannot disagree with
the walls it came from.

So every edit is resolved against what the detectors actually found:

    delete a row the detectors found         ->  add it to "del"
    delete a row that is only there as "add" ->  drop that add
    add a row that "del" is hiding           ->  drop that del
    add a row the detectors never had        ->  append to "add"

which is the minimal fix for the state on screen, and never a stale one.
Furniture, arrows and openings skip all of it: those lists are the source, so
an edit there is an edit to the list.

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
import shutil
import contextlib
import runpy
import traceback

import hou
from PySide6 import QtCore, QtGui, QtWidgets

# ---------------------------------------------------------------------------
# Everything this tool reads or writes, in one place and nowhere else.
#
# Two trees, and the split is not arbitrary: map-ai-parsing/ is the pipeline -
# its scans and its json are what the scripts make and remake, and nothing
# there is drawn by a person. assets/quests/ is the authored side - the scene,
# this tool, and art. sprites/ sits on the authored side but is GENERATED, so
# the one thing you may hand it is sprites_hand/, which step 11 reads and
# never writes.
# ---------------------------------------------------------------------------
HIP = hou.text.expandString("$HIP")             # assets/quests - the .hip's own dir
ROOT = os.path.dirname(os.path.dirname(HIP))    # the repo
PARSE = os.path.join(ROOT, "map-ai-parsing")

# Ours. Everything this tool writes is here, next to the scene it edits.
MANUAL = os.path.join(HIP, "manual.json")       # every hand correction
CATALOG = os.path.join(HIP, "catalog.json")     # the items, and the layers they sit in
HAND_ART = os.path.join(HIP, "sprites_hand")    # your own drawings, never overwritten
SPRITES = os.path.join(HIP, "sprites")          # GENERATED by step 11 - do not hand-edit
BUILD = os.path.join(HIP, "build_quests_hou.py")  # Apply rebuilds the scene with this

# Theirs. Read-only, plus two scripts we run: the pipeline owns all of it.
DS = os.path.join(PARSE, "ds")                  # cNN.png, the scan behind the map
WORK = os.path.join(PARSE, "work")              # the detectors and their json
ASSEMBLE = os.path.join(WORK, "09_assemble.py")     # Apply runs this
SPRITES_STEP = os.path.join(WORK, "11_sprites.py")  # Sprite... runs this

W, H = 26, 19
QUESTS = ["%02d" % i for i in range(1, 11)]

# How many of a row's leading values name the thing, the same keylen
# 09_assemble.py applies add and del with: 2 for a square, 3 for a door,
# because one square can carry both a north and a west one.
KEYLEN = {"doors": 3, "monsters": 2, "marks": 2, "special": 2}

# The layers that are not the catalogue's: each has its own row shape and
# its own meaning, and none of them is a thing you place from a list.
FIXED_LAYERS = ["doors", "openings", "monsters", "marks", "special",
                "squares", "arrows"]

SPECIALS = ["orange", "deep_red"]
LETTERS = ["A", "B", "C", "D", "E", "F", "X"]


def _sprite_names(kind, fallback):
    """The names step 11 has cut a symbol for, so the pickers offer what the
    scene can actually draw. A kind with no sprite yet is still legal - the
    furniture picker is editable and step 11 will cut one for a new name."""
    try:
        idx = json.load(open(os.path.join(SPRITES, "index.json")))
        return sorted(idx["sprites"].get(kind, {})) or fallback
    except Exception:
        return fallback


# ============================================================================
# the data
# ============================================================================

class Catalog(object):
    """work/catalog.json - the items you can place, and which layer offers them.

    An item is a name and a footprint, and a layer is a list of them. That is
    the whole file. It exists so that adding a piece of furniture, or a whole
    new layer to keep pieces in, is something done in the tool or in a JSON
    file rather than in this source.

    A layer here is also a list in manual.json under the same key, holding
    [x0, y0, x1, y1, name] rows, and 09_assemble.py copies every one of them
    into quests_data.json. So a layer added here is a layer that exists all
    the way through, without a line of code anywhere.
    """

    def __init__(self):
        self.reload()

    def reload(self):
        self.doc = json.load(open(CATALOG))
        self.doc.setdefault("layers", {})

    @property
    def layers(self):
        return sorted(self.doc["layers"])

    def items(self, layer):
        return self.doc["layers"].setdefault(layer, [])

    def names(self, layer):
        return [i["name"] for i in self.items(layer)]

    def find(self, name):
        """(layer, item) for a name, or (None, None)."""
        for layer in self.doc["layers"]:
            for it in self.doc["layers"][layer]:
                if it["name"] == name:
                    return layer, it
        return None, None

    def size(self, name):
        """The footprint one click lays down. An unknown name is 1x1 - typing
        a new name into the place box has to keep working."""
        _layer, it = self.find(name)
        return (int(it["w"]), int(it["h"])) if it else (1, 1)

    def add(self, layer, name, w, h):
        if self.find(name)[1] is not None:
            return "%s is already in the catalogue" % name
        self.items(layer).append({"name": name, "w": int(w), "h": int(h)})
        self.items(layer).sort(key=lambda i: i["name"])
        return "added %s %dx%d to %s" % (name, w, h, layer)

    def remove(self, name):
        layer, it = self.find(name)
        if it is None:
            return "%s is not in the catalogue" % name
        self.items(layer).remove(it)
        return "removed %s from %s" % (name, layer)

    def set_size(self, name, w, h):
        _layer, it = self.find(name)
        if it is None:
            return "%s is not in the catalogue" % name
        it["w"], it["h"] = int(w), int(h)
        return "%s is now %dx%d" % (name, w, h)

    def move(self, name, layer):
        """Put an item in another layer. The placements follow - see
        Model.move_placements, which the panel calls with this."""
        old, it = self.find(name)
        if it is None:
            return "%s is not in the catalogue" % name
        if old == layer:
            return "%s is already in %s" % (name, layer)
        self.items(old).remove(it)
        self.items(layer).append(it)
        self.items(layer).sort(key=lambda i: i["name"])
        return "%s: %s -> %s" % (name, old, layer)

    def save(self):
        json.dump(self.doc, open(CATALOG, "w"), indent=1)


CAT = Catalog()


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
    # Every catalogue layer, whether or not this quest uses it - a layer that
    # writes nothing is a layer you cannot tell from one that is not there.
    for layer in CAT.layers:
        if out[-1][-1] != ",":
            out[-1] += ","
        key = '  "%s":' % layer
        out.append(key + _rows(d.get(layer, []), len(key) + 1))
    if d.get("arrows"):
        out[-1] += ","
        out.append('  "arrows":' + _rows(d["arrows"], len('  "arrows":[')))
    if d.get("openings"):
        out[-1] += ","
        out.append('  "openings":' + _rows(d["openings"],
                                           len('  "openings":[')))
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
    "opening": QtGui.QColor(205, 125, 255),
    "wall": QtGui.QColor(80, 190, 255, 150),
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


def _abbr(t):
    """A few letters that tell the ten types apart at 20 px."""
    return {"dread_warrior": "DW", "dread_sorcerer": "DS", "abomination": "ABM",
            "skeleton": "SKL", "zombie": "ZMB", "mummy": "MUM", "goblin": "GOB",
            "orc": "ORC", "gargoyle": "GAR", "unknown": "???"}.get(t, t[:3].upper())


# ============================================================================
# the panel
# ============================================================================

def all_layers():
    """The dropdown: the fixed layers, then whatever the catalogue declares."""
    return FIXED_LAYERS + CAT.layers


def has_hand_art(layer, name):
    """Is this item drawn by hand rather than cut off the scan?"""
    return os.path.exists(os.path.join(HAND_ART, layer, "%s.png" % name))


def _layer_colour(layer):
    """A stable colour per catalogue layer, so a new one is legible at once.

    furniture keeps the colour it has had; anything else is placed around the
    hue circle by its name, which is arbitrary but never changes under you.
    """
    if layer == "furniture":
        return QtGui.QColor(COL["furniture"])
    hue = (sum(ord(c) * (i + 1) for i, c in enumerate(layer)) * 47) % 360
    return QtGui.QColor.fromHsv(hue, 170, 245)


class ItemsDialog(QtWidgets.QDialog):
    """The catalogue, as a table.

    Name, footprint, and the layer that offers it - one row per item, and that
    is the whole of what an item is. The layer column is free text: a name
    that does not exist yet is a layer that does, after OK.
    """

    def __init__(self, parent):
        super(ItemsDialog, self).__init__(parent)
        self.setWindowTitle("Items")
        self.resize(560, 620)
        self.table = QtWidgets.QTableWidget(0, 4)
        self.table.setHorizontalHeaderLabels(["name", "w", "h", "layer"])
        self.table.horizontalHeader().setStretchLastSection(True)
        self.table.setSelectionBehavior(QtWidgets.QAbstractItemView.SelectRows)
        self.fill()
        b_add = QtWidgets.QPushButton("Add")
        b_add.clicked.connect(self.add)
        b_del = QtWidgets.QPushButton("Remove")
        b_del.clicked.connect(self.remove)
        buttons = QtWidgets.QDialogButtonBox(
            QtWidgets.QDialogButtonBox.Ok | QtWidgets.QDialogButtonBox.Cancel)
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        row = QtWidgets.QHBoxLayout()
        row.addWidget(b_add)
        row.addWidget(b_del)
        row.addStretch(1)
        lay = QtWidgets.QVBoxLayout(self)
        lay.addWidget(QtWidgets.QLabel(
            "A name, the footprint one click lays down, and the layer that "
            "offers it. Type a layer that does not exist and it will. Pieces "
            "already on the maps follow an item that changes layer."))
        lay.addWidget(self.table, 1)
        lay.addLayout(row)
        lay.addWidget(buttons)

    def fill(self):
        rows = [(i["name"], i["w"], i["h"], layer)
                for layer in CAT.layers for i in CAT.items(layer)]
        self.table.setRowCount(len(rows))
        for r, vals in enumerate(rows):
            for c, v in enumerate(vals):
                self.table.setItem(r, c, QtWidgets.QTableWidgetItem(str(v)))

    def add(self):
        r = self.table.rowCount()
        layer = (self.table.item(r - 1, 3).text() if r else "furniture")
        self.table.insertRow(r)
        for c, v in enumerate(["new_item", "1", "1", layer]):
            self.table.setItem(r, c, QtWidgets.QTableWidgetItem(v))
        self.table.setCurrentCell(r, 0)
        self.table.editItem(self.table.item(r, 0))

    def remove(self):
        for r in sorted({i.row() for i in self.table.selectedItems()},
                        reverse=True):
            self.table.removeRow(r)

    def rows(self):
        """The table as catalogue rows. A blank name or layer is a row you
        started and abandoned, not an item."""
        out = []
        for r in range(self.table.rowCount()):
            cell = [self.table.item(r, c) for c in range(4)]
            name, w, h, layer = [(c.text().strip() if c else "") for c in cell]
            if not name or not layer:
                continue
            try:
                w, h = max(1, int(w)), max(1, int(h))
            except ValueError:
                w = h = 1
            out.append({"name": name, "w": w, "h": h, "layer": layer})
        return out


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
        self.layer.addItems(all_layers())
        self.layer.currentIndexChanged.connect(self.on_layer)

        self.value = QtWidgets.QComboBox()

        self.scan = QtWidgets.QCheckBox("scan")
        self.scan.setChecked(True)
        self.scan.toggled.connect(self.on_show)
        self.parse = QtWidgets.QCheckBox("parse")
        self.parse.setChecked(True)
        self.parse.toggled.connect(self.on_show)
        self.walls = QtWidgets.QCheckBox("walls")
        self.walls.setChecked(True)
        self.walls.setToolTip("the walls the room rectangles imply - nothing "
                              "stores them, so this is the rule drawn out")
        self.walls.toggled.connect(self.on_show)

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
        b_items = QtWidgets.QPushButton("Items...")
        b_items.setToolTip("the catalogue: what every layer offers, and at "
                           "what size. Adds layers too. Not tied to the "
                           "layer selected above - it edits the whole file.")
        b_items.clicked.connect(self.edit_items)
        self.b_items = b_items
        b_sprite = QtWidgets.QPushButton("Sprite...")
        b_sprite.setToolTip("give the item in the place box a drawing of your "
                            "own, instead of the one cut off the scan")
        b_sprite.clicked.connect(self.set_sprite)
        b_rename = QtWidgets.QPushButton("Rename kind everywhere")
        b_rename.setToolTip("rename the furniture name in the place box "
                            "across all ten quests, in one undo step")
        b_rename.clicked.connect(self.rename_kind)
        self.b_rename = b_rename

        side = QtWidgets.QVBoxLayout()
        form = QtWidgets.QFormLayout()
        form.addRow("quest", self.quest)
        form.addRow("layer", self.layer)
        form.addRow("place", self.value)
        side.addLayout(form)
        row = QtWidgets.QHBoxLayout()
        row.addWidget(self.scan)
        row.addWidget(self.parse)
        row.addWidget(self.walls)
        row.addStretch(1)
        side.addLayout(row)
        tip = QtWidgets.QLabel(
            "Left click places. Right click clears the square - what is on "
            "it, then the square itself; the doors and openings layers try "
            "the nearest wall first. Furniture drags out a footprint. "
            "Cyan means the hand put it there, not a detector. "
            "Ctrl+Z undoes; nothing reaches disk until Apply.")
        tip.setWordWrap(True)
        side.addWidget(tip)
        side.addWidget(QtWidgets.QLabel("this quest's fix"))
        side.addWidget(self.fixview)
        side.addWidget(b_items)
        side.addWidget(b_sprite)
        side.addWidget(b_rename)
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
        self.board.show_walls = self.walls.isChecked()
        self.board.update()

    def on_quest(self):
        self.board.set_quest(self.q)
        self.refresh()

    def on_layer(self):
        layer = self.layer.currentText()
        catalogue = layer in CAT.layers
        if catalogue:
            opts = [("%s  %dx%d%s"
                     % (i["name"], i["w"], i["h"],
                        "  (own art)" if has_hand_art(layer, i["name"]) else ""))
                    for i in CAT.items(layer)]
        else:
            opts = {"doors": ["auto (nearest wall)", "N", "W"],
                    "openings": ["auto (nearest wall)", "N", "W"],
                    "monsters": _sprite_names("monster", ["orc"]),
                    "marks": LETTERS,
                    "special": SPECIALS,
                    "squares": ["in (right click clears, then shades out)"],
                    "arrows": ["N", "S", "W", "E"]}[layer]
        self.value.clear()
        self.value.addItems(opts)
        self.value.setEditable(catalogue)
        self.board.drag_kind = catalogue
        self.board.update()

    def value_name(self):
        """The place box without the size the catalogue shows next to it."""
        return self.value.currentText().split("  ")[0].strip()

    def reload_layers(self):
        """Rebuild the layer dropdown after the catalogue changed."""
        want = self.layer.currentText()
        self.layer.blockSignals(True)
        self.layer.clear()
        self.layer.addItems(all_layers())
        i = self.layer.findText(want)
        self.layer.setCurrentIndex(i if i >= 0 else 0)
        self.layer.blockSignals(False)
        self.on_layer()

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
                bits.append("furniture %s (%d placed)" % (f[4], len(m.where(f[4]))))
        for ox, oy, oo in m.openings(q):
            if ox == x and oy == y:
                bits.append("opening %s" % oo)
        self.say("(%d,%d) %s   %s"
                 % (x, y, "in play" if m.grid(q)[y][x] == "o" else "SHADED OUT",
                    "   ".join(bits)))

    # -- clicks ----------------------------------------------------------

    def on_click(self, x, y, fx, fy, button, mods):
        right = button == int(QtCore.Qt.RightButton.value)
        layer = self.layer.currentText()
        v = self.value_name()
        m, q = self.model, self.q
        try:
            if right:
                # Right click means the same thing on every layer: one step
                # away from what is under the pointer. The doors and openings
                # layers get first refusal on the nearest wall, because that
                # is the thing they are for - but only when there is one there
                # to take, so a right click never comes back as a shrug.
                msg = None
                if layer in ("doors", "openings"):
                    dx, dy, o = _wall(x, y, fx, fy, v if v in ("N", "W") else None)
                    if layer == "doors":
                        if m.find(q, "doors", [dx, dy, o])[0] is not None:
                            msg = "door (%d,%d)%s: %s" % (
                                dx, dy, o, m.delete(q, "doors", [dx, dy, o]))
                    elif [dx, dy, o] in [list(r) for r in m.openings(q)]:
                        msg = "opening (%d,%d)%s: %s" % (
                            dx, dy, o, m.del_opening(q, dx, dy, o))
                if msg is None:
                    msg = "(%d,%d): %s" % (x, y, m.clear_square(q, x, y))
            elif layer == "doors":
                dx, dy, o = _wall(x, y, fx, fy, v if v in ("N", "W") else None)
                msg = "door (%d,%d)%s: %s" % (dx, dy, o,
                                              m.add(q, "doors", [dx, dy, o]))
            elif layer == "openings":
                dx, dy, o = _wall(x, y, fx, fy, v if v in ("N", "W") else None)
                msg = "opening (%d,%d)%s: %s" % (dx, dy, o,
                                                 m.add_opening(q, dx, dy, o))
            elif layer in ("monsters", "marks", "special"):
                msg = "%s (%d,%d) %s: %s" % (layer[:-1], x, y, v,
                                             m.add(q, layer, [x, y, v]))
            elif layer == "squares":
                msg = "square (%d,%d): %s" % (x, y, m.set_square(q, x, y, True))
            elif layer in CAT.layers:
                msg = "%s (%d,%d): %s" % (layer, x, y,
                                          m.name_item(q, layer, x, y, v))
            elif layer == "arrows":
                msg = "arrow (%d,%d): %s" % (x, y, m.add_arrow(q, x, y, v))
        except Exception:
            self.note(traceback.format_exc())
            return
        self.note(msg)
        self.say(msg)
        self.refresh()

    def on_drag(self, x0, y0, x1, y1):
        layer = self.layer.currentText()
        if layer not in CAT.layers:
            return
        v = self.value_name()
        msg = self.model.place_item(self.q, layer, x0, y0, x1, y1, v)
        self.note("%s (%d,%d)-(%d,%d): %s" % (layer, x0, y0, x1, y1, msg))
        self.refresh()

    # -- the buttons -----------------------------------------------------

    def set_sprite(self):
        """Install a drawing of your own for the item in the place box.

        It is copied into sprites_hand/<layer>/<name>.png, which step 11 reads
        and never writes - so the cut off the scan is replaced and stays
        replaced, however many times the sprites are regenerated. Step 11 then
        runs, because the index is what the scene actually reads and a file
        nothing points at changes nothing.
        """
        layer = self.layer.currentText()
        if layer not in CAT.layers:
            self.say("pick a catalogue layer first - a sprite belongs to an item")
            return
        name = self.value_name()
        if not name:
            self.say("pick an item in the place box")
            return
        cur = os.path.join(HAND_ART, layer, "%s.png" % name)
        if os.path.exists(cur):
            box = QtWidgets.QMessageBox(self)
            box.setWindowTitle("Sprite")
            box.setText("%s already has a drawing of your own.\n\n%s" % (name, cur))
            pick = box.addButton("Pick another", QtWidgets.QMessageBox.AcceptRole)
            drop = box.addButton("Back to the scan", QtWidgets.QMessageBox.DestructiveRole)
            box.addButton(QtWidgets.QMessageBox.Cancel)
            box.exec()
            if box.clickedButton() is drop:
                return self.clear_sprite()
            if box.clickedButton() is not pick:
                return
        path, _f = QtWidgets.QFileDialog.getOpenFileName(
            self, "Drawing for %s" % name, HAND_ART,
            "Images (*.png *.tif *.tiff *.tga)")
        if not path:
            return
        os.makedirs(os.path.dirname(cur), exist_ok=True)
        if os.path.abspath(path) != os.path.abspath(cur):
            shutil.copyfile(path, cur)
        self.note("%s: %s -> %s" % (name, path, cur))
        out, ok = _run(SPRITES_STEP, PARSE)
        self.note(out)
        if ok:
            out, ok = _run(BUILD, HIP)
            self.note(out)
        msg = ("%s now uses your drawing" % name) if ok else "step 11 or the rebuild failed"
        self.say(msg)
        self.on_layer()
        self.refresh()

    def clear_sprite(self):
        """Drop the hand drawing and go back to the cut off the scan."""
        layer = self.layer.currentText()
        name = self.value_name()
        cur = os.path.join(HAND_ART, layer, "%s.png" % name)
        if not os.path.exists(cur):
            self.say("%s has no hand drawing - it is cut off the scan" % name)
            return
        os.remove(cur)
        self.note("removed %s" % cur)
        out, _ok = _run(SPRITES_STEP, PARSE)
        self.note(out)
        self.say("%s is back to the cut off the scan" % name)
        self.refresh()

    def edit_items(self):
        """The catalogue dialog, and what its OK means.

        The table is the whole catalogue, so OK replaces it rather than
        patching it - which is also what makes removing an item and adding a
        layer the same gesture as editing one.
        """
        before = {i["name"]: layer for layer in CAT.layers
                  for i in CAT.items(layer)}
        dlg = ItemsDialog(self)
        if not dlg.exec():
            return
        rows = dlg.rows()
        names = [r["name"] for r in rows]
        dupes = sorted({n for n in names if names.count(n) > 1})
        if dupes:
            self.say("two items called %s - the name is the key, so it has to "
                     "be unique" % ", ".join(dupes))
            return
        moving = [r for r in rows
                  if r["name"] in before and before[r["name"]] != r["layer"]]
        if moving:
            self.model.snapshot()
        CAT.doc["layers"] = {}
        for r in rows:
            CAT.items(r["layer"]).append(
                {"name": r["name"], "w": r["w"], "h": r["h"]})
        for layer in CAT.layers:
            CAT.items(layer).sort(key=lambda i: i["name"])
        CAT.save()
        moved = sum(self.model.move_placements(r["name"], r["layer"])
                    for r in moving)
        orphan = sorted(n for n in before
                        if n not in names and self.model.where(n))
        self.reload_layers()
        msg = "catalogue: %d items in %d layer%s" % (
            len(rows), len(CAT.layers), "" if len(CAT.layers) == 1 else "s")
        if moved:
            msg += ", %d placement%s followed" % (moved, "" if moved == 1 else "s")
        if orphan:
            msg += "; still on the maps but no longer offered: " + ", ".join(orphan)
        self.note(msg)
        self.say(msg)
        self.refresh()

    def rename_kind(self):
        """Rename a furniture name across all ten quests."""
        old = self.value.currentText().strip()
        m = self.model
        hits = m.where(old)
        if not hits:
            self.say("no piece is called %r - pick its name in the place box" % old)
            return
        new, ok = QtWidgets.QInputDialog.getText(
            self, "Rename kind",
            "%d piece%s called %r, in q%s.\n\nNew name:"
            % (len(hits), "" if len(hits) == 1 else "s", old,
               ", q".join(sorted({q for q, _b in hits}))),
            text=old)
        new = new.strip()
        if not ok or not new or new == old:
            return
        msg = m.rename_kind(old, new)
        layer, it = CAT.find(old)
        if it is not None:
            it["name"] = new
            CAT.items(layer).sort(key=lambda i: i["name"])
            CAT.save()
        self.note(msg + "\n  " + "\n  ".join("q%s %s %s" % h for h in hits))
        self.say(msg)
        self.on_layer()
        self.value.setCurrentText(new)
        self.refresh()

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

    stderr is captured too, or a warning and half a failure go to Houdini's
    console instead of to the panel that is showing you the run.
    """
    buf = io.StringIO()
    here = os.getcwd()
    try:
        os.chdir(cwd)
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
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
