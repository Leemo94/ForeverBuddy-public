local ADDON, ns = ...

-- What a class trainer will teach, straight from the trainer window: every spell it offers,
-- the level it wants, what it costs, and whether you have it already. Nothing publishes this
-- for Forever, so one visit per class is how the list gets built.

local SCAN_NAME = "ForeverBuddyTrainerTooltip"
local scanTip

local function ScanTooltip()
  scanTip = scanTip or CreateFrame("GameTooltip", SCAN_NAME, UIParent, "GameTooltipTemplate")
  scanTip:SetOwner(UIParent, "ANCHOR_NONE")
  return scanTip
end

-- The spell behind a service row: the trainer API names it but does not number it, and the
-- tooltip does.
local function ServiceSpell(index)
  local tip = ScanTooltip()
  tip:ClearLines()
  if not pcall(tip.SetTrainerService, tip, index) then return nil end
  local ok, _, spellID = pcall(tip.GetSpell, tip)
  return (ok and spellID) or nil
end

local function Number(fn, index)
  if not fn then return nil end
  local ok, value = pcall(fn, index)
  return (ok and type(value) == "number") and value or nil
end

local function ReadService(index)
  local name, rank, category, expanded = nil, nil, nil, nil
  if GetTrainerServiceInfo then
    local ok, a, b, c, d = pcall(GetTrainerServiceInfo, index)
    if ok then name, rank, category, expanded = a, b, c, d end
  end
  if expanded ~= nil and name == nil then return nil end -- a header row, not a spell
  local level = Number(GetTrainerServiceLevelReq, index)
  local cost = Number(GetTrainerServiceCost, index)
  return {
    spell = ServiceSpell(index),
    name = ns.PublicValue and ns.PublicValue(name) or name,
    rank = ns.PublicValue and ns.PublicValue(rank) or rank,
    category = category,      -- available, unavailable (too low a level), or used (already known)
    level = level,
    cost = cost,
  }
end

-- Trainers hide the rows you cannot use yet, which are exactly the ones worth recording, so
-- every filter goes on for the scan and back to what it was afterwards.
local FILTERS = { "available", "unavailable", "used" }

local function WithEveryRowShowing(scan)
  if not (SetTrainerServiceTypeFilter and GetTrainerServiceTypeFilter) then return scan() end
  local before = {}
  for _, filter in ipairs(FILTERS) do
    local ok, value = pcall(GetTrainerServiceTypeFilter, filter)
    if ok then before[filter] = value and true or false end -- false is an answer, not a miss
    pcall(SetTrainerServiceTypeFilter, filter, 1)
  end
  local ok, result = pcall(scan)
  for _, filter in ipairs(FILTERS) do
    if before[filter] ~= nil then pcall(SetTrainerServiceTypeFilter, filter, before[filter] and 1 or 0) end
  end
  if not ok then error(result) end
  return result
end

-- The trainer you are talking to: its id from the target's guid, and its name.
local function TrainerIdentity()
  local guid = UnitGUID and UnitGUID("npc") or (UnitGUID and UnitGUID("target"))
  local id
  if type(guid) == "string" then
    local kind, _, _, _, _, npcID = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then id = tonumber(npcID) end
  end
  local name = (UnitName and (UnitName("npc") or UnitName("target"))) or nil
  return id, ns.PublicValue and ns.PublicValue(name) or name
end

------------------------------------------------------------------------------
-- What this client actually answers, for when nothing is recorded
------------------------------------------------------------------------------
local API = { "GetNumTrainerServices", "GetTrainerServiceInfo", "GetTrainerServiceLevelReq",
              "GetTrainerServiceCost", "SetTrainerServiceTypeFilter", "GetTrainerServiceTypeFilter" }

local function describe(value)
  if issecretvalue and issecretvalue(value) then return "secret" end
  if value == nil then return "nil" end
  return ("%s(%s)"):format(type(value), tostring(value):sub(1, 40))
end

