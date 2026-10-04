package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")

local FILES = { "Core.lua", "Nav/MapLevels.lua", "UI/Window.lua", "UI/Zones.lua", "Dungeons/Zones.lua" }
local ns = Stub.LoadAddon(FILES)
local printed = {}
ns.Print = function(msg) table.insert(printed, msg) end

local ZONE, CONTINENT = Enum.UIMapType.Zone, Enum.UIMapType.Continent

local function world(clientKnowsLevels)
  Stub.reset(); printed = {}
  ns.db = { features = {} }
  Stub.level = 12
  ns.Zones = {
    { zone = 12, name = "Elwynn Forest", continent = "Eastern Kingdoms", level = { 5, 10 }, quests = 46, faction = "Alliance", leaning = false, alliance = 46, horde = 0, source = "quests" },
    { zone = 40, name = "Westfall", continent = "Eastern Kingdoms", level = { 10, 18 }, quests = 34, faction = "Alliance", leaning = true, alliance = 20, horde = 14, source = "quests" },
    { zone = 0, name = "Riverglades", continent = "Eastern Kingdoms", level = { 33, 45 }, quests = 0, faction = false, source = "reported" },
    { zone = 14, name = "Durotar", continent = "Kalimdor", level = { 4, 12 }, quests = 40, faction = "Horde", leaning = false, alliance = 0, horde = 40, source = "quests" },
  }
  ns.Dungeons = {
    { key = "deadmines", name = "The Deadmines", zone = 1, level = { 17, 26 }, faction = false, aliases = {}, quests = {} },
    { key = "rfc", name = "Ragefire Chasm", zone = 2, level = { 13, 18 }, faction = "Horde", aliases = {}, quests = {} },
    { key = "dalaran", name = "City of Dalaran", zone = 3, level = { 28, 0 }, faction = false, aliases = {}, quests = {} },
    { key = "crypts", name = "Karazhan Crypts", zone = 4, level = false, faction = false, aliases = {}, quests = {} },
  }
  Stub.maps = {
    [1415] = { name = "Eastern Kingdoms", mapType = CONTINENT, children = { 1429, 1436, 1990, 1991 } },
    [1429] = { name = "Elwynn Forest", mapType = ZONE, parent = 1415, rect = { 0.2, 0.4, 0.5, 0.7 },
               levels = clientKnowsLevels and { 5, 10 } or nil },
    [1436] = { name = "Westfall", mapType = ZONE, parent = 1415, rect = { 0.1, 0.3, 0.6, 0.8 } },
    [1990] = { name = "Riverglades", mapType = ZONE, parent = 1415, rect = { 0.5, 0.7, 0.4, 0.6 } },
    -- A Feralas-shaped zone: its rectangle reaches far west over water, and only the eastern
    -- third of it is the zone. It has no level range, so it never reaches the overlay itself.
    [1991] = { name = "Westmarch", mapType = ZONE, parent = 1415, rect = { 0.0, 0.4, 0.0, 0.2 },
               shape = function(x) return x >= 0.25 end },
    [1414] = { name = "Kalimdor", mapType = CONTINENT, children = { 1411 } },
    [1411] = { name = "Durotar", mapType = ZONE, parent = 1414, rect = { 0.6, 0.8, 0.2, 0.4 } },
  }
  Stub.position = { map = 1429, x = 0.3, y = 0.6, zone = "Elwynn Forest", sub = "" }
  WorldMapFrame.mapID = 1415
end

T.run("registers the map levels feature, on by default", function()
  world()
  T.eq(ns.featureIndex.maplevels.name, "Zone levels on the map")
  T.eq(ns.IsFeatureEnabled("maplevels"), true)
end)

T.run("a range comes from the client when it knows one, and from our own data when it does not", function()
  world(true)
  local min, max, source = ns.MapLevels(1429)
  T.eq(min, 5); T.eq(max, 10); T.eq(source, "client")
  world(false)
  min, max, source = ns.MapLevels(1429)
  T.eq(min, 5); T.eq(max, 10); T.eq(source, "quests", "Forever ships no zone tuning, so ours stands in")
  min, max, source = ns.MapLevels(1990)
  T.eq(min, 33); T.eq(max, 45); T.eq(source, "reported", "a new Forever zone")
  T.eq(ns.MapLevels(1415), nil, "a continent has no range")
end)

