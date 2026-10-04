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

T.run("the ladder is every ability the class learns, in level order", function()
  world(17, "PALADIN")
  local spells = ns.AbilityLadder("PALADIN")
  T.eq(#spells, 7, "all of them, not just the ones this character can reach")
  T.eq(spells[1].name, "Holy Light"); T.eq(spells[1].level, 1); T.eq(spells[1].rank, 1)
  T.eq(spells[3].name, "Holy Light"); T.eq(spells[3].level, 14, "the rank at 14 comes after level 1")
  T.eq(spells[#spells].name, "Hammer of Justice"); T.eq(spells[#spells].level, 24)
end)

T.run("what you already know changes nothing: the ladder is the whole ladder", function()
  world(17, "PALADIN")
  _G.IsSpellKnown = function() return true end
  T.eq(#ns.AbilityLadder("PALADIN"), 7)
  _G.IsSpellKnown = nil
end)

T.run("the screen shows level 1 to 60 whatever level you are", function()
  world(17, "PALADIN")
  local w = ns.ShowWindow("abilities")
  T.eq(w.current, "abilities")
  local page = w.pages.abilities
  T.eq(page.classToken, "PALADIN")
  T.eq(page.heading:GetText(), "Paladin abilities")
  T.eq(page.total, 7)
  T.truthy(page.subheading:GetText():find("7 abilities, level 1 to 60", 1, true), page.subheading:GetText())
  T.eq(page.rows[1].text:GetText(), "Level 1", "it opens on the first level, not on your own")
  T.eq(page.rows[2].text:GetText(), "Holy Light (rank 1)")
  T.eq(page.rows[2].note:GetText(), "", "the level is the heading above; the note is for a price")
  local shown = page.shownRows

  -- A level-up used to leave the top list stale. Now there is nothing to go stale.
  Stub.level = 60
  local again = ns.SelectScreen("abilities")
  T.eq(again.total, 7)
  T.eq(again.shownRows, shown)
  T.eq(again.rows[1].text:GetText(), "Level 1")
  ns.HideWindow()
end)

T.run("a class with no abilities loaded says so rather than showing an empty page", function()
  world(17, "PALADIN")
  ns.Abilities = {}
  local page = ns.SelectScreen("abilities")
  T.eq(page.total, 0)
  T.eq(page.rows[1].text:GetText(), "No abilities are known for this class yet.")
  ns.HideWindow()
end)

T.run("/fb abilities takes a class, or anything else as something to look for", function()
  world(17, "PALADIN")
  T.eq(ns.SlashHandlers.abilities("mage"), "MAGE")
  T.eq(_G.ForeverBuddyFrame.pages.abilities.classToken, "MAGE")
  T.eq(ns.SlashHandlers.abilities(""), nil, "no class named means your own")
  local page = _G.ForeverBuddyFrame.pages.abilities
  T.eq(page.classToken, "PALADIN")

  T.eq(ns.SlashHandlers.abilities("hammer"), "hammer", "not a class, so it is a search")
  T.eq(page.searching, "hammer")
  T.eq(page.matched, 1)
  T.eq(page.rows[2].text:GetText(), "Hammer of Justice")

  ns.SlashHandlers.abilities("paladin")
  T.eq(page.searching, false, "naming a class clears the box")
  ns.HideWindow()
end)

T.run("the search box filters the ladder, headings and all", function()
  world(17, "PALADIN")
  local page = ns.SelectScreen("abilities")
  T.eq(page.matched, 7, "everything, to start with")

  page.search:SetText("holy light")
  page = ns.SelectScreen("abilities")
  T.eq(page.matched, 2, "both ranks")
  T.eq(page.rows[1].text:GetText(), "Level 1", "with the level it is learned at above it")
  T.eq(page.rows[2].text:GetText(), "Holy Light (rank 1)")
  T.eq(page.rows[3].text:GetText(), "Level 14")
  T.eq(page.rows[4].text:GetText(), "Holy Light (rank 2)")
  T.truthy(page.subheading:GetText():find('2 matching "holy light"', 1, true), page.subheading:GetText())

  page.search:SetText("HAMMER")
  page = ns.SelectScreen("abilities")
  T.eq(page.matched, 1, "case is nobody's problem but ours")

  page.search:SetText("holy light 2")
  page = ns.SelectScreen("abilities")
  T.eq(page.matched, 1, "a rank can be searched for too")

  page.search:SetText("sandwich")
  page = ns.SelectScreen("abilities")
  T.eq(page.matched, 0)
  T.truthy(page.rows[1].text:GetText():find('Nothing matching "sandwich"', 1, true), page.rows[1].text:GetText())

  page.search:SetText("")
  page = ns.SelectScreen("abilities")
  T.eq(page.matched, 7, "clearing it gives the ladder back")
  T.eq(page.searching, false)
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

  local mine = ns.AbilityLadder("PRIEST", "Scourge")
  local names = {}
  for _, spell in ipairs(mine) do names[spell.name] = true end
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

T.run("a talent says so, because you cannot walk in and buy one", function()
  world(17, "HUNTER")
  ns.Abilities = {
    HUNTER = {
      { 19434, "Aimed Shot", 20, 0, "icon", true, false, false },
      { 1299346, "Trueshot Aura", 25, 0, "icon", false, false, true },
      { 19506, "Trueshot Aura", 40, 0, "icon", true, false, true },
    },
  }
  local ladder = ns.AbilityLadder("HUNTER")
  T.eq(ladder[1].talent, false, "Aimed Shot is sold by the trainer in Forever")
  T.eq(ladder[2].talent, true, "Trueshot Aura is a Marksmanship talent")

  local page = ns.SelectScreen("abilities")
  local byLevel = {}
  for i = 1, page.shownRows do
    local text = page.rows[i].text:GetText()
    if page.rows[i].spellID then byLevel[#byLevel + 1] = text end
  end
  T.eq(byLevel[1], "Aimed Shot", "nothing is added to something you buy")
  T.truthy(byLevel[2]:find("(talent)", 1, true), byLevel[2])
  T.truthy(byLevel[3]:find("(talent)", 1, true), "later ranks of a talent are still a talent: " .. byLevel[3])
  T.truthy(page.subheading:GetText():find("2 of them are talents", 1, true), page.subheading:GetText())
  ns.HideWindow()
end)

T.finish()
