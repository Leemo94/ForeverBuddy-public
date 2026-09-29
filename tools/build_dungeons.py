"""Build Data/Dungeons.lua and Data/Zones.lua from Questie's Classic database.

Dungeons.lua: for each Classic dungeon, every quest tied to it with where to
pick it up (NPC, zone, coordinates), faction and class limits, the chain in
front of it, the turn-in, and whether it can be shared.

Zones.lua: for each open-world zone, the level range its quests cover and the
faction it leans to, derived from the same quest data.

A quest belongs to a dungeon when any of these hold:
  - the game files it under the dungeon (zoneOrSort == dungeon area id);
  - a kill or object objective lives inside (the NPC/object's PRIMARY zone is
    the dungeon; critters that spawn in many zones only count for their primary zone);
  - a quest-item objective (item class 12) drops from such an NPC or object;
  - the quest giver or turn-in NPC stands inside.
Cloth, leather and other ordinary drops must not count, or every dungeon would
claim every "bring me 20 Linen Cloth" quest.

Shareable = questFlags bit 8. Otherwise "chain" when the quest has a
prerequisite, a follow-up or a parent, else "single" (usually item-started).

Usage: python3 tools/build_dungeons.py            # fetches Questie files into tools/cache/questie/
"""
import argparse
import datetime
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_data import fetch, lua_string, parse_lua_value, parse_questie  # noqa: E402

QUESTIE = "https://raw.githubusercontent.com/Questie/Questie/master/"
FILES = {
    "classicQuestDB.lua": "Database/Classic/classicQuestDB.lua",
    "classicNpcDB.lua": "Database/Classic/classicNpcDB.lua",
    "classicObjectDB.lua": "Database/Classic/classicObjectDB.lua",
    "classicItemDB.lua": "Database/Classic/classicItemDB.lua",
    "lookupZones.lua": "Localization/lookups/lookupZones.lua",
    "subZoneToParentZone.lua": "Database/Zones/data/subZoneToParentZone.lua",
    "areaIdToUiMapId.lua": "Database/Zones/data/areaIdToUiMapId.lua",
}

# The dungeon's own loading screen, as a FileDataID, for the cover behind each card in the
# journal. Joined out of the client's own tables for build 1.60.1.69893: Map.db2 gives each
# instance a LoadingScreenID, and LoadingScreens.db2 turns that into a file - NarrowScreen for
# the Classic dungeons, MainImage for the ones Forever added. To refresh after a patch, fetch
# both tables from wago.tools with that build number and join them on LoadingScreenID again.
LOADING_SCREENS = {
    "hallofthanes": 7963781,
    "ruinsoflordaeron": 7963782,
    "excavationwetlands": 7963777,
    "ragefirechasm": 131862,
    "wailingcaverns": 131882,
    "deadmines": 131833,
    "shadowfangkeep": 131869,
    "stockade": 131870,
    "blackfathomdeeps": 131823,
    "gnomeregan": 131841,
    "razorfenkraul": 131865,
    "scarletmonastery": 131852,
    "razorfendowns": 131864,
    "uldaman": 131876,
    "zulfarrak": 131885,
    "maraudon": 131850,
    "sunkentemple": 131872,
    "blackrockdepths": 131824,
    "blackrockspire": 131825,
    "diremaul": 131835,
    "scholomance": 131868,
    "stratholme": 131871,
}

