#!/usr/bin/env python3
"""Build Data/Cities.lua: where the trainers and services stand in each capital.

Usage: python3 tools/build_cities.py

Source is Questie's Classic creature database, which carries each NPC's spawn points per zone
and its title. Questie's flag mask is not the server's, so the title is what decides the kind:
"Warrior Trainer" is a class trainer, "Expert Tailor" and "Herbalism Trainer" are profession
trainers, "Banker" is a bank, "Wind Rider Master" and its kin are flight masters, and an
auctioneer is named rather than titled.

Classic positions. Forever moves and adds NPCs, so the addon marks anything its own records
have seen somewhere else.
"""
import argparse
import collections
import csv
import datetime
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_data import fetch, lua_string, parse_questie  # noqa: E402
from build_dungeons import FILES, QUESTIE, parse_area_maps, field  # noqa: E402

# key, name, Questie zone id, the side whose city it is
CITIES = [
    ("orgrimmar", "Orgrimmar", 1637, "Horde"),
    ("thunderbluff", "Thunder Bluff", 1638, "Horde"),
    ("undercity", "Undercity", 1497, "Horde"),
    ("stormwind", "Stormwind City", 1519, "Alliance"),
    ("ironforge", "Ironforge", 1537, "Alliance"),
    ("darnassus", "Darnassus", 1657, "Alliance"),
]

# One switch each on the map, in this order.
KINDS = ("class", "profession", "weapon", "flight", "bank", "auction")

CLASSES = ("Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid")
PROFESSIONS = ("Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism", "Leatherworking",
               "Mining", "Skinning", "Tailoring", "Cooking", "First Aid", "Fishing", "Poisons")
# "Expert Tailor" and "Apprentice Chef" are trainers too; the noun says which profession.
RANKS = ("Master", "Expert", "Artisan", "Journeyman", "Apprentice")
NOUNS = {"Alchemist": "Alchemy", "Blacksmith": "Blacksmithing", "Enchanter": "Enchanting",
         "Engineer": "Engineering", "Leatherworker": "Leatherworking", "Tailor": "Tailoring",
         "Chef": "Cooking", "Cook": "Cooking", "Miner": "Mining", "Skinner": "Skinning",
         "Herbalist": "Herbalism", "Fisherman": "Fishing"}
FLIGHT = ("Gryphon Master", "Wind Rider Master", "Bat Handler", "Hippogryph Master", "Flight Master")
RANKED = re.compile(r"^(?:%s)\s+(\w+)$" % "|".join(RANKS))


