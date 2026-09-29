"""Known-answer tests for tools/build_weights.py. Run: python3 -m unittest discover -s tools -v"""
import json
import unittest

import build_weights as bw

FURY = """
import { Spec, Stat, PseudoStat } from '../core/proto/common.js';
const SPEC_CONFIG = registerSpecConfig(Spec.SpecWarrior, {
\tepWeights: Stats.fromMap(
\t\t{
\t\t\t[Stat.StatStrength]: 2.51,
\t\t\t[Stat.StatAgility]: 1.86,
\t\t\t[Stat.StatAttackPower]: 1,
\t\t\t[Stat.StatMeleeHit]: 28.67,
\t\t\t[Stat.StatFireResistance]: 0.5,
\t\t},
\t\t{
\t\t\t[PseudoStat.PseudoStatMainHandDps]: 11.92,
\t\t\t[PseudoStat.PseudoStatOffHandDps]: 4.69,
\t\t},
\t),
\tconsumes: Presets.DefaultConsumes,
});
"""

HEALER = """
const SPEC_CONFIG = registerSpecConfig(Spec.SpecHealingPriest, {
\t\tepWeights: Stats.fromMap({
\t\t\t[Stat.StatIntellect]: 2.73,
\t\t\t[Stat.StatSpellPower]: 1,
\t\t\t[Stat.StatMP5]: 2.05,
\t\t}),
});
"""

NO_WEIGHTS = "const SPEC_CONFIG = registerSpecConfig(Spec.SpecRaid, { consumes: {} });"

TREE = json.dumps({"tree": [
    {"path": "ui/core/sim.ts"}, {"path": "ui/warrior/sim.ts"}, {"path": "ui/warrior/presets.ts"},
    {"path": "ui/balance_druid/sim.ts"}, {"path": "sim/core/stats.go"},
]})


class ParseTests(unittest.TestCase):
    def test_two_map_block(self):
        stats, pseudo = bw.parse_ep_weights(FURY)
        # the fire resistance line in the fixture is dropped on purpose, see EXCLUDED_STATS
        self.assertEqual(stats, {"Strength": 2.51, "Agility": 1.86, "AttackPower": 1.0, "MeleeHit": 28.67})
        self.assertEqual(pseudo, {"MainHandDps": 11.92, "OffHandDps": 4.69})

    def test_single_map_block(self):
        stats, pseudo = bw.parse_ep_weights(HEALER)
        self.assertEqual(stats, {"Intellect": 2.73, "SpellPower": 1.0, "MP5": 2.05})
        self.assertEqual(pseudo, {})

    def test_missing_block(self):
        self.assertIsNone(bw.parse_ep_weights(NO_WEIGHTS))
        self.assertIsNone(bw.parse_sim(NO_WEIGHTS))

    def test_spec_record(self):
        record = bw.parse_sim(FURY)
        self.assertEqual(record["key"], "Warrior")
        self.assertEqual(record["class"], "WARRIOR")
        self.assertEqual(record["name"], "Warrior")
        healer = bw.parse_sim(HEALER)
        self.assertEqual(healer["key"], "HealingPriest")
        self.assertEqual(healer["class"], "PRIEST")
        self.assertEqual(healer["name"], "Healing Priest")

    def test_class_and_name_helpers(self):
        self.assertEqual(bw.class_token("FeralTankDruid"), "DRUID")
        self.assertEqual(bw.display_name("FeralTankDruid"), "Feral Tank Druid")
        self.assertEqual(bw.class_token("Mystery"), "UNKNOWN")

    def test_warden_shaman_is_excluded(self):
        self.assertIn("WardenShaman", bw.EXCLUDED_SPECS)

    def test_sim_paths_skip_core_and_non_sim_files(self):
        self.assertEqual(bw.sim_paths(TREE), ["ui/balance_druid/sim.ts", "ui/warrior/sim.ts"])


class EmitTests(unittest.TestCase):
    def test_emit_layout_sorted_and_compact(self):
        specs = [bw.parse_sim(HEALER), bw.parse_sim(FURY)]
        text = bw.emit_weights(specs, {"game": "classic", "generated": "2026-09-14",
                                       "repo": "wowsims/classic", "commit": "7779ebbf79dc"})
        self.assertTrue(text.startswith("local _, ns = ...\n"))
        self.assertIn('ns.WeightsInfo = { game = "classic", generated = "2026-09-14", specs = 2, '
                      'repo = "wowsims/classic", commit = "7779ebbf79dc" }', text)
        self.assertIn('  ["HealingPriest"] = { class = "PRIEST", name = "Healing Priest", source = "?", '
                      'stats = { Intellect = 2.73, MP5 = 2.05, SpellPower = 1 }, pseudo = { } },', text)
        self.assertIn('stats = { Agility = 1.86, AttackPower = 1, MeleeHit = 28.67, Strength = 2.51 }', text)
        self.assertIn('pseudo = { MainHandDps = 11.92, OffHandDps = 4.69 } },', text)
        self.assertNotIn("Resistance = ", text)
        self.assertLess(text.index('["HealingPriest"]'), text.index('["Warrior"]'))
        self.assertTrue(text.endswith("}\n"))



class Resistances(unittest.TestCase):
    SIM = """
    export const Spec = Spec.SpecMage;
    epWeights: Stats.fromMap({
        [Stat.StatIntellect]: 0.49,
        [Stat.StatSpellPower]: 1,
        [Stat.StatFireResistance]: 0.5,
        [Stat.StatShadowResistance]: 0.25,
    }),
    """

    def test_resistance_weights_are_dropped(self):
        record = bw.parse_sim(self.SIM, "ui/mage/sim.ts")
        self.assertEqual(record["stats"], {"Intellect": 0.49, "SpellPower": 1.0})
        self.assertEqual(record["path"], "ui/mage/sim.ts")

    def test_the_rest_of_a_spec_survives(self):
        record = bw.parse_sim(self.SIM, "ui/mage/sim.ts")
        self.assertEqual(record["key"], "Mage")
        self.assertNotIn("FireResistance", record["stats"])

if __name__ == "__main__":
    unittest.main()
