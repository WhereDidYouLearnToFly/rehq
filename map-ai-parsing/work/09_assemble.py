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
"""
import json

grids = json.load(open("work/grids.json"))
mons = json.load(open("work/monsters.json"))
doors = json.load(open("work/doors.json"))
lets = json.load(open("work/letters.json"))
spec = json.load(open("work/special.json"))
man = json.load(open("work/manual.json"))
rooms = json.load(open("work/rooms.json"))

W, H = 26, 19


def die(q, msg):
    raise SystemExit('quest %s: %s\n  (manual.json["%s"]["fix"])' % (q, msg, q))


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
    for f in man[q]["furniture"]:
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

    out[q] = dict(n=i, title=man[q]["title"], wandering=man[q]["wandering"],
                  grid=gridstr, rooms_used=used,
                  doors=quest_doors, monsters=quest_mons,
                  furniture=man[q]["furniture"], marks=quest_marks,
                  arrows=man[q].get("arrows", []), special=quest_spec)

    sealed = []
    for ri in used:
        r = rooms["room%d" % ri]
        cells = {(r["x"] + dx, r["y"] + dy) for dx in range(r["w"]) for dy in range(r["h"])}
        # Both sides in their own parentheses: "a != b in c" chains in Python
        # and would quietly mean something else.
        if not any(((x, y) in cells) != (((x - 1, y) if o == "W" else (x, y - 1)) in cells)
                   for x, y, o in quest_doors):
            sealed.append(ri)

    print("q%s squares=%d doors=%d monsters=%d furniture=%d marks=%d rooms=%s%s"
          % (q, sum(r.count("o") for r in gridstr), len(out[q]["doors"]), len(out[q]["monsters"]),
             len(out[q]["furniture"]), len(out[q]["marks"]), used,
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
              "work/manual.json under [\"fix\"][\"doors\"]",
    "_furniture": "[x0, y0, x1, y1, kind] - the ink footprint of the piece on the map",
    "_marks": "the note letters printed on the map (A..F, X), keyed to the quest notes",
    "_fixing": "every layer here can be corrected by hand without touching a "
               "detector - see 'Fixing it by hand' at the top of "
               "map-ai-parsing/work/09_assemble.py",
    "quests": out,
}
json.dump(DOC, open("E:/github/rehq/assets/quests/quests_data.json", "w"), indent=1)
print("wrote assets/quests/quests_data.json")
