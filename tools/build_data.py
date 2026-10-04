#!/usr/bin/env python3
"""Regenerate Data/Recipes.lua and Data/Quests.lua for the UsedFor addon.

Sources: Blizzard client tables as CSV from wago.tools, and Questie's classic
quest database from GitHub. Standard library only.

    python3 tools/build_data.py --build 1.15.9.69722
"""
import argparse
import csv
import datetime
import io
import os
import re
import sys
import urllib.request

WAGO_URL = "https://wago.tools/db2/{table}/csv?build={build}"
QUESTIE_URL = "https://raw.githubusercontent.com/Questie/Questie/master/Database/Classic/classicQuestDB.lua"
TABLES = ("SpellReagents", "SkillLineAbility", "SkillLine", "SpellEffect", "SpellName", "ItemSparse")

PROFESSION_CATEGORIES = {"9", "11"}  # SkillLine.CategoryID: 9 = secondary, 11 = primary
EFFECT_CREATE_ITEM = "24"            # SpellEffect.Effect value for "create item"
REAGENT_SLOTS = 8


def read_csv(text):
    return list(csv.DictReader(io.StringIO(text)))


def build_recipes(reagent_rows, ability_rows, skill_rows, effect_rows, name_rows, item_rows):
    """Return {reagent_item_id: [(recipe_name, profession, crafted_id, crafted_name, count), ...]}.

    A profession is any skill line in a profession category; only spells with reagents
    produce entries, so skill lines without recipes (riding, racials) never appear.
    """
    professions = {int(r["ID"]): r["DisplayName_lang"] for r in skill_rows
                   if r["CategoryID"] in PROFESSION_CATEGORIES}
    spell_to_skill = {}
    for r in ability_rows:
        spell_to_skill.setdefault(int(r["Spell"]), int(r["SkillLine"]))
    crafted = {int(r["SpellID"]): int(r["EffectItemType"]) for r in effect_rows
               if r["Effect"] == EFFECT_CREATE_ITEM}
    spell_names = {int(r["ID"]): r["Name_lang"] for r in name_rows}
    item_names = {int(r["ID"]): r["Display_lang"] for r in item_rows}

    out = {}
    seen = set()  # (reagent, recipe name, profession): collapses duplicate spells for one recipe
    for r in reagent_rows:
        spell = int(r["SpellID"])
        profession = professions.get(spell_to_skill.get(spell))
        name = spell_names.get(spell)
        if not profession or not name:
            continue
        crafted_id = crafted.get(spell, 0)
        crafted_name = item_names.get(crafted_id, "") if crafted_id else ""
        for i in range(REAGENT_SLOTS):
            item = int(r[f"Reagent_{i}"])
            count = int(r[f"ReagentCount_{i}"])
            key = (item, name, profession)
            if item > 0 and key not in seen:
                seen.add(key)
                out.setdefault(item, []).append((name, profession, crafted_id, crafted_name, count))
    for entries in out.values():
        entries.sort(key=lambda e: (e[1], e[0]))
    return out


# --- quests -------------------------------------------------------------------

ALLIANCE_MASK = 1 | 4 | 8 | 64     # Human, Dwarf, Night Elf, Gnome (cmangos race bits)
HORDE_MASK = 2 | 16 | 32 | 128     # Orc, Undead, Tauren, Troll

# Questie questKeys positions (Questie/Database/questDB.lua)
Q_NAME, Q_RACES, Q_CLASSES, Q_OBJECTIVES, Q_SOURCE_ITEM, Q_REQ_SOURCE_ITEMS, Q_SPECIAL, Q_REP = 1, 6, 7, 10, 11, 21, 24, 26
ITEM_OBJECTIVE_SLOT = 3  # objectives sub-table: 1 creature, 2 object, 3 item, ...
SPECIAL_REPEATABLE = 1

_NUMBER = re.compile(r"-?\d+(?:\.\d+)?")
_WORD = re.compile(r"nil|true|false")
_IDENTIFIER = re.compile(r"([A-Za-z_][A-Za-z0-9_]*)\s*=\s*")
_ENTRY = re.compile(r"^\[(\d+)\] = ", re.M)


