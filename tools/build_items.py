#!/usr/bin/env python3
"""Regenerate Data/Items.lua: equippable items with resolved stats, from the WoWSims item database.

Source: https://github.com/wowsims/<game>/blob/master/assets/database/db.json (MIT). Items are
uncommon quality and up, stats already resolved from tooltips, plus drop/quest/vendor/craft sources.
Standard library only.

    python3 tools/build_items.py --game classic
"""
import argparse
import datetime
import json
import os
import sys

from build_data import fetch, lua_string

GAMES = ("classic", "sod", "tbc", "wotlk")
DB_URL = "https://raw.githubusercontent.com/wowsims/{game}/master/assets/database/db.json"

# proto/common.proto enum Stat, index order. Names match Data/Weights.lua.
STAT_NAMES = [
    "Strength", "Agility", "Stamina", "Intellect", "Spirit", "SpellPower", "ArcanePower", "FirePower",
    "FrostPower", "HolyPower", "NaturePower", "ShadowPower", "MP5", "SpellHit", "SpellCrit", "SpellHaste",
    "SpellPenetration", "AttackPower", "MeleeHit", "MeleeCrit", "MeleeHaste", "ArmorPenetration", "Expertise",
    "Mana", "Energy", "Rage", "Armor", "RangedAttackPower", "Defense", "Block", "BlockValue", "Dodge", "Parry",
    "Resilience", "Health", "ArcaneResistance", "FireResistance", "FrostResistance", "NatureResistance",
    "ShadowResistance", "BonusArmor", "HealingPower", "SpellDamage", "FeralAttackPower",
]
CLASS_TOKENS = {1: "DRUID", 2: "HUNTER", 3: "MAGE", 4: "PALADIN", 5: "PRIEST", 6: "ROGUE", 7: "SHAMAN", 8: "WARLOCK", 9: "WARRIOR"}
FACTIONS = {1: "A", 2: "H"}
PROFESSIONS = {1: "Alchemy", 2: "Blacksmithing", 3: "Enchanting", 4: "Engineering", 5: "Herbalism",
               8: "Leatherworking", 9: "Mining", 10: "Skinning", 11: "Tailoring"}
ITEM_TYPES = {1: "Head", 2: "Neck", 3: "Shoulder", 4: "Back", 5: "Chest", 6: "Wrist", 7: "Hands", 8: "Waist",
              9: "Legs", 10: "Feet", 11: "Finger", 12: "Trinket", 13: "Weapon", 14: "Ranged"}
ARMOR_TYPES = {1: "Cloth", 2: "Leather", 3: "Mail", 4: "Plate"}
WEAPON_TYPES = {1: "Axe", 2: "Dagger", 3: "Fist", 4: "Mace", 5: "OffHand", 6: "Polearm", 7: "Shield", 8: "Staff", 9: "Sword"}
HAND_TYPES = {1: "MainHand", 2: "OneHand", 3: "OffHand", 4: "TwoHand"}
RANGED_TYPES = {1: "Bow", 2: "Crossbow", 3: "Gun", 4: "Idol", 5: "Libram", 6: "Thrown", 7: "Totem", 8: "Wand", 9: "Sigil"}


def stats_map(values):
    """Stat array (proto order) -> {name: value} with zeros dropped."""
    if len(values) != len(STAT_NAMES):
        raise ValueError("expected %d stats, got %d" % (len(STAT_NAMES), len(values)))
    return {STAT_NAMES[i]: v for i, v in enumerate(values) if v}


def sources_list(item):
    """Normalise WoWSims sources to (kind, id, extra) tuples, deduplicated, order kept."""
    out, seen = [], set()
    for source in item.get("sources", []):
        for kind, body in source.items():
            if kind == "drop":
                entry = ("drop", body.get("npcId", 0), body.get("zoneId", 0))
            elif kind == "quest":
                entry = ("quest", body.get("id", 0), body.get("name", ""))
            elif kind == "crafted":
                entry = ("crafted", body.get("spellId", 0), PROFESSIONS.get(body.get("profession"), ""))
            elif kind == "soldBy":
                entry = ("vendor", body.get("npcId", 0), body.get("npcName", ""))
            elif kind == "rep":
                entry = ("rep", body.get("repFactionId", 0), body.get("repLevel", 0))
            else:
                continue
            if entry not in seen:
                seen.add(entry)
                out.append(entry)
    return out


def item_record(item):
    weapon = None
    if item.get("weaponSpeed"):
        weapon = (item.get("weaponDamageMin", 0), item.get("weaponDamageMax", 0), item["weaponSpeed"])
    classes = [CLASS_TOKENS[c] for c in item.get("classAllowlist", []) if c in CLASS_TOKENS]
    return {
        "id": item["id"], "name": item["name"], "quality": item.get("quality", 0), "ilvl": item.get("ilvl", 0),
        "type": item.get("type", 0), "armorType": item.get("armorType", 0), "weaponType": item.get("weaponType", 0),
        "handType": item.get("handType", 0), "rangedType": item.get("rangedWeaponType", 0), "phase": item.get("phase", 0),
        "stats": stats_map(item["stats"]), "weapon": weapon, "unique": bool(item.get("unique")),
        "faction": FACTIONS.get(item.get("factionRestriction")), "classes": classes,
        "setName": item.get("setName"), "sources": sources_list(item),
    }


