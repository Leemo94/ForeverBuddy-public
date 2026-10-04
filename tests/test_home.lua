package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")
local ns = Stub.LoadAddon({ "Core.lua", "Comm/Version.lua", "UsedFor/QuestStatus.lua", "Nav/Arrow.lua", "Nav/MapLevels.lua", "UI/Window.lua", "UI/Home.lua", "UI/Journal.lua",
                            "UI/Zones.lua", "UI/Abilities.lua", "UI/Settings.lua", "Dungeons/Guide.lua" })

local function world()
  Stub.reset()
  ns.db = { features = {} }
  ns.Dungeons = { { key = "rfc", name = "Ragefire Chasm", level = { 13, 18 }, quests = { {}, {} } } }
  ns.AbilityInfo = { abilities = 1600 }
end

T.run("the welcome page names every screen, in rail order", function()
  world()
  local page = ns.ShowWindow("home").pages.home
  T.eq(page.heading:GetText(), "Welcome to ForeverBuddy")
  local titles = {}
  for i, row in ipairs(page.sections) do titles[i] = row.title:GetText() end
  T.eq(table.concat(titles, " / "),
    "Where to level / Abilities / Professions / City map improvements / Settings",
    "the dungeon journal is shelved, so the welcome page does not offer it")
  T.truthy(page.sections[2].body:GetText():find("trainer", 1, true), page.sections[2].body:GetText())
end)

T.run("a section opens the screen it describes", function()
  world()
  local page = ns.ShowWindow("home").pages.home
  page.sections[1]:Click()
  T.eq(_G.ForeverBuddyFrame.current, "zones")
  ns.SelectScreen("home")
  page.sections[2]:Click()
  T.eq(_G.ForeverBuddyFrame.current, "abilities", "the abilities screen is reachable")
  ns.SelectScreen("home")
  page.sections[3]:Click()
  T.eq(_G.ForeverBuddyFrame.current, "home", "the professions section has no screen of its own")
  page.sections[4]:Click()
  T.eq(_G.ForeverBuddyFrame.current, "home", "nor does the city map one")
  ns.HideWindow()
end)

T.run("it says the data is from the beta and who made it", function()
  world()
  local page = ns.SelectScreen("home")
  T.truthy(page.caveat:GetText():find("WoW: Forever beta", 1, true))
  T.truthy(page.caveat:GetText():find("added to frequently", 1, true))
  T.eq(page.made:GetText(), "Made by Leemo")
  T.eq(page.footer, nil, "no tally of what is loaded: it counted a dungeon list that is shelved")
  ns.HideWindow()
end)

T.run("the professions section is there, and opens nothing", function()
  world()
  local page = ns.SelectScreen("home")
  local found
  for _, row in ipairs(page.sections) do
    if row.section.title == "Professions" then found = row.section end
  end
  T.truthy(found, "the shopping list is the largest thing in the addon and was unmentioned")
  T.truthy(found.body:find("Shopping list", 1, true), "it names the button you press")
  T.eq(found.screen, nil, "it lives on Blizzard's profession window, so there is nothing to open")
  ns.HideWindow()
end)

T.run("every screen the welcome page offers is registered", function()
  world()
  for _, row in ipairs(ns.SelectScreen("home").sections) do
    local key = row.section.screen
    if key then T.truthy(ns.screenIndex[key], "no screen called " .. key) end
  end
  T.eq(#ns.screens, 4, "welcome, zones, abilities and settings")
  ns.HideWindow()
end)

T.run("the version line turns into an update notice when a newer one is about", function()
  world()
  ns.AddonVersion = function() return "0.19.1" end
  ns.newerVersion = nil
  local page = ns.SelectScreen("home")
  T.truthy(page.version:GetText():find("Version 0.19.1", 1, true))
  T.eq(page.version:GetText():find("is out", 1, true), nil)
  ns.newerVersion = "0.21.0"
  page = ns.SelectScreen("home")
  T.truthy(page.version:GetText():find("Version 0.21.0 is out", 1, true), page.version:GetText())
  ns.newerVersion = nil
  ns.HideWindow()
end)

T.finish()
