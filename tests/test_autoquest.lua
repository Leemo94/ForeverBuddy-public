package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")
local ns = Stub.LoadAddon({ "Core.lua", "Automation/AutoQuest.lua" })

local function on() Stub.reset(); ns.db = { features = { autoquest = true } } end

T.run("registers the autoquest feature, off by default", function()
  T.eq(ns.featureIndex.autoquest.name, "Automate quests")
  T.eq(ns.IsFeatureEnabled("autoquest"), false)
end)

T.run("off by default: events do nothing", function()
  Stub.reset(); ns.db = nil
  Stub.FireEvent("QUEST_DETAIL")
  T.eq(#Stub.calls, 0)
end)

T.run("accepts on QUEST_DETAIL", function()
  on()
  Stub.FireEvent("QUEST_DETAIL")
  T.eq(Stub.CallNames()[1], "AcceptQuest")
end)

T.run("Shift bypasses every handler", function()
  on(); Stub.shift = true
  Stub.questCompletable = true
  for _, event in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_GREETING", "GOSSIP_SHOW" }) do
    T.eq(ns.AutoQuest(event), nil, event)
  end
  T.eq(#Stub.calls, 0)
end)

T.run("completes on QUEST_PROGRESS only when completable and free", function()
  on(); Stub.questCompletable = true
  T.eq(ns.AutoQuest("QUEST_PROGRESS"), "completed")
  T.eq(Stub.CallNames()[1], "CompleteQuest")
  on(); Stub.questCompletable = false
  T.eq(ns.AutoQuest("QUEST_PROGRESS"), nil)
  on(); Stub.questCompletable = true; Stub.questMoneyToGet = 500
  T.eq(ns.AutoQuest("QUEST_PROGRESS"), nil, "quests that cost money are left alone")
  T.eq(#Stub.calls, 0)
end)

T.run("takes the reward only when there is no real choice", function()
  on(); Stub.questChoices = 0
  T.eq(ns.AutoQuest("QUEST_COMPLETE"), "rewarded")
  T.eq(Stub.calls[1][1], "GetQuestReward"); T.eq(Stub.calls[1][2], 0)
  on(); Stub.questChoices = 1
  T.eq(ns.AutoQuest("QUEST_COMPLETE"), "rewarded")
  T.eq(Stub.calls[1][2], 1)
  on(); Stub.questChoices = 3
  T.eq(ns.AutoQuest("QUEST_COMPLETE"), nil)
  T.eq(#Stub.calls, 0)
end)

T.run("greeting: completable active quest first, else first available", function()
  on()
  Stub.greetingActive = { { title = "Not Yet" }, { title = "Ready", isComplete = true } }
  Stub.greetingAvailable = { { title = "New One" } }
  T.eq(ns.AutoQuest("QUEST_GREETING"), "selected active")
  T.eq(Stub.calls[1][1], "SelectActiveQuest"); T.eq(Stub.calls[1][2], 2)
  on()
  Stub.greetingActive = { { title = "Not Yet" } }
  Stub.greetingAvailable = { { title = "New One" }, { title = "Another" } }
  T.eq(ns.AutoQuest("QUEST_GREETING"), "selected available")
  T.eq(Stub.calls[1][1], "SelectAvailableQuest"); T.eq(Stub.calls[1][2], 1)
  on()
  T.eq(ns.AutoQuest("QUEST_GREETING"), nil)
end)

T.run("gossip: completable active quest first, else first available, never gossip options", function()
  on()
  Stub.gossipActive = { { questID = 10, title = "Not Yet" }, { questID = 11, title = "Ready", isComplete = true } }
  Stub.gossipAvailable = { { questID = 12, title = "New One" } }
  T.eq(ns.AutoQuest("GOSSIP_SHOW"), "selected active")
  T.eq(Stub.calls[1][1], "C_GossipInfo.SelectActiveQuest"); T.eq(Stub.calls[1][2], 11)
  on()
  Stub.gossipAvailable = { { questID = 12, title = "New One" } }
  T.eq(ns.AutoQuest("GOSSIP_SHOW"), "selected available")
  T.eq(Stub.calls[1][1], "C_GossipInfo.SelectAvailableQuest"); T.eq(Stub.calls[1][2], 12)
  on()
  T.eq(ns.AutoQuest("GOSSIP_SHOW"), nil)
  T.eq(#Stub.calls, 0)
end)

T.finish()
