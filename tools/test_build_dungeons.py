"""Known-answer tests for tools/build_dungeons.py. Run: python3 -m unittest discover -s tools -v"""
import unittest

import build_dungeons as bdg

# Questie quest entry layout (1-based positions in the comments): name 1, startedBy 2, finishedBy 3,
# requiredLevel 4, questLevel 5, requiredRaces 6, requiredClasses 7, objectivesText 8, triggerEnd 9,
# objectives 10, sourceItemId 11, preQuestGroup 12, preQuestSingle 13, ..., zoneOrSort 17, ...,
# nextQuestInChain 22, questFlags 23, specialFlags 24, parentQuest 25
def quest(name, giver_npc, level, races, objectives=None, sort=0, flags=8, pre=None, nxt=None, special=0, classes=0):
    e = [None] * 28
    e[0] = name
    e[1] = [[giver_npc], None, None]
    e[2] = [[giver_npc], None]
    e[3] = level - 3
    e[4] = level
    e[5] = races
    e[6] = classes
    e[9] = objectives
    e[12] = pre
    e[16] = sort
    e[21] = nxt
    e[22] = flags
    e[23] = special
    return e

# npc: name 1, ..., spawns 7 {zone: [[x, y]]}, ..., zoneID 9
def npc(name, spawns, primary):
    e = [None] * 15
    e[0] = name
    e[6] = spawns
    e[8] = primary
    return e

# item: name 1, npcDrops 2, objectDrops 3, ..., class 12
def item(name, drops, klass=12):
    e = [None] * 15
    e[0] = name
    e[1] = drops
    e[11] = klass
    return e

RFC, TB, ORG = 2437, 1638, 1637
NPCS = {
    1: npc("Rahauro", {TB: [[70.1, 30.4]]}, TB),
    2: npc("Ragefire Trogg", {RFC: [[-1, -1]]}, RFC),
    3: npc("Taragaman the Hungerer", {RFC: [[-1, -1]]}, RFC),
    4: npc("Black Rat", {10: [[1, 1]], RFC: [[-1, -1]], 1637: [[2, 2]]}, 10),
    5: npc("River Crocolisk", {40: [[3, 3]]}, 40),
    6: npc("Deviate Crocolisk", {718: [[-1, -1]]}, 718),
}
ITEMS = {
    100: item("Taragaman's Heart", [3]),
    101: item("Crocolisk Skin", [5, 5, 5, 6]),
    102: item("Linen Cloth", [2, 3], klass=0),
}
QUESTS = {
    5723: quest("Testing an Enemy's Strength", 1, 15, 178, objectives=[[[2, None]], None, None], sort=RFC),
    5761: quest("Slaying the Beast", 1, 16, 178, objectives=[None, None, [[100, None]]]),
    385: quest("Crocolisk Hunting", 1, 15, 77, objectives=[None, None, [[101, None]]]),
    900: quest("Rat Catching", 1, 10, 0, objectives=[[[4, None]], None, None]),
    901: quest("Cloth Run", 1, 12, 0, objectives=[None, None, [[102, None]]]),
    5724: quest("Returning the Lost Satchel", 1, 16, 178, flags=0, pre=[5722]),
    5722: quest("Searching for the Lost Satchel", 1, 16, 178, nxt=5724),
    777: quest("The Glowing Shard", 1, 26, 0, flags=0),
}
ZONES = {TB: "Thunder Bluff", ORG: "Orgrimmar", RFC: "Ragefire Chasm", 10: "Duskwood", 40: "Westfall", 718: "Wailing Caverns"}


def world():
    return bdg.World(QUESTS, NPCS, {}, ITEMS, ZONES, {z: "Eastern Kingdoms" for z in ZONES}, {}, {TB: 1456, ORG: 1454, RFC: 213})