def _lua_stats(stats):
    if not stats:
        return "{ }"
    return "{ " + ", ".join("%s = %s" % (name, "%g" % stats[name]) for name in sorted(stats)) + " }"


def _lua_value(v):
    if v is None or v is False:
        return "false"
    if v is True:
        return "true"
    if isinstance(v, str):
        return lua_string(v)
    if isinstance(v, float):
        return "%g" % v
    return str(v)


def _lua_sources(sources):
    if not sources:
        return "false"
    return "{ " + ", ".join("{ %s, %s, %s }" % (lua_string(k), _lua_value(a), _lua_value(b)) for k, a, b in sources) + " }"


def _lua_enum(table):
    return "{ " + ", ".join("[%d] = %s" % (k, lua_string(table[k])) for k in sorted(table)) + " }"


def emit_items(records, npcs, zones, info):
    lines = [
        "local _, ns = ...",
        "",
        "-- GENERATED by tools/build_items.py from WoWSims (https://github.com/wowsims, MIT); do not edit by hand.",
        "ns.ItemsInfo = { game = %s, generated = %s, items = %d }" % (lua_string(info["game"]), lua_string(info["generated"]), len(records)),
        "ns.ItemTypes = %s" % _lua_enum(ITEM_TYPES),
        "ns.ArmorTypes = %s" % _lua_enum(ARMOR_TYPES),
        "ns.WeaponTypes = %s" % _lua_enum(WEAPON_TYPES),
        "ns.HandTypes = %s" % _lua_enum(HAND_TYPES),
        "ns.RangedTypes = %s" % _lua_enum(RANGED_TYPES),
        "ns.ItemZones = { " + ", ".join("[%d] = %s" % (z, lua_string(zones[z])) for z in sorted(zones)) + " }",
        "ns.ItemNpcs = { " + ", ".join("[%d] = %s" % (n, lua_string(npcs[n])) for n in sorted(npcs)) + " }",
        "",
        "ns.Items = {",
        "  -- [itemID] = { name, quality, ilvl, type, armorType, weaponType, handType, rangedType, phase,",
        "  --              stats{ StatName = value }, weapon{ min, max, speed }|false, unique, faction \"A\"|\"H\"|false,",
        "  --              classes{ CLASSTOKEN }|false, setName|false, sources{ { kind, id, extra } }|false }",
    ]
    for r in sorted(records, key=lambda r: r["id"]):
        weapon = "{ %s, %s, %s }" % tuple(_lua_value(v) for v in r["weapon"]) if r["weapon"] else "false"
        classes = ("{ " + ", ".join(lua_string(c) for c in r["classes"]) + " }") if r["classes"] else "false"
        lines.append("  [%d] = { %s, %d, %d, %d, %d, %d, %d, %d, %d, %s, %s, %s, %s, %s, %s, %s }," % (
            r["id"], lua_string(r["name"]), r["quality"], r["ilvl"], r["type"], r["armorType"], r["weaponType"],
            r["handType"], r["rangedType"], r["phase"], _lua_stats(r["stats"]), weapon, _lua_value(r["unique"]),
            _lua_value(r["faction"]), classes, _lua_value(r["setName"]), _lua_sources(r["sources"])))
    lines.append("}")
    return "\n".join(lines) + "\n"


def build(db):
    records = [item_record(item) for item in db["items"] if item.get("type") in ITEM_TYPES]
    npcs = {n["id"]: n["name"] for n in db.get("npcs", [])}
    zones = {z["id"]: z["name"] for z in db.get("zones", [])}
    return records, npcs, zones


def main(argv=None):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--game", default="classic", choices=GAMES)
    parser.add_argument("--out", default=os.path.join(root, "Data", "Items.lua"))
    parser.add_argument("--cache", default=os.path.join(root, "tools", "cache"))
    args = parser.parse_args(argv)

    cache = os.path.join(args.cache, "wowsims-" + args.game)
    db = json.loads(fetch(DB_URL.format(game=args.game), os.path.join(cache, "db.json")))
    records, npcs, zones = build(db)
    if not records:
        sys.exit("no items found for " + args.game)
    info = {"game": args.game, "generated": datetime.date.today().isoformat()}
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        f.write(emit_items(records, npcs, zones, info))
    print("%s: %d items, %d npcs, %d zones -> %s" % (args.game, len(records), len(npcs), len(zones), args.out))


if __name__ == "__main__":
    main()
