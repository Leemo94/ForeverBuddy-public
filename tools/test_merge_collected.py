"""Known-answer tests for tools/merge_collected.py. Run: python3 -m unittest discover -s tools -v"""
import json
import os
import tempfile
import unittest

import merge_collected as mc

SAVED = r'''
ForeverBuddyDB = {
	["setupDone"] = true,
	["features"] = {
		["collect"] = true,
	},
	["collected"] = {
		["version"] = 1,
		["noticed"] = true,
		["items"] = {
			[2024] = {
				["name"] = "Ornate Spyglass",
				["link"] = "|cff1eff00|Hitem:2024::::::::15:::::|h[Ornate Spyglass]|h|r",
				["quality"] = 2,
				["seen"] = 1789000000,
				["stats"] = {
					["ITEM_MOD_STAMINA_SHORT"] = 5,
				},
			},
			[769] = {
				["name"] = "Chunk of Boar Meat",
				["seen"] = 1789000001,
			},
		},
		["quests"] = {
			[5723] = {
				["title"] = "Testing an Enemy's Strength",
				["level"] = 15,
				["xp"] = 1150,
				["shareable"] = true,
				["giver"] = { ["id"] = 3442, ["name"] = "Rahauro" },
				["where"] = { ["zone"] = "Thunder Bluff", ["x"] = 70.1, ["y"] = 30.4, ["map"] = 88 },
				["objectives"] = {
					{ ["text"] = "Ragefire Trogg slain: 0/8", ["type"] = "monster", ["need"] = 8 },
					{ ["text"] = "Chunk of Boar Meat: 0/8", ["type"] = "item", ["need"] = 8 },
				},
			},
		},
		["npcs"] = {
			[3281] = { ["name"] = "Sarkoth", ["zone"] = "Durotar", ["x"] = 40, ["y"] = 60 },
		},
		["loot"] = {
			["npc:11520"] = { ["zone"] = "Ragefire Chasm", ["items"] = { [2024] = 1, [2589] = 2 } },
		},
		["vendors"] = {},
		["talents"] = {
			["Tester-Realm"] = { ["class"] = "WARRIOR", ["order"] = { { ["level"] = 10, ["name"] = "Cruelty", ["rank"] = 1 } } },
		},
		["client"] = { ["version"] = "12.1.5", ["build"] = "69999", ["interface"] = 120105 },
		["errors"] = {
			["LOOT_OPENED"] = { ["count"] = 2, ["msg"] = "attempt to index a nil value" },
		},
		["reports"] = {
			{ ["char"] = "Tester-Realm", ["time"] = 1789000002, ["text"] = "wrong giver \"quoted\"" },
		},
	},
}
'''


class ParseTests(unittest.TestCase):
    def test_parses_wow_saved_variables(self):
        db = mc.parse_saved_variables(SAVED)
        c = db["collected"]
        self.assertEqual(c["items"][2024]["name"], "Ornate Spyglass")
        self.assertEqual(c["items"][2024]["stats"]["ITEM_MOD_STAMINA_SHORT"], 5)
        self.assertEqual(c["quests"][5723]["objectives"][1]["type"], "item")
        self.assertEqual(c["loot"]["npc:11520"]["items"][2589], 2)
        self.assertEqual(c["reports"][0]["text"], 'wrong giver "quoted"')

    def test_objective_item_names_both_formats(self):
        self.assertEqual(mc.objective_item_name("Chunk of Boar Meat: 3/8"), "Chunk of Boar Meat")
        self.assertEqual(mc.objective_item_name("3/8 Chunk of Boar Meat"), "Chunk of Boar Meat")
        self.assertIsNone(mc.objective_item_name("Ragefire Trogg slain"))


