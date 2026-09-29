package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")

local FILES = { "Core.lua", "Nav/CityPins.lua" }
local ns = Stub.LoadAddon(FILES)

local function world()
  Stub.reset()
  ns.db = { features = {}, pins = {} }
  ns.Cities = {
    { key = "orgrimmar", name = "Orgrimmar", zone = 1637, map = 1454, faction = "Horde", points = {
      { id = 3352, kind = "class", name = "Ormak Grimshot", sub = "Hunter Trainer", tag = "Hunter", x = 66.0, y = 18.5 },
      { id = 3009, kind = "profession", name = "Yelmak", sub = "Expert Alchemist", tag = "Alchemy", x = 55.8, y = 47.2 },
      { id = 4550, kind = "bank", name = "Kaymard Copperpinch", sub = "Banker", tag = "Bank", x = 50.4, y = 62.1 },
      { id = 8719, kind = "auction", name = "Auctioneer Thathung", sub = "", tag = "Auction house", x = 53.1, y = 74.5 },
      { id = 3310, kind = "flight", name = "Doras", sub = "Wind Rider Master", tag = "Wind Rider Master", x = 45.1, y = 63.9 },
      { id = 3703, kind = "weapon", name = "Sayoc", sub = "Weapon Master", tag = "Weapon master", x = 78.4, y = 31.2 },
    } },
  }
  ns.Observed = { npcs = { [3352] = { name = "Ormak Grimshot", x = 71.4, y = 20.2 } } }
  WorldMapFrame.mapID = 1454
  WorldMapFrame:Show()
end

