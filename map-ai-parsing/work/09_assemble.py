"""Step 9 - put the layers together into one quest file, and let a human win.

Squares that carry something - a monster, a letter, a special fill, a piece of
furniture - are forced in play, whatever step 3 thought: the map only draws on
squares that are in the quest.

Room usage is worked out against the 22 room rectangles of the printed board
(work/rooms.json, read out of /obj/heroquest_base). It doubles as the integrity
check: a room should come out wholly in or wholly out, and in all ten quests it
does, bar two that are genuinely carved by an overlay tile - quest 1's tavern
across room14, quest 10's dragon lair across rooms 3 and 4.

The other check is that every room in play has a way in. Step 4 only knows the
closed white capsule, so anything the pack draws differently is silently
missing, and a sealed room is what that looks like from here.

    out: work/quests.json, copied to assets/quests/quests_data.json


Fixing it by hand
-----------------
Nothing that comes off the scans is beyond argument, and a parse nobody can
correct is worse than no parse. Every layer therefore has a hand channel, and
the hand always wins:

  furniture   manual.json["NN"]["furniture"] - the whole list, hand-written
              off the step-8 contact sheets. There is no detector to override.
  arrows      manual.json["NN"]["arrows"] - likewise.
  openings    manual.json["NN"]["openings"] - likewise. See "Halls" below.
  everything  manual.json["NN"]["fix"] - add and del against what steps 3-7
  else        found:

      "fix": {
        "doors":    {"add": [[3, 14, "W"]], "del": [[12, 12, "N"]]},
        "monsters": {"add": [[5, 5, "orc"]], "del": [[4, 0]]},
        "marks":    {"add": [[7, 2, "D"]],  "del": [[1, 1]]},
        "special":  {"add": [[7, 1, "orange"]], "del": [[24, 1]]},
        "squares":  {"in": [[3, 18]], "out": [[4, 0]]}
      }

`add` carries the whole row, the same shape the layer uses. `del` names the
square only - [x, y], or [x, y, "N"|"W"] for a door, because one square can
carry both an N and a W door. `squares` forces a board square in or out of
play when step 3 read the shading wrong.

A `del` that matches nothing, or an `add` that is already there, is an error
and stops the run. That is the point: when a detector improves and finds what
you had patched, the patch has to be noticed and removed rather than sitting
there being a lie about what the scan says.

The fixes are applied before the grid is forced and before the room and
sealed-room checks, so a hand-placed monster or door counts for both.


Halls
-----
The board's walls are not stored anywhere: two adjacent squares are separated
by a wall when their room ids differ, which is the rule game/quest_structures.i
states and the reason there is no wall list in the game either. A door is the
hole a quest punches through one of those walls.

An opening is the other thing a quest can do to one: take the wall away
entirely, so the two rooms are one room for as long as this quest lasts. The
pack does it with a printed cardboard overlay laid across the board - quest 1's
tavern over room14, quest 10's dragon lair over rooms 3 and 4 - and those are
the two the room check already reports as partial.

An opening is written exactly like a door, as the NORTH or the WEST wall of a
square, so the two index the same segment and a segment can carry one or the
other but not both.

`halls` is DERIVED from them and never written by hand: rooms joined by an
opening, transitively, come out as one group. There is no second list saying
which rooms are a hall, so there is nothing that can disagree with the walls.
"""
import json

grids = json.load(open("work/grids.json"))
mons = json.load(open("work/monsters.json"))
doors = json.load(open("work/doors.json"))
lets = json.load(open("work/letters.json"))
spec = json.load(open("work/special.json"))
# The hand-authored files live with the tool that writes them, not with the
# detector json this directory is otherwise full of - see assets/quests/README.md.
AUTHORED = "../assets/quests/"

man = json.load(open(AUTHORED + "manual.json"))
# The catalogue names the placement layers. A layer is a list in manual.json
# under the same key holding [x0, y0, x1, y1, name] rows, and every one of
# them comes out in quests_data.json - so adding a layer to catalog.json is
# all it takes to have one, here and in the editor, with no code to change.
ITEM_LAYERS = sorted(json.load(open(AUTHORED + "catalog.json"))["layers"])
rooms = json.load(open("work/rooms.json"))

W, H = 26, 19


def die(q, msg, key="fix"):
    raise SystemExit('quest %s: %s\n  (manual.json["%s"][%r])' % (q, msg, q, key))