# key, name, Questie/AreaTable zone id, recommended level range, faction whose city holds the entrance (or None), aliases
DUNGEONS = [
    # Forever's own dungeons. Their minimum levels come from the client's ContentTuning table;
    # they hold no quests here until someone records or writes them up.
    ("hallofthanes", "The Hall of Thanes", 16919, 13, 20, "Alliance", ["hot", "thanes", "hall"]),
    # Both sides quest here, so no emblem: the Horde chain starts in the Undercity and the
    # Alliance one starts on Captain Truman inside.
    ("ruinsoflordaeron", "Ruins of Lordaeron", 16611, 15, 22, None, ["rol", "lordaeron", "ruins"]),
    ("excavationwetlands", "Excavation Site: Wetlands", 16732, 26, 33, None, ["esw", "excavation", "wetlandsdig"]),
    ("ragefirechasm", "Ragefire Chasm", 2437, 13, 18, "Horde", ["rfc", "ragefire"]),
    ("wailingcaverns", "Wailing Caverns", 718, 17, 24, None, ["wc", "wailing"]),
    ("deadmines", "The Deadmines", 1581, 17, 26, None, ["dm", "vc", "deadmines"]),
    ("shadowfangkeep", "Shadowfang Keep", 209, 22, 30, None, ["sfk", "shadowfang"]),
    ("stockade", "The Stockade", 717, 22, 30, "Alliance", ["stocks", "stockades", "stockade"]),
    ("blackfathomdeeps", "Blackfathom Deeps", 719, 24, 32, None, ["bfd", "blackfathom"]),
    ("gnomeregan", "Gnomeregan", 721, 29, 38, None, ["gnomer", "gnome"]),
    ("razorfenkraul", "Razorfen Kraul", 491, 29, 38, None, ["rfk", "kraul"]),
    ("scarletmonastery", "Scarlet Monastery", 796, 34, 45, None, ["sm", "scarlet", "monastery"]),
    ("razorfendowns", "Razorfen Downs", 722, 37, 46, None, ["rfd", "downs"]),
    ("uldaman", "Uldaman", 1337, 41, 51, None, ["uld"]),
    ("zulfarrak", "Zul'Farrak", 1176, 44, 54, None, ["zf", "zulfarrak", "farrak"]),
    ("maraudon", "Maraudon", 2100, 46, 55, None, ["mara"]),
    ("sunkentemple", "Sunken Temple", 1477, 50, 60, None, ["st", "sunken", "atalhakkar", "temple"]),
    ("blackrockdepths", "Blackrock Depths", 1584, 52, 60, None, ["brd", "depths"]),
    ("blackrockspire", "Blackrock Spire", 1583, 55, 60, None, ["brs", "lbrs", "ubrs", "spire"]),
    ("diremaul", "Dire Maul", 2557, 55, 60, None, ["dire", "maul"]),
    ("stratholme", "Stratholme", 2017, 58, 60, None, ["strat"]),
    ("scholomance", "Scholomance", 2057, 58, 60, None, ["scholo"]),
]
DUNGEON_ZONES = {d[2] for d in DUNGEONS}

# Quests written up by hand, for dungeons the Classic database knows nothing about. Ids and
# levels are checked against Wowhead's Forever data; places come from playing and from what the
# collector recorded. Anything here is merged on top of what the rules find.
CURATED = {
    "ruinsoflordaeron": [
        {"id": 92401, "name": "A Frightened Request", "level": 22, "faction": "Horde", "share": "yes",
         "giver": {"name": "Tabitha Heartweaver", "where": "Silverpine Forest", "map": 1421, "x": None, "y": None, "kind": "npc"},
         "note": "At the Sepulcher"},
        {"id": 95216, "name": "The New Plague", "level": 22, "faction": "Horde", "share": "yes",
         "giver": {"name": "Theodore Griffs", "where": "Undercity", "map": 1458, "x": None, "y": None, "kind": "npc"},
         "note": "In the Apothecarium: take the path under it, not the corridor to the Royal Quarters"},
        {"id": 92422, "name": "The Wrath of Rath'mael", "level": 22, "faction": "Horde", "share": "yes",
         "giver": {"name": "Deathguard Kristof", "where": "Tirisfal Glades", "map": 1420, "x": 65.5, "y": 60.0, "kind": "npc"},
         "note": "Outside the Undercity, on the path to the right, near the skinning trainer"},
        {"id": 92421, "name": "Light's Justice", "level": 22, "faction": "Horde", "share": "yes",
         "giver": {"name": "Morbin Lightbane", "where": "Undercity", "map": 1458, "x": None, "y": None, "kind": "npc"},
         "note": "In the Royal Quarters, next to Sylvanas"},
        {"id": 95250, "name": "Abominable Creatures", "level": 21, "faction": "Alliance", "share": "yes",
         "inside": "start",
         "giver": {"name": "Captain Truman", "where": "Ruins of Lordaeron", "map": None, "x": None, "y": None, "kind": "npc"},
         "note": "Inside the dungeon: turn left as you enter. Handed in to him as well"},
    ],
    # Found by matching Forever's new quest ids against Wowhead's Forever data: their objectives
    # name the dungeon. Givers are not in that data, so they wait for someone to play them.
    "hallofthanes": [
        {"id": 96395, "name": "An Ancient Grudge", "level": 15, "faction": None, "share": "yes",
         "note": "Put the spirit of Faldrim Anvilmar to rest. Giver not known yet"},
        {"id": 96403, "name": "Important Heirlooms", "level": 15, "faction": None, "share": "yes",
         "note": "Collect 8 Dwarven Heirlooms. Giver not known yet"},
        {"id": 96393, "name": "Old Ironforge Incursion", "level": 16, "faction": None, "share": "yes",
         "note": "Claim the Head of Durgen Dirgehammer beneath Old Ironforge. Giver not known yet"},
    ],
}
CITY_ZONES = {1497, 1519, 1537, 1637, 1638, 1657}
RAID_AND_OTHER_ZONES = {2159, 2717, 2677, 1977, 3428, 3429, 2597, 3277, 3358, 2257, 1941, 2079}  # Onyxia, MC, BWL, ZG, AQ, AV, WSG, AB, tram, CoT, Alcaz
ALLIANCE_MASK, HORDE_MASK = 77, 178
SHARE_FLAG = 8
QUEST_ITEM_CLASS = 12
CLASS_NAMES = {1: "Warrior", 2: "Paladin", 4: "Hunter", 8: "Rogue", 16: "Priest", 64: "Shaman", 128: "Mage", 256: "Warlock", 1024: "Druid"}


