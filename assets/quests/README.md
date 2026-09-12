# assets/quests

The quest scene, the tool that edits it, and the art it draws with.

## Where everything is

Two trees, and the split is not arbitrary. `map-ai-parsing/` is the **pipeline**:
its scans and its json are what the numbered scripts make and remake, and
nothing in it is drawn by a person. `assets/quests/` is the **authored** side —
the scene, the tool, and art.

`sprites/` is the exception that proves it: it sits on the authored side but is
generated, which is why `sprites_hand/` exists next to it.

| path | what | who writes it |
|---|---|---|
| `quests.hipnc` | the scene: `/obj/quest_01 … quest_10` | `build_quests_hou.py`, rebuilt from scratch |
| `build_quests_hou.py` | how a quest becomes nodes | by hand |
| `quest_editor/` | the Quest Editor (shelf → **Quest Editor**) — a package, one class per file | by hand |
| `quests_data.json` | the ten quests, final | `09_assemble.py` |
| `sprites/` | one PNG per symbol, plus `index.json` | **generated** — `11_sprites.py` owns it |
| `sprites_hand/` | your own drawings | **by hand**, never overwritten |
| `manual.json` | every hand correction | the editor, or by hand |
| `catalog.json` | the items and the layers | the editor's **Items…**, or by hand |
| `../scans/*.pdf` | the source quest pack | the scanner |
| `../../map-ai-parsing/ds/cNN.png` | the canonical scan the editor draws | `02_canon.py` |
| `../../map-ai-parsing/work/*.json` | what the detectors found | steps 3–7 |

`manual.json` and `catalog.json` were in `map-ai-parsing/work/` and were moved
here: that directory is machine output, and these two are hand-authored. The
pipeline reads them across at `../assets/quests/`.

So the tool is as close to standalone as it can be without duplicating the
scans: **everything it writes is in this folder.** Outside it, it reads
`ds/cNN.png` for the picture behind the map, and runs two pipeline scripts —
`09_assemble.py` on Apply and `11_sprites.py` on Sprite…

`quest_editor/paths.py` names all of these once and nowhere else — if a path
moves, that file is the only place that has to know.

All of it is **one quest book's**. `manual.json`, `catalog.json`, `sprites/`,
`quests_data.json` and the ten objects in the scene are the Crypt pack and
nothing else; `quest_editor/paths.py:34` lists its ten quests by name. Nothing
in the tool or the pipeline takes a pack as an argument, so a second book
overwrites the first until one is threaded through — see **A second quest
book** in `map-ai-parsing/README.md`.

## The editor's own files

One class per file, and the pieces a class needs beside it:

| file | holds |
|---|---|
| `paths.py` | every location the tool reads or writes, and the board size |
| `catalog.py` | `Catalog` — the items, the layers, and the `CAT` singleton |
| `manualfile.py` | reading and writing `manual.json` in its own style |
| `sprites.py` | what the sprite library offers, and your own drawings |
| `model.py` | `Model` — the parse with the hand file merged over it |
| `board.py` | `Board` — the map, the painting, and where a click landed |
| `items.py` | `ItemsDialog` — the catalogue as a table |
| `panel.py` | `Editor` — the controls, and what each button does |
| `pipeline.py` | running a pipeline step with what it printed captured |

It is a package, so `importlib.reload()` on it reloads only `__init__.py`.
`show()` reloads the parts itself, deepest first — which is what makes editing
one of them show up on the next press of the shelf button.

## The catalogue

`catalog.json` is what the editor offers you to place:

```json
{"layers": {"furniture": [{"name": "table", "w": 3, "h": 2}]}}
```

An item is a **name and a footprint**. A key under `"layers"` **is a layer** —
adding one there adds it to the editor's dropdown, gives it a list in
`manual.json` under the same key holding `[x0, y0, x1, y1, name]` rows, gets it
exported by `09_assemble.py`, and gets its sprites cut by `11_sprites.py`. No
code changes anywhere.

Edit it with **Items…** in the editor, or by hand. Moving an item to another
layer moves the pieces already on the maps with it — the catalogue and the maps
are not allowed to disagree about which layer a piece is on.

## Sprites

`11_sprites.py` cuts one sprite per item out of the canonical scans, picking the
modal footprint and then the instance with the most ink — the one least likely
to be half under a monster. It rewrites `sprites/` and `index.json` completely
on every run, so **nothing hand-made survives in there**.

`sprites_hand/<layer>/<name>.png` is the override. Step 11 reads it, prefers it
to the cut, and never writes to it. An item with hand art but no placement on
any map still gets an index entry, so you can draw a piece before you have
anywhere to put it.

The editor's **Sprite…** button installs one and re-runs step 11; the place box
marks such items `(own art)`, and the same button offers to drop it and go back
to the cut.
