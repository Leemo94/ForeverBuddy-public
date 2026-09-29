import unittest

import build_loot as loot


class Build(unittest.TestCase):
    def db(self):
        return {
            "items": [
                {"id": 1, "name": "Tunic of Westfall", "quality": 3, "ilvl": 24,
                 "sources": [{"quest": {"id": 166, "name": "The Defias Brotherhood"}}]},
                {"id": 2, "name": "Green Rag", "quality": 2, "ilvl": 20,
                 "sources": [{"drop": {"npcId": 644, "zoneId": 1581}}]},
                {"id": 3, "name": "Blue Blade", "quality": 3, "ilvl": 26,
                 "sources": [{"drop": {"npcId": 644, "zoneId": 1581}}]},
                {"id": 4, "name": "Somewhere Cloak", "quality": 4, "ilvl": 30,
                 "sources": [{"drop": {"zoneId": 1581}}]},
                {"id": 5, "name": "Elsewhere", "quality": 4, "ilvl": 60,
                 "sources": [{"drop": {"npcId": 9, "zoneId": 2017}}]},
            ],
            "npcs": [{"id": 644, "name": "Edwin VanCleef"}],
        }

    def test_rewards_only_for_quests_we_draw(self):
        rewards, _ = loot.build(self.db(), {"deadmines": [166]})
        self.assertEqual(rewards[166], [(1, "Tunic of Westfall", 3, 24)])
        rewards, _ = loot.build(self.db(), {"deadmines": [999]})
        self.assertEqual(rewards, {})

    def test_boss_drops_are_rare_and_better_only(self):
        _, drops = loot.build(self.db(), {})
        names = [i[1] for b in drops["deadmines"] for i in b["items"]]
        self.assertIn("Blue Blade", names)
        self.assertNotIn("Green Rag", names, "Forever's bosses drop no greens")

    def test_a_drop_with_no_creature_is_named_not_dropped(self):
        _, drops = loot.build(self.db(), {})
        unknown = [b for b in drops["deadmines"] if b["npc"] == 0]
        self.assertEqual(len(unknown), 1)
        self.assertEqual(unknown[0]["name"], "Somewhere inside")
        self.assertEqual(drops["deadmines"][-1]["npc"], 0, "and it sorts last")

    def test_every_dungeon_with_loot_is_a_dungeon_we_know(self):
        _, drops = loot.build(self.db(), {})
        keys = {d[0] for d in loot.DUNGEONS}
        self.assertTrue(set(drops) <= keys)

    def test_emit_is_loadable_lua(self):
        rewards, drops = loot.build(self.db(), {"deadmines": [166]})
        text = loot.emit(rewards, drops, "2026-09-27")
        self.assertIn('ns.QuestRewards = {', text)
        self.assertIn('[166] = { { 1, "Tunic of Westfall", 3, 24 } },', text)
        self.assertIn('{ npc = 644, name = "Edwin VanCleef", items = {', text)
        self.assertEqual(text.count("ns.DungeonLoot"), 1)


if __name__ == "__main__":
    unittest.main()