# --- parsing -------------------------------------------------------------------

def parse_db(text, marker):
    """Return the table inside `<marker> = [[return { ... }]]` of a Questie data file."""
    i = text.index(marker)
    j = text.index("[[return ", i) + len("[[return ")
    k = text.index("]]", j)
    value, _ = parse_lua_value(text[j:k].strip(), 0)
    return value


CONTINENTS = {0: "Eastern Kingdoms", 1: "Kalimdor"}  # zoneLookup block keys; other blocks are instance maps


def parse_zone_names(text):
    """{zoneId: name} and {zoneId: continentName} from lookupZones.lua (blocks keyed by map: 0 = EK, 1 = Kalimdor)."""
    names, continents = {}, {}
    block = text[text.index("l10n.zoneLookup"):]
    continent = None
    for m in re.finditer(r'\[(\d+)\]\s*=\s*(\{|"([^"]*)")', block):
        key, opener, value = int(m.group(1)), m.group(2), m.group(3)
        if opener == "{":
            continent = CONTINENTS.get(key)
        elif not (key == 0 and value in CONTINENTS.values()):
            names[key] = value
            continents[key] = continent
    return names, continents


def parse_subzones(text):
    return {int(a): int(b) for a, b in re.findall(r"\[(\d+)\]\s*=\s*(\d+)", text)}


def parse_area_maps(text):
    """{areaId: uiMapId}; the map ids the client's C_Map functions and the arrow use."""
    return {int(a): int(b) for a, b in re.findall(r"\[(\d+)\]\s*=\s*(\d+)", text) if int(b) > 0}


# --- helpers ------------------------------------------------------------------

def field(entry, position):
    return entry[position - 1] if entry and len(entry) >= position else None


def as_list(value):
    if isinstance(value, list):
        return value
    if isinstance(value, dict):
        return list(value.values())
    return []


def as_positional(value):
    """Questie writes {a, b, c} tables that our parser may return as a list or a {1:..} dict."""
    if isinstance(value, dict):
        return value
    if isinstance(value, list):
        return {i + 1: v for i, v in enumerate(value)}
    return {}


def zones_of(entry, spawns_pos, zone_pos):
    """The zones an NPC/object belongs to: its primary zone, or its only spawn zone."""
    if not entry:
        return set()
    spawns = field(entry, spawns_pos)
    zones = set(spawns.keys()) if isinstance(spawns, dict) else set()
    primary = field(entry, zone_pos)
    if primary:
        return {primary} if len(zones) > 1 else (zones | {primary})
    return zones


