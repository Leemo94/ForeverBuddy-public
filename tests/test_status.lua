package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")
local ns = Stub.LoadAddon({ "Core.lua", "UsedFor/QuestStatus.lua" })

local BOAR = "Chunk of Boar Meat"

T.run("available when neither on quest nor completed", function()
  Stub.reset(); ns.RebuildLiveIndex()
  T.eq(ns.GetQuestStatus(86, false, BOAR), "available")
end)

T.run("done when flagged completed", function()
  Stub.reset(); ns.RebuildLiveIndex()
  Stub.completed[86] = true
  T.eq(ns.GetQuestStatus(86, false, BOAR), "done")
end)

T.run("repeatable when not completed and flagged repeatable", function()
  Stub.reset(); ns.RebuildLiveIndex()
  T.eq(ns.GetQuestStatus(9999, true, BOAR), "repeatable")
end)

T.run("repeatable beats completed: a farmed turn-in is never done", function()
  Stub.reset(); ns.RebuildLiveIndex()
  Stub.completed[9999] = true
  T.eq(ns.GetQuestStatus(9999, true, BOAR), "repeatable")
end)

T.run("active beats done and carries have/need from the live index", function()
  Stub.reset()
  Stub.completed[86] = true
  Stub.onQuest[86] = true
  Stub.questLog = { { title = "Pie for Billy", questID = 86 } }
  Stub.objectives[86] = { { text = "Chunk of Boar Meat: 3/8", type = "item" } }
  ns.RebuildLiveIndex()
  local status, have, need = ns.GetQuestStatus(86, false, BOAR)
  T.eq(status, "active"); T.eq(have, 3); T.eq(need, 8)
end)

T.run("active without have/need when objectives are not loaded", function()
  Stub.reset()
  Stub.onQuest[86] = true
  ns.RebuildLiveIndex()
  local status, have = ns.GetQuestStatus(86, false, BOAR)
  T.eq(status, "active"); T.eq(have, nil)
end)

T.run("active quest missing from the log list still gets have/need from the client", function()
  Stub.reset(); ns.RebuildLiveIndex()
  Stub.onQuest[86] = true
  Stub.objectives[86] = { { text = "Chunk of Boar Meat: 2/8", type = "item", numFulfilled = 2, numRequired = 8 } }
  local status, have, need = ns.GetQuestStatus(86, false, BOAR)
  T.eq(status, "active"); T.eq(have, 2); T.eq(need, 8)
end)

T.run("client counts are preferred over the objective text", function()
  Stub.reset()
  Stub.onQuest[86] = true
  Stub.questLog = { { title = "Pie for Billy", questID = 86 } }
  Stub.objectives[86] = { { text = "Chunk of Boar Meat: 3/8", type = "item", numFulfilled = 4, numRequired = 8 } }
  ns.RebuildLiveIndex()
  local _, have = ns.GetQuestStatus(86, false, BOAR)
  T.eq(have, 4)
end)

T.run("eligibility by faction", function()
  Stub.reset(); Stub.faction = "Horde"
  T.eq(ns.IsQuestEligible({ 86, "Pie for Billy", "objective", false, "A", 0 }), false)
  T.eq(ns.IsQuestEligible({ 1, "x", "objective", false, "H", 0 }), true)
  T.eq(ns.IsQuestEligible({ 1, "x", "objective", false, "B", 0 }), true)
  Stub.faction = "Alliance"
  T.eq(ns.IsQuestEligible({ 86, "Pie for Billy", "objective", false, "A", 0 }), true)
end)

T.run("eligibility by class mask, unknown classes pass", function()
  Stub.reset(); Stub.classToken = "PALADIN"
  T.eq(ns.IsQuestEligible({ 1, "x", "objective", false, "B", 2 }), true)
  T.eq(ns.IsQuestEligible({ 1, "x", "objective", false, "B", 1 }), false)
  T.eq(ns.IsQuestEligible({ 1, "x", "objective", false, "B", 1 + 2 }), true)
  T.eq(ns.IsQuestEligible({ 1, "x", "objective", false, "B", 0 }), true)
  Stub.classToken = "SKYWARDEN"
  T.eq(ns.IsQuestEligible({ 1, "x", "objective", false, "B", 1 }), true)
end)

T.run("CollectQuests orders by status then name and merges the live index", function()
  Stub.reset()
  ns.Quests[769] = {
    { 86,  "Pie for Billy",     "objective", false, "A", 0 },
    { 317, "Stocking Jetsteam", "objective", false, "A", 0 },
    { 500, "Done One",          "objective", false, "B", 0 },
    { 501, "Horde Only",        "objective", false, "H", 0 },
    { 502, "Weekly Farm",       "objective", true,  "B", 0 },
  }
  Stub.completed[500] = true
  Stub.onQuest[317] = true
  Stub.questLog = {
    { title = "Stocking Jetsteam (log)", questID = 317 },
    { title = "A New Forever Quest", questID = 70001 },
  }
  Stub.objectives[317]   = { { text = "Chunk of Boar Meat: 1/8", type = "item" } }
  Stub.objectives[70001] = { { text = "Chunk of Boar Meat: 0/4", type = "item" } }
  ns.RebuildLiveIndex()
  local list = ns.CollectQuests(769, BOAR)
  T.eq(#list, 5, "Horde-only quest dropped, live-only quest added, no duplicate for 317")
  T.eq(list[1].name, "A New Forever Quest"); T.eq(list[1].status, "active"); T.eq(list[1].need, 4)
  T.eq(list[2].name, "Stocking Jetsteam", "data name wins over the log title"); T.eq(list[2].status, "active"); T.eq(list[2].have, 1)
  T.eq(list[3].name, "Pie for Billy");       T.eq(list[3].status, "available")
  T.eq(list[4].name, "Weekly Farm");         T.eq(list[4].status, "repeatable")
  T.eq(list[5].name, "Done One");            T.eq(list[5].status, "done")
  T.eq(list[2].questID, 317)
  ns.Quests[769] = nil
end)

T.run("CollectQuests keeps an on-quest entry even when shipped faction data says ineligible", function()
  Stub.reset(); ns.RebuildLiveIndex()
  ns.Quests[770] = { { 600, "Loosened Lock", "objective", false, "H", 0 } }
  Stub.onQuest[600] = true
  local list = ns.CollectQuests(770, "Some Item")
  T.eq(#list, 1); T.eq(list[1].name, "Loosened Lock"); T.eq(list[1].status, "active")
  Stub.onQuest[600] = nil
  T.eq(#ns.CollectQuests(770, "Some Item"), 0)
  ns.Quests[770] = nil
end)

T.run("CollectQuests returns an empty list for unknown items", function()
  Stub.reset(); ns.RebuildLiveIndex()
  T.eq(#ns.CollectQuests(123456, "Nothing"), 0)
end)

T.finish()
