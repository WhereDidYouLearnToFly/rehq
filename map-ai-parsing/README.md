# map-ai-parsing

Turning the scanned quest pack into quest data.

`assets/scans/crypt_of_eternal_darkness.pdf` is a flat scan of *The Crypt of
Perpetual Darkness* — ten quests, one per page, a map on the top half and the
quest notes below. No text layer, no vectors, just photographs of paper. This
directory is the pipeline that reads the ten maps off those photographs and
writes `assets/quests/quests_data.json`, plus the record of how it was done and
how far it can be trusted.

The output feeds two things: `assets/quests/build_quests_hou.py`, which builds
`/obj/quest_01 … /obj/quest_10` in `assets/quests/quests.hipnc`, and eventually
`assets/quests_to_asm.py`, whose docstring says the quest half "has no source
file yet". This is that source file.

Step 11 also cuts the printed symbols themselves out of the scans — one image
per monster type, note letter, door, arrow and furniture kind — into
`assets/quests/sprites/`. That is what makes the .hip show a quest as it was
drawn rather than as coloured rectangles, and it is the beginning of the
sprite set the ZX side will want.

---

## The plan

The board is the same in all ten maps. It is the printed HeroQuest board:
26×19 squares, 22 rooms at fixed rectangles, a corridor ring and cross. What
differs per quest is an overlay — which squares are shaded out of play, where
the doors are, which monsters stand where, what furniture is placed, and the
lettered note markers.

So the job is not "read a map" but "read the overlay", and that suggests the
shape of the whole thing:

1. **Normalise first, recognise second.** Every technique that failed did so
   because it ran on the raw scans, where the page scale differs by a percent
   or two between pages and nothing lines up. Find the printed frame, warp
   every map onto one canonical raster where a square is exactly 80×80 px, and
   suddenly a door is the same object in pixels in all ten maps and plain
   template matching separates it cleanly. This is the single decision the
   pipeline turns on.

2. **Let the ten maps describe the board for each other.** Take a high
   per-pixel percentile across all ten canonical maps and you get the bare
   board: the rules and walls are dark in every map so they survive, while
   monsters, furniture, letters and shading are dark in only a few and get
   voted away. Subtracting that plate's ink is what isolates furniture.

3. **Automate what is regular, look at what is not.** Squares, doors and
   letters are fixed graphics on a fixed grid — those are machine work, and
   they are exact. Furniture is line art with no two pieces alike; a table, a
   tomb, an altar and a forge have nothing in common to match against. So the
   pipeline crops the furniture out into contact sheets and a human reads them.
   Monster icons sit in between: too many to read one at a time, too varied to
   template, so they get clustered and the ~88 cluster medians are labelled
   once by eye against the reference icons the manual prints on its own
   "Wandering Monster in this Quest" lines.

4. **Check against something that was not part of the parse.** The board has
   22 room rectangles; a room is either in a quest or it is not, so every room
   coming out wholly in or wholly out is a real integrity check. And quest 1
   already existed as a hand-built Houdini node, which makes it ground truth
   nobody derived from this code.

---

## What the pipeline does

Run from this directory, in order. Steps 0–2 take a couple of minutes; the rest
are seconds.

| Step | Script | What it does | Output |
|---|---|---|---|
| 0 | `work/00_pages.py` | Renders the map half of each quest page at 300 dpi | `hi/qNN.png` |
| 1 | `work/01_frames.py` | Deskews, then finds the inner board frame on each side | `ds/qNN.png`, `work/frames.json` |
| 2 | `work/02_canon.py` | Warps to the canonical 2080×1520 raster; votes out the board plate | `ds/cNN.png`, `ds/plate.png` |
| 3 | `work/03_grid.py` | Which squares are in play | `work/grids.json` |
| 4 | `work/04_doors.py` | Doors, by template match | `work/doors.json` |
| 5 | `work/05_monsters.py` | Monster squares, clustered and typed | `work/monsters.json`, `work/clusters.png` |
| 6 | `work/06_letters.py` | Note markers A–F and X | `work/letters.json` |
| 7 | `work/07_special.py` | Orange and deep-red squares | `work/special.json` |
| 8 | `work/08_furniture.py` | Crops furniture into contact sheets to be read | `work/fmNN.png` |
| 9 | `work/09_assemble.py` | Merges every layer, checks rooms | `work/quests.json` → `assets/quests/quests_data.json` |
| 10 | `work/10_verify.py` | Draws the parse back over the scan | `assets/quests/verify/qNN.png` |
| 11 | `work/11_sprites.py` | Cuts the printed symbols out, one per symbol | `assets/quests/sprites/**.png`, `work/sprites.png` |