def first_spawn(entry, spawns_pos, zone_pos):
    """(zoneId, x, y) of the first listed spawn, or (primaryZone, None, None)."""
    spawns = field(entry, spawns_pos) if entry else None
    if isinstance(spawns, dict):
        for zone, points in spawns.items():
            points = as_list(points)
            if points and isinstance(points[0], list) and points[0][0] is not None and points[0][0] >= 0:
                return zone, points[0][0], points[0][1]
            return zone, None, None
    return (field(entry, zone_pos) if entry else None), None, None


def faction_of(entry, world=None):
    """The side a quest belongs to: its own race mask first, then whoever hands it out. A quest
    open to every race is still one side's quest when only that side can talk to its giver."""
    races = field(entry, 6) or 0
    if races not in (0, 255):
        a, h = races & ALLIANCE_MASK, races & HORDE_MASK
        if a and not h:
            return "Alliance"
        if h and not a:
            return "Horde"
    return world.giver_faction(entry) if world else None


def share_of(entry):
    if (field(entry, 23) or 0) & SHARE_FLAG:
        return "yes"
    chained = as_list(field(entry, 12)) or as_list(field(entry, 13)) or field(entry, 22) or field(entry, 25)
    return "chain" if chained else "single"


class World:
    def __init__(self, quests, npcs, objects, items, zone_names, continents, subzones, area_maps=None):
        self.quests, self.npcs, self.objects, self.items = quests, npcs, objects, items
        self.zone_names, self.continents, self.subzones = zone_names, continents, subzones
        self.area_maps = area_maps or {}

    def zone_name(self, zone):
        return self.zone_names.get(zone, "zone %s" % zone)

    def npc_zones(self, npc):
        return zones_of(self.npcs.get(npc), 7, 9)

    def object_zones(self, obj):
        return zones_of(self.objects.get(obj), 4, 5)

    def place(self, kind, ident):
        """{name, where, x, y, kind} for an NPC or object id."""
        if kind == "npc":
            entry = self.npcs.get(ident)
            zone, x, y = first_spawn(entry, 7, 9)
        else:
            entry = self.objects.get(ident)
            zone, x, y = first_spawn(entry, 4, 5)
        if not entry:
            return None
        return {"name": field(entry, 1), "where": self.zone_name(zone) if zone else None, "x": x, "y": y, "kind": kind,
                "map": self.area_maps.get(zone) if zone else None}

    def giver(self, entry):
        started = as_positional(field(entry, 2))
        for npc in as_list(started.get(1)):
            p = self.place("npc", npc)
            if p:
                return p
        for obj in as_list(started.get(2)):
            p = self.place("object", obj)
            if p:
                return p
        for item in as_list(started.get(3)):
            it = self.items.get(item)
            if it:
                return {"name": field(it, 1), "where": None, "x": None, "y": None, "kind": "item"}
        return None

    def turnin(self, entry):
        finished = as_positional(field(entry, 3))
        for npc in as_list(finished.get(1)):
            p = self.place("npc", npc)
            if p:
                return p
        for obj in as_list(finished.get(2)):
            p = self.place("object", obj)
            if p:
                return p
        return None

    def giver_faction(self, entry):
        """Alliance or Horde when only one side's NPCs offer or take this quest."""
        sides = set()
        for position, index in ((2, 1), (3, 1)):        # startedBy and finishedBy creatures
            for npc in as_list(field(as_list(field(entry, position)), index)) or []:
                friendly = field(self.npcs.get(npc), 13)
                if friendly in ("A", "H"):
                    sides.add(friendly)
        if len(sides) == 1:
            return "Alliance" if sides.pop() == "A" else "Horde"
        return None

    def chain(self, quest_id, depth=0):
        """Prerequisites from the root down to the direct parent: [(id, name, giver, faction)].
        A step inherits the side of the chain: you cannot reach a Horde quest through an
        Alliance one, so the first step of the Defias chain is as Alliance as its last."""
        entry = self.quests.get(quest_id)
        if not entry or depth > 8:
            return []
        pres = as_list(field(entry, 13)) or as_list(field(entry, 12))
        if not pres:
            return []
        parent = pres[0]
        p = self.quests.get(parent)
        if not p:
            return []
        return self.chain(parent, depth + 1) + [(parent, field(p, 1), self.giver(p), faction_of(p, self))]

    def drops_mostly_in(self, item, zone):
        """True when at least half of the item's droppers (NPCs and objects) live in the zone.
        Crocolisk Skin drops from crocolisks everywhere, so one dropper in Wailing Caverns must not count."""
        droppers = [("npc", n) for n in as_list(field(item, 2))] + [("object", o) for o in as_list(field(item, 3))]
        if not droppers:
            return False
        inside = sum(1 for kind, ident in droppers if zone in (self.npc_zones(ident) if kind == "npc" else self.object_zones(ident)))
        return inside * 2 >= len(droppers)

    def match(self, entry, zone):
        """Why a quest belongs to a dungeon zone, as a list of tags (empty = it doesn't)."""
        why = []
        if field(entry, 17) == zone:
            why.append("sort")
        objectives = as_positional(field(entry, 10))
        if any(zone in self.npc_zones(c[0]) for c in as_list(objectives.get(1)) if isinstance(c, list) and c):
            why.append("kill")
        if any(zone in self.object_zones(o[0]) for o in as_list(objectives.get(2)) if isinstance(o, list) and o):
            why.append("object")
        for it in as_list(objectives.get(3)):
            item = self.items.get(it[0]) if isinstance(it, list) and it else None
            if item and field(item, 12) == QUEST_ITEM_CLASS and self.drops_mostly_in(item, zone):
                why.append("drop")
                break
        started = as_positional(field(entry, 2))
        if any(zone in self.npc_zones(n) for n in as_list(started.get(1))):
            why.append("starts-inside")
        finished = as_positional(field(entry, 3))
        if any(zone in self.npc_zones(n) for n in as_list(finished.get(1))):
            why.append("ends-inside")
        return why


