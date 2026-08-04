#!/usr/bin/env python3
"""Give the extracted cards their real names.

extract_cards.py can only name a card after the scan it came off and its place
on the glass, so everything downstream inherits card5_08 instead of orcs_bane.
The titles were read off the scans once and live in card_names.json; this walks
whatever directories you point it at and renames every cardN_MM.* file to match.

Two cards in the deck share the title "Ball of Flame", so the second one is
ball_of_flame_2 -- names have to stay unique to be usable as labels.

Safe to run twice: a file that is already renamed is simply not found again.

Usage:
    python rename_cards.py                     # every known output directory
    python rename_cards.py art_zx art64_zx     # only these
    python rename_cards.py --dry-run           # show what would happen
"""

import argparse
import glob
import json
import os
import re
import sys

NAMES = "card_names.json"

# everywhere a cardN_MM name may have been carried to
DEFAULT_DIRS = [
    os.path.join("original_cards", "cards"),
    os.path.join("original_cards", "cards_zx"),
    os.path.join("original_cards", "heroes_big"),
    os.path.join("original_cards", "heroes_fig"),
    "art", "art_zx",
    "art64", "art64_zx", "art64_clean_zx",
    "art64t", "art64t_zx",
    "art_square", "art_square_zx",
]

CARD = re.compile(r"^(card\d+_\d+)(\..+)$")


def rename_dir(path, names, dry_run):
    if not os.path.isdir(path):
        return 0, 0
    done = clash = 0
    for entry in sorted(os.listdir(path)):
        m = CARD.match(entry)
        if not m:
            continue
        stem, ext = m.groups()
        new = names.get(stem)
        if new is None:
            print(f"  ?? {path}/{entry}: no name for {stem}")
            continue
        dst = os.path.join(path, new + ext)
        if os.path.exists(dst):
            print(f"  !! {path}/{entry}: {new + ext} already there, left alone")
            clash += 1
            continue
        if not dry_run:
            os.rename(os.path.join(path, entry), dst)
        done += 1
    return done, clash


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dirs", nargs="*", help="directories (default: all known)")
    ap.add_argument("--names", default=NAMES, help=f"name table ({NAMES})")
    ap.add_argument("--dry-run", action="store_true", help="show, do not rename")
    args = ap.parse_args()

    if not os.path.exists(args.names):
        sys.exit(f"no name table at {args.names}")
    names = json.load(open(args.names))

    total = clashes = 0
    for d in (args.dirs or DEFAULT_DIRS):
        done, clash = rename_dir(d, names, args.dry_run)
        total += done
        clashes += clash
        if done or clash:
            print(f"{d}: {done} renamed" + (f", {clash} skipped" if clash else ""))

    verb = "would rename" if args.dry_run else "renamed"
    print(f"{verb} {total} files" + (f", {clashes} skipped" if clashes else ""))


if __name__ == "__main__":
    main()
