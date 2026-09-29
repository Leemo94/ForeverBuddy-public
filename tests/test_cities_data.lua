package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")
local ns = Stub.LoadAddon({ "Data/Cities.lua", "Core.lua" })

local KINDS = { class = true, profession = true, weapon = true, flight = true, bank = true, auction = true }

T.run("all six capitals are there, each with a map of its own", function()
  T.eq(ns.CityInfo.cities, 6)
  T.eq(#ns.Cities, 6)
  local seen = {}
  for _, city in ipairs(ns.Cities) do
    T.truthy(city.map > 0, city.name .. " has no map id")
    T.eq(seen[city.map], nil, "two cities sharing a map")
    seen[city.map] = true
    T.truthy(city.faction == "Horde" or city.faction == "Alliance", city.name)
  end
end)

T.run("every point is a kind we have a switch for, and sits on the map", function()
  local counted, kinds = 0, {}
  for _, city in ipairs(ns.Cities) do
    for _, point in ipairs(city.points) do
      counted = counted + 1
      T.eq(KINDS[point.kind], true, ("%s: %s is not a kind"):format(city.name, tostring(point.kind)))
      kinds[point.kind] = (kinds[point.kind] or 0) + 1
      T.truthy(point.name and point.name ~= "", city.name .. " point with no name")
      T.truthy(point.x > 0 and point.x <= 100, ("%s: x %s"):format(point.name, tostring(point.x)))
      T.truthy(point.y > 0 and point.y <= 100, ("%s: y %s"):format(point.name, tostring(point.y)))
    end
  end
  T.eq(counted, ns.CityInfo.points)
  T.truthy(kinds.class >= 100, "class trainers across six cities: " .. tostring(kinds.class))
  T.truthy(kinds.profession >= 100, "profession trainers: " .. tostring(kinds.profession))
  T.truthy(kinds.bank >= 6 and kinds.auction >= 6, "a bank and an auction house in every city")
  T.truthy(kinds.weapon >= 6, "a weapon master in every capital: " .. tostring(kinds.weapon))
end)

T.run("each city holds the trainers you would walk to it for", function()
  local byKey = {}
  for _, city in ipairs(ns.Cities) do byKey[city.key] = city end
  local function tags(key, kind)
    local out = {}
    for _, point in ipairs(byKey[key].points) do
      if point.kind == kind and point.tag then out[point.tag] = true end
    end
    return out
  end
  local horde = tags("orgrimmar", "class")
  T.eq(horde.Shaman, true, "Orgrimmar trains shamans")
  T.eq(horde.Paladin, nil, "and no paladins")
  local alliance = tags("stormwind", "class")
  T.eq(alliance.Paladin, true, "Stormwind trains paladins")
  T.eq(alliance.Shaman, nil, "and no shamans")
  T.eq(tags("ironforge", "profession").Engineering, true, "Ironforge trains engineers")
end)

T.finish()
