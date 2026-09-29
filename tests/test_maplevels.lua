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
    { zone = 12, name = "Elwynn Forest", continent = "Eastern Kingdoms", level = { 5, 10 }, quests = 46, faction = "Alliance", source = "quests" },
    { zone = 40, name = "Westfall", continent = "Eastern Kingdoms", level = { 10, 18 }, quests = 34, faction = "Alliance", source = "quests" },
    { zone = 0, name = "Riverglades", continent = "Eastern Kingdoms", level = { 33, 45 }, quests = 0, faction = false, source = "reported" },
    { zone = 14, name = "Durotar", continent = "Kalimdor", level = { 4, 12 }, quests = 40, faction = "Horde", source = "quests" },
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

T.run("the zones screen lists every zone by level, per continent", function()
  world(false)
  local page = ns.SelectScreen("zones")
  T.eq(page.shownZones, 4, "three on the map, plus Durotar from our own list")
  T.eq(page.columns[1].title:GetText(), "Eastern Kingdoms")
  T.eq(page.columns[1].rows[1]:GetText(), "5-10  Elwynn Forest")
  T.eq(page.columns[1].rows[3]:GetText(), "33-45  Riverglades")
  T.truthy(page.subheading:GetText():find("You are level 12", 1, true))
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

T.run("a zone the client's map tree never lists joins its continent, not a column of its own", function()
  world(false)
  table.insert(ns.Zones, { zone = 25, name = "Blackrock Mountain", continent = "Eastern Kingdoms",
                           level = { 60, 60 }, quests = 15, faction = false, source = "quests" })
  local lists = ns.ZoneList()
  T.eq(#lists, 2, "Eastern Kingdoms and Kalimdor, and nothing after them")
  T.eq(lists[1].continent, "Eastern Kingdoms")
  local last = lists[1].zones[#lists[1].zones]
  T.eq(last.name, "Blackrock Mountain", "in with the rest, at the end because it is the highest")
  local page = ns.SelectScreen("zones")
  T.eq(#page.columns, 2)
  T.eq(page.columns[1].rows[4]:GetText(), "60  Blackrock Mountain")
  ns.HideWindow()
end)

T.run("clicking a zone opens the map on its continent", function()
  world(false)
  local page = ns.SelectScreen("zones")
  local row = page.columns[1].rows[1]
  T.eq(row.zone.name, "Elwynn Forest"); T.eq(row.zone.parent, 1415)
  WorldMapFrame:Hide()
  row:Click()
  T.eq(WorldMapFrame:IsShown(), true)
  T.eq(WorldMapFrame:GetMapID(), 1415, "the continent, so the zone can be seen in place")
  T.eq(_G.ForeverBuddyFrame:IsShown(), false, "our window steps out of the way")
  T.truthy(printed[#printed]:find("Elwynn Forest, level 5-10", 1, true), printed[#printed])
  -- Lighting the zone up is shelved: the client's highlight art paints a grey sheet over the
  -- whole map. Nothing is drawn, and nothing errors when it is asked for.
  T.eq(ns.UpdateZoneHighlight(), nil)
  T.eq(ns.HighlightZone(1415, 1429), nil)
  T.eq(_G.ForeverBuddyZoneHighlight, nil, "no frame is even made while it is off")
end)

T.run("a zone with no map of its own says so instead of opening nothing", function()
  world(false)
  table.insert(ns.Zones, { zone = 25, name = "Blackrock Mountain", continent = "Eastern Kingdoms",
                           level = { 60, 60 }, quests = 15, faction = false, source = "quests" })
  local page = ns.SelectScreen("zones")
  local row = page.columns[1].rows[4]
  T.eq(row.zone.name, "Blackrock Mountain")
  T.eq(row.zone.mapID, nil, "the client's map tree never offered one")
  printed = {}
  row:Click()
  T.eq(printed[1], "no map for Blackrock Mountain")
  ns.HideWindow()
end)

T.finish()
