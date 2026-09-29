import unittest

import build_abilities as ba


class Build(unittest.TestCase):
    DATA = {"build": "1.60.1.69893", "spells": {
        "853": {"name": "Hammer of Justice", "level": 8, "rank": None, "icon": "a", "classes": ["Paladin"]},
        "5588": {"name": "Hammer of Justice", "level": 24, "rank": 2, "icon": "a", "classes": ["Paladin"]},
        "635": {"name": "Holy Light", "level": 1, "rank": None, "icon": "b", "classes": ["Paladin"]},
        "19982": {"name": "Holy Light", "level": 1, "rank": None, "icon": "b", "classes": ["Paladin"]},
        "999": {"name": "Nothing Known", "level": None, "rank": None, "icon": "c", "classes": ["Paladin"]},
        "133": {"name": "Fireball", "level": 1, "rank": 1, "icon": "d", "classes": ["Mage"]},
        "1": {"name": "Stray", "level": 5, "rank": None, "icon": "e", "classes": ["Death Knight"]},
    }}

    def test_ranks_are_kept_but_a_repeat_at_one_level_is_not(self):
        out = ba.build(self.DATA)
        paladin = [(s["name"], s["level"]) for s in out["PALADIN"]]
        self.assertEqual(paladin, [("Holy Light", 1), ("Hammer of Justice", 8), ("Hammer of Justice", 24)],
                         "two ids for Holy Light at level 1 is one rung")

    def test_a_spell_with_no_level_is_left_out(self):
        out = ba.build(self.DATA)
        self.assertNotIn("Nothing Known", [s["name"] for s in out["PALADIN"]])

    def test_only_classes_this_game_has(self):
        out = ba.build(self.DATA)
        self.assertEqual(set(out), {"PALADIN", "MAGE"}, "no Death Knight in Forever")

    def test_emit_is_loadable_lua(self):
        text = ba.emit(ba.build(self.DATA), "2026-09-28", "1.60.1.69893")
        self.assertIn('ns.AbilityInfo = { generated = "2026-09-28", build = "1.60.1.69893", '
                      'classes = 2, abilities = 4 }', text)
        self.assertIn('  PALADIN = {', text)
        self.assertIn('    { 853, "Hammer of Justice", 8, 0, "a", false, false },', text)
        self.assertTrue(text.endswith("}\n"))


class OnlyWhatATrainerSells(unittest.TestCase):
    DATA = {"build": "b", "spells": {
        "12294": {"name": "Mortal Strike", "level": 40, "rank": 1, "icon": "a", "classes": ["Warrior"]},
        "21551": {"name": "Mortal Strike", "level": 48, "rank": 2, "icon": "a", "classes": ["Warrior"]},
        "12809": {"name": "Concussion Blow", "level": 30, "rank": None, "icon": "b", "classes": ["Warrior"]},
        "78": {"name": "Heroic Strike", "level": 1, "rank": None, "icon": "c", "classes": ["Warrior"]},
        "5308": {"name": "Execute", "level": 24, "rank": None, "icon": "d", "classes": ["Warrior"]},
    }}
    # A level 1 warrior's trainer: it sells Execute and the later rank of Mortal Strike.
    OFFERED = {"WARRIOR": {"spells": {5308, 21551}, "names": {"Execute", "Mortal Strike"}, "floor": 1}}
    ACQUIRE = {78: {"2"}, 12294: {"0"}, 21551: {"0"}, 12809: {"0"}, 5308: {"0"}}

    def names(self, **kwargs):
        return [s["name"] for s in ba.build(self.DATA, self.ACQUIRE, None, self.OFFERED)["WARRIOR"]]

    def test_a_talent_the_trainer_never_mentions_goes(self):
        self.assertNotIn("Concussion Blow", self.names(), "a talent is not something you can buy")

    def test_what_the_level_grants_stays(self):
        self.assertIn("Heroic Strike", self.names(), "granted with the level, never sold")

    def test_a_talent_ladder_the_trainer_continues_stays_whole(self):
        self.assertEqual(self.names().count("Mortal Strike"), 2,
                         "rank 1 is a talent, but the trainer sells rank 2, so the ladder is kept")

    def test_below_the_floor_the_trainer_proves_nothing(self):
        offered = {"WARRIOR": {"spells": set(), "names": set(), "floor": 35}}
        names = [s["name"] for s in ba.build(self.DATA, self.ACQUIRE, None, offered)["WARRIOR"]]
        self.assertIn("Execute", names, "level 24 is beneath what that trainer would list")
        self.assertIn("Concussion Blow", names, "so is level 30, so its silence there means nothing")


