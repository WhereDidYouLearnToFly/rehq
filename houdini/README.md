# houdini

The repo's own Houdini package — the tooling the project brings with it, so a
checkout has the shelf and the assets rather than each machine growing its own
copy in the user preferences.

```
houdini/
  rehq.json          the package file Houdini reads
  toolbar/
    rehq.shelf       the "rehq" shelf: the Quest Editor button
  hda/               digital assets, scanned automatically. Empty so far.
```

## Installing it

Add one line to `$HOUDINI_USER_PREF_DIR/houdini.env` — on this machine
`C:/Users/misha/OneDrive/Documents/houdini21.0/houdini.env`:

```
HOUDINI_PACKAGE_DIR = E:/github/rehq/houdini
```

and restart Houdini. That is the only machine-specific part; everything it
points at is in the repo. `rehq.json` adds its own directory to `HOUDINI_PATH`,
and Houdini then scans `toolbar/` for shelves.

Assets need the other line in `rehq.json`. Houdini scans `otls/` for digital
assets and **not** `hda/` — checked by planting an asset in each and looking
for it from a cold `hython`, where the one in `otls/` was found and the one in
`hda/` was not. So the package puts `@/otls;@/hda` on
`HOUDINI_OTLSCAN_PATH`, which makes `hda/` work; the stock asset libraries load
unchanged either way, which was checked the same way.

The shelf tab still has to be switched on in the shelf set you want it in —
that is a per-user preference and lives in the user's `default.shelf`, which is
right: which tabs are showing is not a property of the project.

## What is in it

**Quest Editor** (`toolbar/rehq.shelf`) — corrects map-ai-parsing's reading of
the quest scans by clicking on them. The button is a launcher; the tool itself
is `assets/quests/quest_editor.py`, next to `build_quests_hou.py` and the rest
of the quest-scene code, and the launcher finds it through `$HIP` because the
tool needs `assets/quests/quests.hipnc` open anyway — it rebuilds
`/obj/quest_01 … /obj/quest_10` and reads `$HIP/sprites`. See **Fixing it by
hand** in `map-ai-parsing/README.md`.

**`hda/`** — nothing yet. The quest objects are deliberately not assets: they
are built from `quests_data.json` by `assets/quests/build_quests_hou.py`, so
the scene is regenerable rather than something to maintain by hand.

Putting an asset here and using it in `quests.hipnc` needs nothing from this
package: a .hip records the path of every asset library it uses and reinstalls
it on load, so the moment a node of that type is in the saved scene, the two
are linked. Checked by saving a scene against an asset in `hda/` and opening it
in a `hython` with no package and no environment at all — the node came back
with its definition resolved.

What the package adds is the part that link cannot do: the path the .hip
records is **absolute**, so it is right on this machine and nowhere else, and
an asset nothing in the scene uses yet is not recorded at all. The scan path
finds assets here by name instead, wherever the repo is checked out.

## Editing the shelf

Houdini owns `toolbar/rehq.shelf` while it is running and rewrites it when a
tool changes, so edit the tool in Houdini (right-click the button → Edit Tool)
rather than in the file, and commit what Houdini writes. The XML says as much
at the top.
