-- Fake of the WoW client API surface UsedFor touches. Registration state
-- (frames, tooltip post-calls) persists across Stub.reset(); game state does not.
-- Stub.reset() discards queued timers; call Stub.RunTimers() first if a test scheduled one.
local Stub = { frames = {}, postCalls = {}, timers = {} }

-- tooltips -----------------------------------------------------------------
function Stub.NewTooltip(name, firstLine)
  local t = { name = name, lines = {}, shown = false, forbidden = false }
  function t:GetName() return self.name end
  function t:IsForbidden() return self.forbidden end
  function t:AddLine(text, r, g, b) table.insert(self.lines, { text = text, r = r, g = g, b = b }) end
  function t:Show() self.shown = true end
  function t:Hide() self.shown = false end
  function t:IsShown() return self.shown end
  function t:SetOwner() end
  function t:SetPoint() end
  function t:ClearAllPoints() end
  -- The client re-processes the tooltip on SetHyperlink and runs the registered post-calls.
  function t:SetHyperlink(link)
    self.hyperlink = link
    self.lines = {}
    local id = tonumber(link:match("item:(%d+)"))
    local shown = Stub.tooltipLines[id] or { firstLine }
    self.numLines = #shown
    for i, text in ipairs(shown) do
      _G[name .. "TextLeft" .. i] = { GetText = function() return text end }
    end
    for _, postCall in ipairs(Stub.postCalls[Enum.TooltipDataType.Item] or {}) do
      postCall(self, { id = id })
    end
  end
  function t:GetItem()
    local id = tonumber(self.hyperlink and self.hyperlink:match("item:(%d+)"))
    local entry = Stub.items[id]
    local name = type(entry) == "table" and entry.name or (type(entry) == "string" and entry) or firstLine
    local link = (type(entry) == "table" and entry.link) or self.hyperlink
    return name, link, id
  end
  function t:NumLines() return self.numLines or 1 end
  _G[name .. "TextLeft1"] = { GetText = function() return firstLine end }
  return t
end

