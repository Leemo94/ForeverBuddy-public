package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")
local ns = Stub.LoadAddon({ "Core.lua", "UsedFor/QuestStatus.lua" })

T.run("parses item objective text", function()
  local name, have, need = ns.ParseItemObjective("Chunk of Boar Meat: 3/8")
  T.eq(name, "Chunk of Boar Meat"); T.eq(have, 3); T.eq(need, 8)
  name, have, need = ns.ParseItemObjective("Bloodpetal Sprout:0/12")
  T.eq(name, "Bloodpetal Sprout"); T.eq(have, 0); T.eq(need, 12)
end)

T.run("Mainline objective text (count first) parses too", function()
  local name, have, need = ns.ParseItemObjective("3/8 Chunk of Boar Meat")
  T.eq(name, "Chunk of Boar Meat"); T.eq(have, 3); T.eq(need, 8)
  name, have, need = ns.ParseItemObjective("  0/12 Bloodpetal Sprout ")
  T.eq(name, "Bloodpetal Sprout"); T.eq(have, 0); T.eq(need, 12)
  T.eq(ns.ParseItemObjective("3/8"), nil)
end)

T.run("parser is type-agnostic; the index filters by objective type", function()
  T.eq(ns.ParseItemObjective("Defias Thug slain: 3/8"), "Defias Thug slain")
  T.eq(ns.ParseItemObjective("Speak with Marshal Dughan"), nil)
  T.eq(ns.ParseItemObjective(nil), nil)
  T.eq(ns.ParseItemObjective(": 1/2"), nil)
end)

T.run("index skips headers and non-item objectives, keys case-insensitively", function()
  Stub.reset()
  Stub.questLog = {
    { title = "Elwynn Forest", isHeader = true, questID = 0 },
    { title = "Pie for Billy", questID = 86 },
    { title = "Wolves Across the Border", questID = 40 },
  }
  Stub.objectives[86] = {
    { text = "Chunk of Boar Meat: 3/8", type = "item" },
    { text = "Young Goretusk slain: 0/8", type = "monster" },
  }
  Stub.objectives[40] = { { text = "Chunk of Boar Meat: 1/1", type = "item" } }
  Stub.objectives[0] = { { text = "Header Junk: 1/1", type = "item" } }
  ns.RebuildLiveIndex()
  T.eq(ns.LiveMatches("Header Junk"), nil, "headers are skipped even though the client gives them questID 0")
  local m = ns.LiveMatches("chunk OF boar meat")
  T.eq(#m, 2)
  T.eq(m[1].questID, 86); T.eq(m[1].title, "Pie for Billy"); T.eq(m[1].have, 3); T.eq(m[1].need, 8)
  T.eq(m[2].questID, 40)
  T.eq(ns.LiveMatches("Young Goretusk slain"), nil)
  T.eq(ns.LiveMatches(nil), nil)
end)

T.run("rebuild replaces the previous index", function()
  Stub.reset()
  Stub.questLog = { { title = "Pie for Billy", questID = 86 } }
  Stub.objectives[86] = { { text = "Chunk of Boar Meat: 3/8", type = "item" } }
  ns.RebuildLiveIndex()
  Stub.questLog = {}
  ns.RebuildLiveIndex()
  T.eq(ns.LiveMatches("Chunk of Boar Meat"), nil)
end)

T.run("quest log events coalesce into one timed rebuild", function()
  Stub.reset()
  Stub.questLog = { { title = "Pie for Billy", questID = 86 } }
  Stub.objectives[86] = { { text = "Chunk of Boar Meat: 3/8", type = "item" } }
  Stub.FireEvent("QUEST_LOG_UPDATE")
  Stub.FireEvent("QUEST_LOG_UPDATE")
  Stub.FireEvent("PLAYER_ENTERING_WORLD")
  T.eq(#Stub.timers, 1)
  T.eq(Stub.timers[1].delay, 0.5)
  Stub.RunTimers()
  T.eq(ns.LiveMatches("Chunk of Boar Meat")[1].have, 3)
  Stub.FireEvent("QUEST_LOG_UPDATE")
  T.eq(#Stub.timers, 1, "schedules again after the pending rebuild ran")
end)

T.run("tolerates stray whitespace and rejects uncached placeholder text", function()
  local name, have, need = ns.ParseItemObjective("  Chunk of Boar Meat : 1/2")
  T.eq(name, "Chunk of Boar Meat"); T.eq(have, 1); T.eq(need, 2)
  T.eq(ns.ParseItemObjective(" : 3/8"), nil)
end)

T.run("index tolerates missing, empty, and textless objectives", function()
  Stub.reset()
  Stub.questLog = {
    { title = "No Data Yet", questID = 1 },
    { title = "Empty", questID = 2 },
    { title = "Textless", questID = 3 },
    { title = "Pie for Billy", questID = 86 },
  }
  Stub.objectives[2] = {}
  Stub.objectives[3] = { { type = "item" } }
  Stub.objectives[86] = { { text = "Chunk of Boar Meat: 3/8", type = "item" } }
  ns.RebuildLiveIndex()
  T.eq(#ns.LiveMatches("Chunk of Boar Meat"), 1)
  T.eq(ns.LiveMatches("No Data Yet"), nil)
end)

T.run("Mainline (Forever) quest log API builds the same index", function()
  Stub.reset(); Stub.mainlineQuestLog = true
  Stub.questLog = {
    { title = "Elwynn Forest", isHeader = true, questID = 0 },
    { title = "Pie for Billy", questID = 86 },
  }
  Stub.objectives[86] = { { text = "Chunk of Boar Meat: 3/8", type = "item" } }
  ns.RebuildLiveIndex()
  local m = ns.LiveMatches("Chunk of Boar Meat")
  T.eq(#m, 1); T.eq(m[1].questID, 86); T.eq(m[1].have, 3)
  Stub.mainlineQuestLog = false
end)

T.finish()