# --- dungeons -----------------------------------------------------------------

def curated_rows(key):
    """Hand-written quests for a dungeon, in the shape the emitter expects."""
    rows = []
    for entry in CURATED.get(key, []):
        rows.append({
            "id": entry["id"], "name": entry["name"], "level": entry.get("level", 0), "req": entry.get("req", 0),
            "faction": entry.get("faction"), "classes": entry.get("classes", 0), "share": entry.get("share", "single"),
            "repeatable": entry.get("repeatable", False), "inside": entry.get("inside"),
            "giver": entry.get("giver"), "turnin": entry.get("turnin") or entry.get("giver"),
            "pre": [], "note": entry.get("note"),
        })
    return rows


def build_dungeons(world):
    out = []
    for key, name, zone, lo, hi, faction, aliases in DUNGEONS:
        rows = []
        for quest_id, entry in world.quests.items():
            why = world.match(entry, zone)
            if not why:
                continue
            rows.append({
                "id": quest_id, "name": field(entry, 1), "level": field(entry, 5) or 0, "req": field(entry, 4) or 0,
                "faction": faction_of(entry, world), "classes": field(entry, 7) or 0, "share": share_of(entry),
                "repeatable": bool((field(entry, 24) or 0) & 1),
                "giver": world.giver(entry), "turnin": world.turnin(entry), "pre": world.chain(quest_id),
                "inside": "start" if "starts-inside" in why else ("end" if "ends-inside" in why else None),
            })
        # A step with no side of its own takes the side of the quest it leads to: you cannot
        # reach an Alliance quest through a chain the Horde can finish.
        for row in rows:
            if row["faction"]:
                row["pre"] = [(pid, pname, pgiver, pfaction or row["faction"])
                              for pid, pname, pgiver, pfaction in row["pre"]]
        have = {r["id"] for r in rows}
        rows.extend(r for r in curated_rows(key) if r["id"] not in have)
        rows.sort(key=lambda r: (r["level"], r["name"]))
        out.append({"key": key, "name": name, "zone": zone, "lo": lo, "hi": hi, "faction": faction, "aliases": aliases,
                    "screen": LOADING_SCREENS.get(key), "quests": rows})
    out.sort(key=lambda d: (d["lo"], d["hi"], d["name"]))
    return out


