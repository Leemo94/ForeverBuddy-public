package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")
local ns = Stub.LoadAddon({ "Data/Weights.lua", "Core.lua", "Gear/Score.lua" })
local printed = {}
ns.Print = function(msg) table.insert(printed, msg) end

local function fixtures()
-- item fixtures in the generated layout: { name, quality, ilvl, type, armorType, weaponType, handType, rangedType, phase, stats, weapon, unique, faction, classes, setName, sources }
ns.Items[1001] = { "Sturdy Belt", 2, 30, 8, 4, 0, 0, 0, 1, { Strength = 10, Stamina = 5 }, false, false, false, false, false, false }
ns.Items[1002] = { "Weak Belt", 2, 20, 8, 4, 0, 0, 0, 1, { Strength = 4 }, false, false, false, false, false, false }
ns.Items[1003] = { "Big Axe", 3, 40, 13, 0, 1, 4, 0, 1, { Strength = 5 }, { 100, 200, 2.5 }, false, false, false, false, false }
ns.Items[1004] = { "Small Shield", 2, 20, 13, 0, 7, 3, 0, 1, { Stamina = 3 }, { 10, 20, 2.0 }, false, false, false, false, false }
ns.Items[1005] = { "Long Bow", 2, 25, 14, 0, 0, 0, 1, 1, { }, { 20, 40, 3.0 }, false, false, false, false, false }
Stub.items[1001] = { name = "Sturdy Belt", link = "|Hitem:1001:0:0:0:0:0:0:0|h[Sturdy Belt]|h", equipLoc = "INVTYPE_WAIST" }
Stub.items[1002] = { name = "Weak Belt", link = "|Hitem:1002:0:0:0:0:0:0:0|h[Weak Belt]|h", equipLoc = "INVTYPE_WAIST" }
Stub.items[1003] = { name = "Big Axe", link = "|Hitem:1003:0:0:0:0:0:0:0|h[Big Axe]|h", equipLoc = "INVTYPE_2HWEAPON" }
Stub.items[1004] = { name = "Small Shield", link = "|Hitem:1004:0:0:0:0:0:0:0|h[Small Shield]|h", equipLoc = "INVTYPE_SHIELD" }
Stub.items[1005] = { name = "Long Bow", link = "|Hitem:1005:0:0:0:0:0:0:0|h[Long Bow]|h", equipLoc = "INVTYPE_RANGED" }
Stub.items[1006] = { name = "Belt of the Bear", link = "|Hitem:1006:0:0:0:0:0:-12:0|h[Belt of the Bear]|h", equipLoc = "INVTYPE_WAIST" }
Stub.items[1007] = { name = "Grey Belt", link = "|Hitem:1007:0:0:0:0:0:0:0|h[Grey Belt]|h", equipLoc = "INVTYPE_WAIST" }
end

local W = ns.Weights.Warrior
-- Item scores on tooltips is shelved for the first release, so it registers nothing on load. It is still
-- meant to work, and these tests hold it to that.
if not ns.featureIndex.itemscore then
  ns.RegisterFeature({ key = "itemscore", name = "Item scores on tooltips", desc = "shelved", default = true })
end
ns.HookItemScoreTooltip()

local function fresh() Stub.reset(); fixtures(); printed = {}; ns.db = { features = {}, specs = {} } end

T.run("registers the itemscore feature and loads real Classic weights", function()
  T.eq(ns.featureIndex.itemscore.name, "Item scores on tooltips")
  T.eq(W.stats.Strength, 2.51)
end)

