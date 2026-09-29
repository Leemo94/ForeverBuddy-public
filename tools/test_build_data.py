"""Known-answer tests for tools/build_data.py. Run: python3 -m unittest discover -s tools -v"""
import unittest

import build_data as bd

REAGENTS = """ID,SpellID,Reagent_0,Reagent_1,Reagent_2,Reagent_3,Reagent_4,Reagent_5,Reagent_6,Reagent_7,ReagentCount_0,ReagentCount_1,ReagentCount_2,ReagentCount_3,ReagentCount_4,ReagentCount_5,ReagentCount_6,ReagentCount_7
1,6412,6889,2678,0,0,0,0,0,0,1,1,0,0,0,0,0,0
2,21143,6889,2678,2596,0,0,0,0,0,1,1,1,0,0,0,0,0
3,21144,6889,2596,0,0,0,0,0,0,1,1,0,0,0,0,0,0
4,2538,769,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0
5,2539,769,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0
6,688,6265,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0
7,7418,10940,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0
"""

ABILITIES = """ID,SkillLine,Spell
1,185,6412
2,185,21143
3,185,21144
4,185,2538
5,185,2539
6,355,688
7,148,458
8,333,7418
"""

SKILLS = """ID,CategoryID,DisplayName_lang
185,9,Cooking
333,11,Enchanting
355,7,Demonology
148,9,Horse Riding
"""

EFFECTS = """ID,SpellID,Effect,EffectItemType
1,6412,24,6888
2,21143,24,17197
3,21144,24,17198
4,2538,24,2681
5,2539,24,2681
6,688,28,0
7,7418,53,0
"""

NAMES = """ID,Name_lang
6412,Herb Baked Egg
21143,Gingerbread Cookie
21144,Egg Nog
2538,Roasted Boar Meat
2539,Roasted Boar Meat
688,Summon Imp
458,Horse Riding
7418,Enchant Bracer - Minor Health
"""

ITEMS = """ID,Display_lang
6888,Herb Baked Egg
17197,Gingerbread Cookie
17198,Egg Nog
2681,Roasted Boar Meat
6889,Small Egg
769,Chunk of Boar Meat
"""


def build_fixture_recipes():
    return bd.build_recipes(
        bd.read_csv(REAGENTS), bd.read_csv(ABILITIES), bd.read_csv(SKILLS),
        bd.read_csv(EFFECTS), bd.read_csv(NAMES), bd.read_csv(ITEMS),
    )


class RecipeBuildTests(unittest.TestCase):
    def setUp(self):
        self.recipes = build_fixture_recipes()

    def test_small_egg_has_three_cooking_recipes_sorted_by_name(self):
        self.assertEqual(self.recipes[6889], [
            ("Egg Nog", "Cooking", 17198, "Egg Nog", 1),
            ("Gingerbread Cookie", "Cooking", 17197, "Gingerbread Cookie", 1),
            ("Herb Baked Egg", "Cooking", 6888, "Herb Baked Egg", 1),
        ])

    def test_duplicate_spells_for_one_recipe_collapse(self):
        self.assertEqual(self.recipes[769], [("Roasted Boar Meat", "Cooking", 2681, "Roasted Boar Meat", 1)])

    def test_class_skill_lines_are_not_professions(self):
        self.assertNotIn(6265, self.recipes)

    def test_riding_never_appears(self):
        professions = {e[1] for entries in self.recipes.values() for e in entries}
        self.assertEqual(professions, {"Cooking", "Enchanting"})

    def test_enchant_has_no_crafted_item(self):
        self.assertEqual(self.recipes[10940], [("Enchant Bracer - Minor Health", "Enchanting", 0, "", 1)])

    def test_shared_reagent_lists_every_recipe(self):
        self.assertEqual([e[0] for e in self.recipes[2678]], ["Gingerbread Cookie", "Herb Baked Egg"])