def apply_fix(q, layer, rows, keylen):
    """rows, with this quest's fix for `layer` applied.

    keylen is how many of a row's leading values name the thing: 2 for a
    square, 3 for a door, because one square can carry both an N and a W one.
    """
    fix = man[q].get("fix", {}).get(layer, {})
    for bad in set(fix) - {"add", "del"}:
        die(q, "%s has no %r - only add and del" % (layer, bad))
    rows = [list(r) for r in rows]

    for d in fix.get("del", []):
        key = list(d)
        if len(key) != keylen:
            die(q, "%s del %r wants %d values, the square that names it"
                   % (layer, d, keylen))
        hit = [r for r in rows if r[:keylen] == key]
        if not hit:
            die(q, "%s del %r matches nothing - the parse no longer says that, "
                   "so the fix is stale and should go" % (layer, d))
        for r in hit:
            rows.remove(r)

    for a in fix.get("add", []):
        a = list(a)
        if any(r[:keylen] == a[:keylen] for r in rows):
            die(q, "%s add %r is already there - the parse found it, so the fix "
                   "is stale and should go" % (layer, a))
        rows.append(a)

    for r in rows:
        if not (0 <= r[0] < W and 0 <= r[1] < H):
            die(q, "%s %r is off the 26x19 board" % (layer, r))
    return rows


# Square to room id, -1 for the corridor. The rectangles overlap on exactly
# one square - (17,13), claimed by both room17 and room21, which is the L that
# keeps data/board.asm out of the build - so they are laid down lowest id
# first and the higher one wins, deterministically rather than by dict order.
ROOM_AT = [[-1] * W for _ in range(H)]
for _name in sorted(rooms, key=lambda s: int(s[4:])):
    _r = rooms[_name]
    for _dy in range(_r["h"]):
        for _dx in range(_r["w"]):
            ROOM_AT[_r["y"] + _dy][_r["x"] + _dx] = int(_name[4:])


def _side(x, y, o):
    """The square on the other side of this segment."""
    return (x - 1, y) if o == "W" else (x, y - 1)


def openings_of(q, quest_doors, gridstr):
    """This quest's hand-written openings, checked against the board.

    Every one of these is a claim that a wall the board has is not there this
    quest, so every one of them has to name a wall that exists - the same rule
    as a del that matches nothing, and for the same reason.
    """
    rows = [list(o) for o in man[q].get("openings", [])]
    seen = set()
    for o in rows:
        if len(o) != 3 or o[2] not in ("N", "W"):
            die(q, 'opening %r wants [x, y, "N"|"W"]' % (o,), "openings")
        x, y, side = o
        if not (0 <= x < W and 0 <= y < H):
            die(q, "opening %r is off the 26x19 board" % (o,), "openings")
        if tuple(o) in seen:
            die(q, "opening %r is in the list twice" % (o,), "openings")
        seen.add(tuple(o))
        nx, ny = _side(x, y, side)
        if not (0 <= nx < W and 0 <= ny < H):
            die(q, "opening %r is the outside edge of the board, not a wall "
                   "between two squares" % (o,), "openings")
        if gridstr[y][x] != "o" or gridstr[ny][nx] != "o":
            die(q, "opening %r has a square out of play on one side - open a "
                   "wall into a room the quest does not use and the room is "
                   "still not in it" % (o,), "openings")
        if o in [list(d) for d in quest_doors]:
            die(q, "opening %r already carries a door - a segment is a wall, a "
                   "door or a gap, not two of them" % (o,), "openings")
        a, b = ROOM_AT[y][x], ROOM_AT[ny][nx]
        if a == b:
            die(q, "opening %r has no wall to remove - both squares are %s"
                   % (o, "room%d" % a if a >= 0 else "corridor"), "openings")
    rows.sort(key=lambda o: (o[1], o[0], o[2]))
    return rows


def has_way_in(ri, segments):
    """Does any of `segments` straddle room ri's boundary?

    Both sides in their own parentheses: "a != b in c" chains in Python and
    would quietly mean something else.
    """
    r = rooms["room%d" % ri]
    cells = {(r["x"] + dx, r["y"] + dy)
             for dx in range(r["w"]) for dy in range(r["h"])}
    return any(((x, y) in cells) != (_side(x, y, o) in cells)
               for x, y, o in segments)


def halls_of(quest_open):
    """Rooms an opening has joined, transitively. Derived, never written."""
    parent = {}

    def find(k):
        parent.setdefault(k, k)
        while parent[k] != k:
            parent[k] = parent[parent[k]]
            k = parent[k]
        return k

    for x, y, side in quest_open:
        nx, ny = _side(x, y, side)
        a, b = ROOM_AT[y][x], ROOM_AT[ny][nx]
        if a < 0 or b < 0:
            continue                    # opened onto the corridor, not a hall
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb
    groups = {}
    for k in list(parent):
        groups.setdefault(find(k), set()).add(k)
    return sorted(sorted(g) for g in groups.values() if len(g) > 1)