Needs `pymupdf`, `opencv-python`, `numpy`.

Three files in `work/` are inputs, not outputs, and are the only hand-made
parts of the data:

- **`rooms.json`** — the 22 room rectangles of the printed board, read out of
  `/obj/heroquest_base` in the .hip.
- **`ctypes.json`** — which icon cluster is which monster. Cluster ids match
  `work/clusters.png`, so a type can be re-checked or corrected there.
`manual.json` used to be in this directory and is **not** any more. It and
`catalog.json` live in `assets/quests/`, with the tool that writes them —
everything here is machine output, and those two are the opposite. See
`assets/quests/README.md`.

- **`../../assets/quests/manual.json`** — quest titles, wandering monsters,
  furniture read off the step-8 contact sheets, the escape arrows, the
  openings, and per-quest `fix` blocks that correct anything steps 3–7 got
  wrong. Written by hand or by clicking on the scan in
  `assets/quests/quest_editor.py`. See **Fixing it by hand** below.

### The bits worth knowing

**Squares in play** (step 3) classify by *how much of the square is mauve*, not
by how dark it is. Darkness alone calls a square blocked when a big piece of
furniture is drawn on it — which is exactly what quest 1's tavern tile does to
half a dozen squares. The mauve fill is a specific flat colour, and any
threshold from 0.45 to 0.65 gives the same answer.

**Doors** (step 4) is where normalising pays off. On the raw scans, five
different approaches all failed — white-blob detection (the beige floor is as
bright as a door leaf), the door outline's parallel edges, ink-excess on the
wall band, binary-mask correlation, and template matching against a raw crop.
On the canonical raster the same template matching separates immediately: real
doors score 0.65–1.00 and everything else piles up at 0.61 and below. The
script prints the lowest kept and highest dropped score per quest so the gap
stays visible; quest 6 is the tightest at 0.65 against 0.61.

Two things about it are worth knowing. The slop between the print and the
ideal grid is 16 px and not the 6 it started at: the warp is linear and the
printed board is not, so a wall can sit a dozen pixels off its line, and at 6
the template was landing beside quest 7's (12,15)W rather than on it and
scoring 0.09 — anti-correlated, nowhere near the cut. Widening it found that
door and quest 3's (18,14)W and added no false positive anywhere in the pack.
And it finds a door drawn **closed** and nothing else, which is what the
sealed-room check in step 9 is for.

**Furniture** (step 8) is not detection, it is presentation. The point is to
turn "find the furniture across ten scans" into "look at ten contact sheets
where each crop is labelled with its board square".

**The symbols** (step 11) are cut with the plate again, and for the same
reason as step 8: the plate is the board with every overlay voted away, so
what a quest added to a square is just the pixels that differ from it. Two
corrections make that a usable cutout. The board's own dilated ink comes off,
because the warp is good to a pixel and not to nothing, so every grid line
leaves a hairline of difference along its edge — every kind but the doors,
which are printed *on* a wall and would go with it. And the solid kinds get
their holes flood-filled: the pale crown of a goblin's head is almost exactly
the colour of the beige floor, so a plain difference punches a hole through
the top of its skull. That fill needs a few pixels of slack cut around the
symbol, because a monster disc overlaps the grid line at the bottom of its own
square, and the gap that leaves is right at the edge of an 80×80 crop where
there is nothing to close it against.

Furniture and the escape arrows skip the cutout and stay opaque, background
and all. Cutting out is right for a thing with a silhouette — a monster disc,
a bold letter, a door — but a table is a dozen thin strokes, and reduced to
just those it reads as scratches floating on whatever colour the room happens
to be. It was drawn on a patch of printed floor and it looks like the map when
it keeps it.