T.run("level text and colour follow your own level", function()
  world()
  T.eq(ns.LevelRangeText(5, 10), "5-10")
  T.eq(ns.LevelRangeText(60, 60), "60")
  T.eq(ns.LevelRangeColor(33, 45, 12), ns.COLORS.keep, "ahead of you")
  T.eq(ns.LevelRangeColor(10, 18, 12), ns.COLORS.available, "right for you")
  T.eq(ns.LevelRangeColor(5, 10, 20), ns.COLORS.done, "behind you")
end)

T.run("the map overlay writes a range over every zone of the open continent", function()
  world(false)
  WorldMapFrame:Show()
  local shown = ns.UpdateMapLevels()
  T.eq(shown, 3, "Elwynn, Westfall and Riverglades")
  T.eq(_G.ForeverBuddyMapLevels ~= nil, true)
  local zones = ns.ZonesOnMap(1415)
  T.eq(zones[1].name, "Elwynn Forest"); T.eq(zones[1].min, 5)
  T.near(zones[1].x, 0.3); T.near(zones[1].y, 0.6, "the middle of the zone")
  T.eq(zones[3].name, "Riverglades")
end)

T.run("the overlay hides when the map is closed or the feature is off", function()
  world(false)
  WorldMapFrame:Show()
  ns.UpdateMapLevels()
  WorldMapFrame:Hide()
  T.eq(ns.UpdateMapLevels(), nil)
  WorldMapFrame:Show()
  ns.SetFeatureEnabled("maplevels", false)
  T.eq(ns.UpdateMapLevels(), nil)
end)