out = {}
for i in range(1, 11):
    q = "%02d" % i

    # The detectors, then the hand. Doors keep step 4's score off the row.
    quest_doors = apply_fix(q, "doors", [d[:3] for d in doors[q]], 3)
    quest_mons = apply_fix(q, "monsters", mons[q], 2)
    quest_marks = apply_fix(q, "marks", [[x, y, L] for x, y, L, s in lets[q]], 2)
    quest_spec = apply_fix(q, "special", spec[q], 2)
    quest_doors.sort(key=lambda d: (d[1], d[0], d[2]))
    for rows in (quest_mons, quest_marks, quest_spec):
        rows.sort(key=lambda r: (r[1], r[0]))

    grid = [list(r) for r in grids[q]]
    for rows in (quest_mons, quest_marks, quest_spec):
        for r in rows:
            grid[r[1]][r[0]] = "o"
    for f in [r for layer in ITEM_LAYERS for r in man[q].get(layer, [])]:
        for xx in range(f[0], f[2] + 1):
            for yy in range(f[1], f[3] + 1):
                if 0 <= xx < W and 0 <= yy < H:
                    grid[yy][xx] = "o"
    sq = man[q].get("fix", {}).get("squares", {})
    for bad in set(sq) - {"in", "out"}:
        die(q, "squares has no %r - only in and out" % bad)
    for x, y in sq.get("in", []):
        grid[y][x] = "o"
    for x, y in sq.get("out", []):
        grid[y][x] = "."
    gridstr = ["".join(r) for r in grid]

    used, mixed = [], []
    for name in sorted(rooms, key=lambda s: int(s[4:])):
        r = rooms[name]
        cells = [(r["x"] + dx, r["y"] + dy) for dx in range(r["w"]) for dy in range(r["h"])]
        f = sum(1 for cx, cy in cells if gridstr[cy][cx] == "o") / len(cells)
        if f > 0.9:
            used.append(int(name[4:]))
        elif f > 0.1:
            mixed.append("%s=%.2f" % (name, f))

    quest_open = openings_of(q, quest_doors, gridstr)
    halls = halls_of(quest_open)

    out[q] = dict(n=i, title=man[q]["title"], wandering=man[q]["wandering"],
                  grid=gridstr, rooms_used=used,
                  doors=quest_doors, openings=quest_open, halls=halls,
                  monsters=quest_mons,
                  marks=quest_marks,
                  arrows=man[q].get("arrows", []), special=quest_spec,
                  **{layer: man[q].get(layer, []) for layer in ITEM_LAYERS})

    # A hall is entered through any of its rooms, so the far end of one is not
    # sealed just because its own four walls are unbroken.
    segments = quest_doors + quest_open
    sealed = [ri for ri in used if not has_way_in(ri, segments)
              and not any(has_way_in(r, segments)
                          for h in halls if ri in h for r in h)]

    print("q%s squares=%d doors=%d monsters=%d items=%s marks=%d rooms=%s%s%s"
          % (q, sum(r.count("o") for r in gridstr), len(out[q]["doors"]), len(out[q]["monsters"]),
             " ".join("%s=%d" % (l, len(out[q][l])) for l in ITEM_LAYERS),
             len(out[q]["marks"]), used,
             ("  halls: " + " ".join("+".join(str(r) for r in h) for h in halls))
             if halls else "",
             ("  partial: " + " ".join(mixed)) if mixed else ""))
    if sealed:
        print("   NO WAY IN: %s - a door step 4 cannot see; read it off the scan "
              "into manual.json[\"%s\"][\"fix\"][\"doors\"][\"add\"]"
              % (", ".join("room%d" % r for r in sealed), q))

json.dump(out, open("work/quests.json", "w"), indent=1)

DOC = {
    "_source": "assets/scans/crypt_of_eternal_darkness.pdf "
               "(The Crypt of Perpetual Darkness quest pack), quest pages",
    "_grid": "26x19 squares, x 0..25 left to right, y 0..18 top to bottom of the "
             "printed map. Houdini prim index on /obj/heroquest_base/OUT is y*26+x.",
    "_grid_key": "'o' = square in play, '.' = square shaded out of play",
    "_doors": "a door is the NORTH or WEST wall of the square named, "
              "matching data/quest_data.asm. Step 4 finds the closed white "
              "capsule; anything the pack draws otherwise is hand-added in "
              "assets/quests/manual.json under [\"fix\"][\"doors\"]",
    "_openings": "a wall this quest takes away, named the same way a door is - "
                 "the NORTH or WEST wall of the square. The board's walls are "
                 "not stored: two squares are walled apart when their room ids "
                 "differ, so an opening is how a quest says two rooms are one "
                 "hall, the way the pack does it with a cardboard overlay",
    "_halls": "rooms the openings have joined, transitively - DERIVED in "
              "09_assemble.py, never hand-written, so it cannot disagree",
    "_furniture": "[x0, y0, x1, y1, kind] - the ink footprint of the piece on the map",
    "_layers": "the placement layers, listed in assets/quests/catalog.json "
               "and named as keys here - 'furniture' is one of them. Every one "
               "holds rows of the _furniture shape. The catalogue also says "
               "what each layer offers and at what size, which is what the "
               "Quest Editor places from",
    "_marks": "the note letters printed on the map (A..F, X), keyed to the quest notes",
    "_fixing": "every layer here can be corrected by hand without touching a "
               "detector - see 'Fixing it by hand' at the top of "
               "map-ai-parsing/work/09_assemble.py",
    "quests": out,
}
json.dump(DOC, open("E:/github/rehq/assets/quests/quests_data.json", "w"), indent=1)
print("wrote assets/quests/quests_data.json")