class RaceLocks(unittest.TestCase):
    DATA = {"build": "b", "spells": {
        "10797": {"name": "Starshards", "level": 10, "rank": None, "icon": "a", "classes": ["Priest"]},
        "2652": {"name": "Touch of Weakness", "level": 10, "rank": None, "icon": "b", "classes": ["Priest"]},
        "585": {"name": "Smite", "level": 1, "rank": None, "icon": "c", "classes": ["Priest"]},
    }}
    OFFERED = {"PRIEST": {"spells": {2652, 585}, "names": {"Touch of Weakness", "Smite"}, "floor": 1}}
    RACES = {10797: "NightElf", 2652: "Scourge"}

    def test_a_race_locked_spell_survives_a_trainer_that_never_offered_it(self):
        rows = ba.build(self.DATA, None, None, self.OFFERED, self.RACES)["PRIEST"]
        names = [r["name"] for r in rows]
        self.assertIn("Starshards", names, "an Undead trainer is never asked about Night Elf spells")
        self.assertEqual({r["name"]: r["races"] for r in rows}["Starshards"], "NightElf")

    def test_masks_read_as_races(self):
        self.assertEqual(ba.race_names(0), "")
        self.assertEqual(ba.race_names(-1), "", "every race is the same as no lock")
        self.assertEqual(ba.race_names(8), "NightElf")
        self.assertEqual(ba.race_names(16), "Scourge")
        self.assertEqual(ba.race_names(5), "Human,Dwarf")

    def test_the_races_reach_the_lua(self):
        text = ba.emit(ba.build(self.DATA, None, None, self.OFFERED, self.RACES), "2026-09-28", "b")
        self.assertIn('"Starshards", 10, 0, "a", false, "NightElf" },', text)
        self.assertIn('"Smite", 1, 0, "c", false, false },', text)


class TrainerTruth(unittest.TestCase):
    DATA = {"build": "1.60.1.69893", "spells": {
        "853": {"name": "Hammer of Justice", "level": 8, "rank": None, "icon": "a", "classes": ["Paladin"]},
        "635": {"name": "Holy Light", "level": 1, "rank": None, "icon": "b", "classes": ["Paladin"]},
    }}

    def test_a_trainer_overrules_the_scrape(self):
        out = ba.build(self.DATA, None, {853: 12})
        rows = {s["name"]: s for s in out["PALADIN"]}
        self.assertEqual(rows["Hammer of Justice"]["level"], 12, "the trainer window is the game itself")
        self.assertTrue(rows["Hammer of Justice"]["trained"])
        self.assertEqual(rows["Holy Light"]["level"], 1)
        self.assertFalse(rows["Holy Light"]["trained"], "nobody has seen this one at a trainer")

    def test_the_order_follows_the_corrected_level(self):
        out = ba.build(self.DATA, None, {635: 30})
        self.assertEqual([s["name"] for s in out["PALADIN"]], ["Hammer of Justice", "Holy Light"])

    def test_trainer_levels_survive_a_round_trip(self):
        import json as _json, tempfile, os as _os
        union = {"trainers": {"3706": {"services": [
            {"spell": 853, "level": 12}, {"spell": 999, "level": None}, {"name": "no id", "level": 4}]}}}
        with tempfile.TemporaryDirectory() as d:
            path = _os.path.join(d, "observed.json")
            with open(path, "w") as f:
                _json.dump(union, f)
            self.assertEqual(ba.trainer_levels(path), {853: 12})
        self.assertEqual(ba.trainer_levels("/nope.json"), {})

    def test_emit_carries_the_trained_flag(self):
        text = ba.emit(ba.build(self.DATA, None, {853: 12}), "2026-09-28", "b")
        self.assertIn('{ 853, "Hammer of Justice", 12, 0, "a", true, false },', text)
        self.assertIn('{ 635, "Holy Light", 1, 0, "b", false, false },', text)


if __name__ == "__main__":
    unittest.main()