-- A line per thing worth knowing: which calls exist, what the count is, what a row looks like.
function ns.TrainerProbe()
  local out = {}
  for _, name in ipairs(API) do
    table.insert(out, ("%s: %s"):format(name, rawget(_G, name) and "yes" or "MISSING"))
  end
  if rawget(_G, "GetNumTrainerServices") then
    local ok, count = pcall(GetNumTrainerServices)
    table.insert(out, ("GetNumTrainerServices -> %s %s"):format(ok and "ok" or "ERROR", describe(count)))
    if ok and type(count) == "number" then
      for i = 1, math.min(3, count) do
        local fine, a, b, c, d = pcall(GetTrainerServiceInfo, i)
        table.insert(out, ("row %d: %s name=%s rank=%s category=%s extra=%s"):format(
          i, fine and "ok" or "ERROR", describe(a), describe(b), describe(c), describe(d)))
        table.insert(out, ("row %d: level=%s cost=%s spell=%s"):format(
          i, describe(Number(GetTrainerServiceLevelReq, i)), describe(Number(GetTrainerServiceCost, i)),
          describe(ServiceSpell(i))))
      end
    end
  end
  local frames = { "ClassTrainerFrame", "TrainerFrame", "ProfessionsTrainerFrame" }
  for _, name in ipairs(frames) do
    local frame = rawget(_G, name)
    if frame then table.insert(out, ("%s: exists, shown=%s"):format(name, tostring(frame:IsShown()))) end
  end
  return out
end

function ns.RecordTrainer()
  if not ns.IsFeatureEnabled("collect") then return nil end
  local c = ns.CollectedStore and ns.CollectedStore()
  if not c then return nil end
  if not GetNumTrainerServices then
    ns.CollectError("trainers", "this client has no GetNumTrainerServices")
    return nil
  end
  local services = WithEveryRowShowing(function()
    local out = {}
    local count = Number(GetNumTrainerServices) or 0
    for i = 1, count do
      local service = ReadService(i)
      if service and service.name then table.insert(out, service) end
    end
    return out
  end)
  if not services or #services == 0 then
    -- Nothing came back. Keep what the client said, so the next file explains why.
    c.trainerProbe = { at = time and time() or 0, lines = ns.TrainerProbe() }
    return nil
  end
  c.trainers = c.trainers or {}

  local id, name = TrainerIdentity()
  local key = id or (name or "trainer")
  local _, classToken = UnitClass("player")
  local _, raceFile = UnitRace("player")
  -- The race matters: two trainers of one class differ only by the race lines they sell, and
  -- the client does not mark Forever's own ones.
  c.trainers[key] = { id = id, name = name, class = classToken, race = ns.PublicValue(raceFile),
                      level = UnitLevel("player"), seen = time and time() or 0, services = services }
  ns.collectLast.trainers = ("%s: %d spells"):format(tostring(name), #services)
  ns.Print(("recorded %d spells from %s. Thank you, that list is not published anywhere."):format(
    #services, tostring(name)))
  return services
end

local function Attempt()
  local ok, err = pcall(ns.RecordTrainer)
  if not ok then ns.CollectError("trainers", err) end
  return ok
end

local events = CreateFrame("Frame")
events:RegisterEvent("TRAINER_SHOW")
events:RegisterEvent("TRAINER_UPDATE")
events:SetScript("OnEvent", function(self, event)
  Attempt()
  -- The list is not always there the moment the window opens.
  if event == "TRAINER_SHOW" and C_Timer and C_Timer.After then
    C_Timer.After(0.5, Attempt)
    C_Timer.After(2, Attempt)
  end
end)

-- /fb trainer says what has been recorded so far, and from whom.
ns.SlashHandlers.trainer = function(rest)
  if rest == "probe" then
    ns.Print("trainer probe, with the trainer window open:")
    for _, line in ipairs(ns.TrainerProbe()) do ns.Print("  " .. line) end
    return true
  end
  return ns.TrainerList()
end

function ns.TrainerList()
  local c = ns.CollectedStore and ns.CollectedStore()
  local trainers = c and c.trainers
  if not trainers or not next(trainers) then
    ns.Print("no trainer recorded yet. Open a class trainer with data recording on and it saves itself.")
    return 0
  end
  local counted = 0
  for _, trainer in pairs(trainers) do
    counted = counted + 1
    ns.Print(("%s (%s, level %s): %d spells"):format(
      tostring(trainer.name), tostring(trainer.class), tostring(trainer.level), #trainer.services))
  end
  return counted
end
