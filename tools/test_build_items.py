"""Known-answer tests for tools/build_items.py. Run: python3 -m unittest discover -s tools -v"""
import unittest

import build_items as bi

ZERO = [0] * 44


def stats(**named):
    values = list(ZERO)
    for name, v in named.items():
        values[bi.STAT_NAMES.index(name)] = v
    return values


RING = {"id": 13098, "name": "Painweaver Band", "icon": "x", "type": 11, "stats": stats(Stamina=7, AttackPower=16, MeleeCrit=1, RangedAttackPower=16),
        "ilvl": 63, "phase": 1, "quality": 3, "unique": True,
        "sources": [{"drop": {"npcId": 10363, "zoneId": 1583}}, {"drop": {"difficulty": 1, "npcId": 10363, "zoneId": 1583}}]}
SWORD = {"id": 727, "name": "Notched \"Short\" Sword", "icon": "x", "type": 13, "weaponType": 9, "handType": 2, "stats": ZERO,
         "randomSuffixOptions": [6, 15], "weaponDamageMin": 8, "weaponDamageMax": 15, "weaponSpeed": 2.1, "ilvl": 10, "phase": 1, "quality": 2}
CHEST = {"id": 7930, "name": "Heavy Mithril Breastplate", "icon": "x", "type": 5, "armorType": 4, "stats": stats(Stamina=15, Armor=536),
         "ilvl": 46, "phase": 1, "quality": 2, "factionRestriction": 2, "classAllowlist": [9, 4], "setName": "Mithril Set",
         "sources": [{"crafted": {"profession": 2, "spellId": 9959}}, {"quest": {"id": 53, "name": "Sweet Amber"}},
                     {"soldBy": {"npcId": 209889, "npcName": "Barebones"}}, {"rep": {"repFactionId": 87, "repLevel": 5}}]}
BAG = {"id": 1, "name": "Not Gear", "icon": "x", "type": 0, "stats": ZERO, "ilvl": 1, "phase": 1, "quality": 2}
DB = {"items": [SWORD, RING, CHEST, BAG], "npcs": [{"id": 10363, "name": "General Angerforge", "zoneId": 1583}], "zones": [{"id": 1583, "name": "Blackrock Depths"}]}


class RecordTests(unittest.TestCase):
    def test_stats_map_drops_zeros_and_checks_length(self):
        self.assertEqual(bi.stats_map(stats(Strength=5, Armor=100)), {"Strength": 5, "Armor": 100})
        with self.assertRaises(ValueError):
            bi.stats_map([0, 1])

    def test_ring_record_dedupes_sources(self):
        r = bi.item_record(RING)
        self.assertEqual(r["stats"], {"Stamina": 7, "AttackPower": 16, "MeleeCrit": 1, "RangedAttackPower": 16})
        self.assertEqual(r["sources"], [("drop", 10363, 1583)])
        self.assertTrue(r["unique"]); self.assertIsNone(r["faction"]); self.assertIsNone(r["weapon"])

    def test_weapon_record(self):
        r = bi.item_record(SWORD)
        self.assertEqual(r["weapon"], (8, 15, 2.1)); self.assertEqual(r["handType"], 2); self.assertEqual(r["weaponType"], 9)

    def test_chest_record_sources_faction_classes_set(self):
        r = bi.item_record(CHEST)
        self.assertEqual(r["sources"], [("crafted", 9959, "Blacksmithing"), ("quest", 53, "Sweet Amber"), ("vendor", 209889, "Barebones"), ("rep", 87, 5)])
        self.assertEqual(r["faction"], "H"); self.assertEqual(r["classes"], ["WARRIOR", "PALADIN"]); self.assertEqual(r["setName"], "Mithril Set")

    def test_build_skips_non_gear(self):
        records, npcs, zones = bi.build(DB)
        self.assertEqual([r["id"] for r in records], [727, 13098, 7930])
        self.assertEqual(npcs, {10363: "General Angerforge"}); self.assertEqual(zones, {1583: "Blackrock Depths"})


class EmitTests(unittest.TestCase):
    def test_layout(self):
        records, npcs, zones = bi.build(DB)
        text = bi.emit_items(records, npcs, zones, {"game": "classic", "generated": "2026-09-14"})
        self.assertTrue(text.startswith("local _, ns = ...\n"))
        self.assertIn('ns.ItemsInfo = { game = "classic", generated = "2026-09-14", items = 3 }', text)
        self.assertIn('ns.ItemTypes = { [1] = "Head", [2] = "Neck"', text)
        self.assertIn('ns.ItemNpcs = { [10363] = "General Angerforge" }', text)
        self.assertIn('  [727] = { "Notched \\"Short\\" Sword", 2, 10, 13, 0, 9, 2, 0, 1, { }, { 8, 15, 2.1 }, false, false, false, false, false },', text)
        self.assertIn('  [13098] = { "Painweaver Band", 3, 63, 11, 0, 0, 0, 0, 1, { AttackPower = 16, MeleeCrit = 1, RangedAttackPower = 16, Stamina = 7 }, false, true, false, false, false, { { "drop", 10363, 1583 } } },', text)
        self.assertIn('  [7930] = { "Heavy Mithril Breastplate", 2, 46, 5, 4, 0, 0, 0, 1, { Armor = 536, Stamina = 15 }, false, false, "H", { "WARRIOR", "PALADIN" }, "Mithril Set", { { "crafted", 9959, "Blacksmithing" }, { "quest", 53, "Sweet Amber" }, { "vendor", 209889, "Barebones" }, { "rep", 87, 5 } } },', text)
        self.assertLess(text.index("[727]"), text.index("[7930]")); self.assertLess(text.index("[7930]"), text.index("[13098]"))
        self.assertTrue(text.endswith("}\n"))


if __name__ == "__main__":
    unittest.main()