def parse_lua_value(s, i):
    """Parse one Lua literal at s[i]; return (value, index_after).

    Tables with only positional entries become lists (nil kept as None);
    tables with [key]= entries become dicts. Enough for Questie's data files.
    """
    while s[i] in " \t\r\n":
        i += 1
    c = s[i]
    if c == "{":
        i += 1
        items, keyed = [], {}
        while True:
            while s[i] in " \t\r\n,":
                i += 1
            if s[i] == "}":
                return (keyed if keyed else items), i + 1
            if s[i] == "[":
                j = s.index("]", i)
                key = s[i + 1:j].strip().strip("'\"")
                key = int(key) if key.lstrip("-").isdigit() else key
                i = j + 1
                while s[i] in " \t=":
                    i += 1
                value, i = parse_lua_value(s, i)
                keyed[key] = value
            else:
                # A bare key, as the generated data files write them: { key = "rfc", level = 13 }.
                m = _IDENTIFIER.match(s, i)
                if m:
                    i = m.end()
                    value, i = parse_lua_value(s, i)
                    keyed[m.group(1)] = value
                else:
                    value, i = parse_lua_value(s, i)
                    items.append(value)
    if c in "'\"":
        j = i + 1
        out = []
        while s[j] != c:
            if s[j] == "\\":
                out.append(s[j + 1])
                j += 2
            else:
                out.append(s[j])
                j += 1
        return "".join(out), j + 1
    m = _NUMBER.match(s, i)
    if m:
        text = m.group()
        return (float(text) if "." in text else int(text)), m.end()
    m = _WORD.match(s, i)
    if m:
        return {"nil": None, "true": True, "false": False}[m.group()], m.end()
    raise ValueError(f"unexpected Lua at offset {i}: {s[i:i + 40]!r}")


def parse_questie(text):
    """Return {quest_id: entry_list} from Questie's classicQuestDB.lua text."""
    quests = {}
    for m in _ENTRY.finditer(text):
        value, _ = parse_lua_value(text, m.end())
        quests[int(m.group(1))] = value
    return quests


def faction_from_mask(mask):
    if not mask:
        return "B"
    alliance = bool(mask & ALLIANCE_MASK)
    horde = bool(mask & HORDE_MASK)
    unknown = bool(mask & ~(ALLIANCE_MASK | HORDE_MASK))
    if unknown or (alliance and horde):
        return "B"
    return "A" if alliance else "H"


def _field(entry, position):
    return entry[position - 1] if isinstance(entry, list) and len(entry) >= position else None


def _item_objectives(objectives):
    if isinstance(objectives, dict):
        return objectives.get(ITEM_OBJECTIVE_SLOT) or []
    if isinstance(objectives, list) and len(objectives) >= ITEM_OBJECTIVE_SLOT:
        return objectives[ITEM_OBJECTIVE_SLOT - 1] or []
    return []


def build_quests(quests):
    """Return {item_id: [(quest_id, name, kind, repeatable, faction, class_mask, rep), ...]}.

    rep is a tuple of (faction_id, amount) pairs rewarded on turn-in, or () when none.
    """
    out = {}
    for quest_id, entry in sorted(quests.items()):
        name = _field(entry, Q_NAME)
        if not isinstance(name, str):
            continue
        faction = faction_from_mask(_field(entry, Q_RACES) or 0)
        class_mask = _field(entry, Q_CLASSES) or 0
        repeatable = bool((_field(entry, Q_SPECIAL) or 0) & SPECIAL_REPEATABLE)
        rep = tuple((pair[0], pair[1]) for pair in (_field(entry, Q_REP) or [])
                    if isinstance(pair, list) and len(pair) >= 2 and isinstance(pair[0], int) and isinstance(pair[1], int))
        uses = []
        for objective in _item_objectives(_field(entry, Q_OBJECTIVES)):
            if isinstance(objective, list) and objective and isinstance(objective[0], int):
                uses.append((objective[0], "objective"))
        source = _field(entry, Q_SOURCE_ITEM)
        if isinstance(source, int) and source > 0:
            uses.append((source, "provided"))
        for item in _field(entry, Q_REQ_SOURCE_ITEMS) or []:
            if isinstance(item, int) and item > 0:
                uses.append((item, "needed"))
        seen = set()
        for item, kind in uses:
            if (item, kind) in seen:
                continue
            seen.add((item, kind))
            out.setdefault(item, []).append((quest_id, name, kind, repeatable, faction, class_mask, rep))
    for entries in out.values():
        entries.sort(key=lambda e: (e[1], e[0]))
    return out


# --- output -------------------------------------------------------------------