T.run("the feature is registered and on by default", function()
  world()
  T.eq(ns.featureIndex.citypins.name, "City trainers on the map")
  T.eq(ns.IsFeatureEnabled("citypins"), true)
  T.eq(#ns.PIN_KINDS, 6, "one switch per kind")
  T.eq(ns.pinIndex.weapon.name, "Weapon masters")
end)

T.run("every kind is on until someone turns it off, and the choice is remembered", function()
  world()
  for _, def in ipairs(ns.PIN_KINDS) do T.eq(ns.PinEnabled(def.key), true, def.key) end
  T.eq(ns.SetPinEnabled("bank", false), true)
  T.eq(ns.PinEnabled("bank"), false)
  T.truthy(ns.SettingsString():find("p=bank:0", 1, true), ns.SettingsString())
  ns.db.pins = {}
  T.eq(ns.PinEnabled("bank"), true, "cleared again")
  T.eq(ns.SetPinEnabled("nonsense", false), false)
end)

T.run("a city map gets a pin for every point a switch is showing", function()
  world()
  T.eq(ns.CityForMap(1454).name, "Orgrimmar")
  T.eq(ns.CityForMap(1458), nil, "no data for Undercity here")
  T.eq(ns.UpdateCityPins(), 6)
  T.eq(_G.ForeverBuddyCityPins:IsShown(), true)
  T.eq(_G.ForeverBuddyCityPins.title:GetText(), "Orgrimmar")
  ns.SetPinEnabled("class", false)
  ns.SetPinEnabled("profession", false)
  T.eq(ns.UpdateCityPins(), 4, "the two trainer kinds are off")
  T.eq(#ns.CityPoints(ns.Cities[1]), 4)
end)

T.run("nothing is drawn away from a city, or with the feature off", function()
  world()
  WorldMapFrame:SetMapID(1415)
  T.eq(ns.UpdateCityPins(), nil, "Eastern Kingdoms is not a city")
  WorldMapFrame:SetMapID(1454)
  T.eq(ns.UpdateCityPins(), 6)
  ns.SetFeatureEnabled("citypins", false)
  T.eq(ns.UpdateCityPins(), nil)
  ns.SetFeatureEnabled("citypins", true)
  WorldMapFrame:Hide()
  T.eq(ns.UpdateCityPins(), nil, "and not while the map is closed")
end)

T.run("a class trainer wears its class icon and a profession its trade icon", function()
  world()
  _G.CLASS_ICON_TCOORDS = { HUNTER = { 0, 0.25, 0.25, 0.5 }, MAGE = { 0.25, 0.49, 0, 0.25 } }
  local texture, coords = ns.PinArt("class", "Hunter")
  T.truthy(texture:find("CharacterCreate-Classes", 1, true), texture)
  T.eq(coords[1], 0); T.eq(coords[2], 0.25)
  texture, coords = ns.PinArt("profession", "Alchemy")
  T.eq(texture, "Interface\\Icons\\Trade_Alchemy"); T.eq(coords, nil)
  texture = ns.PinArt("bank", "Bank")
  T.eq(texture, ns.pinIndex.bank.icon, "a bank keeps the tracking icon")
  _G.CLASS_ICON_TCOORDS = nil
  texture, coords = ns.PinArt("class", "Hunter")
  T.eq(texture, ns.pinIndex.class.icon, "and falls back when the client has no class art")
end)

T.run("each class and profession is its own tick, on until turned off", function()
  world()
  local classes = ns.CityTags(ns.Cities[1], "class")
  T.eq(#classes, 1); T.eq(classes[1], "Hunter")
  T.eq(ns.TagEnabled("Hunter"), true)
  T.eq(ns.UpdateCityPins(), 6)
  ns.SetTagEnabled("Hunter", false)
  T.eq(ns.UpdateCityPins(), 5, "the hunter trainer steps out")
  T.truthy(ns.SettingsString():find("t=Hunter", 1, true), ns.SettingsString())
  ns.SetTagEnabled("Hunter", true)
  T.eq(ns.UpdateCityPins(), 6)
end)

T.run("the switch list opens a class out into its own list, with All and None", function()
  world()
  ns.UpdateCityPins()
  local panel = _G.ForeverBuddyCityPins
  T.eq(panel.shownRows, 6, "one row per kind while everything is closed")
  panel.rows[1].expand:Click()
  T.eq(panel.shownRows, 8, "the class row, an All and None row, and the one class")
  T.eq(panel.rows[2].all:GetText(), "All")
  T.eq(panel.rows[3].label:GetText(), "Hunter")
  panel.rows[2].none:Click()
  T.eq(ns.TagEnabled("Hunter"), false, "None clears every class in this city")
  panel.rows[2].all:Click()
  T.eq(ns.TagEnabled("Hunter"), true)
  panel.rows[1].expand:Click()
  T.eq(panel.shownRows, 6, "and folds away again")
end)

T.run("a trainer our own records found joins the map, even where Classic never had one", function()
  world()
  -- Forever moved the hunter trainer out of Ironforge and into Stormwind's Dwarven District.
  ns.Cities[1].map = 1453
  WorldMapFrame:SetMapID(1453)
  ns.Observed = {
    npcs = { [5515] = { name = "Einris Brightspear", zone = "Stormwind City", map = 1453, x = 67.4, y = 36.4 },
             [3352] = { name = "Ormak Grimshot", map = 1453, x = 66.0, y = 18.5 } },
    trainers = { [5515] = { name = "Einris Brightspear", class = "HUNTER", services = {} },
                 [3352] = { name = "Ormak Grimshot", class = "HUNTER", services = {} } },
  }
  local found = ns.RecordedTrainers(1453)
  T.eq(#found, 2)
  local einris
  for _, point in ipairs(found) do
    if point.id == 5515 then einris = point end
  end
  T.truthy(einris, "the hunter trainer is not there")
  T.eq(einris.kind, "class"); T.eq(einris.tag, "Hunter"); T.eq(einris.x, 67.4)
  local points = ns.CityPoints(ns.Cities[1])
  local ids = {}
  for _, point in ipairs(points) do ids[point.id] = (ids[point.id] or 0) + 1 end
  T.eq(ids[5515], 1, "the new one is drawn")
  T.eq(ids[3352], 1, "and the one the city data already had is not drawn twice")
  ns.Observed = nil
end)

T.finish()