# --- zones --------------------------------------------------------------------

# Forever's own zones, and anything the quest data cannot see. Ranges here are what public
# previews and guides report, not client data, and are marked as such in the output.
CURATED_ZONES = [
    ("Zephras Isle", "Kalimdor", 1, 12, "reported"),
    ("Riverglades", "Eastern Kingdoms", 33, 45, "reported"),
]

# Ranges the quest levels alone get wrong. Dun Morogh's quests run up to 30 because the
# Gnomeregan chain starts there, but it is a starting zone and should read as one.
ZONE_OVERRIDES = {
    "Dun Morogh": (5, 12),
}


def level_range(levels, cover=0.75):
    """The narrowest level span that holds at least `cover` of the zone's quests.
    Stranglethorn has a tail of level-60 Zul'Gurub quests; the band most players quest in is 32 to 45."""
    s = sorted(levels)
    if not s:
        return None
    need = max(1, int(len(s) * cover + 0.999))
    best = None
    for i in range(0, len(s) - need + 1):
        lo, hi = s[i], s[i + need - 1]
        if best is None or hi - lo < best[1] - best[0]:
            best = (lo, hi)
    return max(1, best[0]), max(best[1], best[0])


def zone_faction(a, h, n):
    if n and a / n >= 0.6:
        return "Alliance"
    if n and h / n >= 0.6:
        return "Horde"
    return None


def build_zones(world, min_quests=6):
    per_zone = {}
    for entry in world.quests.values():
        zone = field(entry, 17)
        if not zone or zone < 0:
            continue
        zone = world.subzones.get(zone, zone)
        if zone in DUNGEON_ZONES or zone in CITY_ZONES or zone in RAID_AND_OTHER_ZONES:
            continue
        if world.continents.get(zone) not in ("Eastern Kingdoms", "Kalimdor"):
            continue
        if (field(entry, 24) or 0) & 1:
            continue  # repeatable turn-ins skew nothing useful
        z = per_zone.setdefault(zone, {"levels": [], "a": 0, "h": 0})
        z["levels"].append(field(entry, 5) or field(entry, 4) or 1)
        f = faction_of(entry)
        if f == "Alliance":
            z["a"] += 1
        elif f == "Horde":
            z["h"] += 1
    out = []
    for zone, z in per_zone.items():
        if len(z["levels"]) < min_quests:
            continue
        lo, hi = ZONE_OVERRIDES.get(world.zone_name(zone)) or level_range(z["levels"])
        out.append({"zone": zone, "name": world.zone_name(zone), "continent": world.continents.get(zone),
                    "lo": lo, "hi": hi, "quests": len(z["levels"]), "faction": zone_faction(z["a"], z["h"], len(z["levels"]))})
    have = {r["name"] for r in out}
    for name, continent, lo, hi, source in CURATED_ZONES:
        if name not in have:
            out.append({"zone": 0, "name": name, "continent": continent, "lo": lo, "hi": hi,
                        "quests": 0, "faction": None, "source": source})
    out.sort(key=lambda r: (r["lo"], r["hi"], r["name"]))
    return out


# --- output -------------------------------------------------------------------

def lua_place(p):
    if not p:
        return "false"
    return "{ name = %s, where = %s, map = %s, x = %s, y = %s, kind = %s }" % (
        lua_string(p["name"] or "?"), lua_string(p["where"]) if p["where"] else "false", p.get("map") or "false",
        ("%.1f" % p["x"]) if p["x"] is not None else "false", ("%.1f" % p["y"]) if p["y"] is not None else "false", lua_string(p["kind"]))