-- game state ---------------------------------------------------------------
function Stub.reset()
  Stub.onQuest = {}      -- [questID] = true
  Stub.completed = {}    -- [questID] = true
  Stub.objectives = {}   -- [questID] = { { text=, type= }, ... }
  Stub.questLog = {}     -- { { title=, questID=, isHeader= }, ... }
  Stub.items = {}        -- [itemID] = name
  Stub.requested = nil   -- last itemID passed to RequestLoadItemDataByID
  Stub.faction = "Alliance"
  Stub.classToken = "WARRIOR"
  Stub.raceFile = "Scourge"
  Stub.sent = {}              -- addon messages this session
  Stub.guild, Stub.group = false, nil
  Stub.now = 0                -- what GetTime answers
  Stub.shift = false
  Stub.ctrl = false
  Stub.registeredPrefix = nil
  Stub.bank = {}
  Stub.professions = nil
  Stub.timers = {}
  Stub.calls = {}        -- { {name, arg1, arg2, ...}, ... } every automation-relevant C call
  Stub.money = 0
  Stub.canRepair = false -- CanMerchantRepair()
  Stub.repairCost = 0    -- GetRepairAllCost() -> cost, canRepair(cost > 0)
  Stub.bags = {}         -- [bag] = { [slot] = { itemID=, quality=, stackCount=, hasNoValue=, isLocked= } }
  Stub.questChoices = 0  -- GetNumQuestChoices()
  Stub.questCompletable = false
  Stub.questMoneyToGet = 0
  Stub.greetingActive = {}    -- { { title=, isComplete= }, ... }
  Stub.greetingAvailable = {} -- { { title= }, ... }
  Stub.gossipActive = {}      -- { { questID=, title=, isComplete= }, ... }
  Stub.gossipAvailable = {}   -- { { questID=, title= }, ... }
  Stub.equipped = {}          -- [inventorySlot] = itemID
  Stub.inCombat = false
  Stub.scanLines = {}         -- ["bag:slot"] = { { text, r, g, b }, ... } for the hidden tooltip scan
  Stub.popups = {}            -- StaticPopup_Show calls: { which, arg1, arg2, data }
  Stub.itemStats = {}         -- [link] = { ITEM_MOD_STRENGTH_SHORT = 10, ... } for GetItemStats
  Stub.factions = {}          -- [factionID] = name for GetFactionInfoByID
  Stub.dialogs = {}           -- [which] = fake StaticPopup dialog for StaticPopup_FindVisible
  Stub.resized = {}           -- StaticPopup_Resize calls
  -- collector inputs
  Stub.level = 1
  Stub.quest = {}             -- the open quest window: { id=, title=, objectives=, xp=, money=, rewards={links}, choices={links} }
  Stub.units = {}             -- [unit] = { guid=, name= } for UnitGUID/UnitName
  Stub.position = { map = 1, x = 0.5, y = 0.5, zone = "Nowhere", sub = "" }
  Stub.loot = {}              -- { { link=, sources = { guid, qty, ... } }, ... }
  Stub.merchant = {}          -- { { link=, price=, name= }, ... }
  Stub.talents = nil          -- { { name=, talents = { { name=, tier=, column=, rank=, maxRank= } } }, ... } or nil (API absent)
  Stub.pushable = {}          -- [questID] = true for IsPushableQuest
  Stub.tooltipLines = {}      -- [itemID] = { "line", ... } shown by the client before post-calls run
  Stub.questLevels = {}       -- [questID] = level (quest log)
  Stub.cursor = { x = 0.25, y = 0.75 } -- world map cursor, normalized; nil when off the map
  Stub.facing = 0             -- GetPlayerFacing, radians counterclockwise from north
  Stub.worldScale = 1000      -- GetWorldPosFromMapPos: world = map * scale (+ map id * 10000 as a continent offset)
  Stub.continents = {}        -- [mapID] = continent id (default 0)
  Stub.traits = nil           -- Forever talents: { configID=, treeID=, groups={ {groupID=, displayName=, orderIndex=} }, nodes={ [nodeID]={...TraitNodeInfo} }, entries={ [entryID]={definitionID=} }, defs={ [definitionID]={spellID=, overrideName=} }, spells={ [spellID]=name }, specGroup=1, configs={ [specGroup]=configID } }
  Stub.targetDead = false
  Stub.deadUnits = {}         -- [unit] = true for UnitIsDead
  Stub.canUseItem = nil       -- nil: everything usable; else [itemID] = false for what the class cannot use
  Stub.cvars = Stub.cvars or {} -- the game's settings file: survives reset, like Config.wtf survives a session
  Stub.maps = {}              -- the client's map tree, see C_Map below
  Stub.lootSlots = {}         -- [slot] = quantity for GetLootSlotInfo
  WorldMapFrame = Stub.NewMock("Frame", "WorldMapFrame")
  WorldMapFrame.mapID = 1
  function WorldMapFrame:GetMapID() return self.mapID end
  function WorldMapFrame:SetMapID(id) self.mapID = id end
  WorldMapFrame.ScrollContainer = Stub.NewMock("Frame", "WorldMapFrameScrollContainer")
  WorldMapFrame.ScrollContainer.Child = Stub.NewMock("Frame", "WorldMapFrameScrollChild")
  function WorldMapFrame.ScrollContainer.Child:GetWidth() return 1000 end
  function WorldMapFrame.ScrollContainer.Child:GetHeight() return 666 end
  function WorldMapFrame.ScrollContainer:GetNormalizedCursorPosition() if Stub.cursor then return Stub.cursor.x, Stub.cursor.y end return -1, -1 end
  Minimap = Stub.NewMock("Frame", "Minimap")
  MerchantFrame = Stub.NewMock("Frame", "MerchantFrame")
  GameTooltip = Stub.NewTooltip("GameTooltip", "Fallback Name")
  ItemRefTooltip = Stub.NewTooltip("ItemRefTooltip", "Ref Fallback")
end