Which instance to cut is a different answer per kind, and that is most of the
step. A monster *type* is not one drawing — step 5's ~88 clusters land on ~10
types, so an orc is nine or so poses and a median across all of them is mush;
the sharp answer is the median of the type's largest cluster, which is why
step 5 exposes its clustering rather than keeping it in `__main__`. A note
letter is one fixed glyph, so the median across every placement is both sharp
and representative. Furniture has no two pieces alike and nothing to cluster,
so a kind is cut from a single real instance: the modal footprint first, then
the drawing with the most ink on it. Placements sitting on an orange or
deep-red square are skipped, because there the fill *is* the difference — but
the footprint is chosen before that filter, or the stairway, which is drawn on
a deep-red square in six quests out of seven, would take its shape from an
outlier.

`work/sprites.png` is the check, and it is the only one: 44 symbols on a
checker, and whether they are right is a thing to look at.

---

## Fixing it by hand

A parse nobody can correct is worse than no parse, so every layer has a hand
channel and the hand always wins. Nothing below needs a detector touched, and
nothing below is undone by re-running the pipeline.

### By clicking on the scan

`assets/quests/quest_editor.py` is the whole of what follows with the map in
front of it. It runs in Houdini — the **Quest Editor** tool on the **rehq**
shelf (`houdini/toolbar/rehq.shelf`, installed by the package in
`houdini/README.md`), or `import quest_editor; quest_editor.show()` in the
Python shell — and
draws `ds/cNN.png` with the parse over it: shaded squares washed out, doors on
their walls, monsters as their type, letters, fills and furniture footprints,
with anything the hand put there outlined in cyan.

Pick a layer and a value, then left click a square to place and right click to
take away; furniture drags out a footprint; a door click takes the nearest
wall, so you click the capsule you can see rather than work out whose north
wall it is. Ctrl+Z undoes. Nothing reaches disk until **Apply**, which writes
`manual.json`, runs step 9 and shows what it printed — the room checks and the
sealed-room list included — then rebuilds the ten quest objects in the scene.

It writes the same `fix` rows as below, and it *cancels* rather than stacks:
deleting something a detector found becomes a `del`, deleting something you had
added drops that `add` again, and putting back what a `del` is hiding drops the
`del`. So the file never accumulates the stale entries step 9 refuses to run
with. Only the quests actually edited are rewritten — every other quest keeps
its bytes.

The rest of this section is the same channel by hand, which is still the way to
make a wholesale change, and the only way to read what is already there.

**Furniture and the escape arrows** are already wholly hand-written, in
`assets/quests/manual.json` under `"furniture"` and `"arrows"`. There is no detector to
override — step 8 only crops the contact sheets, a human reads them. Add,
remove or move a piece by editing the list. A footprint is `[x0, y0, x1, y1,
kind]`; the kind is any name in `assets/quests/sprites/index.json`, and a new
name is fine — step 11 will cut a sprite for it from the instance you named.

**Everything the machine finds** — squares in play, doors, monsters, note
letters, special fills — is corrected in the same file under `"fix"`:

```json
"01": {"title": "...", "wandering": "orc",
  "fix": {
    "doors":    {"add": [[3, 14, "W"]], "del": [[12, 12, "N"]]},
    "monsters": {"add": [[5, 5, "orc"]], "del": [[4, 0]]},
    "marks":    {"add": [[7, 2, "D"]],  "del": [[1, 1]]},
    "special":  {"add": [[7, 1, "orange"]], "del": [[24, 1]]},
    "squares":  {"in": [[3, 18]], "out": [[4, 0]]}
  },
  "furniture": [...]}
```

`add` carries the whole row, the same shape the layer uses. `del` names only
the square — `[x, y]`, or `[x, y, "N"|"W"]` for a door, because one square can
carry both. `squares` forces a square in or out of play when step 3 misread
the shading.

A `del` that matches nothing, or an `add` that is already there, **stops the
run**. That is deliberate: when a detector improves and finds what you had
patched, the patch has to be noticed and deleted rather than sitting there
misrepresenting the scan. There is one live example — quest 10's phantom
`unknown` monster at (4,0), a patch of dragon-lair artwork that step 5 read as
an icon, is deleted through this channel instead of being carried to the asm
side and dropped there.

Then re-run what depends on it:

```
cd map-ai-parsing
python work/09_assemble.py      # quests_data.json
python work/10_verify.py        # the overlays to check it against the scan
python work/11_sprites.py       # only if a furniture kind was added or renamed
cd ../assets && python quests_to_asm.py
```

and rebuild the Houdini scene — in Houdini's Python shell:

```python
exec(open("E:/github/rehq/assets/quests/build_quests_hou.py").read())
```