QUESTIE = r'''-- AUTO GENERATED FILE! DO NOT EDIT!
QuestieDB.questData = [[return {
[22] = {"Goretusk Liver Pie",{{235}},{{235}},9,12,77,nil,{"Salma Saldean needs 8 Goretusk livers to make a Goretusk Liver Pie."},nil,{nil,nil,{{723}}},nil,nil,nil,nil,nil,nil,40,nil,nil,nil,nil,nil,8,nil,nil,{{72,250}}},
[86] = {"Pie for Billy",{{247}},{{246}},5,6,77,nil,{"Bring 4 Chunks of Boar Meat to Auntie Bernice Stonefield at the Stonefield's Farm."},nil,{nil,nil,{{769}}},nil,nil,{85},nil,nil,nil,12,nil,nil,nil,nil,84,8,nil,nil,{{72,150}}},
[317] = {"Stocking Jetsteam",{{1378}},{{1378}},2,6,77,nil,{"Gather 4 Chunks of Boar Meat and 2 Thick Bear Furs, and deliver them to Pilot Bellowfiz at Steelgrill's Depot."},nil,{nil,nil,{{769},{6952}}},nil,nil,nil,nil,nil,nil,1,nil,nil,nil,nil,318,8,nil,nil,{{47,150},{54,350}}},
[9998] = {"Feathers for the Chieftain",nil,nil,1,1,178,0,nil,nil,{nil,nil,{{5000,nil}}},nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,0,1},
[9997] = {"Paladin \"Errand\"",nil,nil,1,1,77,2,nil,nil,nil,5001,nil,nil,nil,nil,nil,nil,nil,nil,nil,{5002,5003},nil,0,0},
[9996] = {"Mixed Faction Quest",nil,nil,1,1,255,0,nil,nil,{[3]={{769}}},nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,0,0},
[9995] = {"Unknown Race Bits",nil,nil,1,1,4096,0,nil,nil,{nil,nil,{{769}}}},
}]]
'''


class LuaParserTests(unittest.TestCase):
    def test_scalars_and_strings(self):
        self.assertEqual(bd.parse_lua_value('"Bob\\"s Egg"', 0)[0], 'Bob"s Egg')
        self.assertEqual(bd.parse_lua_value("'x'", 0)[0], "x")
        self.assertEqual(bd.parse_lua_value(" 42,", 0), (42, 3))
        self.assertEqual(bd.parse_lua_value("-7", 0)[0], -7)
        self.assertEqual(bd.parse_lua_value("nil", 0)[0], None)
        self.assertEqual(bd.parse_lua_value("true", 0)[0], True)

    def test_positional_table_keeps_nil_slots(self):
        self.assertEqual(bd.parse_lua_value("{nil,nil,{{769},{6952}}}", 0)[0], [None, None, [[769], [6952]]])

    def test_keyed_table_becomes_dict(self):
        self.assertEqual(bd.parse_lua_value("{[3]={{769}}}", 0)[0], {3: [[769]]})

    def test_garbage_raises(self):
        with self.assertRaises(ValueError):
            bd.parse_lua_value("@", 0)

    def test_parse_questie_finds_every_quest(self):
        quests = bd.parse_questie(QUESTIE)
        self.assertEqual(sorted(quests), [22, 86, 317, 9995, 9996, 9997, 9998])
        self.assertEqual(quests[86][0], "Pie for Billy")
        self.assertEqual(quests[9997][0], 'Paladin "Errand"')


class FactionTests(unittest.TestCase):
    def test_masks(self):
        self.assertEqual(bd.faction_from_mask(0), "B")
        self.assertEqual(bd.faction_from_mask(77), "A")
        self.assertEqual(bd.faction_from_mask(1), "A")
        self.assertEqual(bd.faction_from_mask(178), "H")
        self.assertEqual(bd.faction_from_mask(32), "H")
        self.assertEqual(bd.faction_from_mask(255), "B")
        self.assertEqual(bd.faction_from_mask(4096), "B")