-- globals the addon reads --------------------------------------------------
Enum = { TooltipDataType = { Item = 0, Spell = 1, Unit = 2 },
         UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 } }
TooltipDataProcessor = {
  AddTooltipPostCall = function(tooltipType, func)
    Stub.postCalls[tooltipType] = Stub.postCalls[tooltipType] or {}
    table.insert(Stub.postCalls[tooltipType], func)
  end,
}
-- Stub.mainlineQuestLog = true switches the quest log to the Mainline/Forever API (C_QuestLog.GetInfo).
C_QuestLog = {
  GetInfo = function(i)
    if not Stub.mainlineQuestLog then return nil end
    local e = Stub.questLog[i]
    if not e then return nil end
    return { title = e.title, isHeader = e.isHeader or false, questID = e.questID or 0, level = Stub.questLevels[e.questID] }
  end,
  GetNumQuestLogEntries = function() if Stub.mainlineQuestLog then return #Stub.questLog, #Stub.questLog end return nil end,
  IsOnQuest = function(id) return Stub.onQuest[id] == true end,
  IsQuestFlaggedCompleted = function(id) return Stub.completed[id] == true end,
  GetQuestObjectives = function(id) return Stub.objectives[id] end,
  IsPushableQuest = function(id) return Stub.pushable[id] == true end,
}
local function call(name, ...) table.insert(Stub.calls, { name, ... }) end
Stub.call = call
function Stub.CallNames() local out = {} for i, c in ipairs(Stub.calls) do out[i] = c[1] end return out end

C_Item = {
  -- Everything in the bags, plus Stub.bank when the caller asks for it, the way the client
  -- counts an item across the places it can be.
  GetItemCount = function(id, includeBank)
    local total = 0
    for _, slots in pairs(Stub.bags or {}) do
      for _, info in pairs(slots or {}) do
        if info and info.itemID == id then total = total + (info.stackCount or 1) end
      end
    end
    if includeBank then
      for item, n in pairs(Stub.bank or {}) do
        if item == id then total = total + n end
      end
    end
    return total
  end,
  -- Stub.items[id] is a name, or { name=, sellPrice= }; GetItemInfo returns the 11 client values used by the addon.
  GetItemInfo = function(id)
    local entry = Stub.items[id]
    if entry == nil then return nil end
    if type(entry) == "string" then return entry end
    return entry.name, entry.link or ("[" .. entry.name .. "]"), entry.quality, entry.ilvl, nil, nil, nil, nil,
      entry.equipLoc, nil, entry.sellPrice, entry.classID, entry.subclassID
  end,
  GetItemInfoInstant = function(id)
    local entry = Stub.items[id]
    if type(entry) ~= "table" then return id, nil, nil, "", nil, nil, nil end
    return id, nil, nil, entry.equipLoc or "", nil, entry.classID, entry.subclassID
  end,
  EquipItemByName = function(link, slot) call("EquipItemByName", link, slot) end,
  RequestLoadItemDataByID = function(id) Stub.requested = id end,
}
C_Timer = { After = function(delay, fn) table.insert(Stub.timers, { delay = delay, fn = fn }) end }
SlashCmdList = {}
bit = bit or require("bit")

function GetNumQuestLogEntries() return #Stub.questLog end
function GetQuestLogTitle(i)
  local e = Stub.questLog[i]
  return e.title, Stub.questLevels[e.questID] or 1, 0, e.isHeader or false, false, false, 0, e.questID or 0  -- headers carry questID 0 in the client
end
function UnitFactionGroup() return Stub.faction end
function UnitClass() return "Name", Stub.classToken end
function UnitRace() return Stub.raceName or "Undead", Stub.raceFile or "Scourge" end
function IsShiftKeyDown() return Stub.shift end
function IsControlKeyDown() return Stub.ctrl end

