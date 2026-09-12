"""The catalogue, as a table you can edit."""
from PySide6 import QtWidgets

from .catalog import CAT


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
