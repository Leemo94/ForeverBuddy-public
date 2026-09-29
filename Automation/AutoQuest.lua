local ADDON, ns = ...

ns.RegisterFeature({
  key = "autoquest",
  name = "Automate quests",
  desc = "Accepts quests and hands them in for you. Hold Shift to do it by hand. Rewards you must choose between are always left to you.",
  default = false,
})

-- Each handler returns what it did (for tests) or nil.
local handlers = {}

function handlers.QUEST_DETAIL()
  AcceptQuest()
  return "accepted"
end

function handlers.QUEST_PROGRESS()
  if IsQuestCompletable() and GetQuestMoneyToGet() == 0 then
    CompleteQuest()
    return "completed"
  end
end

function handlers.QUEST_COMPLETE()
  local choices = GetNumQuestChoices()
  if choices <= 1 then
    GetQuestReward(choices)
    return "rewarded"
  end
end

function handlers.QUEST_GREETING()
  for i = 1, GetNumActiveQuests() do
    local _, isComplete = GetActiveTitle(i)
    if isComplete then
      SelectActiveQuest(i)
      return "selected active"
    end
  end
  if GetNumAvailableQuests() > 0 then
    SelectAvailableQuest(1)
    return "selected available"
  end
end

function handlers.GOSSIP_SHOW()
  for _, quest in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
    if quest.isComplete then
      C_GossipInfo.SelectActiveQuest(quest.questID)
      return "selected active"
    end
  end
  local available = C_GossipInfo.GetAvailableQuests() or {}
  if available[1] then
    C_GossipInfo.SelectAvailableQuest(available[1].questID)
    return "selected available"
  end
end

ns.AutoQuestHandlers = handlers

function ns.AutoQuest(event)
  if not ns.IsFeatureEnabled("autoquest") or IsShiftKeyDown() then return nil end
  local handler = handlers[event]
  return handler and handler() or nil
end

local frame = CreateFrame("Frame")
for event in pairs(handlers) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent", function(_, event) ns.AutoQuest(event) end)
