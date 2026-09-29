package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")
local ns = Stub.LoadAddon({ "Core.lua", "UI/Window.lua", "UI/Abilities.lua" })
local printed = {}
ns.Print = function(msg) table.insert(printed, msg) end

local function world(level, class)
  Stub.reset(); printed = {}
  ns.db = { features = {} }
  Stub.level = level or 17
  Stub.classToken = class or "PALADIN"
  ns.Abilities = {
    PALADIN = {
      { 635, "Holy Light", 1, 1, "spell_holy_holybolt" },
      { 21084, "Seal of Righteousness", 1, 0, "spell_holy_righteousnessaura" },
      { 639, "Holy Light", 14, 2, "spell_holy_holybolt" },
      { 498, "Divine Protection", 18, 0, "spell_holy_divineprotection" },
      { 20271, "Judgement", 18, 0, "spell_holy_righteousfury" },
      { 26573, "Consecration", 20, 0, "spell_holy_innerfire" },
      { 853, "Hammer of Justice", 24, 0, "spell_holy_sealofmight" },
    },
    MAGE = { { 133, "Fireball", 1, 1, "spell_fire_flamebolt" } },
  }
end

T.run("the plan splits what you can learn now from what is still to come", function()
  world(17, "PALADIN")
  local ready, later = ns.AbilityPlan("PALADIN", 17)
  T.eq(#ready, 3, "two at level 1 and the rank at 14")
  T.eq(ready[1].name, "Holy Light"); T.eq(ready[1].level, 1)
  T.eq(#later, 4)
  T.eq(later[1].level, 18, "the next rung up")
  T.eq(later[#later].name, "Hammer of Justice"); T.eq(later[#later].level, 24)
end)

T.run("anything already known drops off the ready list", function()
  world(17, "PALADIN")
  _G.IsSpellKnown = function(id) return id == 635 or id == 21084 end
  local ready = ns.AbilityPlan("PALADIN", 17)
  T.eq(#ready, 1, "only the rank you have not trained yet")
  T.eq(ready[1].rank, 2)
  _G.IsSpellKnown = nil
end)

T.run("the screen opens on your own class, in level order", function()
  world(17, "PALADIN")
  local w = ns.ShowWindow("abilities")
  T.eq(w.current, "abilities")
  local page = w.pages.abilities
  T.eq(page.classToken, "PALADIN")
  T.eq(page.heading:GetText(), "Paladin abilities")
  T.truthy(page.subheading:GetText():find("next at level 18", 1, true), page.subheading:GetText())
  T.eq(page.readyCount, 3)
  T.eq(page.rows[1].text:GetText(), "Ready to learn at level 17")
  T.eq(page.rows[2].text:GetText(), "Holy Light (rank 1)")
  T.eq(page.rows[2].note:GetText(), "level 1")
  ns.HideWindow()
end)

T.run("a level with nothing new says so", function()
  world(17, "PALADIN")
  _G.IsSpellKnown = function() return true end
  local page = ns.SelectScreen("abilities")
  T.eq(page.readyCount, 0)
  T.eq(page.rows[2].text:GetText(), "Nothing new for you at this level.")
  _G.IsSpellKnown = nil
  ns.HideWindow()
end)

T.run("/fb abilities takes a class, and says so when it is not one", function()
  world(17, "PALADIN")
  T.eq(ns.SlashHandlers.abilities("mage"), "MAGE")
  T.eq(_G.ForeverBuddyFrame.pages.abilities.classToken, "MAGE")
  T.eq(ns.SlashHandlers.abilities("wizard"), nil)
  T.truthy(printed[#printed]:find("no class called wizard", 1, true), printed[#printed])
  T.eq(ns.SlashHandlers.abilities(""), nil, "no class named means your own")
  T.eq(_G.ForeverBuddyFrame.pages.abilities.classToken, "PALADIN")
  ns.HideWindow()
end)

T.run("a spell someone has seen at a trainer shows who teaches it and what they want", function()
  world(17, "PALADIN")
  ns.Observed = { trainers = { [928] = { name = "Brother Sarno", class = "PALADIN", services = {
    { spell = 639, name = "Holy Light", rank = "Rank 2", level = 14, cost = 12000 },
    { spell = 853, name = "Hammer of Justice", level = 8 },
  } } } }
  T.eq(ns.TrainerFor(639).name, "Brother Sarno")
  T.eq(ns.TrainerFor(639).cost, 12000)
  T.eq(ns.TrainerFor(26573), nil, "nobody has seen this one")
  T.truthy(ns.CostText(12000), "a price reads as money")
  T.eq(ns.CostText(0), nil); T.eq(ns.CostText(nil), nil)
  local page = ns.SelectScreen("abilities")
  local row
  for i = 1, page.shownRows do
    if page.rows[i].spellID == 639 then row = page.rows[i] end
  end
  T.truthy(row, "the rank is on the list")
  T.truthy(row.note:GetText() ~= "" and row.note:GetText() ~= "level 14", "the price replaces the level")
  ns.Observed = nil
  ns.HideWindow()
end)

T.run("a race-locked spell only shows for the race that can train it", function()
  world(20, "PRIEST")
  Stub.raceFile = "Scourge"
  ns.Abilities = {
    PRIEST = {
      { 2050, "Lesser Heal", 1, 1, "a", true, false },
      { 2652, "Touch of Weakness", 10, 0, "b", false, "Scourge" },
      { 10797, "Starshards", 10, 0, "c", false, "NightElf" },
      { 13908, "Desperate Prayer", 10, 0, "d", false, "Human,Dwarf" },
    },
  }
  T.eq(ns.RaceAllows(false, "Scourge"), true, "no lock means everyone")
  T.eq(ns.RaceAllows("Scourge", "Scourge"), true)
  T.eq(ns.RaceAllows("NightElf", "Scourge"), false)
  T.eq(ns.RaceAllows("Human,Dwarf", "Dwarf"), true, "a list of races, not one")
  T.eq(ns.RaceAllows("Human,Dwarf", "Human"), true)
  T.eq(ns.RaceAllows("NightElf", nil), true, "browsing another class shows the lot")

  local ready = ns.AbilityPlan("PRIEST", 20, "Scourge")
  local names = {}
  for _, spell in ipairs(ready) do names[spell.name] = true end
  T.eq(names["Touch of Weakness"], true, "an Undead priest trains this")
  T.eq(names["Starshards"], nil, "and is never offered this")
  T.eq(names["Desperate Prayer"], nil)
  T.eq(names["Lesser Heal"], true)

  local page = ns.SelectScreen("abilities")
  local shown = {}
  for i = 1, page.shownRows do
    if page.rows[i].spellID then shown[page.rows[i].spellID] = page.rows[i].text:GetText() end
  end
  T.truthy(shown[2652], "the screen shows the Undead one")
  T.eq(shown[10797], nil, "and not the Night Elf one")
  T.truthy(shown[2652]:find("Scourge", 1, true), "it says whose it is: " .. tostring(shown[2652]))
  ns.HideWindow()
end)

T.finish()
