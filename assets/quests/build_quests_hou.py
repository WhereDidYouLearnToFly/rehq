"""Build /obj/quest_01 .. /obj/quest_10 from assets/quests/quests_data.json.

Each quest becomes one geo object:

    board_in -> CORE -> room_id -> in_play -> clean_empty -> BOARD ------.
    entities (python SOP, the quest's own data baked in) -> flat_colour - OUT

BOARD is the shared 26x19 board from /obj/heroquest_base/OUT with the squares
shaded out of this quest's map blasted away.

It keeps the base's flat per-room colour. That colour is a data channel and
not decoration: it is what assets/quests_to_asm.py flood-fills to recover the
22 room rectangles out of a rendered PNG, so nothing in this chain may average
it, blur it across a room boundary, or flatten it to one board colour. The
hand-built /obj/quest_0, which predates this script, keeps it the same way -
it recolours one group and leaves the rest of the palette alone.

room_id turns the base's room0..room21 prim groups into an int prim attribute
`room`: 0..21 the way rooms.json numbers them, and -1 for the corridor. It
runs before the blast, while a prim number is still y*26+x.

The entities carry `room` too, for the square they stand on, and they have to:
a merge fills in an attribute the other input is missing with its default, so
entity prims with no `room` of their own would every one of them come out
claiming room 0. It is also the thing the asm side wants - QuestMonster has no
room field precisely because the square already says it.

entities is one flat quad per door, monster, furniture piece, note letter,
arrow and special square, each at its own height so a top view stacks them in
a sensible order. kind/name/orient and the board square in cellx/celly are
PRIM attributes and the colour is a prim Cd - both deliberately:

  - a point Cd on this input would hand every board point a default white one
    when the merge runs, and point Cd beats prim Cd in the viewport, so the
    whole board would go white;
  - a flat-coloured face is a thing a render can read a colour back off,
    which is the same reason the room colours are what they are.

Each entity also wears the symbol the pack actually prints for it. The images
are cut out of the scans by map-ai-parsing/work/11_sprites.py, one per symbol,
and sit in sprites/ next to this file with an index.json saying what is there.
A quad whose kind and name match a sprite gets a material built from it, UVs,
and its exact printed footprint - no inset, so the art lands where the ink
landed. A quad with no sprite - a special square is a flat fill and has no
symbol to cut - keeps the inset and shows as its colour.

A textured entity therefore carries a WHITE Cd - the viewport and the renderer
both multiply the texture by it, and a green monster disc times a red
"monster" Cd comes out black. Its separation colour moves to a `flat` prim
attribute instead, so nothing is lost.

The flat_colour node is the switch between the two, and it is bypassed.
Un-bypass it to drop every material and copy `flat` back into Cd, which gives
the flat-colour board a readback wants; leave it bypassed to see the quests as
drawn.

Run it from Houdini:  exec(open(".../build_quests_hou.py").read())
Re-running rebuilds all ten from scratch, and the materials with them. Nothing
else in the scene is touched.
"""
import os
import json

import hou

# The digitised quests live next to the .hip file.
DATA_FILE = os.path.join(hou.text.expandString("$HIP"), "quests_data.json")
DATA = json.load(open(DATA_FILE))["quests"]
W, H = 26, 19
ROOM_COUNT = 22
BASE = "/obj/heroquest_base/OUT"
obj = hou.node("/obj")

# room0..room21 arrive as prim groups on the base. Reading them here rather
# than re-reading rooms.json keeps the scene its own source of truth, and it
# has to happen before the blast, while a prim number is still y*26+x.
ROOM_ID_VEX = """// GENERATED - see build_quests_hou.py
// The base carries the 22 rooms as prim groups. Turn them into the id
// rooms.json and quests_data.json's rooms_used already use, and leave the
// corridor - the ring and the cross - at -1.
//
// -1 and not 0: everything on this side of the pipeline numbers rooms from
// zero, and quests_to_asm.py is the one place that renumbers to the asm's
// ROOM_CORRIDOR = 0, rooms 1..22.
i@room = -1;
for (int i = 0; i < %d; i++) {
    if (inprimgroup(0, sprintf("room%%d", i), @primnum)) {
        i@room = i;
        break;
    }
}
""" % ROOM_COUNT

