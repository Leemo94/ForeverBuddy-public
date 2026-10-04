"""Known-answer tests for tools/merge_scan.py. Run: python3 -m unittest discover -s tools -v"""
import json
import os
import tempfile
import unittest

import merge_scan as ms

SAVED = r'''
ForeverBuddyScanDB = {
	["quests"] = {
		[92401] = {
			["name"] = "A Frightened Request",
			["level"] = 22,
			["xp"] = 1850,
			["objectives"] = {
				{ ["text"] = "Speak to Tabitha Heartweaver", ["type"] = "monster", ["need"] = 1 },
			},
			["rewards"] = {
				{ ["item"] = 769, ["name"] = "Chunk of Boar Meat", ["count"] = 2, ["quality"] = 1 },
			},
			["waypoint"] = { ["map"] = 1421, ["x"] = 0.451, ["y"] = 0.679 },
		},
		[26] = {
			["name"] = "A Lesson to Learn",
		},
	},
	["missing"] = {
		[99366] = true,
	},
	["info"] = {
		["build"] = "1.60.1.70178",
		["scanner"] = "0.1.0",
		["realm"] = "Test Realm",
		["when"] = "2026-10-02 19:00",
	},
}
'''

# The same quest from a second run, this time with the level and the gold the first one missed.
RICHER = r'''
ForeverBuddyScanDB = {
	["quests"] = {
		[26] = {
			["name"] = "A Lesson to Learn",
			["level"] = 60,
			["money"] = 4500,
			["objectives"] = {
				{ ["text"] = "Speak with Dendrite Starblaze", ["type"] = "monster", ["need"] = 1 },
			},
		},
	},
	["info"] = { ["build"] = "1.60.1.70178" },
}
'''


def write(folder, name, text):
    path = os.path.join(folder, name)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    return path


class MergeScanTest(unittest.TestCase):
    def test_first_file_is_all_new(self):
        with tempfile.TemporaryDirectory() as folder:
            union = ms.load_union(os.path.join(folder, "none.json"))
            added, improved, same, info = ms.merge_file(union, write(folder, "a.lua", SAVED))
            self.assertEqual((added, improved, same), (2, 0, 0))
            self.assertEqual(info["build"], "1.60.1.70178")
            self.assertEqual(union["quests"]["92401"]["name"], "A Frightened Request")
            self.assertEqual(union["quests"]["92401"]["waypoint"]["map"], 1421)
            self.assertEqual(union["missing"], [99366])

    def test_the_same_file_twice_changes_nothing(self):
        with tempfile.TemporaryDirectory() as folder:
            path = write(folder, "a.lua", SAVED)
            union = ms.load_union(os.path.join(folder, "none.json"))
            ms.merge_file(union, path)
            added, improved, same, _ = ms.merge_file(union, path)
            self.assertEqual((added, improved, same), (0, 0, 2))

    def test_a_fuller_record_wins(self):
        with tempfile.TemporaryDirectory() as folder:
            union = ms.load_union(os.path.join(folder, "none.json"))
            ms.merge_file(union, write(folder, "a.lua", SAVED))
            added, improved, same, _ = ms.merge_file(union, write(folder, "b.lua", RICHER))
            self.assertEqual((added, improved, same), (0, 1, 0))
            self.assertEqual(union["quests"]["26"]["level"], 60)
            self.assertEqual(union["quests"]["26"]["money"], 4500)
            self.assertEqual(union["quests"]["92401"]["name"], "A Frightened Request",
                             "the other quest is left alone")

    def test_a_thinner_record_does_not_overwrite_a_fuller_one(self):
        with tempfile.TemporaryDirectory() as folder:
            union = ms.load_union(os.path.join(folder, "none.json"))
            ms.merge_file(union, write(folder, "b.lua", RICHER))
            ms.merge_file(union, write(folder, "a.lua", SAVED))
            self.assertEqual(union["quests"]["26"]["level"], 60)

    def test_summary_counts_what_questie_does_not_know(self):
        with tempfile.TemporaryDirectory() as folder:
            union = ms.load_union(os.path.join(folder, "none.json"))
            ms.merge_file(union, write(folder, "a.lua", SAVED))
            stats = ms.summarise(union)
            self.assertEqual(stats["quests"], 2)
            self.assertEqual(stats["with_rewards"], 1)
            self.assertEqual(stats["with_waypoint"], 1)
            self.assertEqual(stats["missing"], 1)
            # 92401 is a Forever id; 26 is an old Classic one Questie has.
            self.assertIn("92401", stats["sample_new"])

    def test_union_round_trips_as_json(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "union.json")
            union = ms.load_union(path)
            ms.merge_file(union, write(folder, "a.lua", SAVED))
            with open(path, "w", encoding="utf-8") as f:
                json.dump(union, f)
            again = ms.load_union(path)
            self.assertEqual(again["quests"]["92401"]["xp"], 1850)


if __name__ == "__main__":
    unittest.main()
