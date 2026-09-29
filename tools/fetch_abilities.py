#!/usr/bin/env python3
"""Fetch Forever's class abilities and the level each one is learned at.

Usage: python3 tools/fetch_abilities.py --build 1.60.1.69893 [--delay 0.3] [--limit N]

Nothing publishes Forever's ability ladder. The client knows which spells belong to which class
(SkillLineAbility joined to the class skill lines, category 7) but not when you learn them:
SpellLevels holds the spell's own level, not the trainer's requirement, and reads the same in
Classic Era as it does here. Wowhead's Forever data does carry it, one tooltip at a time, as a
"Requires level" line, so this walks the class spell list and reads that.

Each tooltip is cached under tools/cache/wowhead-forever/spells, so a second run is free and an
interrupted one carries on where it stopped. Output: tools/data/forever-abilities.json.
"""
import argparse
import collections
import csv
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

TOOLTIP = "https://nether.wowhead.com/tooltip/spell/{id}?dataEnv=16&locale=0"
CLASS_MASK = {1: "Warrior", 2: "Paladin", 4: "Hunter", 8: "Rogue", 16: "Priest",
              64: "Shaman", 128: "Mage", 256: "Warlock", 1024: "Druid"}
CLASS_SKILL_CATEGORY = "7"

LEVEL = re.compile(r"Requires level (\d+)")
RANK = re.compile(r'whtt-rank">Rank (\d+)')
REQUIRES = re.compile(r"Requires ([A-Z][a-zA-Z ]+?)</div>")


def class_spells(cache):
    """{spell id: [class names]} for every spell on a class skill line."""
    with open(os.path.join(cache, "SkillLine.csv"), encoding="utf-8") as f:
        lines = {int(r["ID"]): r for r in csv.DictReader(f)}
    out = collections.defaultdict(list)
    with open(os.path.join(cache, "SkillLineAbility.csv"), encoding="utf-8") as f:
        for row in csv.DictReader(f):
            line = lines.get(int(row["SkillLine"] or 0))
            if not line or line.get("CategoryID") != CLASS_SKILL_CATEGORY:
                continue
            mask = int(row["ClassMask"] or 0)
            spell = int(row["Spell"] or 0)
            if not spell:
                continue
            for bit, name in CLASS_MASK.items():
                if mask & bit and name not in out[spell]:
                    out[spell].append(name)
    return out


def fetch_spell(spell_id, cache_dir, delay):
    """The tooltip JSON for a spell, from the cache when we have already asked."""
    path = os.path.join(cache_dir, "%d.json" % spell_id)
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return json.load(f), True
    request = urllib.request.Request(TOOLTIP.format(id=spell_id),
                                     headers={"User-Agent": "Mozilla/5.0 (ForeverBuddy)"})
    for attempt in range(3):
        try:
            body = urllib.request.urlopen(request, timeout=25).read().decode("utf-8")
            break
        except urllib.error.HTTPError as error:
            if error.code == 404:
                body = "{}"
                break
            time.sleep(2 + attempt * 3)
        except OSError:
            time.sleep(2 + attempt * 3)
    else:
        return None, False
    try:
        data = json.loads(body)
    except ValueError:
        data = {}
    os.makedirs(cache_dir, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f)
    time.sleep(delay)
    return data, False


def parse(data):
    """{name, icon, level, rank, requires} from a tooltip, or None when Wowhead knows nothing."""
    if not data or not data.get("name"):
        return None
    tooltip = data.get("tooltip") or ""
    level = LEVEL.search(tooltip)
    rank = RANK.search(tooltip)
    requires = REQUIRES.search(tooltip)
    return {"name": data["name"], "icon": data.get("icon"),
            "level": int(level.group(1)) if level else None,
            "rank": int(rank.group(1)) if rank else None,
            "requires": requires.group(1).strip() if requires else None}


def main(argv=None):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", default="1.60.1.69893")
    parser.add_argument("--delay", type=float, default=0.3)
    parser.add_argument("--limit", type=int, default=0, help="stop after this many new fetches")
    parser.add_argument("--out", default=os.path.join(root, "tools", "data", "forever-abilities.json"))
    args = parser.parse_args(argv)

    build_cache = os.path.join(root, "tools", "cache", args.build)
    spell_cache = os.path.join(root, "tools", "cache", "wowhead-forever", "spells")
    spells = class_spells(build_cache)
    print("%d class spells to ask about" % len(spells), flush=True)

    found, missing, fetched = {}, 0, 0
    for i, spell_id in enumerate(sorted(spells), start=1):
        data, cached = fetch_spell(spell_id, spell_cache, args.delay)
        if not cached:
            fetched += 1
        entry = parse(data)
        if entry:
            entry["classes"] = spells[spell_id]
            found[spell_id] = entry
        else:
            missing += 1
        if i % 100 == 0:
            with_level = sum(1 for e in found.values() if e["level"])
            print("%d/%d asked, %d named, %d with a level, %d unknown"
                  % (i, len(spells), len(found), with_level, missing), flush=True)
        if args.limit and fetched >= args.limit:
            print("stopping after %d new fetches" % fetched, flush=True)
            break

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump({"build": args.build, "spells": found}, f, indent=1, sort_keys=True)
    with_level = sum(1 for e in found.values() if e["level"])
    print("%d spells named, %d with a learn level -> %s" % (len(found), with_level, args.out), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