The .hip does not read `quests_data.json` at cook time: `build_quests_hou.py`
bakes each quest's data into the `entities` Python SOP, so the scene does not
change until that line is run and the file saved.

The editor's **Apply** is the first line and the last one — step 9 and the
scene rebuild. The overlays, the sprites and the asm are left to be run
deliberately, so a fix made by clicking still wants `10_verify.py` (and
`11_sprites.py`, if a furniture kind was added or renamed) before it is
believed, and `quests_to_asm.py` before it reaches the game.

`assets/quests/verify/qNN.png` is how you check a fix landed — it draws the
data back over the scan, labelled, so a wrong square is obvious.

## A second quest book

Everything here is written for *one* pack, and says so nowhere else: the PDF is
a constant, "ten quests" is a `range(1, 11)` in nine scripts, and every output
name is flat — `ds/cNN.png`, `work/*.json`, one `quests_data.json`, one
`sprites/`. Point step 0 at another book and it overwrites this one without a
word. So the first job is not running the pipeline, it is giving the pack a
name.

**What is per-pack** — the PDF path, first page and map rect
(`work/00_pages.py:12-14`); the quest count — `range(10)` in
`00_pages.py:18`, `range(1, 11)` in `02_canon.py:27`, `03_grid.py:87`, `04_doors.py:79`,
`05_monsters.py:57`, `06_letters.py:51`, `07_special.py:18`,
`08_furniture.py:67`, `09_assemble.py:231` and `11_sprites.py:89`; the output
paths, which are flat everywhere; the one data file (`09_assemble.py:332`) and
the one sprite tree (`11_sprites.py:74`); and on the authored side
`manual.json`, `catalog.json`, `sprites/`, `quest_editor/paths.py:34` and the
ten objects `build_quests_hou.py:498` builds.

**What carries over** — the detectors themselves, and `work/rooms.json`, *if*
the new book is played on the same printed board. Kellar's Keep and Return of
the Witch Lord are; a pack with a board of its own is a different job, and
`rooms.json`, `/obj/heroquest_base` and the 26×19 in `quest_editor/paths.py:33`
all have to be redone before any of this means anything.

**What does not carry over even though it looks like it does** —
`work/ctypes.json`. It names a monster and lists the cluster ids that are that
monster, and step 5 numbers its clusters afresh against whatever set of maps it
is given, so this book's ids are noise for the next one. Relabel it against the new `work/clusters.png`. The
thresholds are the other half of this: step 3's mauve fraction and step 4's
0.65 door score were set against *this* scan's paper and ink, and a book
scanned on another machine may sit somewhere else.

Then the order, once the pack is a parameter:

1. The PDF into `assets/scans/`; set its path, `FIRST_QUEST_PAGE`, the quest
   count and `MAP_RECT` — check the rect by eye on `hi/qNN.png`.
2. Steps 0–2, **then stop and look at `ds/cNN.png` and `ds/plate.png`.** This is
   the make-or-break: a frame the finder missed or a warp that is off makes
   everything downstream meaningless. The plate is voted per pack — do not
   reuse this book's.
3. Steps 3–7, the detectors.
4. Step 8, then read the contact sheets and write `manual.json`: furniture,
   arrows, openings, titles, wandering monsters. This is most of the human
   time — 190 pieces for the ten quests here.
5. Relabel `ctypes.json` against the new `clusters.png`.
6. Step 9, and read what it prints: whole rooms, sealed rooms, connectivity.
   Those checks are how you know the parse held.
7. Step 10, then correct by clicking in the Quest Editor.
8. Step 11; new furniture names into `catalog.json`, bad cuts overridden in
   `sprites_hand/`, and `work/sprites.png` to check it.
9. `build_quests_hou.py` in Houdini — **and save the .hip**, or the scene keeps
   the build it already had.
10. `assets/quests_to_asm.py`, watching the three it flags here: no stairway
    means no start square, a title over 28 columns draws cut off, and 32 is
    `MAX_MONSTERS`. A second book is also a second `quest_data.asm` — about
    1.8 KB of bank per ten quests.

Two ways to do the naming. Thread a pack through — one constants module every
step reads, outputs under `ds/<pack>/` and `assets/quests/<pack>/` — or copy
both trees per pack and live with the duplication. The first is an hour of
work; the second is free until the third book.

## What came out