def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def emit_recipes(recipes, info):
    lines = [
        "local _, ns = ...",
        "",
        "-- GENERATED by tools/build_data.py; do not edit by hand.",
        "ns.DataInfo = { build = %s, generated = %s, recipes = %d, quests = %d }" % (
            lua_string(info["build"]), lua_string(info["generated"]), info["recipes"], info["quests"]),
        "",
        "ns.Recipes = {",
        "  -- [reagentItemID] = { { recipeName, professionName, craftedItemID, craftedItemName, reagentCount }, ... }",
    ]
    for item in sorted(recipes):
        entries = ", ".join(
            "{ %s, %s, %d, %s, %d }" % (lua_string(name), lua_string(prof), crafted_id, lua_string(crafted_name), count)
            for name, prof, crafted_id, crafted_name, count in recipes[item])
        lines.append("  [%d] = { %s }," % (item, entries))
    lines.append("}")
    return "\n".join(lines) + "\n"


def emit_quests(quests):
    lines = [
        "local _, ns = ...",
        "",
        "-- GENERATED by tools/build_data.py; do not edit by hand.",
        "ns.Quests = {",
        "  -- [itemID] = { { questID, questName, kind, repeatable, faction, classMask, rep{ { factionID, amount } }|false }, ... }",
    ]
    for item in sorted(quests):
        entries = ", ".join(
            "{ %d, %s, %s, %s, %s, %d, %s }" % (
                quest_id, lua_string(name), lua_string(kind), "true" if repeatable else "false",
                lua_string(faction), class_mask,
                ("{ " + ", ".join("{ %d, %d }" % pair for pair in rep) + " }") if rep else "false")
            for quest_id, name, kind, repeatable, faction, class_mask, rep in quests[item])
        lines.append("  [%d] = { %s }," % (item, entries))
    lines.append("}")
    return "\n".join(lines) + "\n"


# --- fetching and main --------------------------------------------------------

def check_rows(table, rows, build):
    if not rows or "ID" not in rows[0]:
        sys.exit(f"{table}: no usable rows for build {build} (wrong build number, or wago.tools changed)")
    return rows


def fetch(url, cache_path):
    """Download url to cache_path once; later runs read the cached copy."""
    if os.path.exists(cache_path):
        with open(cache_path, encoding="utf-8") as f:
            return f.read()
    request = urllib.request.Request(url, headers={"User-Agent": "UsedFor build_data.py"})
    last_error = None
    for attempt in range(3):  # wago.tools occasionally resets long downloads
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                text = response.read().decode("utf-8")
            break
        except OSError as error:
            last_error = error
            print(f"retry {attempt + 1}/3 for {url}: {error}", file=sys.stderr)
    else:
        raise last_error
    os.makedirs(os.path.dirname(cache_path), exist_ok=True)
    with open(cache_path, "w", encoding="utf-8") as f:
        f.write(text)
    return text


def main(argv=None):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--build", required=True, help="client build number, e.g. 1.15.9.69722")
    parser.add_argument("--out", default=os.path.join(root, "Data"), help="output folder (default: Data/)")
    parser.add_argument("--cache", default=os.path.join(root, "tools", "cache"), help="download cache folder")
    args = parser.parse_args(argv)

    cache = os.path.join(args.cache, args.build)
    tables = {}
    for table in TABLES:
        text = fetch(WAGO_URL.format(table=table, build=args.build), os.path.join(cache, table + ".csv"))
        tables[table] = check_rows(table, read_csv(text), args.build)
    recipes = build_recipes(tables["SpellReagents"], tables["SkillLineAbility"], tables["SkillLine"],
                            tables["SpellEffect"], tables["SpellName"], tables["ItemSparse"])
    quests = build_quests(parse_questie(fetch(QUESTIE_URL, os.path.join(cache, "classicQuestDB.lua"))))

    info = {"build": args.build, "generated": datetime.date.today().isoformat(),
            "recipes": len(recipes), "quests": len(quests)}
    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "Recipes.lua"), "w", encoding="utf-8") as f:
        f.write(emit_recipes(recipes, info))
    with open(os.path.join(args.out, "Quests.lua"), "w", encoding="utf-8") as f:
        f.write(emit_quests(quests))
    print(f"build {args.build}: {info['recipes']} reagent items, {info['quests']} quest items -> {args.out}")


if __name__ == "__main__":
    main()
