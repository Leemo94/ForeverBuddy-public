local ADDON, ns = ...

-- cmangos class bits, matching the classMask baked by tools/build_data.py
ns.CLASS_BITS = {
  WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16,
  SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024,
}

-- entry = { questID, name, kind, repeatable, faction, classMask }
function ns.IsQuestEligible(entry)
  local faction = entry[5]
  if faction == "A" or faction == "H" then
    local mine = UnitFactionGroup("player")
    if faction == "A" and mine ~= "Alliance" then return false end
    if faction == "H" and mine ~= "Horde" then return false end
  end
  local mask = entry[6] or 0
  if mask ~= 0 then
    local _, token = UnitClass("player")
    local classBit = ns.CLASS_BITS[token]
    if classBit and bit.band(mask, classBit) == 0 then return false end
  end
  return true
end

-- Live quest-log index: [lowercase item name] = { { questID, title, have, need }, ... }
local liveIndex = {}
local rebuildPending = false

-- Classic writes "Chunk of Boar Meat: 3/8", Mainline (Forever) writes "3/8 Chunk of Boar Meat".
-- Returns name, have, need; tolerates stray whitespace.
function ns.ParseItemObjective(text)
  if type(text) ~= "string" then return nil end
  local name, have, need = text:match("^%s*(.-)%s*:%s*(%d+)/(%d+)%s*$")
  if not name then
    have, need, name = text:match("^%s*(%d+)/(%d+)%s+(.-)%s*$")
  end
  if not name or name == "" then return nil end
  return name, tonumber(have), tonumber(need)
end

-- Item objectives of one quest as { name=, have=, need= }; the client's counts win over the parsed text.
local function ItemObjectives(questID)
  local out = {}
  for _, o in ipairs(C_QuestLog.GetQuestObjectives(questID) or {}) do
    if o.type == "item" then
      local name, have, need = ns.ParseItemObjective(o.text)
      if name then
        table.insert(out, { name = name, have = o.numFulfilled or have, need = o.numRequired or need })
      end
    end
  end
  return out
end

-- One row of the quest log: title, isHeader, questID. Mainline (Forever) has C_QuestLog.GetInfo; Classic has GetQuestLogTitle.
local function QuestLogEntry(i)
  if C_QuestLog.GetInfo then
    local info = C_QuestLog.GetInfo(i)
    if info then return info.title, info.isHeader, info.questID, info.level end
    if not GetQuestLogTitle then return nil end
  end
  local title, level, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
  return title, isHeader, questID, level
end

local function NumQuestLogEntries()
  if C_QuestLog.GetNumQuestLogEntries then
    local n = C_QuestLog.GetNumQuestLogEntries()
    if n then return n end
  end
  return GetNumQuestLogEntries()
end
ns.QuestLogEntry, ns.NumQuestLogEntries = QuestLogEntry, NumQuestLogEntries

function ns.RebuildLiveIndex()
  rebuildPending = false
  liveIndex = {}
  for i = 1, NumQuestLogEntries() do
    local title, isHeader, questID = QuestLogEntry(i)
    if title and not isHeader and questID and questID ~= 0 then
      for _, o in ipairs(ItemObjectives(questID)) do
        local key = o.name:lower()
        liveIndex[key] = liveIndex[key] or {}
        table.insert(liveIndex[key], { questID = questID, title = title, have = o.have, need = o.need })
      end
    end
  end
  return liveIndex
end

function ns.ScheduleLiveRebuild()
  if rebuildPending then return end
  rebuildPending = true
  C_Timer.After(0.5, ns.RebuildLiveIndex)
end

function ns.LiveMatches(itemName)
  if type(itemName) ~= "string" then return nil end
  return liveIndex[itemName:lower()]
end

local liveFrame = CreateFrame("Frame")
liveFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
liveFrame:RegisterEvent("QUEST_LOG_UPDATE")
liveFrame:SetScript("OnEvent", ns.ScheduleLiveRebuild)

-- Returns "active"|"repeatable"|"done"|"available", plus have, need when active and known.
-- Repeatable is checked before the completed flag: a farmed turn-in must never read as "done".
function ns.GetQuestStatus(questID, repeatable, itemName)
  if C_QuestLog.IsOnQuest(questID) then
    for _, m in ipairs(ns.LiveMatches(itemName) or {}) do
      if m.questID == questID then return "active", m.have, m.need end
    end
    -- Not in the live index (its header is collapsed, or the index is stale): ask the client directly.
    if type(itemName) == "string" then
      local wanted = itemName:lower()
      for _, o in ipairs(ItemObjectives(questID)) do
        if o.name:lower() == wanted then return "active", o.have, o.need end
      end
    end
    return "active"
  end
  if repeatable then return "repeatable" end
  if C_QuestLog.IsQuestFlaggedCompleted(questID) then return "done" end
  return "available"
end

ns.STATUS_ORDER = { active = 1, available = 2, repeatable = 3, done = 4 }

-- Returns a sorted array of { questID, name, status, have, need, rep } for one item:
-- eligible quests from the shipped data, then quests found only in the live index.
function ns.CollectQuests(itemID, itemName)
  local out, seen = {}, {}
  for _, entry in ipairs(ns.Quests[itemID] or {}) do
    -- The client's own log beats shipped faction/class data (Forever loosens race/class locks).
    if ns.IsQuestEligible(entry) or C_QuestLog.IsOnQuest(entry[1]) then
      local status, have, need = ns.GetQuestStatus(entry[1], entry[4], itemName)
      table.insert(out, { questID = entry[1], name = entry[2], status = status, have = have, need = need, rep = entry[7] or nil })
      seen[entry[1]] = true
    end
  end
  for _, m in ipairs(ns.LiveMatches(itemName) or {}) do
    if not seen[m.questID] then
      table.insert(out, { questID = m.questID, name = m.title, status = "active", have = m.have, need = m.need })
      seen[m.questID] = true
    end
  end
  table.sort(out, function(a, b)
    local oa, ob = ns.STATUS_ORDER[a.status] or 99, ns.STATUS_ORDER[b.status] or 99
    if oa ~= ob then return oa < ob end
    return a.name < b.name
  end)
  return out
end