class MergeTests(unittest.TestCase):
    def test_merge_and_quest_items(self):
        union = mc.empty_union()
        new = mc.merge_file(union, mc.parse_saved_variables(SAVED)["collected"], "abc")
        self.assertEqual(new["items"], 2)
        self.assertEqual(new["quests"], 1)
        self.assertEqual(new["loot"], 2)
        self.assertEqual(new["reports"], 1)
        qi = mc.quest_items(union, mc.item_names(union))
        self.assertEqual(qi, {769: [(5723, "Testing an Enemy's Strength")]})

    def test_second_merge_adds_loot_counts_but_not_duplicate_reports(self):
        union = mc.empty_union()
        c = mc.parse_saved_variables(SAVED)["collected"]
        mc.merge_file(union, c, "a")
        new = mc.merge_file(union, c, "b")
        self.assertEqual(union["loot"]["npc:11520"]["items"]["2589"], 4)
        self.assertEqual(len(union["reports"]), 1)
        self.assertEqual(new["quests"], 0)

    def test_emit_observed_lua(self):
        union = mc.empty_union()
        mc.merge_file(union, mc.parse_saved_variables(SAVED)["collected"], "abc")
        text = mc.emit_observed(union, mc.quest_items(union, mc.item_names(union)), "2026-09-15")
        self.assertIn('[769] = { { 5723, "Testing an Enemy\'s Strength" } },', text)
        self.assertIn('[5723] = { title = "Testing an Enemy\'s Strength", level = 15, xp = 1150, shareable = true, giver = { id = 3442, name = "Rahauro", zone = "Thunder Bluff", map = 88, x = 70.1, y = 30.4 }, turnin = false },', text)
        self.assertIn("[11520] = { 2024, 2589 },", text)
        self.assertIn('[3281] = { name = "Sarkoth", zone = "Durotar", map = false, x = 40, y = 60 },', text)

    def test_main_skips_already_merged_file(self):
        with tempfile.TemporaryDirectory() as d:
            src = os.path.join(d, "ForeverBuddy.lua")
            with open(src, "w", encoding="utf-8") as f:
                f.write(SAVED)
            observed, out = os.path.join(d, "observed.json"), os.path.join(d, "Observed.lua")
            import contextlib, io
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                mc.main([src, "--observed", observed, "--out", out, "--item-names", os.path.join(d, "none.csv")])
                mc.main([src, "--observed", observed, "--out", out, "--item-names", os.path.join(d, "none.csv")])
            self.assertIn("client 12.1.5 build 69999, interface 120105", buf.getvalue())
            self.assertIn("ERROR in LOOT_OPENED (x2): attempt to index a nil value", buf.getvalue())
            union = json.load(open(observed, encoding="utf-8"))
            self.assertEqual(len(union["files"]), 1)
            self.assertEqual(union["loot"]["npc:11520"]["items"]["2589"], 2, "second run skipped, counts not doubled")
            self.assertIn("ns.Observed = {", open(out, encoding="utf-8").read())




class Trainers(unittest.TestCase):
    def collected(self, services):
        return {"trainers": {"3706": {"id": 3706, "name": "Ur'kyo", "class": "PRIEST",
                                      "services": services}}}

    def test_a_longer_list_wins(self):
        union = mc.empty_union()
        short = [{"spell": 589, "name": "Shadow Word: Pain", "level": 4, "cost": 100}]
        long = short + [{"spell": 8106, "name": "Mind Blast", "level": 30, "cost": 5000}]
        mc.merge_file(union, self.collected(long), "a")
        mc.merge_file(union, self.collected(short), "b")
        self.assertEqual(len(union["trainers"]["3706"]["services"]), 2,
                         "a low character sees fewer rows; that must not erase the fuller list")

    def test_levels_come_back_by_spell(self):
        union = mc.empty_union()
        mc.merge_file(union, self.collected([
            {"spell": 589, "name": "Shadow Word: Pain", "level": 4},
            {"spell": 8106, "name": "Mind Blast", "level": 30},
            {"name": "No spell id", "level": 12},
        ]), "a")
        self.assertEqual(mc.trainer_levels(union), {589: 4, 8106: 30})

    def test_they_reach_the_lua(self):
        union = mc.empty_union()
        mc.merge_file(union, self.collected([
            {"spell": 8106, "name": "Mind Blast", "rank": "Rank 4", "level": 30, "cost": 5000}]), "a")
        text = mc.emit_observed(union, {}, "2026-09-28")
        self.assertIn("trainers = 1 }", text)
        self.assertIn('[3706] = { name = "Ur', text)
        self.assertIn('class = "PRIEST", services = {', text)
        self.assertIn('{ spell = 8106, name = "Mind Blast", rank = "Rank 4", level = 30, cost = 5000 },', text)


if __name__ == "__main__":
    unittest.main()