# Questie's coordinates are read off the Classic map. Forever redrew Stormwind to take in the
# harbour, which moves and shrinks everything already on it, so a pin placed at Classic's numbers
# sits up and to the left of where it belongs. Both builds state each map's world bounds in
# UiMapAssignment, and a point's world position has not moved, so Classic UI coordinates convert
# to this build's exactly. Cities whose bounds are unchanged come through untouched.
def map_bounds(path):
    """{UiMapID: (minX, minY, maxX, maxY)} in world coordinates."""
    out = {}
    with open(path, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            out[int(row["UiMapID"])] = (float(row["Region_0"]), float(row["Region_1"]),
                                        float(row["Region_3"]), float(row["Region_4"]))
    return out


def transform_for(era, now):
    """(offsetX, scaleX, offsetY, scaleY) taking Classic UI percentages to this build's."""
    eMinX, eMinY, eMaxX, eMaxY = era
    nMinX, nMinY, nMaxX, nMaxY = now
    spanXe, spanYe = eMaxX - eMinX, eMaxY - eMinY
    spanXn, spanYn = nMaxX - nMinX, nMaxY - nMinY
    if spanXn == 0 or spanYn == 0:
        return None
    # UI x runs along the world's y axis and UI y along its x axis, both counting down.
    return ((nMaxY - eMaxY) / spanYn * 100, spanYe / spanYn,
            (nMaxX - eMaxX) / spanXn * 100, spanXe / spanXn)


def map_transforms(now_path, era_path):
    """{UiMapID: transform} for every map whose bounds moved between the two builds."""
    if not (os.path.exists(now_path) and os.path.exists(era_path)):
        return {}
    now, era = map_bounds(now_path), map_bounds(era_path)
    out = {}
    for ui_map, bounds in now.items():
        old_bounds = era.get(ui_map)
        if old_bounds and old_bounds != bounds:
            moved = transform_for(old_bounds, bounds)
            if moved:
                out[ui_map] = moved
    return out


def move(point, transform):
    if not transform:
        return point
    offsetX, scaleX, offsetY, scaleY = transform
    point["x"] = round(offsetX + point["x"] * scaleX, 1)
    point["y"] = round(offsetY + point["y"] * scaleY, 1)
    return point


def classify(name, sub):
    """(kind, tag) for an NPC, or (None, None) when it is not one of the five."""
    sub = (sub or "").strip()
    if name.startswith("Auctioneer"):
        return "auction", "Auction house"
    if sub == "Banker":
        return "bank", "Bank"
    if sub == "Weapon Master":
        return "weapon", "Weapon master"   # teaches weapon skills; the merchants are vendors
    if sub in FLIGHT:
        return "flight", sub
    if sub.endswith(" Trainer"):
        what = sub[:-len(" Trainer")].strip()
        if what in CLASSES:
            return "class", what
        if what == "Portal":
            return "class", "Mage portals"
        if what in PROFESSIONS:
            return "profession", what
        return None, None
    ranked = RANKED.match(sub)
    if ranked and ranked.group(1) in NOUNS:
        return "profession", NOUNS[ranked.group(1)]
    return None, None


def build(npcs, area_maps, transforms=None):
    transforms = transforms or {}
    cities = []
    for key, name, zone, faction in CITIES:
        points = []
        for npc_id, entry in npcs.items():
            spawns = field(entry, 7)
            if not isinstance(spawns, dict):
                continue
            here = spawns.get(zone)
            if not isinstance(here, list):
                continue
            spot = next((c for c in here if isinstance(c, list) and len(c) == 2), None)
            if not spot:
                continue
            npc_name = field(entry, 1) or "?"
            kind, tag = classify(npc_name, field(entry, 14))
            if not kind:
                continue
            points.append({"id": npc_id, "kind": kind, "name": npc_name, "sub": field(entry, 14) or "",
                           "tag": tag, "x": round(float(spot[0]), 1), "y": round(float(spot[1]), 1)})
        ui_map = area_maps.get(zone, 0)
        for point in points:
            move(point, transforms.get(ui_map))
        points.sort(key=lambda p: (KINDS.index(p["kind"]), p["tag"] or "", p["name"]))
        cities.append({"key": key, "name": name, "zone": zone, "map": ui_map,
                       "faction": faction, "points": points,
                       "moved": bool(transforms.get(ui_map))})
    return cities


def emit(cities, generated):
    total = sum(len(c["points"]) for c in cities)
    lines = ["local _, ns = ...", "",
             "-- GENERATED by tools/build_cities.py from Questie's Classic creature database; do not edit.",
             "-- The kind comes from the NPC's title: Questie's flag mask is not the server's.",
             "ns.CityInfo = { generated = %s, cities = %d, points = %d }" % (
                 lua_string(generated), len(cities), total),
             "", "ns.Cities = {"]
    for city in cities:
        lines.append("  { key = %s, name = %s, zone = %d, map = %d, faction = %s, points = {" % (
            lua_string(city["key"]), lua_string(city["name"]), city["zone"], city["map"],
            lua_string(city["faction"])))
        for p in city["points"]:
            lines.append("    { id = %d, kind = %s, name = %s, sub = %s, tag = %s, x = %.1f, y = %.1f }," % (
                p["id"], lua_string(p["kind"]), lua_string(p["name"]), lua_string(p["sub"]),
                lua_string(p["tag"]) if p["tag"] else "false", p["x"], p["y"]))
        lines.append("  } },")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main(argv=None):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", default=os.path.join(root, "tools", "cache", "questie"))
    parser.add_argument("--out", default=os.path.join(root, "Data", "Cities.lua"))
    parser.add_argument("--build", default="1.60.1.69893", help="this game's client build")
    parser.add_argument("--era", default="1.15.9.69722", help="the Classic build Questie's coordinates came from")
    args = parser.parse_args(argv)

    npcs = parse_questie(fetch(QUESTIE + FILES["classicNpcDB.lua"],
                               os.path.join(args.cache, "classicNpcDB.lua")))
    area_maps = parse_area_maps(fetch(QUESTIE + FILES["areaIdToUiMapId.lua"],
                                      os.path.join(args.cache, "areaIdToUiMapId.lua")))
    builds = os.path.join(root, "tools", "cache")
    transforms = map_transforms(os.path.join(builds, args.build, "UiMapAssignment.csv"),
                                os.path.join(builds, args.era, "UiMapAssignment.csv"))
    cities = build(npcs, area_maps, transforms)
    with open(args.out, "w", encoding="utf-8") as f:
        f.write(emit(cities, datetime.date.today().isoformat()))

    for city in cities:
        counts = collections.Counter(p["kind"] for p in city["points"])
        print("%-16s map %-6s %s%s" % (city["name"], city["map"] or "?",
                                       ", ".join("%s %d" % (k, counts.get(k, 0)) for k in KINDS),
                                       "   (map redrawn, coordinates converted)" if city.get("moved") else ""))
    print("written to %s" % args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