class QuestBuildTests(unittest.TestCase):
    def setUp(self):
        self.quests = bd.build_quests(bd.parse_questie(QUESTIE))

    def test_boar_meat_quests_sorted_by_name(self):
        self.assertEqual(self.quests[769], [
            (9996, "Mixed Faction Quest", "objective", False, "B", 0, ()),
            (86, "Pie for Billy", "objective", False, "A", 0, ((72, 150),)),
            (317, "Stocking Jetsteam", "objective", False, "A", 0, ((47, 150), (54, 350))),
            (9995, "Unknown Race Bits", "objective", False, "B", 0, ()),
        ])

    def test_goretusk_liver(self):
        self.assertEqual(self.quests[723], [(22, "Goretusk Liver Pie", "objective", False, "A", 0, ((72, 250),))])

    def test_second_item_objective_in_same_quest(self):
        self.assertEqual(self.quests[6952], [(317, "Stocking Jetsteam", "objective", False, "A", 0, ((47, 150), (54, 350)))])

    def test_repeatable_horde_quest(self):
        self.assertEqual(self.quests[5000], [(9998, "Feathers for the Chieftain", "objective", True, "H", 0, ())])

    def test_provided_and_needed_items_with_class_mask(self):
        self.assertEqual(self.quests[5001], [(9997, 'Paladin "Errand"', "provided", False, "A", 2, ())])
        self.assertEqual(self.quests[5002], [(9997, 'Paladin "Errand"', "needed", False, "A", 2, ())])
        self.assertEqual(self.quests[5003], [(9997, 'Paladin "Errand"', "needed", False, "A", 2, ())])

    def test_short_entry_without_flags_is_not_repeatable(self):
        self.assertEqual(self.quests[769][3][3], False)


class EmitTests(unittest.TestCase):
    def test_lua_string_escapes_quotes_and_backslashes(self):
        self.assertEqual(bd.lua_string('Paladin "Errand" \\ x'), '"Paladin \\"Errand\\" \\\\ x"')

    def test_emit_recipes_layout(self):
        info = {"build": "1.15.9.69722", "generated": "2026-09-13", "recipes": 1, "quests": 2}
        text = bd.emit_recipes({6889: [("Herb Baked Egg", "Cooking", 6888, "Herb Baked Egg", 1)]}, info)
        self.assertTrue(text.startswith("local _, ns = ...\n"))
        self.assertIn('ns.DataInfo = { build = "1.15.9.69722", generated = "2026-09-13", recipes = 1, quests = 2 }', text)
        self.assertIn('  [6889] = { { "Herb Baked Egg", "Cooking", 6888, "Herb Baked Egg", 1 } },', text)
        self.assertTrue(text.endswith("}\n"))

    def test_emit_quests_layout(self):
        text = bd.emit_quests({769: [(86, "Pie for Billy", "objective", False, "A", 0, ((72, 150),)),
                                     (9998, "Feathers", "objective", True, "H", 2, ())]})
        self.assertTrue(text.startswith("local _, ns = ...\n"))
        self.assertIn('  [769] = { { 86, "Pie for Billy", "objective", false, "A", 0, { { 72, 150 } } }, '
                      '{ 9998, "Feathers", "objective", true, "H", 2, false } },', text)

    def test_items_emitted_in_id_order(self):
        text = bd.emit_quests({769: [(86, "Pie", "objective", False, "A", 0, ())],
                               723: [(22, "Liver", "objective", False, "A", 0, ())]})
        self.assertLess(text.index("[723]"), text.index("[769]"))

    def test_check_rows_rejects_wago_error_payload(self):
        with self.assertRaises(SystemExit):
            bd.check_rows("SpellReagents", bd.read_csv('{"errors":"Table not found."}'), "9.9.9.1")
        rows = bd.read_csv("ID,SpellID\n1,2\n")
        self.assertIs(bd.check_rows("SpellReagents", rows, "1.15.9.69722"), rows)


if __name__ == "__main__":
    unittest.main()