def emit_dungeons(dungeons, generated):
    lines = ["local _, ns = ...", "", "-- GENERATED by tools/build_dungeons.py from Questie's Classic database; do not edit by hand.",
             "ns.DungeonInfo = { generated = %s, dungeons = %d, quests = %d }" % (
                 lua_string(generated), len(dungeons), sum(len(d["quests"]) for d in dungeons)), "", "ns.Dungeons = {"]
    for d in dungeons:
        lines.append("  { key = %s, name = %s, zone = %d, level = { %d, %d }, faction = %s, screen = %s, aliases = { %s }, quests = {" % (
            lua_string(d["key"]), lua_string(d["name"]), d["zone"], d["lo"], d["hi"],
            lua_string(d["faction"]) if d["faction"] else "false", d["screen"] or "false",
            ", ".join(lua_string(a) for a in d["aliases"])))
        for q in d["quests"]:
            pre = ", ".join("{ id = %d, name = %s, faction = %s, giver = %s }" % (
                pid, lua_string(pname), lua_string(pfaction) if pfaction else "false", lua_place(pgiver))
                for pid, pname, pgiver, pfaction in q["pre"])
            lines.append("    { id = %d, name = %s, level = %d, req = %d, faction = %s, classes = %d, share = %s, repeatable = %s, inside = %s," % (
                q["id"], lua_string(q["name"]), q["level"], q["req"], lua_string(q["faction"]) if q["faction"] else "false",
                q["classes"], lua_string(q["share"]), "true" if q["repeatable"] else "false", lua_string(q["inside"]) if q["inside"] else "false"))
            note = (", note = %s" % lua_string(q["note"])) if q.get("note") else ""
            lines.append("      giver = %s, turnin = %s, pre = { %s }%s }," % (lua_place(q["giver"]), lua_place(q["turnin"]), pre, note))
        lines.append("  } },")
    lines.append("}")
    return "\n".join(lines) + "\n"


def emit_zones(zones, generated):
    lines = ["local _, ns = ...", "", "-- GENERATED by tools/build_dungeons.py from Questie's Classic database; do not edit by hand.",
             "ns.ZoneInfo = { generated = %s, zones = %d }" % (lua_string(generated), len(zones)), "", "ns.Zones = {"]
    for z in zones:
        lines.append("  { zone = %d, name = %s, continent = %s, level = { %d, %d }, quests = %d, faction = %s, source = %s }," % (
            z["zone"], lua_string(z["name"]), lua_string(z["continent"] or "?"), z["lo"], z["hi"], z["quests"],
            lua_string(z["faction"]) if z["faction"] else "false", lua_string(z.get("source") or "quests")))
    lines.append("}")
    return "\n".join(lines) + "\n"


def load_world(cache):
    texts = {name: fetch(QUESTIE + path, os.path.join(cache, name)) for name, path in FILES.items()}
    zone_names, continents = parse_zone_names(texts["lookupZones.lua"])
    return World(parse_questie(texts["classicQuestDB.lua"]), parse_db(texts["classicNpcDB.lua"], "QuestieDB.npcData"),
                 parse_db(texts["classicObjectDB.lua"], "QuestieDB.objectData"), parse_db(texts["classicItemDB.lua"], "QuestieDB.itemData"),
                 zone_names, continents, parse_subzones(texts["subZoneToParentZone.lua"]), parse_area_maps(texts["areaIdToUiMapId.lua"]))


def main(argv=None):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", default=os.path.join(root, "Data"))
    parser.add_argument("--cache", default=os.path.join(root, "tools", "cache", "questie"))
    args = parser.parse_args(argv)
    world = load_world(args.cache)
    dungeons, zones = build_dungeons(world), build_zones(world)
    generated = datetime.date.today().isoformat()
    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "Dungeons.lua"), "w", encoding="utf-8") as f:
        f.write(emit_dungeons(dungeons, generated))
    with open(os.path.join(args.out, "Zones.lua"), "w", encoding="utf-8") as f:
        f.write(emit_zones(zones, generated))
    print("Dungeons.lua: %d dungeons, %d quests" % (len(dungeons), sum(len(d["quests"]) for d in dungeons)))
    print("Zones.lua: %d zones" % len(zones))
    for z in zones:
        print("  %-24s %2d-%-2d %3d quests %s" % (z["name"], z["lo"], z["hi"], z["quests"], z["faction"] or "both"))


if __name__ == "__main__":
    main()
