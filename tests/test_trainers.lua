package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")
local ns = Stub.LoadAddon({ "Core.lua", "Collect/Collector.lua", "Collect/Trainers.lua" })
local printed = {}
ns.Print = function(msg) table.insert(printed, msg) end

local function world()
  Stub.reset(); printed = {}
  ns.db = { features = { collect = true } }
  Stub.classToken = "PRIEST"
  Stub.level = 17
  Stub.units.npc = { guid = "Creature-0-1-1-1-3706-000012345", name = "Ur'kyo" }
  Stub.trainer = {
    -- what the window shows by default: the ones you are high enough for
    filters = { available = true, used = true },
    services = {
      { name = "Power Word: Fortitude", rank = "Rank 2", category = "available", level = 16, cost = 1200, spell = 1244 },
      { name = "Shadow Word: Pain", rank = "Rank 3", category = "used", level = 18, cost = 1800, spell = 594 },
      { name = "Mind Blast", rank = "Rank 4", category = "unavailable", level = 30, cost = 5000, spell = 8106 },
      { name = "Prayer of Healing", rank = "Rank 1", category = "unavailable", level = 40, cost = 20000, spell = 596 },
    },
  }
end

T.run("opening a trainer records every spell it teaches, high levels included", function()
  world()
  Stub.FireEvent("TRAINER_SHOW")
  local store = ns.CollectedStore()
  local trainer = store.trainers[3706]
  T.truthy(trainer, "nothing recorded")
  T.eq(trainer.name, "Ur'kyo")
  T.eq(trainer.class, "PRIEST")
  T.eq(trainer.race, "Scourge", "two trainers of one class differ by their race lines")
  T.eq(trainer.level, 17)
  T.eq(#trainer.services, 4, "the two you are too low for count most")
  local byName = {}
  for _, s in ipairs(trainer.services) do byName[s.name] = s end
  T.eq(byName["Mind Blast"].level, 30)
  T.eq(byName["Mind Blast"].category, "unavailable")
  T.eq(byName["Mind Blast"].spell, 8106, "the id comes from the tooltip")
  T.eq(byName["Power Word: Fortitude"].cost, 1200)
  T.eq(byName["Power Word: Fortitude"].rank, "Rank 2")
  T.truthy(printed[#printed]:find("recorded 4 spells from Ur'kyo", 1, true), printed[#printed])
end)

T.run("the window's own filters are put back the way they were", function()
  world()
  Stub.FireEvent("TRAINER_SHOW")
  T.eq(GetTrainerServiceTypeFilter("available"), true)
  T.eq(GetTrainerServiceTypeFilter("unavailable"), false, "left as the player had it")
  T.eq(GetTrainerServiceTypeFilter("used"), true)
end)

T.run("nothing is recorded with data recording turned off", function()
  world()
  ns.db.features.collect = false
  Stub.FireEvent("TRAINER_SHOW")
  T.eq(ns.CollectedStore().trainers, nil)
end)

T.run("/fb trainer lists what has been recorded", function()
  world()
  T.eq(ns.SlashHandlers.trainer(), 0)
  T.truthy(printed[#printed]:find("no trainer recorded yet", 1, true))
  Stub.FireEvent("TRAINER_SHOW")
  printed = {}
  T.eq(ns.SlashHandlers.trainer(), 1)
  T.truthy(printed[1]:find("Ur'kyo (PRIEST, level 17): 4 spells", 1, true), printed[1])
end)

T.finish()
