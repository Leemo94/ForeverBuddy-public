package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")
local ns = Stub.LoadAddon({ "Data/Weights.lua", "Core.lua" })

local CLASSES = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true, SHAMAN = true, MAGE = true, WARLOCK = true, DRUID = true }

T.run("weights file loads with Classic specs", function()
  T.eq(ns.WeightsInfo.game, "classic")
  local n = 0
  for _ in pairs(ns.Weights) do n = n + 1 end
  T.eq(n, ns.WeightsInfo.specs)
  T.truthy(n >= 18, "spec count " .. n)
  T.eq(ns.Weights.WardenShaman, nil, "Warden Shaman is excluded for now")
end)

T.run("fury warrior weights match WoWSims", function()
  local w = ns.Weights.Warrior
  T.eq(w.class, "WARRIOR"); T.eq(w.name, "Warrior")
  T.eq(w.stats.Strength, 2.51); T.eq(w.stats.MeleeHit, 28.67); T.eq(w.stats.AttackPower, 1)
  T.eq(w.pseudo.MainHandDps, 11.92)
end)

T.run("every spec has a known class and numeric weights", function()
  for key, spec in pairs(ns.Weights) do
    T.truthy(CLASSES[spec.class], key .. " class " .. tostring(spec.class))
    T.truthy(next(spec.stats) ~= nil, key .. " has stats")
    for stat, value in pairs(spec.stats) do T.eq(type(value), "number", key .. "." .. stat) end
    for stat, value in pairs(spec.pseudo) do T.eq(type(value), "number", key .. "." .. stat) end
  end
end)

T.run("no spec is paid for resistance, and every spec says where it came from", function()
  for key, spec in pairs(ns.Weights) do
    for stat in pairs(spec.stats) do
      T.eq(stat:find("Resistance") == nil, true,
        ("%s carries %s, which WoWSims only weights for a raid resistance fight"):format(key, stat))
    end
    T.truthy(spec.source and spec.source:find("sim.ts", 1, true), key .. " has no source file")
  end
  T.truthy(ns.WeightsInfo.commit and ns.WeightsInfo.commit ~= "?", "the commit the weights were read at")
  T.eq(ns.WeightsInfo.repo, "wowsims/classic")
end)

T.finish()
