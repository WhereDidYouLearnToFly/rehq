"""The sprite library, from this side of it.

Step 11 owns assets/quests/sprites/ and rewrites it whole, so the only thing
the tool may put there is a name - it never edits a file in it. What it CAN
hand you is sprites_hand/, which step 11 reads and never writes: a drawing of
your own that survives every regeneration.
"""
import json
import os

from .paths import HAND_ART, SPRITES


def _sprite_names(kind, fallback):
    """The names step 11 has cut a symbol for, so the pickers offer what the
    scene can actually draw. A kind with no sprite yet is still legal - the
    furniture picker is editable and step 11 will cut one for a new name."""
    try:
        idx = json.load(open(os.path.join(SPRITES, "index.json")))
        return sorted(idx["sprites"].get(kind, {})) or fallback
    except Exception:
        return fallback


def has_hand_art(layer, name):
    """Is this item drawn by hand rather than cut off the scan?"""
    return os.path.exists(os.path.join(HAND_ART, layer, "%s.png" % name))
