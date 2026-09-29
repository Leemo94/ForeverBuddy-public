#!/usr/bin/env python3
"""Build Data/Abilities.lua: every class ability and the level Forever teaches it at.

Usage: python3 tools/build_abilities.py

Input is tools/data/forever-abilities.json, written by tools/fetch_abilities.py: the class spell
list comes from the client's own SkillLineAbility, the learn level from Wowhead's Forever data,
which is the only place it is published. The client's files do not carry it - SpellLevels holds
the spell's own level and reads the same in Classic Era as it does here.
"""
import argparse
import collections
import csv
import datetime
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_data import lua_string  # noqa: E402

# How a class comes by a spell, from the client's SkillLineAbility: 0 learned (a trainer), 2
# granted with the level, 3 engraved on a rune. Forever's data environment still carries every
# Season of Discovery rune, and they are not abilities anyone can train, so 3 goes.
TRAINABLE = {"0", "2"}

# Names that are plumbing rather than abilities.
# "Soul Engraving" is the rune slot itself, handed to every class at level 1, not an ability.
JUNK = re.compile(r"^Engrave |PvP|Rune Ability|^S0\d|\(DND\)|Racial Ability|\(Passive\)$|RAQ$"
                  r"|^Soul Engraving$")

CLASS_TOKEN = {"Warrior": "WARRIOR", "Paladin": "PALADIN", "Hunter": "HUNTER", "Rogue": "ROGUE",
               "Priest": "PRIEST", "Shaman": "SHAMAN", "Mage": "MAGE", "Warlock": "WARLOCK",
               "Druid": "DRUID"}


# A race-locked ability is only ever offered to that race's trainer, so one player's list is no
# evidence against it. Undead priests train Touch of Weakness and never see Starshards.
RACE_BITS = {1: "Human", 2: "Orc", 4: "Dwarf", 8: "NightElf", 16: "Scourge",
             32: "Tauren", 64: "Gnome", 128: "Troll"}


def race_names(mask):
    """The races a mask allows, or "" when it allows everyone."""
    if mask in (0, -1):
        return ""
    found = [name for bit, name in sorted(RACE_BITS.items()) if mask & bit]
    return ",".join(found)


def acquire_methods(cache):
    """{spell id: set of AcquireMethod} over the class skill lines only."""
    with open(os.path.join(cache, "SkillLine.csv"), encoding="utf-8") as f:
        lines = {int(r["ID"]): r for r in csv.DictReader(f)}
    out, races = collections.defaultdict(set), {}
    with open(os.path.join(cache, "SkillLineAbility.csv"), encoding="utf-8") as f:
        for row in csv.DictReader(f):
            line = lines.get(int(row["SkillLine"] or 0))
            if line and line.get("CategoryID") == "7":
                spell = int(row["Spell"] or 0)
                out[spell].add(row["AcquireMethod"])
                locked = race_names(int(row["RaceMasks_0"] or 0))
                if locked:
                    races[spell] = locked
    return out, races


def trainer_levels(observed_path):
    """{spell id: level} from every trainer anyone has recorded. Trainers are the last word:
    Wowhead's Forever data is a copy, a trainer window is the game itself."""
    if not os.path.exists(observed_path):
        return {}
    with open(observed_path, encoding="utf-8") as f:
        union = json.load(f)
    out = {}
    for record in (union.get("trainers") or {}).values():
        for service in record.get("services") or []:
            spell, level = service.get("spell"), service.get("level")
            if spell and level:
                out[int(spell)] = int(level)
    return out


def trainer_classes(observed_path):
    """{CLASS: {spells, floor}} per recorded trainer: what it teaches, and the lowest level it
    would talk about. A character above level 1 is never shown the rungs beneath it, so below
    that floor the trainer's silence proves nothing."""
    if not os.path.exists(observed_path):
        return {}
    with open(observed_path, encoding="utf-8") as f:
        union = json.load(f)
    out = {}
    for record in (union.get("trainers") or {}).values():
        token = record.get("class")
        if not token:
            continue
        spells, names, levels = set(), set(), []
        for service in record.get("services") or []:
            if service.get("spell"):
                spells.add(int(service["spell"]))
            if service.get("name"):
                names.add(service["name"])
            if service.get("level"):
                levels.append(int(service["level"]))
        if not spells:
            continue
        seen = out.setdefault(token, {"spells": set(), "names": set(), "floor": 99})
        seen["spells"] |= spells
        seen["names"] |= names
        seen["floor"] = min(seen["floor"], min(levels) if levels else 99)
    return out


