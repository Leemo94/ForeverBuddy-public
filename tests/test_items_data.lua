package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")
local ns = Stub.LoadAddon({ "Data/Items.lua", "Core.lua" })

T.run("items file loads with thousands of Classic items", function()
  T.eq(ns.ItemsInfo.game, "classic")
  local n = 0
  for _ in pairs(ns.Items) do n = n + 1 end
  T.eq(n, ns.ItemsInfo.items); T.truthy(n > 7000, "item count " .. n)
  T.eq(ns.ItemTypes[13], "Weapon"); T.eq(ns.ArmorTypes[4], "Plate")
end)

T.run("Thunderfury and Painweaver Band match WoWSims", function()
  local tf = ns.Items[19019]
  T.eq(tf[1], "Thunderfury, Blessed Blade of the Windseeker"); T.eq(tf[2], 5); T.eq(tf[3], 80); T.eq(tf[4], 13)
  T.eq(tf[11][3], 1.9); T.eq(tf[10].Agility, 5); T.eq(tf[16][1][1], "quest")
  local ring = ns.Items[13098]
  T.eq(ring[10].AttackPower, 16); T.eq(ring[12], true); T.eq(ring[16][1][2], 10363)
  T.eq(ns.ItemNpcs[10363], "General Drakkisath"); T.eq(ns.ItemZones[1583], "Blackrock Spire")
end)

T.finish()