class MatchingTests(unittest.TestCase):
    def test_filed_under_the_dungeon_and_kill_inside(self):
        self.assertEqual(world().match(QUESTS[5723], RFC), ["sort", "kill"])

    def test_quest_item_dropped_only_inside_counts(self):
        self.assertEqual(world().match(QUESTS[5761], RFC), ["drop"])

    def test_item_dropped_mostly_elsewhere_does_not_count(self):
        self.assertEqual(world().match(QUESTS[385], 718), [])

    def test_ordinary_drop_does_not_count(self):
        self.assertEqual(world().match(QUESTS[901], RFC), [])

    def test_multi_zone_critter_counts_only_for_its_primary_zone(self):
        self.assertEqual(world().match(QUESTS[900], RFC), [])
        self.assertEqual(world().match(QUESTS[900], 10), ["kill"])


class ClassificationTests(unittest.TestCase):
    def test_share(self):
        self.assertEqual(bdg.share_of(QUESTS[5723]), "yes")
        self.assertEqual(bdg.share_of(QUESTS[5724]), "chain")
        self.assertEqual(bdg.share_of(QUESTS[777]), "single")

    def test_faction(self):
        self.assertEqual(bdg.faction_of(QUESTS[5723]), "Horde")
        self.assertEqual(bdg.faction_of(QUESTS[385]), "Alliance")
        self.assertIsNone(bdg.faction_of(QUESTS[900]))

    def test_giver_and_chain(self):
        w = world()
        self.assertEqual(w.giver(QUESTS[5723]), {"name": "Rahauro", "where": "Thunder Bluff", "x": 70.1, "y": 30.4, "kind": "npc", "map": 1456})
        self.assertEqual([c[1] for c in w.chain(5724)], ["Searching for the Lost Satchel"])

    def test_build_dungeons_rows(self):
        rows = {d["key"]: d for d in bdg.build_dungeons(world())}["ragefirechasm"]["quests"]
        self.assertEqual([r["name"] for r in rows], ["Testing an Enemy's Strength", "Slaying the Beast"])
        self.assertEqual(rows[0]["share"], "yes")


class ZoneTests(unittest.TestCase):
    def test_level_range_ignores_the_high_tail(self):
        levels = [30, 31, 32, 33, 34, 35, 36, 37, 38, 40, 42, 44, 45, 60, 60, 60]
        self.assertEqual(bdg.level_range(levels), (30, 44))

    def test_level_range_small(self):
        self.assertEqual(bdg.level_range([5]), (5, 5))
        self.assertIsNone(bdg.level_range([]))

    def test_zone_faction(self):
        # side, leaning
        self.assertEqual(bdg.zone_faction(30, 2, 40), ("Alliance", False))
        self.assertEqual(bdg.zone_faction(2, 30, 40), ("Horde", False))
        self.assertEqual(bdg.zone_faction(15, 15, 40), (None, False))

    def test_zone_faction_leans(self):
        # Stonetalon: 17 Alliance and 23 Horde of 46 quests is a lean, not a claim.
        self.assertEqual(bdg.zone_faction(17, 23, 46), ("Horde", True))
        # Ashenvale leans the other way.
        self.assertEqual(bdg.zone_faction(47, 23, 70), ("Alliance", True))

    def test_zone_faction_ignores_a_handful_in_a_neutral_zone(self):
        # Tanaris: 6 and 9 among 91 quests says nothing about whose zone it is.
        self.assertEqual(bdg.zone_faction(6, 9, 91), (None, False))
        # But a side with no quests at all is still worth saying, however neutral the rest is.
        self.assertEqual(bdg.zone_faction(0, 9, 29), ("Horde", False))

    def test_zone_faction_needs_enough_to_judge(self):
        self.assertEqual(bdg.zone_faction(1, 2, 19), (None, False))
        self.assertEqual(bdg.zone_faction(0, 0, 8), (None, False))

    def test_parse_zone_names(self):
        text = '''l10n.zoneLookup = {
    [0]={
        [0]="Eastern Kingdoms",
        [12]="Elwynn Forest",
    },
    [1]={
        [14]="Durotar",
    },
    [13]={
        [1581]="The Deadmines",
    },
}'''
        names, continents = bdg.parse_zone_names(text)
        self.assertEqual(names[12], "Elwynn Forest")
        self.assertEqual(continents[12], "Eastern Kingdoms")
        self.assertEqual(continents[14], "Kalimdor")
        self.assertIsNone(continents[1581])
        self.assertNotIn(0, names)


