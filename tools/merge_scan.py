#!/usr/bin/env python3
"""Fold a ForeverBuddyScan run into tools/data/scanned-quests.json, and say what is new.

    python3 tools/merge_scan.py ~/Desktop/ForeverAddons/inbox/ForeverBuddyScan.lua

The input is the scanner's saved-variables file (WTF/Account/<account>/SavedVariables/
ForeverBuddyScan.lua), written when the player logs out. Several runs merge cleanly: a quest
already in the union is only replaced when the new record says more than the old one.

What comes out is a plain JSON file, which the dungeon and quest builders read. The scanner
never learns who gives a quest, so nothing here invents a giver: that still comes from Questie
for the Classic quests and from ForeverBuddy's own collector for Forever's new ones.
"""
import argparse
import datetime
import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from merge_collected import parse_saved_variables  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UNION = os.path.join(ROOT, "tools", "data", "scanned-quests.json")
QUESTIE = os.path.join(ROOT, "tools", "cache", "questie", "classicQuestDB.lua")


def questie_ids(path=QUESTIE):
    """Every quest id the Classic database knows, so we can count what it does not."""
    if not os.path.exists(path):
        return set()
    with open(path, encoding="utf-8", errors="replace") as f:
        return {int(m) for m in re.findall(r"^\s*\[(\d+)\]\s*=\s*\{", f.read(), re.M)}


def load_union(path=UNION):
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    return {"generated": None, "build": None, "quests": {}, "missing": []}


def richness(record):
    """How much a record actually says, for deciding which of two to keep."""
    if not isinstance(record, dict):
        return -1
    score = 1 if record.get("name") else 0
    for key in ("objectives", "rewards", "choices"):
        score += len(record.get(key) or [])
    for key in ("level", "xp", "money", "waypoint", "tag"):
        if record.get(key):
            score += 1
    return score


def merge_file(union, path):
    with open(path, encoding="utf-8", errors="replace") as f:
        db = parse_saved_variables(f.read(), "ForeverBuddyScanDB")
    quests = db.get("quests") or {}
    if isinstance(quests, list):  # an empty Lua table parses as a list
        quests = {}
    added, improved, same = 0, 0, 0
    for quest_id, record in quests.items():
        key = str(quest_id)
        old = union["quests"].get(key)
        if old is None:
            union["quests"][key] = record
            added += 1
        elif richness(record) > richness(old):
            union["quests"][key] = record
            improved += 1
        else:
            same += 1
    missing = db.get("missing") or {}
    if isinstance(missing, dict):
        union["missing"] = sorted(set(union.get("missing") or []) | {int(k) for k in missing})
    info = db.get("info") or {}
    if isinstance(info, dict) and info.get("build"):
        union["build"] = info["build"]
    return added, improved, same, info


def summarise(union):
    quests = union["quests"]
    known = questie_ids()
    new = [q for q in quests if int(q) not in known]
    with_rewards = [q for q, r in quests.items() if (r.get("rewards") or r.get("choices"))]
    with_waypoint = [q for q, r in quests.items() if r.get("waypoint")]
    return {
        "quests": len(quests),
        "new_to_questie": len(new),
        "with_rewards": len(with_rewards),
        "with_waypoint": len(with_waypoint),
        "missing": len(union.get("missing") or []),
        "sample_new": sorted(new, key=lambda q: int(q))[:10],
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("files", nargs="+", help="ForeverBuddyScan.lua files (globs are fine)")
    parser.add_argument("--union", default=UNION)
    args = parser.parse_args(argv)

    paths = [p for pattern in args.files for p in sorted(glob.glob(os.path.expanduser(pattern)))]
    if not paths:
        raise SystemExit("no files matched")

    union = load_union(args.union)
    for path in paths:
        added, improved, same, info = merge_file(union, path)
        print("%s: %d new, %d better, %d already had (build %s, %s)" % (
            os.path.basename(path), added, improved, same, info.get("build", "?"), info.get("when", "?")))

    union["generated"] = datetime.date.today().isoformat()
    os.makedirs(os.path.dirname(args.union), exist_ok=True)
    with open(args.union, "w", encoding="utf-8") as f:
        json.dump(union, f, indent=1, sort_keys=True)

    stats = summarise(union)
    print("\n%(quests)d quests in the union, %(new_to_questie)d of them unknown to Questie." % stats)
    print("%(with_rewards)d carry rewards, %(with_waypoint)d carry a waypoint, "
          "%(missing)d ids the server would not name." % stats)
    if stats["sample_new"]:
        print("new ids, first few: " + ", ".join(
            "%s (%s)" % (q, union["quests"][q].get("name", "?")) for q in stats["sample_new"]))
    print("-> %s" % args.union)


if __name__ == "__main__":
    main()