-- Frame mock: any unknown method is a no-op; the handful the addon reads back are stateful.
-- A frame answers any method we have not bothered to write with a no-op, so the addon can call
-- whatever the client offers. Only methods: the client's are all CamelCase, and a plain field
-- nobody has set reads as nil, as it does in the game. Handing back a no-op for those was
-- hiding real bugs - a GetText() that returned a function, and a field set to nil that read
-- back as one.
local MockMT = {}
MockMT.__index = function(self, key)
  if type(key) ~= "string" or not key:match("^%u") then return nil end
  local noop = function() end
  rawset(self, key, noop)
  return noop
end

local function NewMock(kind, name, template)
  local m = setmetatable({ kind = kind, name = name, template = template, events = {}, scripts = {},
                           shown = false, checked = false, text = nil, children = {} }, MockMT)
  function m:RegisterEvent(e) self.events[e] = true end
  function m:UnregisterEvent(e) self.events[e] = nil end
  function m:SetScript(n, fn) self.scripts[n] = fn end
  function m:GetScript(n) return self.scripts[n] end
  function m:GetName() return self.name end
  function m:Show() self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
  function m:Hide()
    local wasShown = self.shown
    self.shown = false
    if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
  end
  function m:IsShown() return self.shown end
  function m:SetShown(v) if v then self:Show() else self:Hide() end end
  m.enabled = true
  function m:Enable() self.enabled = true end
  function m:Disable() self.enabled = false end
  function m:IsEnabled() return self.enabled end
  function m:SetChecked(v) self.checked = v and true or false end
  function m:GetChecked() return self.checked end
  function m:SetText(t) self.text = t end
  -- rawget, or a frame nobody has called SetText on answers with the no-op that __index hands
  -- out for any missing field, and the caller gets a function where it expected a string.
  function m:GetText() return rawget(self, "text") end
  function m:Click()
    if self.kind == "CheckButton" then self.checked = not self.checked end
    if self.scripts.OnClick then self.scripts.OnClick(self, "LeftButton") end
  end
  if kind == "GameTooltip" then
    m.numLines = 0
    function m:SetOwner() end
    function m:SetTrainerService(i)
      local service = Stub.VisibleTrainerService and Stub.VisibleTrainerService(i)
      self.spell = service and { service.name, service.spell } or nil
      return self.spell ~= nil
    end
    function m:GetSpell()
      if not self.spell then return nil end
      return self.spell[1], self.spell[2]
    end
    function m:ClearLines() self.numLines = 0 end
    function m:NumLines() return self.numLines end
    function m:SetBagItem(bag, slot)
      local lines = Stub.scanLines[bag .. ":" .. slot] or { { "Unknown Item", 1, 1, 1 } }
      self.numLines = #lines
      for i, l in ipairs(lines) do
        _G[self.name .. "TextLeft" .. i] = {
          GetText = function() return l[1] end,
          GetTextColor = function() return l[2], l[3], l[4], 1 end,
        }
      end
    end
  end
  if kind == "FontString" then
    function m:SetTextColor(r, g, b) self.color = { r, g, b } end
    function m:GetTextColor() local c = self.color or { 1, 1, 1 }; return c[1], c[2], c[3], 1 end
  end
  if kind == "Texture" then
    function m:SetTexture(path) self.texture = path end
    function m:GetTexture() return self.texture end
    function m:SetAlpha(value) self.alpha = value end
    function m:GetAlpha() return self.alpha or 1 end
  end
  function m:CreateTexture(n, layer)
    local tx = NewMock("Texture", n)
    table.insert(self.children, tx)
    return tx
  end
  function m:CreateFontString(n, layer, tmpl)
    local fs = NewMock("FontString", n, tmpl)
    table.insert(self.children, fs)
    return fs
  end
  return m
end
Stub.NewMock = NewMock

function CreateFrame(kind, name, parent, template)
  local f = NewMock(kind or "Frame", name, template)
  if type(parent) == "table" and parent.children then table.insert(parent.children, f) end
  table.insert(Stub.frames, f)
  if name then _G[name] = f end
  return f
end

