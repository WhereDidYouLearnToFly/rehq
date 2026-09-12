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

THE FILES THIS IS IN

One class per file, and the pieces a class needs beside it:

    paths.py        every location the tool reads or writes, and the board size
    catalog.py      class Catalog - the items, the layers, and CAT
    manualfile.py   reading and writing manual.json in its own style
    sprites.py      what the sprite library offers, and your own drawings
    model.py        class Model - the parse with the hand file merged over it
    board.py        class Board - the map, the painting, where a click landed
    items.py        class ItemsDialog - the catalogue as a table
    panel.py        class Editor - the controls, and what each button does
    pipeline.py     running a pipeline step with what it printed captured

    import quest_editor; quest_editor.show()
"""
import importlib

import hou
from PySide6 import QtCore

# The order is the dependency order, and it matters. The shelf button reloads
# this package so that editing a file shows up without restarting Houdini, and
# reloading a package does NOT reload what is inside it - so it is done here,
# by hand, deepest first.
_PARTS = ("paths", "catalog", "manualfile", "sprites", "model", "board",
          "items", "pipeline", "panel")

_WIN = None


def _reload_parts():
    for name in _PARTS:
        importlib.reload(importlib.import_module("." + name, __name__))


def show():
    global _WIN
    _reload_parts()
    from .panel import Editor
    if _WIN is not None:
        _WIN.close()
    _WIN = Editor()
    _WIN.setParent(hou.qt.mainWindow(), QtCore.Qt.Window)
    _WIN.show()
    return _WIN
