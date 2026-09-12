"""Writing manual.json back in the shape it is read in.

manual.json is hand-made and hand-read, and a formatter that reflowed the whole
thing on every save would bury one changed row in a file-sized diff. So only
the quests actually edited are rewritten, and every other quest keeps its bytes
exactly - which is what _splice is for.
"""
import json

from .catalog import CAT


WRAP = 114


def _c(o):
    return json.dumps(o, separators=(",", ":"))


def _rows(rows, col):
    """Rows one after another, wrapped, continuations under the first one."""
    lines, cur = [], ""
    for r in rows:
        s = _c(r)
        if cur and len(cur) + 1 + len(s) > WRAP - col:
            lines.append(cur + ",")
            cur = s
        else:
            cur = (cur + "," + s) if cur else s
    lines.append(cur)
    pad = " " * col
    return "[" + ("\n" + pad).join(lines) + "]"


def _block(q, d):
    """One quest, as the lines it occupies in manual.json."""
    out = ['"%s": {"title":%s,"wandering":%s,'
           % (q, _c(d["title"]), _c(d["wandering"]))]
    fix = d.get("fix")
    if fix:
        parts = ["%s:%s" % (_c(k), _c(v)) for k, v in sorted(fix.items())]
        one = '  "fix":{%s},' % ",".join(parts)
        if len(one) <= WRAP:
            out.append(one)
        else:
            pad = " " * len('  "fix":{')
            out.append('  "fix":{' + (",\n" + pad).join(parts) + "},")
    # Every catalogue layer, whether or not this quest uses it - a layer that
    # writes nothing is a layer you cannot tell from one that is not there.
    for layer in CAT.layers:
        if out[-1][-1] != ",":
            out[-1] += ","
        key = '  "%s":' % layer
        out.append(key + _rows(d.get(layer, []), len(key) + 1))
    if d.get("arrows"):
        out[-1] += ","
        out.append('  "arrows":' + _rows(d["arrows"], len('  "arrows":[')))
    if d.get("openings"):
        out[-1] += ","
        out.append('  "openings":' + _rows(d["openings"],
                                           len('  "openings":[')))
    out[-1] += "}"
    return out


def _splice(text, q, block):
    """Put `block` where quest q's lines are now, and leave the rest alone.

    A quest block is the line starting `"NN": {` and every line under it
    until the next one starts at column 0 - which is the file's own shape,
    not a guess: every key is at column 0 and every continuation is indented.
    """
    lines = text.split("\n")
    head = '"%s": {' % q
    start = next(i for i, l in enumerate(lines) if l.startswith(head))
    end = start
    while end + 1 < len(lines) and lines[end + 1].startswith(" "):
        end += 1
    if lines[end].rstrip().endswith(","):
        block = list(block)
        block[-1] += ","
    return "\n".join(lines[:start] + list(block) + lines[end + 1:])