Stub.version = "0.3.0"
C_AddOns = { GetAddOnMetadata = function(name, field) return Stub.version end }
function ContainerFrame_Update() end
function ContainerFrameItemButton_OnModifiedClick() end -- Classic bag buttons
-- The client's font objects, which the addon reads a font file and size out of.
GameFontNormal = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end }
GameFontNormalLarge = GameFontNormal
UIParent = NewMock("Frame", "UIParent")
MerchantFrame = NewMock("Frame", "MerchantFrame")
UISpecialFrames = {}
tinsert = table.insert

Enum.ItemQuality = { Poor = 0, Common = 1, Uncommon = 2, Rare = 3, Epic = 4 }
NUM_BAG_SLOTS = 4
C_Container = {
  GetContainerNumSlots = function(bag) local b = Stub.bags[bag]; return b and #b or 0 end,
  GetContainerItemInfo = function(bag, slot) local b = Stub.bags[bag]; return b and b[slot] or nil end,
  UseContainerItem = function(bag, slot) call("UseContainerItem", bag, slot) end,
}
C_GossipInfo = {
  GetActiveQuests = function() return Stub.gossipActive end,
  GetAvailableQuests = function() return Stub.gossipAvailable end,
  SelectActiveQuest = function(questID) call("C_GossipInfo.SelectActiveQuest", questID) end,
  SelectAvailableQuest = function(questID) call("C_GossipInfo.SelectAvailableQuest", questID) end,
}
function GetInventoryItemID(unit, slot) return Stub.equipped[slot] end
function GetInventoryItemLink(unit, slot)
  local id = Stub.equipped[slot]
  return id and select(2, C_Item.GetItemInfo(id)) or nil
end
function InCombatLockdown() return Stub.inCombat end
StaticPopupDialogs = {}
function StaticPopup_Show(which, arg1, arg2, data)
  local dialog = { which = which, data = data }
  table.insert(Stub.popups, { which, arg1, arg2, data })
  return dialog
end
function GetItemStats(link) return Stub.itemStats[link] end
function UnitLevel() return Stub.level or 1 end
time = os.time
function GetTime() return Stub.now or 0 end

-- Addon chatter: Stub.sent collects what went out, Stub.group/Stub.guild say who can hear it.
C_ChatInfo = {
  RegisterAddonMessagePrefix = function(prefix)
    Stub.registeredPrefix = prefix
    return true
  end,
  SendAddonMessage = function(prefix, message, channel)
    table.insert(Stub.sent, { prefix = prefix, message = message, channel = channel })
    return true
  end,
}
-- The character's professions, as two primaries plus the secondaries, the way the client
-- reports them. Stub.professions is a list of names.
function GetProfessions()
  local list = Stub.professions or {}
  return list[1] and 1 or nil, list[2] and 2 or nil, nil, list[3] and 3 or nil,
         list[4] and 4 or nil, list[5] and 5 or nil
end
function GetProfessionInfo(index)
  local name = (Stub.professions or {})[index]
  return name
end

function IsInGuild() return Stub.guild == true end
function IsInGroup() return Stub.group == "party" or Stub.group == "raid" end
function IsInRaid() return Stub.group == "raid" end

-- The game's own splitter, returning each piece as a separate value, empty ones included.
function strsplit(sep, text)
  local out, start = {}, 1
  text = tostring(text)
  while true do
    local at = text:find(sep, start, true)
    if not at then
      table.insert(out, text:sub(start))
      break
    end
    table.insert(out, text:sub(start, at - 1))
    start = at + #sep
  end
  return unpack(out)
end

-- Trainer window: Stub.trainer = { npc = {id=, name=}, services = { {name=, rank=, category=,
-- level=, cost=, spell=} }, filters = { available=true, ... } }
function GetNumTrainerServices()
  local t = Stub.trainer
  if not t then return 0 end
  local n = 0
  for _, s in ipairs(t.services or {}) do
    if t.filters == nil or t.filters[s.category] then n = n + 1 end
  end
  return n
end

local function visible(index)
  local t = Stub.trainer
  if not t then return nil end
  local n = 0
  for _, s in ipairs(t.services or {}) do
    if t.filters == nil or t.filters[s.category] then
      n = n + 1
      if n == index then return s end
    end
  end
  return nil