def read_board():
    """(room_map, room_size) off the base's prim groups.

    room_map is 19 rows of 26 room ids, -1 for corridor; room_size is how many
    squares each room has, which is what makes "wholly in play" a question
    that can be asked. Both come from the scene rather than from rooms.json,
    so there is one source of truth and it is the one being built against.
    """
    base = hou.node(BASE)
    if base is None:
        raise RuntimeError("%s is missing - the board has to exist first" % BASE)
    g = base.geometry()
    if len(g.prims()) != W * H:
        raise RuntimeError("%s has %d prims, expected %d (%dx%d)"
                           % (BASE, len(g.prims()), W * H, W, H))
    room_map = [[-1] * W for _ in range(H)]
    room_size = [0] * ROOM_COUNT
    for i in range(ROOM_COUNT):
        grp = g.findPrimGroup("room%d" % i)
        if grp is None:
            raise RuntimeError("%s has no room%d group" % (BASE, i))
        for p in grp.prims():
            room_map[p.number() // W][p.number() % W] = i
            room_size[i] += 1
    return room_map, room_size


ROOM_MAP, ROOM_SIZE = read_board()

SPRITE_DIR = os.path.join(hou.text.expandString("$HIP"), "sprites")
MAT = "/mat"
MAT_PREFIX = "qsym_"


def read_sprites():
    """{kind: {name: {file, w, h}}} - the symbols step 11 cut, or {} if none.

    Missing sprites are not an error. The .hip is useful without them, it
    just shows coloured tiles, so a scene built before step 11 has been run
    still builds.
    """
    idx = os.path.join(SPRITE_DIR, "index.json")
    if not os.path.exists(idx):
        print("no %s - building without symbols; run map-ai-parsing/work/"
              "11_sprites.py to cut them" % idx)
        return {}
    return json.load(open(idx))["sprites"]


SPRITES = read_sprites()

FLAT_COLOUR_VEX = """// GENERATED - see build_quests_hou.py
// Bypassed, and meant to stay that way while anyone is looking at the scene.
// Un-bypass it to take the printed symbols off and put the flat separation
// colours back - one colour per kind, nothing textured, which is what a
// readback of a render can actually tell apart.
//
// Two things and not one: dropping the material is not enough on its own,
// because a textured prim carries a white Cd so the texture is not tinted,
// and white is not a colour anything could separate on.
s@shop_materialpath = "";
v@Cd = v@flat;
"""


def build_materials():
    """One principled shader per symbol, under /mat.

    basecolor_useTextureAlpha is the whole trick: the sprites are RGBA with
    the board cut away, so the same image is the colour and the mask and
    there is no second texture to keep in step with the first.
    """
    mat = hou.node(MAT)
    for n in mat.children():
        if n.name().startswith(MAT_PREFIX):
            n.destroy()
    made = 0
    for kind in sorted(SPRITES):
        for name in sorted(SPRITES[kind]):
            sh = mat.createNode("principledshader::2.0",
                                "%s%s_%s" % (MAT_PREFIX, kind, name))
            sh.parm("basecolor_useTexture").set(1)
            sh.parm("basecolor_texture").set(
                "$HIP/sprites/%s" % SPRITES[kind][name]["file"])
            sh.parm("basecolor_useTextureAlpha").set(1)
            sh.parm("rough").set(1)
            sh.parm("reflect").set(0)
            made += 1
    if made:
        mat.layoutChildren()
    return made

ENTITY_CODE = '''# GENERATED - quest entities for %(name)s
# One flat quad per entity, drawn at its footprint on the board. kind/name say
# what it is; cellx/celly is the board square (x 0..25 left to right, y 0..18
# top to bottom, matching the printed quest map) and cellw/cellh its size in
# squares. All of it is on the PRIMITIVE, colour included - see the module
# docstring in build_quests_hou.py for why it may not be on the point.
node = hou.pwd()
geo = node.geometry()
DATA = %(data)s
ROOM_MAP = %(room_map)s
SPRITES = %(sprites)s
MAT_PATH = "%(mat)s/%(prefix)s%%s_%%s"

ORIGIN_X, ORIGIN_Z = -12.5, -9.0    # world position of the centre of square 0,0

# Height above the board, and so the order a top view stacks them in: the
# shaded square underneath, then the furniture standing on it, then the door
# in the wall, then whoever is standing there, then the note letter on top.
LAYER = {"special": 0.05, "furniture": 0.12, "door": 0.20,
         "monster": 0.28, "arrow": 0.34, "mark": 0.40}

# Flat, and checked against the board palette by report() - two regions the
# same colour is two regions a render cannot tell apart.
COLOUR = {
    "door":      (1.00, 1.00, 1.00),
    "monster":   (0.90, 0.10, 0.10),
    "furniture": (0.60, 0.40, 0.15),
    "mark":      (0.95, 0.95, 0.20),
    "arrow":     (0.10, 0.90, 0.60),
    "special":   (0.95, 0.35, 0.60),
}
# The two special fills are different things in the quest notes - a trap and a
# pool - so they get different colours rather than one shared "special".
COLOUR_SPECIAL = {"orange": (1.00, 0.60, 0.20), "deep_red": (0.55, 0.05, 0.12)}

INSET = 0.06        # so the board colour still shows between the tiles
TOKEN = 0.68        # a figure is a token on a square, not the whole square
MARK = 0.44         # a note letter is smaller again, it sits on top of both
DOOR_T = 0.18       # a door is a bar across the wall it is in

for n, d in (("kind", ""), ("name", ""), ("orient", ""), ("shop_materialpath", "")):
    geo.addAttrib(hou.attribType.Prim, n, d)
for n in ("cellx", "celly", "cellw", "cellh"):
    geo.addAttrib(hou.attribType.Prim, n, 0)
geo.addAttrib(hou.attribType.Prim, "room", -1)
geo.addAttrib(hou.attribType.Prim, "Cd", (1.0, 1.0, 1.0))
# The separation colour, kept out of Cd because a textured prim needs a white
# Cd: the viewport and the renderer both multiply the texture by it, and a
# green monster disc times a red "monster" Cd comes out black. flat_colour
# puts it back in Cd when the symbols are switched off.
geo.addAttrib(hou.attribType.Prim, "flat", (1.0, 1.0, 1.0))
geo.addAttrib(hou.attribType.Vertex, "uv", (0.0, 0.0, 0.0))
geo.addAttrib(hou.attribType.Global, "title", "")
geo.addAttrib(hou.attribType.Global, "wandering", "")
geo.addAttrib(hou.attribType.Global, "quest", 0)
geo.setGlobalAttribValue("title", DATA["title"])
geo.setGlobalAttribValue("wandering", DATA["wandering"])
geo.setGlobalAttribValue("quest", DATA["n"])

groups = {}


def art(kind, name):
    """Is there a cut-out symbol for this? Doors and arrows are indexed by
    their orientation rather than by their name, so they say which."""
    return name in SPRITES.get(kind, {})


def tile(kind, name, cellx, celly, cellw, cellh, cx, cz, w, h, orient="",
         cd=None, sprite=None):
    """One entity. cx,cz is its centre and w,h its size, both in board squares.

    cellx/celly/cellw/cellh is the square it is ON, which is not the same
    thing: a door is a bar a fifth of a square wide sitting on the wall
    between two squares, and it is recorded against one of them.
    """
    y = LAYER[kind]
    x0, x1 = ORIGIN_X + cx - w * 0.5, ORIGIN_X + cx + w * 0.5
    z0, z1 = ORIGIN_Z + cz - h * 0.5, ORIGIN_Z + cz + h * 0.5
    poly = geo.createPolygon()
    # v runs the other way from z: the sprite's first row is the top of the
    # printed map, which is the SMALLEST z, and v = 1 there.
    for (px, pz), uv in (((x0, z0), (0.0, 1.0)), ((x1, z0), (1.0, 1.0)),
                         ((x1, z1), (1.0, 0.0)), ((x0, z1), (0.0, 0.0))):
        pt = geo.createPoint()
        pt.setPosition(hou.Vector3(px, y, pz))
        poly.addVertex(pt).setAttribValue("uv", (uv[0], uv[1], 0.0))
    sym = sprite or name
    has_art = art(kind, sym)
    if has_art:
        poly.setAttribValue("shop_materialpath", MAT_PATH %% (kind, sym))
    poly.setAttribValue("kind", kind)
    poly.setAttribValue("name", name)
    poly.setAttribValue("orient", orient)
    poly.setAttribValue("cellx", int(cellx)); poly.setAttribValue("celly", int(celly))
    poly.setAttribValue("cellw", int(cellw)); poly.setAttribValue("cellh", int(cellh))
    poly.setAttribValue("room", ROOM_MAP[int(celly)][int(cellx)])
    flat = cd or COLOUR[kind]
    poly.setAttribValue("flat", flat)
    poly.setAttribValue("Cd", (1.0, 1.0, 1.0) if has_art else flat)
    if kind not in groups:
        groups[kind] = geo.createPrimGroup(kind)
    groups[kind].add(poly)
    return poly


# The sizes below come in pairs: the printed footprint when there is a symbol
# to put on it, and a smaller token when there is not. A sprite was cut at
# exactly one square (or exactly the piece's footprint), so shrinking the quad
# would shrink the art off the square it was drawn on.

for x, y, o in DATA["doors"]:
    # A door is the NORTH or the WEST wall of square (x, y), so it straddles
    # the edge - the quad is centred on the wall, and half of it lies in the
    # next square, exactly as the sprite was cut.
    cx, cz = (x - 0.5, y) if o == "W" else (x, y - 0.5)
    if art("door", o):
        w = h = 1.0
    elif o == "W":
        w, h = DOOR_T, 1 - 2 * INSET
    else:
        w, h = 1 - 2 * INSET, DOOR_T
    tile("door", "door", x, y, 1, 1, cx, cz, w, h, o, sprite=o)

for x, y, t in DATA["monsters"]:
    s = 1.0 if art("monster", t) else TOKEN
    tile("monster", t, x, y, 1, 1, x, y, s, s)

for x0, y0, x1, y1, kind in DATA["furniture"]:
    w, h = x1 - x0 + 1, y1 - y0 + 1
    pad = 0.0 if art("furniture", kind) else 2 * INSET
    tile("furniture", kind, x0, y0, w, h,
         (x0 + x1) * 0.5, (y0 + y1) * 0.5, w - pad, h - pad)

for x, y, L in DATA["marks"]:
    s = 1.0 if art("mark", L) else MARK
    tile("mark", L, x, y, 1, 1, x, y, s, s)

for x, y, o in DATA["arrows"]:
    s = 1.0 if art("arrow", o) else TOKEN
    tile("arrow", "escape", x, y, 1, 1, x, y, s, s, o, sprite=o)

# No sprite for these: an orange or deep-red square is a flat fill, and there
# is no symbol printed on it to cut out.
for x, y, t in DATA["special"]:
    tile("special", t, x, y, 1, 1, x, y, 1 - 2 * INSET, 1 - 2 * INSET,
         cd=COLOUR_SPECIAL.get(t))
'''


def prim_list(grid):
    out = []
    for y in range(H):
        for x in range(W):
            if grid[y][x] == 'o':
                out.append(y * W + x)
    # compress into ranges, the way a groupcreate basegroup reads best
    runs, s = [], None
    for i, v in enumerate(out):
        if s is None:
            s = p = v
        elif v == p + 1:
            p = v
        else:
            runs.append((s, p)); s = p = v
    if s is not None:
        runs.append((s, p))
    return ' '.join('%d' % a if a == b else '%d-%d' % (a, b) for a, b in runs)


def build(q):
    d = DATA[q]
    name = "quest_%s" % q
    old = obj.node(name)
    if old:
        old.destroy()
    geo = obj.createNode("geo", name)
    geo.setPosition(hou.Vector2(-6 + ((d["n"] - 1) % 5) * 4, -3 - ((d["n"] - 1) // 5) * 3))
    geo.addSpareParmTuple(hou.StringParmTemplate("quest_title", "Quest Title", 1,
                                                 default_value=(d["title"],)))
    geo.addSpareParmTuple(hou.StringParmTemplate("quest_wandering", "Wandering Monster", 1,
                                                 default_value=(d["wandering"],)))

    om = geo.createNode("object_merge", "board_in")
    om.parm("objpath1").set(BASE)
    core = geo.createNode("null", "CORE"); core.setFirstInput(om)
    rid = geo.createNode("attribwrangle", "room_id"); rid.setFirstInput(core)
    rid.parm("class").set(1)               # primitives
    rid.parm("snippet").set(ROOM_ID_VEX)
    grp = geo.createNode("groupcreate", "in_play"); grp.setFirstInput(rid)
    grp.parm("groupname").set("in_play")
    grp.parm("grouptype").set(0)           # primitives
    grp.parm("groupbase").set(1)
    grp.parm("basegroup").set(prim_list(d["grid"]))
    blast = geo.createNode("blast", "clean_empty"); blast.setFirstInput(grp)
    blast.parm("group").set("in_play")
    blast.parm("grouptype").set(4)
    blast.parm("negate").set(1)            # keep the group, drop the rest
    # No colour node here on purpose: the board arrives already separated into
    # one flat colour per room, and that separation is the thing being kept.
    board = geo.createNode("null", "BOARD"); board.setFirstInput(blast)

    ent = geo.createNode("python", "entities")
    ent.parm("python").set(ENTITY_CODE % dict(name=name, data=repr(d),
                                              room_map=repr(ROOM_MAP),
                                              sprites=repr(SPRITES),
                                              mat=MAT, prefix=MAT_PREFIX))

    # Bypassed. Un-bypass to strip the symbols back off and get the flat
    # colours a readback wants - see the module docstring.
    flat = geo.createNode("attribwrangle", "flat_colour"); flat.setFirstInput(ent)
    flat.parm("class").set(1)                  # primitives
    flat.parm("snippet").set(FLAT_COLOUR_VEX)
    flat.bypass(True)

    out = geo.createNode("merge", "OUT")
    out.setInput(0, board); out.setInput(1, flat)
    out.setDisplayFlag(True); out.setRenderFlag(True)
    geo.layoutChildren()
    return geo


def report():
    """Print what came out, and check the two things that would break a read.

    Room usage is the check the README leans on: a room is either in a quest
    or it is not, so a room with only some of its squares left in play is
    either the shading art crossing a room boundary or a parse that went
    wrong, and either way it is worth naming. `room` here comes off the
    base's prim groups and rooms_used came out of the scans, so the two
    agreeing is a genuine cross-check and not a tautology.

    The other check is the palette. The board says which room a square is in
    by its colour, so an entity painted a colour a room already uses is a
    region the readback would swallow into the room underneath it.
    """
    from collections import Counter

    board_cd = set()
    for p in hou.node(BASE).geometry().prims():
        board_cd.add(tuple(round(v, 3) for v in p.attribValue("Cd")))

    clash, partial = set(), []
    for q in sorted(DATA):
        g = hou.node("/obj/quest_%s/OUT" % q).geometry()
        # An entity carries a room of its own, so the board is the prims with
        # no kind on them - not everything with a room >= 0.
        board = [p for p in g.prims() if not p.attribValue("kind")]
        kinds = Counter(p.attribValue("kind") for p in g.prims() if p.attribValue("kind"))
        left = Counter(p.attribValue("room") for p in board if p.attribValue("room") >= 0)

        whole = sorted(r for r in left if left[r] == ROOM_SIZE[r])
        for r in sorted(left):
            if left[r] != ROOM_SIZE[r]:
                partial.append((q, r, left[r], ROOM_SIZE[r]))
        print("quest_%s  board=%-4d rooms=%-2d  %s"
              % (q, len(board), len(whole), dict(kinds)))
        if whole != sorted(DATA[q]["rooms_used"]):
            print("    ROOMS DISAGREE with quests_data.json rooms_used: %s vs %s"
                  % (whole, sorted(DATA[q]["rooms_used"])))

        for p in g.prims():
            # `flat` and not Cd: a textured entity's Cd is white so the
            # texture is not tinted, and the separation colour lives here.
            if p.attribValue("kind"):
                cd = tuple(round(v, 3) for v in p.attribValue("flat"))
                if cd in board_cd:
                    clash.add((q, p.attribValue("kind"), p.attribValue("name"), cd))

    for q, r, n, size in partial:
        print("partial room: quest_%s room%d has %d of its %d squares in play"
              % (q, r, n, size))

    # A door is a hole in the wall between two squares, so both of them being
    # in play is a thing that should be true and is worth saying when it is
    # not. Two of the 107 are real printed exceptions, not parse errors - the
    # capsule is plainly there on the scan and the square past it is plainly
    # shaded out. Quest 10's has note marker B sitting on the square it names,
    # which is very likely the note that explains it; quest 5's has nothing
    # on it and stays unexplained until the quest notes are transcribed.
    for q in sorted(DATA):
        grid = DATA[q]["grid"]
        marks = {(x, y): L for x, y, L in DATA[q]["marks"]}
        for x, y, o in DATA[q]["doors"]:
            nx, ny = (x - 1, y) if o == "W" else (x, y - 1)
            for sx, sy in ((x, y), (nx, ny)):
                if not (0 <= sx < W and 0 <= sy < H and grid[sy][sx] == "o"):
                    note = marks.get((x, y))
                    print("door to nowhere: quest_%s (%d,%d)%s - square (%d,%d) is "
                          "shaded out of play%s"
                          % (q, x, y, o, sx, sy,
                             "; note %r is on it" % note if note else ""))

    # Anything with no symbol on it shows as a coloured tile. The specials
    # are meant to; anything else in this list is a sprite that was not cut.
    if SPRITES:
        gap = Counter()
        for q in sorted(DATA):
            for p in hou.node("/obj/quest_%s/OUT" % q).geometry().prims():
                k = p.attribValue("kind")
                if k and k != "special" and not p.attribValue("shop_materialpath"):
                    gap[(k, p.attribValue("name"))] += 1
        for (k, n), c in sorted(gap.items()):
            print("no symbol: %s %r on %d tiles - it shows as a colour" % (k, n, c))
    for c in sorted(clash):
        print("colour clash: quest_%s %s %r is also a board colour %s" % c)
    if not clash:
        print("no entity colour collides with the %d board colours" % len(board_cd))


print("materials: %d symbols under %s" % (build_materials(), MAT))
built = []
for i in range(1, 11):
    built.append(build('%02d' % i).name())
print("built:", built)
report()