| Quest | Title | Squares | Doors | Monsters | Furniture | Notes |
|---|---|---|---|---|---|---|
| 1 | The Rat and Candle Tavern | 352 | 10 | 27 | 15 | A–D |
| 2 | Jail Break | 293 | 11 | 24 | 10 | A–E, X |
| 3 | Marsh of Sorrows | 222 | 7 | 21 | 10 | A–E |
| 4 | Lost Mine of Tyjit Shaleaxe | 268 | 9 | 21 | 7 | A–C |
| 5 | Sunken City of Buubhealxea | 308 | 11 | 33 | 15 | A–F, X |
| 6 | Tomb of Hate | 266 | 9 | 27 | 13 | A–C |
| 7 | Halls of Doom | 299 | 16 | 33 | 10 | A–D |
| 8 | Forge of the Mountain King | 284 | 14 | 31 | 18 | A–F |
| 9 | Throne of the Death Knight | 297 | 9 | 33 | 15 | A–C |
| 10 | The Crypt of Perpetual Darkness | 328 | 13 | 29 | 13 | A–E, X |

Doors are recorded the way `data/quest_data.asm` wants them: always the NORTH
or WEST wall of the square named. Grid coordinates are x 0..25 left to right,
y 0..18 top to bottom of the printed map, so the Houdini prim index on
`/obj/heroquest_base/OUT` is `y*26+x`.

## How much to trust it

**Exact, and checked:**

- **Quest 1's board reproduces the hand-built `/obj/quest_0` square for
  square** — 352 squares, no difference either way. That node predates this
  code, so it is genuine ground truth, and it is what the step-3 threshold was
  set against.
- **Room usage is clean in all ten quests.** Every one of the 22 rooms comes
  out wholly in play or wholly out, in four places rather than none — and all
  four are the shading art crossing a room edge, not a parse that went wrong.
  Quest 1's tavern tile takes room14 down to 8 squares of its 16 and clips the
  corner of room11, leaving it 2 of 16; quest 10's dragon lair art covers part
  of rooms 3 and 4, leaving each 12 of 20. `build_quests_hou.py` prints all
  four every time it runs, off the board in the .hip rather than off this
  parse, so a fifth would be noticed.