end
Stub.VisibleTrainerService = visible

function GetTrainerServiceInfo(i)
  local s = visible(i)
  if not s then return nil end
  return s.name, s.rank, s.category, false
end
function GetTrainerServiceLevelReq(i) local s = visible(i); return s and s.level end
function GetTrainerServiceCost(i) local s = visible(i); return s and s.cost end
function GetTrainerServiceTypeFilter(filter)
  local t = Stub.trainer
  return t and t.filters and t.filters[filter] or false
end
function SetTrainerServiceTypeFilter(filter, on)
  local t = Stub.trainer
  if not t then return end
  t.filters = t.filters or {}
  t.filters[filter] = on == 1 or on == true
end
NUM_BANKBAGSLOTS = 6
BANK_CONTAINER = -1
function GetFactionInfoByID(id) return Stub.factions[id] end
Stub.hooks = {}
function hooksecurefunc(target, name, fn)
  if type(target) == "table" then -- hooksecurefunc(table, "method", fn)
    local key = tostring(target) .. "." .. name
    Stub.hooks[key] = Stub.hooks[key] or {}; table.insert(Stub.hooks[key], fn)
    local original = target[name]
    target[name] = function(...) local r = original and original(...); for _, h in ipairs(Stub.hooks[key]) do h(...) end; return r end
    return
  end
  fn = name; name = target
  Stub.hooks[name] = Stub.hooks[name] or {}; table.insert(Stub.hooks[name], fn)
end
function Stub.CallHook(name, ...) for _, fn in ipairs(Stub.hooks[name] or {}) do fn(...) end end
function StaticPopup_FindVisible(which) return Stub.dialogs[which] end
function StaticPopup_Resize(dialog, which) table.insert(Stub.resized, which) end
-- Fire the registered post-calls for a unit or spell tooltip, as the client does.
function Stub.ShowUnitTooltip(tooltip, guid)
  for _, postCall in ipairs(Stub.postCalls[Enum.TooltipDataType.Unit] or {}) do postCall(tooltip, { guid = guid }) end
end
function Stub.ShowSpellTooltip(tooltip, spellID)
  for _, postCall in ipairs(Stub.postCalls[Enum.TooltipDataType.Spell] or {}) do postCall(tooltip, { id = spellID }) end
end
function UnitName() return "Tester" end
function GetRealmName() return "Realm" end
function GetMoney() return Stub.money end
function GetMoneyString(copper) return tostring(copper) .. "c" end
function CanMerchantRepair() return Stub.canRepair end
function GetRepairAllCost() return Stub.repairCost, Stub.repairCost > 0 end
function RepairAllItems(guild) call("RepairAllItems", guild) end
function AcceptQuest() call("AcceptQuest") end
function CompleteQuest() call("CompleteQuest") end
function GetQuestReward(choice) call("GetQuestReward", choice) end
function GetNumQuestChoices() return Stub.questChoices end
function IsQuestCompletable() return Stub.questCompletable end
function GetQuestMoneyToGet() return Stub.questMoneyToGet end
function GetNumActiveQuests() return #Stub.greetingActive end
function GetActiveTitle(i) local q = Stub.greetingActive[i]; return q.title, q.isComplete or false end
function SelectActiveQuest(i) call("SelectActiveQuest", i) end
function GetNumAvailableQuests() return #Stub.greetingAvailable end
function SelectAvailableQuest(i) call("SelectAvailableQuest", i) end

