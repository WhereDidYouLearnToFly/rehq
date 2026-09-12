"""The catalogue: what you can place, and which layer offers it."""
import json

from .paths import CATALOG


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