T.run("the levels are cut into bands, with the untuned dungeons last", function()
  world(false)
  local bands = ns.LevelBands("Alliance")
  T.eq(#bands, 13, "twelve bands of five, then the dungeons with no level")
  T.eq(bands[1].lo, 1); T.eq(bands[1].hi, 5)
  T.eq(bands[12].lo, 56); T.eq(bands[12].hi, 60)
  T.eq(bands[13].lo, false, "the ones Forever has not tuned")
  T.eq(#bands[13].dungeons, 1)
  T.eq(bands[13].dungeons[1].name, "Karazhan Crypts")

  local names = {}
  for _, z in ipairs(bands[2].zones) do table.insert(names, z.name) end  -- levels 6-10
  T.eq(table.concat(names, ", "), "Elwynn Forest, Westfall",
    "Durotar is wholly the Horde's, so an Alliance list leaves it out")
  T.eq(ns.BandIndexFor(bands, 12), 3, "level 12 is in the 11-15 band")
  T.eq(ns.BandIndexFor(bands, 60), 12)

  local dungeons = {}
  for _, d in ipairs(bands[4].dungeons) do table.insert(dungeons, d.name) end -- 16-20
  T.eq(table.concat(dungeons, ", "), "The Deadmines, Ragefire Chasm")
end)

T.run("a zone wholly the other side's is left off, one that only leans is not", function()
  world(false)
  local names = {}
  for _, z in ipairs(ns.LevelBands("Horde")[2].zones) do table.insert(names, z.name) end
  T.eq(table.concat(names, ", "), "Durotar, Westfall",
    "Elwynn is wholly Alliance and goes; Westfall only leans and stays")

  -- Westfall wholly Alliance: a new table, because the name index notices a swap, not an edit
  local zones = {}
  for i, z in ipairs(ns.Zones) do zones[i] = z end
  zones[2] = { zone = 40, name = "Westfall", continent = "Eastern Kingdoms", level = { 10, 18 },
               quests = 34, faction = "Alliance", leaning = false, alliance = 34, horde = 0, source = "quests" }
  ns.Zones = zones
  names = {}
  for _, z in ipairs(ns.LevelBands("Horde")[2].zones) do table.insert(names, z.name) end
  T.eq(table.concat(names, ", "), "Durotar")
end)

T.run("the colours are the game's own, by the band and your level", function()
  world(false)
  T.eq(ns.DifficultyColor(20, 30, 12), ns.DIFFICULTY.red, "eight levels short")
  T.eq(ns.DifficultyColor(14, 20, 12), ns.DIFFICULTY.orange, "nearly there")
  T.eq(ns.DifficultyColor(10, 18, 12), ns.DIFFICULTY.yellow, "where you should be")
  T.eq(ns.DifficultyColor(5, 13, 12), ns.DIFFICULTY.green, "running out")
  T.eq(ns.DifficultyColor(4, 10, 12), ns.DIFFICULTY.grey, "behind you")
  T.eq(ns.DifficultyColor(nil, nil, 12), ns.DIFFICULTY.grey, "a dungeon with no level at all")
end)

T.run("it answers the question in one line", function()
  world(false)
  local said = ns.LevellingAdvice(12, "Alliance")
  T.truthy(said:find("At 12:", 1, true), said)
  T.truthy(said:find("quest in Westfall", 1, true), said)
  T.truthy(said:find("run Ragefire Chasm (13-18)", 1, true), said)
  T.truthy(said:find("Next dungeon: The Deadmines at 17", 1, true), said)

  Stub.level = 50
  said = ns.LevellingAdvice(50, "Alliance")
  T.truthy(said:find("At 50", 1, true), said)
  T.eq(said:find("Next dungeon", 1, true), nil, "nothing left above you")
end)

T.run("the screen opens on your own band, with zones then dungeons", function()
  world(false)
  local page = ns.SelectScreen("zones")
  T.eq(page.shownBands, 13)
  T.eq(page.band, 3, "level 12 opens the 11-15 band")
  T.eq(page.rail[3].title:GetText(), "Level 11-15")
  T.eq(page.rail[3].mark:IsShown(), true, "and it is the one marked")
  T.eq(page.rail[1].title:GetText(), "Level 1-5")
  T.eq(page.rail[13].title:GetText(), "Not tuned yet")
  T.truthy(page.advice:GetText():find("At 12:", 1, true), page.advice:GetText())

  local rows = {}
  for i = 1, page.shownRows do table.insert(rows, page.rows[i].name:GetText()) end
  T.eq(rows[1], "Levels 11 to 15")
  T.eq(type(page.rows[2].zone), "table", "a zone row")
  T.eq(rows[2], "Westfall")
  T.eq(page.rows[2].levels:GetText(), "10-18")
  T.eq(page.rows[2].where:GetText(), "Eastern Kingdoms")
  T.eq(page.rows[2].last:GetText(), "34 quests")
  local dungeonHeader
  for i, text in ipairs(rows) do if text == "Dungeons" then dungeonHeader = i end end
  T.truthy(dungeonHeader, "the dungeons have their own heading")
  T.eq(page.rows[dungeonHeader + 1].name:GetText(), "Ragefire Chasm")
  T.eq(page.rows[dungeonHeader + 1].levels:GetText(), "13-18")
  T.eq(page.rows[dungeonHeader + 1].where:GetText(), "Horde side")
  ns.HideWindow()
end)

T.run("clicking a band on the rail opens it", function()
  world(false)
  local page = ns.SelectScreen("zones")
  page.rail[7]:Click()   -- levels 31-35
  T.eq(page.band, 7)
  T.eq(page.rows[1].name:GetText(), "Levels 31 to 35")
  T.eq(page.rows[2].name:GetText(), "Riverglades")
  ns.HideWindow()
end)

T.run("a zone row does nothing when clicked, because lighting it up never worked", function()
  world(false)
  local page = ns.SelectScreen("zones")
  WorldMapFrame:Hide()
  T.eq(page.rows[2].scripts.OnClick, nil, "no click handler at all")
  T.eq(WorldMapFrame:IsShown(), false, "and the map is left alone")
  T.eq(ns.ShowZoneOnMap, nil, "the opener is gone with it")
  ns.HideWindow()
end)

T.run("a zone row wears its side's emblem, and the rows say where the numbers came from", function()
  world(false)
  Stub.faction = "Horde"
  local page = ns.SelectScreen("zones")
  page.rail[2]:Click()  -- levels 6-10: Durotar is wholly Horde, Westfall only leans Alliance
  local byName = {}
  for i = 1, page.shownRows do
    local row = page.rows[i]
    if type(row.zone) == "table" then byName[row.zone.name] = row end
  end
  T.eq(byName["Durotar"].icon:GetTexture(), "Interface\\TargetingFrame\\UI-PVP-Horde")
  T.eq(byName["Durotar"].icon:GetAlpha(), 1, "all 40 of its quests are the Horde's")
  T.eq(byName["Westfall"].icon:GetAlpha(), 0.45, "Westfall only leans Alliance")

  byName["Durotar"].scripts.OnEnter(byName["Durotar"])
  local said = {}
  for _, line in ipairs(GameTooltip.lines or {}) do table.insert(said, line.text) end
  T.truthy(table.concat(said, " | "):find("0 Alliance, 40 Horde", 1, true), table.concat(said, " | "))
  T.eq(table.concat(said, " | "):find("Click to see it", 1, true), nil, "nothing is promised that does not happen")
  ns.HideWindow()
end)

T.run("a dungeon with no level of its own sits in its own band and says so", function()
  world(false)
  local page = ns.SelectScreen("zones")
  page.rail[13]:Click()
  T.eq(page.rows[1].name:GetText(), "Not tuned yet")
  local names = {}
  for i = 1, page.shownRows do table.insert(names, page.rows[i].name:GetText()) end
  T.truthy(table.concat(names, " | "):find("Karazhan Crypts", 1, true), table.concat(names, " | "))
  T.truthy(table.concat(names, " | "):find("not given them a level", 1, true), table.concat(names, " | "))
  ns.HideWindow()
end)

T.run("/fb zones opens the screen and still prints the short list", function()
  world(false)
  SlashCmdList.FOREVERBUDDY("zones")
  T.eq(_G.ForeverBuddyFrame.current, "zones")
  T.truthy(printed[1]:find("Zones for level 12", 1, true), tostring(printed[1]))
  ns.HideWindow()
end)

T.run("a range is written on its zone, not in the water its rectangle takes in", function()
  world(false)
  local x, y = ns.ZoneLabelPoint(1415, 1429, 0.2, 0.4, 0.5, 0.7)
  T.near(x, 0.3); T.near(y, 0.6, "a zone that fills its rectangle keeps the plain middle")
  x, y = ns.ZoneLabelPoint(1415, 1991, 0.0, 0.4, 0.0, 0.2)
  T.truthy(x > 0.28, ("written at %.2f, which is west of the zone"):format(x))
  T.truthy(x < 0.37, ("written at %.2f, which is off its eastern edge"):format(x))
  T.near(y, 0.1, "and level with the middle of it")
end)

T.run("a zone the client's map tree never lists still joins its continent", function()
  world(false)
  table.insert(ns.Zones, { zone = 25, name = "Blackrock Mountain", continent = "Eastern Kingdoms",
                           level = { 60, 60 }, quests = 15, faction = false, source = "quests" })
  local lists = ns.ZoneList()
  T.eq(#lists, 2, "Eastern Kingdoms and Kalimdor, and nothing after them")
  T.eq(lists[1].continent, "Eastern Kingdoms")
  local last = lists[1].zones[#lists[1].zones]
  T.eq(last.name, "Blackrock Mountain", "in with the rest, at the end because it is the highest")

  local page = ns.SelectScreen("zones")
  page.rail[12]:Click()   -- levels 56-60
  local names = {}
  for i = 1, page.shownRows do table.insert(names, page.rows[i].name:GetText()) end
  T.truthy(table.concat(names, " | "):find("Blackrock Mountain", 1, true), table.concat(names, " | "))
  ns.HideWindow()
end)

T.run("a zone the client never mapped is still listed, it simply does nothing", function()
  world(false)
  table.insert(ns.Zones, { zone = 25, name = "Blackrock Mountain", continent = "Eastern Kingdoms",
                           level = { 60, 60 }, quests = 15, faction = false, source = "quests" })
  local page = ns.SelectScreen("zones")
  page.rail[12]:Click()
  local row
  for i = 1, page.shownRows do
    if type(page.rows[i].zone) == "table" and page.rows[i].zone.name == "Blackrock Mountain" then row = page.rows[i] end
  end
  T.truthy(row, "it is on the list")
  T.eq(row.zone.mapID, nil, "the client's map tree never offered one")
  ns.HideWindow()
end)

T.run("lighting a zone up stays shelved, and asking for it does nothing at all", function()
  world(false)
  T.eq(ns.UpdateZoneHighlight(), nil)
  T.eq(ns.HighlightZone(1415, 1429), nil)
  T.eq(_G.ForeverBuddyZoneHighlight, nil, "no frame is even made while it is off")
end)

T.run("the band cards fit the window without a scrollbar of their own", function()
  world(false)
  local m = ns.RAIL_METRICS
  local bands = #ns.LevelBands("Horde")
  -- The window is 620 tall; a page starts 30 below its top and stops 10 above its bottom.
  local pageHeight = 620 - 30 - 10
  local room = pageHeight + m.top - 8          -- m.top is negative: the panel starts below the advice
  local needed = m.pad + bands * (m.height + m.gap) - m.gap
  T.truthy(needed <= room, ("%d cards need %dpx and the panel has %dpx"):format(bands, needed, room))
end)

T.finish()