-- collector surface ----------------------------------------------------------
function GetQuestID() return Stub.quest.id end
function GetTitleText() return Stub.quest.title end
function GetObjectiveText() return Stub.quest.objectives end
function GetRewardXP() return Stub.quest.xp or 0 end
function GetRewardMoney() return Stub.quest.money or 0 end
function GetNumQuestRewards() return #(Stub.quest.rewards or {}) end
function GetQuestItemLink(kind, i) local list = kind == "choice" and Stub.quest.choices or Stub.quest.rewards; return list and list[i] end
function UnitGUID(unit) local u = Stub.units[unit]; return u and u.guid end
function UnitName(unit) local u = Stub.units[unit]; return u and u.name or "Tester" end
function ToggleWorldMap() if WorldMapFrame:IsShown() then WorldMapFrame:Hide() else WorldMapFrame:Show() end end
function GetZoneText() return Stub.position.zone end
function GetSubZoneText() return Stub.position.sub end
-- Stub.maps: [mapID] = { name=, parent=, mapType=, levels={min,max}, rect={l,r,t,b}, children={ids} }
C_Map = {
  GetMapChildrenInfo = function(mapID, mapType)
    local out = {}
    for _, id in ipairs((Stub.maps[mapID] or {}).children or {}) do
      local m = Stub.maps[id]
      if m and (not mapType or m.mapType == mapType) then
        table.insert(out, { mapID = id, name = m.name, mapType = m.mapType })
      end
    end
    return out
  end,
  GetMapInfo = function(mapID)
    local m = Stub.maps[mapID]
    return m and { mapID = mapID, name = m.name, parentMapID = m.parent, mapType = m.mapType } or nil
  end,
  GetMapLevels = function(mapID)
    local m = Stub.maps[mapID]
    if not (m and m.levels) then return 0, 0, 0, 0 end
    return m.levels[1], m.levels[2], 0, 0
  end,
  GetMapRectOnMap = function(childID, parentID)
    local m = Stub.maps[childID]
    local r = m and m.rect
    if not r then return nil end
    return r[1], r[2], r[3], r[4]
  end,
  -- Which child of mapID covers this point: its rectangle, and its shape() when it has one
  -- (a zone whose rectangle takes in water or another zone's ground).
  GetMapInfoAtPosition = function(mapID, x, y)
    for _, id in ipairs((Stub.maps[mapID] or {}).children or {}) do
      local m = Stub.maps[id]
      local r = m and m.rect
      if r and x >= r[1] and x <= r[2] and y >= r[3] and y <= r[4] and (not m.shape or m.shape(x, y)) then
        return { mapID = id, name = m.name, mapType = m.mapType, parentMapID = mapID }
      end
    end
    return nil
  end,
  GetBestMapForUnit = function() return Stub.position.map end,
  -- nil inside instances (Stub.position.x == nil), like the client
  GetPlayerMapPosition = function(map) if Stub.position.x == nil then return nil end return { GetXY = function() return Stub.position.x, Stub.position.y end } end,
  GetWorldPosFromMapPos = function(map, pos)
    local continent = Stub.continents[map] or 0
    return continent, { x = pos.x * Stub.worldScale + map * 10000, y = pos.y * Stub.worldScale + map * 10000 }
  end,
}
C_CVar = {
  RegisterCVar = function(name, value) if Stub.cvars[name] == nil then Stub.cvars[name] = value or "" end end,
  GetCVar = function(name) return Stub.cvars[name] end,
  SetCVar = function(name, value) Stub.cvars[name] = tostring(value) end,
}
C_PlayerInfo = { CanUseItem = function(itemID) if Stub.canUseItem == nil then return true end return Stub.canUseItem[itemID] ~= false end }
function CreateVector2D(x, y) return { x = x, y = y } end
C_Traits = {
  GetConfigInfo = function(configID)
    local t = Stub.traits
    if not t then return nil end
    return { ID = configID, treeIDs = { t.treeID }, name = "", type = 1 }
  end,
  GetTreeNodes = function(treeID)
    local t = Stub.traits
    if not t then return {} end
    local ids = {}
    for id in pairs(t.nodes) do table.insert(ids, id) end
    table.sort(ids)
    return ids
  end,
  GetNodeInfo = function(configID, nodeID) local t = Stub.traits; return t and t.nodes[nodeID] end,
  GetEntryInfo = function(configID, entryID) local t = Stub.traits; return t and t.entries[entryID] end,
  GetDefinitionInfo = function(definitionID) local t = Stub.traits; return t and t.defs[definitionID] end,
  GetGroupDisplayInfoByTreeID = function(treeID) local t = Stub.traits; return t and t.groups or {} end,
}
C_SpecializationInfo = {
  GetActiveSpecGroup = function() return Stub.traits and Stub.traits.specGroup or 1 end,
  GetCombatConfigIDForSpecGroup = function(group)
    local t = Stub.traits
    if not t then return nil end
    return (t.configs and t.configs[group]) or t.configID
  end,
}
C_Spell = { GetSpellName = function(id) return Stub.traits and Stub.traits.spells[id] end }
function UnitIsDead(unit) return Stub.deadUnits[unit] or (unit == "target" and Stub.targetDead) or false end
function GetLootSlotInfo(slot) return "icon", "item", Stub.lootSlots[slot] or 1 end
function GetBuildInfo()
  if Stub.mainline then return "12.1.5", "69999", "Sep 16 2026", 120105 end
  return "1.15.9", "69722", "Sep 1 2026", 11509
end
function GetPlayerFacing() return Stub.facing end
function GetNumLootItems() return #Stub.loot end
function GetLootSlotLink(i) return Stub.loot[i] and Stub.loot[i].link end
function GetLootSourceInfo(i) local l = Stub.loot[i]; if l then return unpack(l.sources) end end
function GetMerchantNumItems() return #Stub.merchant end
function GetMerchantItemLink(i) return Stub.merchant[i] and Stub.merchant[i].link end
function GetMerchantItemInfo(i) local m = Stub.merchant[i]; if m then return m.name, nil, m.price, 1, -1, true, true end end
function GetNumTalentTabs() return Stub.talents and #Stub.talents or 0 end
function GetTalentTabInfo(tab) local t = Stub.talents and Stub.talents[tab]; if t then return t.name end end
function GetNumTalents(tab) local t = Stub.talents and Stub.talents[tab]; return t and #t.talents or 0 end
function GetTalentInfo(tab, i)
  local t = Stub.talents and Stub.talents[tab] and Stub.talents[tab].talents[i]
  if t then return t.name, "icon", t.tier, t.column, t.rank, t.maxRank end
end

-- helpers ------------------------------------------------------------------
function Stub.FireEvent(event, ...)
  for _, f in ipairs(Stub.frames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end

function Stub.RunTimers()
  local due = Stub.timers
  Stub.timers = {}
  for _, t in ipairs(due) do t.fn() end
end

-- Loads addon files in order, passing ("ForeverBuddy", ns) like the client does.
function Stub.LoadAddon(files)
  local ns = {}
  for _, path in ipairs(files) do
    local chunk = assert(loadfile(path))
    chunk("ForeverBuddy", ns)
  end
  return ns
end

-- Mainline mode (FB_MAINLINE=1): Classic-only globals disappear, Mainline replacements appear. run.sh runs both.
Stub.mainline = os.getenv("FB_MAINLINE") == "1"
if Stub.mainline then
  Stub.mainlineQuestLog = true
  GetQuestLogTitle = nil
  GetNumQuestLogEntries = nil
  GetItemStats = nil
  GetFactionInfoByID = nil
  ContainerFrame_Update = nil
  ContainerFrameItemButton_OnModifiedClick = nil
  ContainerFrameMixin = { UpdateItems = function() end }
  ContainerFrameItemButtonMixin = { OnModifiedClick = function() end }
  C_Item.GetItemStats = function(link) return Stub.itemStats[link] end
  C_Reputation = { GetFactionDataByID = function(id) local n = Stub.factions[id]; return n and { name = n } or nil end }
  Enum.BagIndex = { CharacterBankTab_1 = 6, CharacterBankTab_2 = 7, CharacterBankTab_3 = 8, CharacterBankTab_4 = 9, CharacterBankTab_5 = 10, CharacterBankTab_6 = 11 }
  local baseReset = Stub.reset
  Stub.reset = function() baseReset(); Stub.mainlineQuestLog = true end
end

Stub.reset()
return Stub
