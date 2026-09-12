"""The panel: the quest, the layer, the buttons, and what a click means."""
import json
import os
import shutil
import traceback

from PySide6 import QtCore, QtGui, QtWidgets

from .board import Board, _wall
from .catalog import CAT
from .items import ItemsDialog
from .model import Model
from .paths import (ASSEMBLE, BUILD, CATALOG, FIXED_LAYERS, HAND_ART, HIP,
                    LETTERS, MANUAL, PARSE, QUESTS, SPECIALS, SPRITES_STEP)
from .pipeline import _run
from .sprites import _sprite_names, has_hand_art


# ============================================================================
# the panel
# ============================================================================

def all_layers():
    """The dropdown: the fixed layers, then whatever the catalogue declares."""
    return FIXED_LAYERS + CAT.layers


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
