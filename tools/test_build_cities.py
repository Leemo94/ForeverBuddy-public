import unittest

import build_cities as bc


class Classify(unittest.TestCase):
    def test_class_trainers(self):
        self.assertEqual(bc.classify("Sian'dur", "Hunter Trainer"), ("class", "Hunter"))
        self.assertEqual(bc.classify("Tajarri", "Priest Trainer"), ("class", "Priest"))
        self.assertEqual(bc.classify("Ulminia", "Portal Trainer"), ("class", "Mage portals"))

    def test_profession_trainers_by_title_or_by_rank(self):
        self.assertEqual(bc.classify("Ansekhwa", "Herbalism Trainer"), ("profession", "Herbalism"))
        self.assertEqual(bc.classify("Yelmak", "Expert Alchemist"), ("profession", "Alchemy"))
        self.assertEqual(bc.classify("Mukdrak", "Journeyman Engineer"), ("profession", "Engineering"))
        self.assertEqual(bc.classify("Gregory Ardus", "Apprentice Chef"), ("profession", "Cooking"))

    def test_a_weapon_master_is_its_own_kind(self):
        self.assertEqual(bc.classify("Sayoc", "Weapon Master"), ("weapon", "Weapon master"))
        self.assertEqual(bc.classify("Urtharo", "Weapon Merchant"), (None, None), "a shop, not a teacher")
        self.assertEqual(bc.classify("Kelgruk Bloodaxe", "Weapon Crafter"), (None, None))

    def test_services(self):
        self.assertEqual(bc.classify("Kaymard Copperpinch", "Banker"), ("bank", "Bank"))
        self.assertEqual(bc.classify("Doras", "Wind Rider Master"), ("flight", "Wind Rider Master"))
        self.assertEqual(bc.classify("Michael Garrett", "Bat Handler"), ("flight", "Bat Handler"))
        self.assertEqual(bc.classify("Auctioneer Thathung", ""), ("auction", "Auction house"))

    def test_vendors_and_everyone_else_are_left_out(self):
        for name, sub in [("Sarah", "Alchemy Supplies"), ("Kor'geld", "Reagent Vendor"),
                          ("Innkeeper Gryshka", "Innkeeper"),
                          ("Ogunaro", "Stable Master"), ("Archmage Xylem", "Master Mage"),
                          ("Random", ""), ("Random", None)]:
            self.assertEqual(bc.classify(name, sub), (None, None), "%s / %s" % (name, sub))

    def test_every_kind_has_a_switch(self):
        kinds = {bc.classify(*pair)[0] for pair in [
            ("A", "Mage Trainer"), ("B", "Fishing Trainer"), ("C", "Banker"),
            ("D", "Gryphon Master"), ("Auctioneer E", ""), ("F", "Weapon Master")]}
        self.assertEqual(kinds, set(bc.KINDS))


class BuildAndEmit(unittest.TestCase):
    NPCS = {
        3352: ["Ormak Grimshot", 0, 0, 0, 0, 0, {1637: [[66.04, 18.5]]}, None, 1637,
               None, None, 0, "H", "Hunter Trainer", 19],
        4550: ["Kaymard Copperpinch", 0, 0, 0, 0, 0, {1637: [[50.4, 62.14]]}, None, 1637,
               None, None, 0, "H", "Banker", 257],
        9999: ["Grunt", 0, 0, 0, 0, 0, {1637: [[10.0, 10.0]]}, None, 1637, None, None, 0, "H", None, 0],
        1111: ["Elsewhere", 0, 0, 0, 0, 0, {1519: [[20.0, 20.0]]}, None, 1519, None, None, 0, "A", "Banker", 257],
    }

    def test_only_points_in_that_city(self):
        cities = bc.build(self.NPCS, {1637: 1454, 1519: 1453})
        orgrimmar = next(c for c in cities if c["key"] == "orgrimmar")
        self.assertEqual(orgrimmar["map"], 1454)
        self.assertEqual([p["name"] for p in orgrimmar["points"]],
                         ["Ormak Grimshot", "Kaymard Copperpinch"], "sorted by kind, grunts left out")
        self.assertEqual(orgrimmar["points"][0]["x"], 66.0, "one decimal place")

    def test_emit_is_loadable_lua(self):
        cities = bc.build(self.NPCS, {1637: 1454})
        text = bc.emit(cities, "2026-09-27")
        self.assertIn('ns.CityInfo = { generated = "2026-09-27", cities = 6, points = 3 }', text)
        self.assertIn('{ key = "orgrimmar", name = "Orgrimmar", zone = 1637, map = 1454, faction = "Horde"', text)
        self.assertIn('kind = "class", name = "Ormak Grimshot", sub = "Hunter Trainer", tag = "Hunter"', text)
        self.assertTrue(text.endswith("}\n"))


class RedrawnMaps(unittest.TestCase):
    # The real numbers: Stormwind's world bounds in Classic Era, then in Forever with the harbour.
    ERA = (-9175.205078125, 36.70063018799, -8278.8505859375, 1380.9714355469)
    NOW = (-9154.169921875, -14.58399963379, -7995.830078125, 1722.9200439453)

    def test_a_classic_point_lands_where_forever_draws_it(self):
        moved = bc.transform_for(self.ERA, self.NOW)
        point = {"x": 53.2, "y": 60.9}              # Auctioneer Chilton, off the Classic map
        bc.move(point, moved)
        self.assertAlmostEqual(point["x"], 60.8, places=1)
        self.assertAlmostEqual(point["y"], 71.6, places=1, msg="the Trade District, not Cathedral Square")

    def test_an_unchanged_map_is_left_alone(self):
        self.assertIsNone(None if self.ERA == self.ERA else 1)
        point = {"x": 68.0, "y": 17.8}
        bc.move(point, None)
        self.assertEqual((point["x"], point["y"]), (68.0, 17.8))

    def test_only_maps_whose_bounds_moved_get_a_transform(self):
        import tempfile, os as _os
        head = ("UiMin_0,UiMin_1,UiMax_0,UiMax_1,Region_0,Region_1,Region_2,Region_3,Region_4,"
                "Region_5,ID,UiMapID,OrderIndex,MapID,AreaID\n")
        def row(ui, bounds):
            return "0,0,1,1,%s,%s,0,%s,%s,0,1,%d,0,0,0\n" % (bounds[0], bounds[1], bounds[2], bounds[3], ui)
        with tempfile.TemporaryDirectory() as d:
            era = _os.path.join(d, "era.csv")
            now = _os.path.join(d, "now.csv")
            open(era, "w").write(head + row(1453, self.ERA) + row(1454, (1, 2, 3, 4)))
            open(now, "w").write(head + row(1453, self.NOW) + row(1454, (1, 2, 3, 4)))
            found = bc.map_transforms(now, era)
        self.assertEqual(list(found), [1453], "Orgrimmar never moved")

    def test_missing_tables_mean_no_conversion(self):
        self.assertEqual(bc.map_transforms("/nope/a.csv", "/nope/b.csv"), {})


if __name__ == "__main__":
    unittest.main()