- **Eleven rooms in play have no door on any wall.** Step 9 checks it and
  names them, because it is the only thing that makes step 4's blind spot
  visible: the template knows the closed white capsule and nothing else. Seven
  of the eleven have a trapdoor inside them or on a square touching them and
  are very likely meant to be entered that way — quest 1's room12 is the
  clearest, note B printed on the square between a trapdoor in the room and a
  trapdoor in the corridor above it. Four have neither: quest 1's room16 and
  quest 3's room16, and quest 10's rooms 0 and 1, which are the two the dragon
  lair artwork is drawn across. All four want the quest notes before anyone
  guesses. (Quest 1's tavern is rooms 15 and 16 drawn as one room under the
  tavern tile, which erases the wall between them, so room15 counts as reached
  through room16's side of it rather than through the trapdoor it touches.)

- **Every quest's play area is one connected piece.** The heroes have to be
  able to walk it, so a square in play that no other square in play touches is
  a misread every time. Step 3 checks it and says so. It found exactly one:
  quest 2's bottom row is scanned lighter than the rest of that map, and
  square (3,18) came out 0.44 mauve against neighbours at 0.68 and 0.83 — in
  play, alone, on a square that is plainly shaded. Loosening the blue ceiling,
  which was capping brightness on a test that should only care about hue,
  fixed it and changed nothing else anywhere in the pack.
- **Every door but two has both its sides in play.** A door is a hole in a
  wall between two squares, so this is a real check, and `build_quests_hou.py`
  runs it. The two are printed exceptions rather than parse errors — the
  capsule is plainly on the scan and the square past it is plainly shaded:
  quest 5's (25,11) and quest 10's (25,2). Quest 10's has note marker B
  sitting on the very square it names, which is very likely the note that
  explains it; quest 5's has nothing on it and stays unexplained until the
  notes are transcribed.
- **Monster typing corroborates the quest text.** Quest 6 comes out
  skeletons, zombies and mummies; quest 3 has exactly one dread sorcerer, the
  swamp hag of its note C; quest 9 has exactly one, Kedrick Gilbane. None of
  that was fed to the classifier.
- The pipeline is deterministic — re-running it from scratch reproduces
  `quests.json` byte for byte, cluster ids included.

**Softer, and worth a look at `assets/quests/verify/qNN.png`:**

- **Furniture kinds** are my reading of line art (`table`, `rack`, `altar`,
  `tomb_sword`, `forge`, `loom`, `bookcase`, `alchemist_bench`, …). Footprints
  are ink bounding boxes, so a piece's box is the extent of the drawing, not
  necessarily the tile's true square count.
- **The cut-out symbols are a representative, not a copy.** A monster type is
  its commonest pose, so the other poses in the pack are not drawn; a
  furniture kind is its modal footprint, so an instance of a different size
  gets that image stretched to fit. `work/sprites.png` is the whole check.
- **Two recurring glyphs are named by appearance, not from the pack's key**:
  `trapdoor` (a hatch with its lid standing open, 21 of them) and `rubble`
  (masonry blocks). I did not confirm what either means in this set's rules.
  `trapdoor` was called `slab` until the placements were looked at one square
  at a time: six of the twenty-six were not the hatch at all but four rubble
  blocks, quest 8's studded cask, and quest 3's (13,8), which is the letter C
  and nothing else. The sprite had been cut from one of the six, so every
  trapdoor in the pack was drawing as a crosshatched grate.
- **Monster types are roughly 90–95%.** Orc, goblin, skeleton, dread warrior,
  abomination and dread sorcerer are reliable. Zombie versus mummy is the fuzzy
  pair: the mummy icon has bandage wraps across the crown, the zombie has
  stringy hair at the sides, and at 80 px that is a fine distinction.
- **The one `unknown` was a false positive, not an unread icon.** Quest 10's
  square (4,0) is a patch of the dragon lair artwork that came out green
  enough to pass step 5's test; there is no icon drawn on it, and the two
  mummies either side of it are the real ones. It is deleted through the hand
  channel — `manual.json["10"]["fix"]["monsters"]["del"]` — rather than by
  tightening step 5, whose cluster ids are what `ctypes.json` is keyed to.
  `assets/quests_to_asm.py` still drops the type on the way out (see
  `NOT_A_MONSTER`), which is now a belt to that brace rather than the only
  thing standing between it and the game.
- **Special squares** are the orange and deep-red fills. What each one *means*
  is in the quest notes (a vine trap, an acid pool, a door marked A) and is not
  in the data yet.

## Not done yet

**The quest notes are not transcribed.** All ten pages have been read, but only
the titles and wandering monsters made it into the data. Still missing:

- the parchment briefing read out before each quest,
- the lettered notes A–F and X the map markers point at,
- the objective and any "must escape" condition,
- what a search of each room turns up.

That is the half `quest_structures.i` calls finds and triggers, and it is text
work off the bottom half of the same pages, not image work — the map half is
done.

`assets/quests_to_asm.py` now writes the quest half. `data/quest_data.asm` is
generated from `quests_data.json`, assembles clean, and cost 1848 bytes in
bank 1 for all ten quests when it was last assembled — 1855 now, two doors at
two bytes and one piece of furniture at three; the figure wants re-measuring
on the next build rather than trusting that arithmetic; the traps, finds and triggers are empty lists with
their labels in place, waiting on the notes above. Every judgement it had to
make is a `; NOTE:` line in the generated file, and these are the ones that
want a human answer:

- **Quest 8 starts at (0,0).** It draws no stairway and no escape arrow, so
  there is nothing to read a start square off. Quests 5 and 10 also draw no
  stairway and take theirs from the first escape arrow, which is a guess.
- **Quest 10's title is 31 columns** against a 28-column row, so it will draw
  cut off. It needs shortening.
- **Quests 5, 7 and 9 have 33 figures** against `MAX_MONSTERS` 32. The rows
  are legal in the bank and the loader spawns lazily, so it only bites if all
  33 are ever live at once.
- **Furniture orientation is mostly unturned.** A footprint here is the ink
  bounding box, not the tile's square count, so it is only trustworthy when
  it is an exact transpose of the kind's shape. Settling it needs the
  `FurnitureType` table, which needs the sprites.

And one that is about the board rather than the quests: **`data/board.asm`
comes out with 21 rooms and is not in the build.** Square (17,13) is claimed
by both room17 and room21, so room21 measures 15 and fails the rectangle
test. The module docstring in `quests_to_asm.py` has the detail.