class AreaMapTests(unittest.TestCase):
    def test_parse_area_maps_skips_zero(self):
        text = "[[return {\n    [0] = 0, -- fail safe\n    [40] = 1436, -- Westfall\n    [1638] = 1456, -- Thunder Bluff\n}]]"
        self.assertEqual(bdg.parse_area_maps(text), {40: 1436, 1638: 1456})


class EmitTests(unittest.TestCase):
    def test_emit_dungeons_is_lua(self):
        text = bdg.emit_dungeons(bdg.build_dungeons(world()), "2026-09-15")
        self.assertIn('ns.Dungeons = {', text)
        self.assertIn('giver = { name = "Rahauro", where = "Thunder Bluff", map = 1456, x = 70.1, y = 30.4, kind = "npc" }', text)
        self.assertIn('share = "yes"', text)



class LoadingScreens(unittest.TestCase):
    def test_every_dungeon_has_its_own_loading_screen(self):
        keys = [d[0] for d in bdg.DUNGEONS]
        missing = [k for k in keys if k not in bdg.LOADING_SCREENS]
        self.assertEqual(missing, [], "these dungeons would show a blank cover")
        # A dungeon Blizzard has tuned has artwork of its own. The instances it has built but
        # not released share a placeholder in the client's own tables, so they are allowed to
        # repeat: that is what Map.db2 says, not a typo of ours.
        tuned = {d[0] for d in bdg.DUNGEONS if d[3] is not None}
        ids = [bdg.LOADING_SCREENS[k] for k in tuned if bdg.LOADING_SCREENS.get(k)]
        self.assertEqual(len(set(ids)), len(ids), "two released dungeons sharing one picture is a typo")
        for key, file_id in bdg.LOADING_SCREENS.items():
            if file_id is None:
                self.assertNotIn(key, tuned, "a released dungeon needs a cover")
                continue
            self.assertIsInstance(file_id, int, key)
            self.assertGreater(file_id, 0, key)




class QuestSides(unittest.TestCase):
    """Race masks miss quests that are one side's only because of who hands them out."""

    class World:
        def __init__(self, npcs):
            self.npcs = npcs

        giver_faction = bdg.World.giver_faction

    def world(self):
        # 234 is Alliance-only, 3701 Horde-only, 1234 talks to everyone.
        return self.World({234: ["Gryan Stoutmantle"] + [None] * 11 + ["A"],
                           3701: ["Neeru Fireblade"] + [None] * 11 + ["H"],
                           1234: ["Neutral Ned"] + [None] * 11 + ["AH"]})

    def quest(self, races, started, finished=None):
        entry = [None] * 15
        entry[0] = "A Quest"
        entry[1] = [[started]]
        entry[2] = [[finished or started]]
        entry[5] = races
        return entry

    def test_the_race_mask_answers_when_it_can(self):
        self.assertEqual(bdg.faction_of(self.quest(77, 234), self.world()), "Alliance")
        self.assertEqual(bdg.faction_of(self.quest(178, 3701), self.world()), "Horde")

    def test_a_quest_open_to_all_races_still_belongs_to_whoever_gives_it(self):
        self.assertEqual(bdg.faction_of(self.quest(0, 234), self.world()), "Alliance",
                         "only Alliance can talk to the man who starts it")
        self.assertEqual(bdg.faction_of(self.quest(255, 3701), self.world()), "Horde")

    def test_a_giver_both_sides_use_leaves_it_neutral(self):
        self.assertIsNone(bdg.faction_of(self.quest(0, 1234), self.world()))

    def test_without_a_world_it_falls_back_to_the_mask_alone(self):
        self.assertIsNone(bdg.faction_of(self.quest(0, 234)))


if __name__ == "__main__":
    unittest.main()