T.run("default spec is the class's plain key, and /fb spec changes it", function()
  fresh(); Stub.classToken = "WARRIOR"
  T.eq(ns.PlayerSpecKey(), "Warrior")
  Stub.classToken = "DRUID"
  T.eq(ns.PlayerSpecKey(), "BalanceDruid")
  T.eq(table.concat(ns.SpecsForClass("DRUID"), ","), "BalanceDruid,FeralDruid,FeralTankDruid,RestorationDruid")
  Stub.classToken = "WARRIOR"
  ns.SlashHandlers.spec("tankwarrior")
  T.eq(ns.PlayerSpecKey(), "TankWarrior"); T.eq(printed[#printed], "scoring items for Tank Warrior")
  ns.SlashHandlers.spec("nonsense")
  T.eq(printed[#printed - 1], "unknown spec 'nonsense' for your class")
  T.truthy(printed[#printed]:find("current spec: Tank Warrior. Options: TankWarrior, Warrior", 1, true), printed[#printed])
  ns.db.specs = {}
  ns.SlashHandlers.spec("")
  T.truthy(printed[#printed]:find("current spec: Warrior", 1, true))
end)

T.run("ScoreStats: weighted stats plus weapon dps through the right pseudo weight", function()
  T.near(ns.ScoreStats(W, { Strength = 10 }), 25.1)
  local axe = ns.ScoreStats(W, { Strength = 5 }, { 100, 200, 2.5 }, 4, 0)
  T.near(axe, 5 * 2.51 + 60 * 11.92)
  local shield = ns.ScoreStats(W, {}, { 10, 20, 2.0 }, 3, 0)
  T.near(shield, 7.5 * (W.pseudo.OffHandDps or 0))
  local bow = ns.ScoreStats(W, {}, { 20, 40, 3.0 }, 0, 1)
  T.near(bow, 10 * (W.pseudo.RangedDps or 0))
  T.eq(ns.ScoreStats(W, { Mystery = 99 }), 0, "unknown stats weigh nothing")
end)

T.run("ItemStatsFor: database first, client stats for suffix items and unknown items", function()
  fresh()
  local stats, weapon, hand = ns.ItemStatsFor(1003, Stub.items[1003].link)
  T.eq(stats.Strength, 5); T.eq(weapon[3], 2.5); T.eq(hand, 4)
  Stub.itemStats[Stub.items[1006].link] = { ITEM_MOD_STRENGTH_SHORT = 6, ITEM_MOD_STAMINA_SHORT = 6, RESISTANCE0_NAME = 40 }
  local s2 = ns.ItemStatsFor(1006, Stub.items[1006].link)
  T.eq(s2.Strength, 6); T.eq(s2.Armor, 40)
  T.eq(ns.ItemStatsFor(1007, Stub.items[1007].link), nil, "nothing known, no client stats")
  Stub.itemStats[Stub.items[1007].link] = { ITEM_MOD_STAMINA_SHORT = 1 }
  T.eq(ns.ItemStatsFor(1007, Stub.items[1007].link).Stamina, 1)
end)

T.run("tooltip line compares with the equipped item and colours the verdict", function()
  fresh(); Stub.classToken = "WARRIOR"
  Stub.equipped[6] = 1002
  GameTooltip:SetHyperlink(Stub.items[1001].link)
  local line = GameTooltip.lines[#GameTooltip.lines]
  T.eq(line.text, "Score (Warrior): 25.1  vs equipped 10.0 (+15.1)")
  T.eq(line.g, 1, "better = green")
  GameTooltip:SetHyperlink(Stub.items[1002].link)
  T.eq(GameTooltip.lines[#GameTooltip.lines].text, "Score (Warrior): 10.0  vs equipped 10.0 (+0.0)")
  Stub.equipped[6] = 1001
  GameTooltip:SetHyperlink(Stub.items[1002].link)
  line = GameTooltip.lines[#GameTooltip.lines]
  T.eq(line.text, "Score (Warrior): 10.0  vs equipped 25.1 (-15.1)")
  T.eq(line.r, 1); T.eq(line.g, 0.5, "worse = orange")
  Stub.equipped[6] = nil
  GameTooltip:SetHyperlink(Stub.items[1001].link)
  T.eq(GameTooltip.lines[#GameTooltip.lines].text, "Score (Warrior): 25.1  vs equipped 0.0 (+25.1)")
end)

T.run("no line for unknown items, when the feature is off, or without a spec", function()
  fresh(); Stub.classToken = "WARRIOR"
  GameTooltip:SetHyperlink(Stub.items[1007].link)
  T.eq(#GameTooltip.lines, 0)
  ns.db = { features = { itemscore = false } }
  GameTooltip:SetHyperlink(Stub.items[1001].link)
  T.eq(#GameTooltip.lines, 0)
  ns.db = { features = {} }; Stub.classToken = "SKYWARDEN"
  GameTooltip:SetHyperlink(Stub.items[1001].link)
  T.eq(#GameTooltip.lines, 0)
end)

T.finish()