def build(data, acquire=None, trainers=None, offered=None, races=None):
    trainers = trainers or {}
    offered = offered or {}
    races = races or {}
    """{CLASSTOKEN: [{id, name, level, rank, icon}]} sorted by level then name."""
    out = collections.defaultdict(list)
    seen = collections.defaultdict(set)
    for spell_id, entry in data["spells"].items():
        level = trainers.get(int(spell_id)) or entry.get("level")
        if not level:
            continue
        if JUNK.search(entry["name"]):
            continue
        if acquire is not None:
            methods = acquire.get(int(spell_id)) or set()
            if not (methods & TRAINABLE):
                continue
        for klass in entry.get("classes") or []:
            token = CLASS_TOKEN.get(klass)
            if not token:
                continue
            # Two ids for one name at one level is a rank Wowhead did not label; keep the first.
            key = (entry["name"], level)
            if key in seen[token]:
                continue
            # A trainer's own list is the authority. Anything it does not offer is a talent, a
            # pet's trick or some other thing you cannot walk in and buy, unless the game hands
            # it to you with the level (acquire method 2) or the trainer never spoke that low.
            teaches = offered.get(token)
            if teaches and level >= teaches["floor"] and int(spell_id) not in teaches["spells"]:
                methods = (acquire or {}).get(int(spell_id)) or set()
                # A talent's first rank is not sold, but its later ranks are, so a ladder whose
                # name the trainer knows stays whole: Mortal Strike keeps its rank 1 at 40.
                if ("2" not in methods and entry["name"] not in teaches["names"]
                        and not races.get(int(spell_id))):
                    continue
            seen[token].add(key)
            out[token].append({"id": int(spell_id), "name": entry["name"], "level": level,
                               "rank": entry.get("rank") or 0, "icon": entry.get("icon") or "",
                               "trained": int(spell_id) in trainers,
                               "races": races.get(int(spell_id)) or ""})
    for token in out:
        out[token].sort(key=lambda s: (s["level"], s["name"], s["rank"]))
    return out


def emit(abilities, generated, build_id):
    total = sum(len(v) for v in abilities.values())
    lines = ["local _, ns = ...", "",
             "-- GENERATED by tools/build_abilities.py; do not edit by hand.",
             "-- Class spell lists from the client's SkillLineAbility, learn levels from Wowhead's",
             "-- Forever data, or from a trainer window where a player has recorded one: the sixth",
             "-- field is true when a trainer itself said so.",
             "ns.AbilityInfo = { generated = %s, build = %s, classes = %d, abilities = %d }" % (
                 lua_string(generated), lua_string(build_id), len(abilities), total),
             "", "-- [CLASS] = { { spellID, name, level, rank, icon, trainerConfirmed, racesOrFalse }, ... }", "ns.Abilities = {"]
    for token in sorted(abilities):
        lines.append("  %s = {" % token)
        for spell in abilities[token]:
            lines.append("    { %d, %s, %d, %d, %s, %s, %s }," % (
                spell["id"], lua_string(spell["name"]), spell["level"], spell["rank"],
                lua_string(spell["icon"]), "true" if spell["trained"] else "false",
                lua_string(spell["races"]) if spell["races"] else "false"))
        lines.append("  },")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main(argv=None):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", default=os.path.join(root, "tools", "data", "forever-abilities.json"))
    parser.add_argument("--out", default=os.path.join(root, "Data", "Abilities.lua"))
    parser.add_argument("--cache", default=None, help="client table folder; defaults to the json's build")
    parser.add_argument("--observed", default=os.path.join(root, "tools", "observed", "observed.json"),
                        help="merged player records, for trainer levels")
    args = parser.parse_args(argv)
    with open(args.json, encoding="utf-8") as f:
        data = json.load(f)
    cache = args.cache or os.path.join(root, "tools", "cache", data.get("build") or "")
    trainers = trainer_levels(args.observed)
    methods, races = acquire_methods(cache) if os.path.isdir(cache) else (None, {})
    abilities = build(data, methods, trainers, trainer_classes(args.observed), races)
    if trainers:
        disagreed = []
        for token, rows in abilities.items():
            for row in rows:
                if row["trained"]:
                    said = (data["spells"].get(str(row["id"])) or {}).get("level")
                    if said and said != row["level"]:
                        disagreed.append((token, row["name"], said, row["level"]))
        print("%d spells confirmed at a trainer, %d of them at a different level than Wowhead said"
              % (len(trainers), len(disagreed)))
        for token, name, said, real in sorted(disagreed)[:20]:
            print("    %-9s %-28s Wowhead %2d, trainer %2d" % (token, name, said, real))
    if not abilities:
        sys.exit("no abilities parsed from %s" % args.json)
    with open(args.out, "w", encoding="utf-8") as f:
        f.write(emit(abilities, datetime.date.today().isoformat(), data.get("build") or "?"))
    for token in sorted(abilities):
        levels = {s["level"] for s in abilities[token]}
        print("  %-9s %4d abilities over %d levels, first %d, last %d" % (
            token, len(abilities[token]), len(levels), min(levels), max(levels)))
    print("written to %s" % args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
