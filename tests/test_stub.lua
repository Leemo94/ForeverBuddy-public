package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")

T.run("events reach registered frames only, and stop after unregister", function()
  local hits = 0
  local f = CreateFrame("Frame")
  f:RegisterEvent("QUEST_LOG_UPDATE")
  f:SetScript("OnEvent", function() hits = hits + 1 end)
  Stub.FireEvent("QUEST_LOG_UPDATE")
  Stub.FireEvent("PLAYER_LOGIN")
  T.eq(hits, 1, "only registered events are delivered")
  f:UnregisterEvent("QUEST_LOG_UPDATE")
  Stub.FireEvent("QUEST_LOG_UPDATE")
  T.eq(hits, 1, "unregistered events stop arriving")
end)

T.run("tooltip records coloured lines and fallback name", function()
  Stub.reset()
  GameTooltip:AddLine("hello", 1, 0.5, 0)
  T.eq(GameTooltip.lines[1].text, "hello")
  T.eq(GameTooltip.lines[1].g, 0.5)
  T.eq(GameTooltipTextLeft1:GetText(), "Fallback Name")
end)

T.run("timers run once and clear", function()
  Stub.reset()
  local n = 0
  C_Timer.After(0.5, function() n = n + 1 end)
  Stub.RunTimers(); Stub.RunTimers()
  T.eq(n, 1)
end)

T.run("LoadAddon passes addon name and namespace; GetQuestLogTitle positions", function()
  local path = os.tmpname()
  local fh = assert(io.open(path, "w"))
  fh:write("local ADDON, ns = ...\nns.loadedAs = ADDON\n")
  fh:close()
  local ns = Stub.LoadAddon({ path })
  os.remove(path)
  T.eq(ns.loadedAs, "ForeverBuddy")
  Stub.reset()
  Stub.questLog = { { title = "Elwynn", isHeader = true }, { title = "Pie for Billy", questID = 86 } }
  if Stub.mainline then
    T.eq(C_QuestLog.GetInfo(2).questID, 86); T.eq(C_QuestLog.GetInfo(1).isHeader, true)
  else
    local title, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(2)
    T.eq(title, "Pie for Billy"); T.eq(isHeader, false); T.eq(questID, 86)
    T.eq(select(4, GetQuestLogTitle(1)), true)
  end
end)

T.finish()
