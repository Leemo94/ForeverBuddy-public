#!/usr/bin/env python3
"""Check every faction tag in Data/Dungeons.lua against the evidence behind it.

    python3 tools/audit_factions.py            # the shipped file
    python3 tools/audit_factions.py --quiet    # only the complaints

A quest's side is decided by its race mask, falling back to whoever hands it out. That is two
sources that can disagree, and a chain adds a third: a step that leads to an Alliance quest is
an Alliance step even when nothing about the step itself says so. This re-derives all three and
reports where they do not line up, so a wrong flag on a dungeon card gets caught here rather
than in game.
"""
import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_data import parse_lua_value  # noqa: E402
import build_dungeons as bdg  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Only the capitals. A starting zone is nearly one side's, but "nearly" is no good here: the
# Barrens holds Ratchet, where both sides take the same warlock quest, and a list of leanings
# would report that as a fault every time. A capital is the one place the other side cannot
# walk into and talk to somebody.
ALLIANCE_PLACES = {"Stormwind City", "Ironforge", "Darnassus"}
HORDE_PLACES = {"Orgrimmar", "Undercity", "Thunder Bluff"}


def load_dungeons(path):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    m = re.search(r"^ns\.Dungeons\s*=\s*", text, re.M)
    if not m:
        raise SystemExit("no ns.Dungeons in %s" % path)
    value, _ = parse_lua_value(text, m.end())
    return value


def place_side(place):
    if not isinstance(place, dict):
        return None
    where = place.get("where")
    if where in ALLIANCE_PLACES:
        return "Alliance"
    if where in HORDE_PLACES:
        return "Horde"
    return None


def race_side(entry):
    """The side the quest's own race mask says, or None for 'anyone'."""
    races = bdg.field(entry, 6) or 0
    if races in (0, 255):
        return None
    a, h = races & bdg.ALLIANCE_MASK, races & bdg.HORDE_MASK
    if a and not h:
        return "Alliance"
    if h and not a:
        return "Horde"
    return None


def audit(dungeons, world, quiet=False):
    problems, counts = [], {"Alliance": 0, "Horde": 0, "both": 0}
    for dungeon in dungeons:
        rows = dungeon.get("quests") or []
        if isinstance(rows, dict):
            rows = list(rows.values())
        for quest in rows:
            shipped = quest.get("faction") or None
            counts[shipped or "both"] = counts.get(shipped or "both", 0) + 1
            entry = world.quests.get(quest["id"])
            races = race_side(entry) if entry else None
            giver = place_side(quest.get("giver"))
            turnin = place_side(quest.get("turnin"))

            # 1. the race mask is the strongest word there is
            if races and shipped != races:
                problems.append((dungeon["name"], quest["id"], quest["name"],
                                 "tagged %s, race mask says %s" % (shipped or "both sides", races)))
            # 2. a quest nobody tagged, handed out somewhere only one side can stand
            elif not shipped and giver:
                problems.append((dungeon["name"], quest["id"], quest["name"],
                                 "tagged both sides, but its giver is in %s (%s)" % (
                                     quest["giver"].get("where"), giver)))
            # 3. picked up on one side and handed in on the other
            elif giver and turnin and giver != turnin:
                problems.append((dungeon["name"], quest["id"], quest["name"],
                                 "picked up in %s but handed in in %s" % (
                                     quest["giver"].get("where"), quest["turnin"].get("where"))))
            # 4. a prerequisite from the other side: you could never reach the quest
            for step in quest.get("pre") or []:
                side = step.get("faction") or None
                if shipped and side and side != shipped:
                    problems.append((dungeon["name"], quest["id"], quest["name"],
                                     "needs %s first, which is tagged %s" % (step.get("name"), side)))
                step_place = place_side(step.get("giver"))
                if shipped and step_place and step_place != shipped:
                    problems.append((dungeon["name"], quest["id"], quest["name"],
                                     "needs %s, handed out in %s" % (
                                         step.get("name"), step["giver"].get("where"))))
    return problems, counts


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--file", default=os.path.join(ROOT, "Data", "Dungeons.lua"))
    parser.add_argument("--cache", default=os.path.join(ROOT, "tools", "cache", "questie"))
    parser.add_argument("--quiet", action="store_true", help="only print the complaints")
    args = parser.parse_args(argv)

    dungeons = load_dungeons(args.file)
    world = bdg.load_world(args.cache)
    problems, counts = audit(dungeons, world)

    total = sum(counts.values())
    if not args.quiet:
        print("%d quests: %d Alliance, %d Horde, %d either side" % (
            total, counts.get("Alliance", 0), counts.get("Horde", 0), counts.get("both", 0)))
        for dungeon in dungeons:
            rows = dungeon.get("quests") or []
            if isinstance(rows, dict):
                rows = list(rows.values())
            a = sum(1 for q in rows if q.get("faction") == "Alliance")
            h = sum(1 for q in rows if q.get("faction") == "Horde")
            n = len(rows) - a - h
            if rows:
                print("  %-28s %2d quests: %2d A, %2d H, %2d either" % (dungeon["name"], len(rows), a, h, n))
    if problems:
        print("\n%d to look at:" % len(problems))
        for dungeon, quest_id, name, why in problems:
            print("  %-24s [%6d] %-34s %s" % (dungeon, quest_id, name[:34], why))
    else:
        print("\nnothing to look at: every tag agrees with its race mask, its giver and its chain.")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
