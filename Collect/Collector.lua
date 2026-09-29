local ADDON, ns = ...

-- Records what the game shows this player into ForeverBuddyDB.collected, so the shipped data can
-- be improved from real play on Forever, where the client tables are partly encrypted and the
-- community databases lag behind. Items hovered, quests accepted and handed in (with giver,
-- place, rewards), loot sources, vendor stock, and where talent points go.
-- Never chat, keystrokes, other players, account details, or anything from combat. Nothing is
-- sent anywhere: the file stays on the player's computer until they hand it over themselves.

ns.RegisterFeature({
  key = "collect",
  name = "Help improve the data",
  desc = "Records items, quests, quest givers, loot, vendors and talent points you see into ForeverBuddy's own saved-variables file, for building the Forever database. Nothing is sent anywhere. /fb collect explains.",
  default = true,
})

ns.COLLECT_EXPLAINER = {
  "ForeverBuddy can record what the game shows YOU, into its own saved-variables file on your computer:",
  "  items you hover (name, stats, price), quests you accept or hand in (giver, place, rewards),",
  "  what drops from what, what vendors sell, and where your talent points go.",
  "That is all. It never records chat, keystrokes, other players, account details, or anything from combat,",
  "and it never sends anything anywhere. The file is plain text, and sharing it is a choice you make by hand.",
  "To send it: log out (the game writes the file then), find World of Warcraft/_classic_/WTF/Account/<your account>/SavedVariables/ForeverBuddy.lua,",
  "and attach it to an issue on the ForeverBuddy GitHub, or send it to Leemo on Discord.",
  "GitHub will not take a .lua file, so zip it or rename it .txt first. Everything sent in is merged into what the addon ships with.",
  "/fb collect off switches it off, /fb collect stats shows what it holds, /fb collect check tests it.",
}

local FIRST_NOTICE = "recording game data you see (items, quests, loot, vendors, talents) to improve the Forever database. /fb collect explains; /fb collect off stops it."
local VERSION = 1

local function now() return time() end

-- Client version and interface number, e.g. "12.1.5", "69999", 120105.
function ns.ClientInfo()
  if not GetBuildInfo then return nil end
  local version, build, _, interface = GetBuildInfo()
  return { version = version, build = build, interface = interface }
end

local function store()
  if not ns.db then return nil end
  local c = ns.db.collected
  if not c or c.version ~= VERSION then
    c = { version = VERSION, items = {}, quests = {}, npcs = {}, loot = {}, vendors = {}, talents = {}, reports = {} }
    ns.db.collected = c
  end
  c.errors = c.errors or {}
  if not c.client then c.client = ns.ClientInfo() end
  return c
end
ns.CollectedStore = store

-- The most recent record of each kind this session, for /fb collect check.
ns.collectLast = {}

-- Errors are kept in the file (so a friend's file shows what broke) and each kind is printed once per session.
local printedErrors = {}
function ns.CollectError(where, err)
  local c = store()
  local msg = tostring(err)
  if c then
    local e = c.errors[where] or { count = 0 }
    e.count, e.msg, e.last = e.count + 1, msg, now()
    c.errors[where] = e
  end
  if not printedErrors[where] then
    printedErrors[where] = true
    ns.Print(("data recording error in %s: %s. /fb collect check shows details."):format(where, msg))
  end
end

local function enabled() return ns.IsFeatureEnabled("collect") and store() ~= nil end

local function noticed(c)
  if c.noticed then return end
  c.noticed = true
  ns.Print(FIRST_NOTICE)
end

function ns.CharacterKey()
  local name, realm = UnitName("player"), GetRealmName()
  return (name or "?") .. "-" .. (realm or "?")
end

-- Forever (Mainline 12.x) can hand addons "secret" values, e.g. a unit's GUID or name in restricted
-- places. They must not be read or stored, so every value from a unit function goes through this.
local function public(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end
ns.PublicValue = public

local function npcIDFromGUID(guid)
  guid = public(guid)
  return tonumber(type(guid) == "string" and guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-") or nil)
end

local function objectIDFromGUID(guid)
  guid = public(guid)
  return tonumber(type(guid) == "string" and guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)%-") or nil)
end

local function itemIDFromLink(link)
  return tonumber(type(link) == "string" and link:match("item:(%d+)") or nil)
end

-- Where the player stands: zone names, map id, and map coordinates as percentages.
function ns.PlayerPosition()
  local where = { zone = GetZoneText and GetZoneText() or nil, sub = GetSubZoneText and GetSubZoneText() or nil }
  if C_Map and C_Map.GetBestMapForUnit then
    local map = C_Map.GetBestMapForUnit("player")
    if map then
      where.map = map
      local pos = C_Map.GetPlayerMapPosition(map, "player")
      if pos then
        local x, y = pos:GetXY()
        if x and y then where.x, where.y = math.floor(x * 1000 + 0.5) / 10, math.floor(y * 1000 + 0.5) / 10 end
      end
    end
  end
  return where
end

------------------------------------------------------------------------------
-- Items: every tooltip the client shows
------------------------------------------------------------------------------
local BIND_LINES = {
  ["Binds when picked up"] = "pickup", ["Binds when equipped"] = "equip", ["Binds when used"] = "use",
  ["Soulbound"] = "soulbound", ["Quest Item"] = "quest",
}

local function tooltipLines(tooltip)
  local lines, name = {}, tooltip:GetName()
  local n = tooltip.NumLines and tooltip:NumLines() or 0
  for i = 1, n do
    local fs = _G[name .. "TextLeft" .. i]
    local text = fs and fs:GetText()
    if text and text ~= "" then table.insert(lines, text) end
  end
  return lines
end

function ns.CollectItem(tooltip, data)
  if not enabled() then return nil end
  if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return nil end
  if tooltip:IsForbidden() then return nil end
  local itemID = data and data.id
  local link
  if TooltipUtil and TooltipUtil.GetDisplayedItem then
    local _, l, id = TooltipUtil.GetDisplayedItem(tooltip)
    link = l; itemID = itemID or id
  elseif tooltip.GetItem then
    local _, l, id = tooltip:GetItem()
    link = l; itemID = itemID or id
  end
  if not itemID then return nil end
  local c = store()
  if c.items[itemID] then ns.collectLast.item = itemID; return c.items[itemID] end
  local name, infoLink, quality, ilvl, _, _, _, _, equipLoc, _, sellPrice, classID, subclassID = C_Item.GetItemInfo(itemID)
  if not name then return nil end -- not cached yet; the next hover will have it
  link = link or infoLink
  local rec = { name = name, link = link, quality = quality, ilvl = ilvl, slot = equipLoc, sell = sellPrice, type = classID, sub = subclassID, seen = now() }
  local getStats = (C_Item and C_Item.GetItemStats) or GetItemStats
  if getStats and link then
    local ok, stats = pcall(getStats, link)
    if ok and type(stats) == "table" and next(stats) then rec.stats = stats end
  end
  for _, text in ipairs(tooltipLines(tooltip)) do
    if BIND_LINES[text] then rec.bind = BIND_LINES[text] end
    local level = text:match("^Requires Level (%d+)$")
    if level then rec.req = tonumber(level) end
    local classes = text:match("^Classes: (.+)$")
    if classes then rec.classes = classes end
    if text == "Unique" then rec.unique = true end
  end
  c.items[itemID] = rec
  ns.collectLast.item = itemID
  noticed(c)
  return rec
end

------------------------------------------------------------------------------
-- Quests: the offer window, acceptance, and the turn-in window
------------------------------------------------------------------------------
-- Level and title from the quest log. With quest automation on, the quest window is gone
-- before this runs, so the log is the only place left to read the title.
local function questLogFacts(questID)
  for i = 1, ns.NumQuestLogEntries() do
    local title, isHeader, id, level = ns.QuestLogEntry(i)
    if not isHeader and id == questID then return level, title end
  end
  return nil, nil
end

local function unitRecord(unit)
  local guid = UnitGUID and UnitGUID(unit)
  local id = npcIDFromGUID(guid)
  if id then return { id = id, name = public(UnitName(unit)) } end
  id = objectIDFromGUID(guid)
  if id then return { id = id, name = public(UnitName(unit)), object = true } end
  return nil
end

-- Who we are talking to. Quest automation can close the window before QUEST_ACCEPTED arrives,
-- so the NPC seen when the quest or gossip window opened is remembered for a few seconds.
local lastNpc, lastNpcAt
local NPC_MEMORY = 20

function ns.RememberQuestNpc()
  local npc = unitRecord("npc") or unitRecord("target")
  if npc then lastNpc, lastNpcAt = npc, now() end
  return npc
end

local function questNpc()
  local npc = unitRecord("npc") or unitRecord("target")
  if npc then return npc end
  if lastNpc and lastNpcAt and (now() - lastNpcAt) <= NPC_MEMORY then return lastNpc end
  return nil
end

function ns.CollectQuestDetail()
  if not enabled() then return nil end
  local questID = GetQuestID()
  if not questID or questID == 0 then return nil end
  local c = store()
  local q = c.quests[questID] or {}
  q.title = GetTitleText() or q.title
  q.text = GetObjectiveText() or q.text
  q.giver = ns.RememberQuestNpc() or q.giver
  q.where = q.where or ns.PlayerPosition()
  if GetRewardXP then q.xp = GetRewardXP() end
  q.offered = q.offered or now()
  c.quests[questID] = q
  ns.collectLast.quest = questID
  return q
end

function ns.CollectQuestAccepted(questID)
  if not enabled() or not questID or questID == 0 then return nil end
  local c = store()
  local q = c.quests[questID] or { where = ns.PlayerPosition() }
  local level, title = questLogFacts(questID)
  q.level = level or q.level
  q.title = q.title or title
  -- The giver is usually still the unit we are talking to, or simply the target.
  q.giver = q.giver or questNpc()
  q.where = q.where or ns.PlayerPosition()
  if C_QuestLog.IsPushableQuest then q.shareable = C_QuestLog.IsPushableQuest(questID) and true or false end
  local objectives = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(questID)
  if type(objectives) == "table" and #objectives > 0 then
    q.objectives = {}
    for _, o in ipairs(objectives) do
      table.insert(q.objectives, { text = o.text, type = o.type, need = o.numRequired })
    end
  end
  q.accepted = q.accepted or now()
  c.quests[questID] = q
  ns.collectLast.quest = questID
  noticed(c)
  if not ns.IsKnownQuest(questID) then
    ns.Print(("recorded a quest the database did not know: %s"):format(q.title or tostring(questID)))
  end
  return q
end

-- The turn-in event carries the real rewards and fires even when the window was closed for us.
function ns.CollectQuestTurnedIn(questID, xpReward, moneyReward)
  if not enabled() or not questID or questID == 0 then return nil end
  local c = store()
  local q = c.quests[questID] or {}
  local _, title = questLogFacts(questID)
  q.title = q.title or title
  q.turnin = q.turnin or questNpc()
  q.turninWhere = q.turninWhere or ns.PlayerPosition()
  if type(xpReward) == "number" and xpReward > 0 then q.xp = xpReward end
  if type(moneyReward) == "number" and moneyReward > 0 then q.money = moneyReward end
  q.done = now()
  c.quests[questID] = q
  ns.collectLast.quest = questID
  return q
end

function ns.CollectQuestComplete()
  if not enabled() then return nil end
  local questID = GetQuestID()
  if not questID or questID == 0 then return nil end
  local c = store()
  local q = c.quests[questID] or { title = GetTitleText and GetTitleText() or nil }
  q.turnin = ns.RememberQuestNpc() or q.turnin
  q.turninWhere = q.turninWhere or ns.PlayerPosition()
  if GetRewardXP then q.xp = GetRewardXP() end
  if GetRewardMoney then q.money = GetRewardMoney() end
  q.rewards, q.choices = {}, {}
  for i = 1, (GetNumQuestRewards and GetNumQuestRewards() or 0) do
    local id = itemIDFromLink(GetQuestItemLink("reward", i))
    if id then table.insert(q.rewards, id) end
  end
  for i = 1, (GetNumQuestChoices and GetNumQuestChoices() or 0) do
    local id = itemIDFromLink(GetQuestItemLink("choice", i))
    if id then table.insert(q.choices, id) end
  end
  q.done = now()
  c.quests[questID] = q
  ns.collectLast.quest = questID
  return q
end

-- Quest ids the shipped data already knows (item uses and dungeon lists), for the "new quest" line.
local known
function ns.IsKnownQuest(questID)
  if not known then
    known = {}
    for _, entries in pairs(ns.Quests or {}) do
      for _, e in ipairs(entries) do known[e[1]] = true end
    end
    for _, d in ipairs(ns.Dungeons or {}) do
      for _, q in ipairs(d.quests) do known[q.id] = true end
    end
    for id in pairs((ns.Observed and ns.Observed.quests) or {}) do known[id] = true end
  end
  return known[questID] == true
end

------------------------------------------------------------------------------
-- NPCs seen, loot sources, vendors
------------------------------------------------------------------------------
function ns.CollectUnit(tooltip, data)
  if not enabled() then return nil end
  local id = npcIDFromGUID(data and data.guid)
  if not id then return nil end
  local c = store()
  if c.npcs[id] then return c.npcs[id] end
  local title = _G[tooltip:GetName() .. "TextLeft1"]
  local rec = ns.PlayerPosition()
  rec.name = title and title:GetText() or nil
  c.npcs[id] = rec
  return rec
end

local function sourceKey(guid)
  local npc = npcIDFromGUID(guid)
  if npc then return "npc:" .. npc end
  local obj = objectIDFromGUID(guid)
  return obj and ("obj:" .. obj) or nil
end

-- isFromItem: LOOT_OPENED's second argument (a clam, a lockbox); such loot has no creature source.
function ns.CollectLoot(isFromItem)
  if not enabled() or not GetNumLootItems then return nil end
  local c = store()
  local recorded = 0
  -- Without GetLootSourceInfo, the looted corpse is the dead target, the dead soft-interact
  -- target (the interact key), or the dead mob under the mouse (right-click looting).
  local fallback
  if not GetLootSourceInfo and not isFromItem and UnitIsDead then
    for _, unit in ipairs({ "target", "softinteract", "mouseover" }) do
      if public(UnitIsDead(unit)) then
        fallback = sourceKey(UnitGUID(unit))
        if fallback then break end
      end
    end
  end
  local function add(key, itemID, qty, guessed)
    local src = c.loot[key] or { items = {} }
    src.items[itemID] = (src.items[itemID] or 0) + (qty or 1)
    src.zone = src.zone or (GetZoneText and GetZoneText())
    if guessed then src.fromTarget = true end
    c.loot[key] = src
    ns.collectLast.loot = key
    recorded = recorded + 1
  end
  for slot = 1, GetNumLootItems() do
    local itemID = itemIDFromLink(GetLootSlotLink(slot))
    if itemID and GetLootSourceInfo then
      local sources = { GetLootSourceInfo(slot) }
      for i = 1, #sources, 2 do
        local key = sourceKey(sources[i])
        if key then add(key, itemID, sources[i + 1]) end
      end
    elseif itemID and fallback then
      local qty = GetLootSlotInfo and select(3, GetLootSlotInfo(slot)) or 1
      add(fallback, itemID, qty, true)
    end
  end
  if recorded > 0 then noticed(c) end
  return recorded
end

function ns.CollectVendor()
  if not enabled() then return nil end
  local npc = unitRecord("npc")
  if not npc then return nil end
  local c = store()
  local v = c.vendors[npc.id] or { items = {} }
  v.name = npc.name
  v.repair = CanMerchantRepair and CanMerchantRepair() and true or false
  local where = ns.PlayerPosition()
  v.zone, v.map, v.x, v.y = where.zone, where.map, where.x, where.y
  local n = GetMerchantNumItems and GetMerchantNumItems() or 0
  for i = 1, n do
    local itemID = itemIDFromLink(GetMerchantItemLink(i))
    if itemID then
      local price
      if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(i)
        price = info and info.price
      elseif GetMerchantItemInfo then
        local _, _, p = GetMerchantItemInfo(i)
        price = p
      end
      v.items[itemID] = price or v.items[itemID] or 0
    end
  end
  c.vendors[npc.id] = v
  ns.collectLast.vendor = npc.id
  noticed(c)
  return v
end

------------------------------------------------------------------------------
-- Talents: the tree as the client reports it, and the order points were spent in
------------------------------------------------------------------------------
local function talentSnapshot()
  if not (GetNumTalentTabs and GetTalentInfo and GetNumTalents) then return nil end
  local tabs = {}
  for tab = 1, GetNumTalentTabs() do
    local name = GetTalentTabInfo and GetTalentTabInfo(tab) or ("tab " .. tab)
    local list = {}
    for i = 1, GetNumTalents(tab) do
      local tname, icon, tier, column, rank, maxRank = GetTalentInfo(tab, i)
      if tname then list[i] = { name = tname, tier = tier, column = column, rank = rank or 0, maxRank = maxRank, icon = icon } end
    end
    tabs[tab] = { name = name, talents = list }
  end
  return tabs
end

-- Forever: talents are a trait tree. The active spec group's combat config holds one tree whose
-- groups are the class's three talent trees (the same calls Blizzard's Forever talent frame makes).
local function traitSnapshot()
  if not (C_Traits and C_Traits.GetConfigInfo and C_Traits.GetTreeNodes and C_Traits.GetNodeInfo) then return nil end
  local configID
  if C_SpecializationInfo and C_SpecializationInfo.GetCombatConfigIDForSpecGroup and C_SpecializationInfo.GetActiveSpecGroup then
    configID = C_SpecializationInfo.GetCombatConfigIDForSpecGroup(C_SpecializationInfo.GetActiveSpecGroup())
  end
  if not configID and C_ClassTalents and C_ClassTalents.GetActiveConfigID then configID = C_ClassTalents.GetActiveConfigID() end
  if not configID then return nil end
  local config = C_Traits.GetConfigInfo(configID)
  if not (config and config.treeIDs and config.treeIDs[1]) then return nil end
  local tabs, byGroup = {}, {}
  for _, treeID in ipairs(config.treeIDs) do
    local displays = {}
    for _, d in ipairs((C_Traits.GetGroupDisplayInfoByTreeID and C_Traits.GetGroupDisplayInfoByTreeID(treeID)) or {}) do
      table.insert(displays, d)
    end
    table.sort(displays, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
    for _, d in ipairs(displays) do
      local tab = { name = d.displayName, group = d.groupID, talents = {} }
      table.insert(tabs, tab)
      byGroup[d.groupID] = tab
    end
    for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
      local node = C_Traits.GetNodeInfo(configID, nodeID)
      if node and node.ID and node.ID ~= 0 and node.isVisible ~= false then
        local tab
        for _, g in ipairs(node.groupIDs or {}) do
          if byGroup[g] then tab = byGroup[g]; break end
        end
        if not tab then
          if not byGroup.other then
            byGroup.other = { name = "Other", talents = {} }
            table.insert(tabs, byGroup.other)
          end
          tab = byGroup.other
        end
        local entryID = (node.activeEntry and node.activeEntry.entryID) or (node.entryIDs and node.entryIDs[1])
        local name, spellID
        local entry = entryID and C_Traits.GetEntryInfo and C_Traits.GetEntryInfo(configID, entryID)
        local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo and C_Traits.GetDefinitionInfo(entry.definitionID)
        if def then
          spellID = def.spellID
          if def.overrideName and def.overrideName ~= "" then name = def.overrideName end
          if not name and spellID and C_Spell and C_Spell.GetSpellName then name = C_Spell.GetSpellName(spellID) end
        end
        tab.talents[nodeID] = { name = name or ("node " .. nodeID), tier = node.posY, column = node.posX,
          rank = node.activeRank or node.ranksPurchased or 0, maxRank = node.maxRanks, spell = spellID, node = nodeID }
      end
    end
  end
  return tabs, configID
end

function ns.CollectTalents()
  if not enabled() then return nil end
  local tabs, configID = talentSnapshot()
  if not tabs or #tabs == 0 then tabs, configID = traitSnapshot() end
  if not tabs or #tabs == 0 then return nil end
  local c = store()
  local key = ns.CharacterKey()
  local _, classToken = UnitClass("player")
  local rec = c.talents[key] or { class = classToken, order = {} }
  local previous = rec.tabs
  -- A different config is the other spec group, not points spent: take a new baseline.
  if rec.configID ~= configID then previous = nil end
  local level = UnitLevel("player")
  local spent = 0
  if previous then
    for tab, t in ipairs(tabs) do
      for i, talent in pairs(t.talents) do
        local before = previous[tab] and previous[tab].talents[i]
        local oldRank = before and before.rank or 0
        for r = oldRank + 1, talent.rank do
          table.insert(rec.order, { level = level, tab = tab, index = i, name = talent.name, rank = r })
          spent = spent + 1
        end
      end
    end
  end
  rec.tabs, rec.level, rec.class, rec.configID = tabs, level, classToken, configID
  c.talents[key] = rec
  return rec, spent
end

------------------------------------------------------------------------------
-- Reports: "this is wrong", with the context captured automatically
------------------------------------------------------------------------------
function ns.CollectReport(text)
  local c = store()
  if not c then return nil end
  local r = { time = now(), char = ns.CharacterKey(), text = text, where = ns.PlayerPosition() }
  r.target = unitRecord("target")
  if GameTooltip and GameTooltip.GetItem and GameTooltip:IsShown() then
    local _, link = GameTooltip:GetItem()
    r.item = link
  end
  local ids = {}
  for i = 1, ns.NumQuestLogEntries() do
    local _, isHeader, id = ns.QuestLogEntry(i)
    if not isHeader and id and id ~= 0 then table.insert(ids, id) end
  end
  r.quests = ids
  if MerchantFrame and MerchantFrame:IsShown() then r.window = "merchant" end
  table.insert(c.reports, r)
  return r
end

------------------------------------------------------------------------------
-- Observed data (Data/Observed.lua, merged from players' files) on top of the generated data
------------------------------------------------------------------------------
-- Adds quest items the generated data does not know. Entry shape follows Data/Quests.lua:
-- { questID, name, kind, repeatable, faction, classMask, rep }; faction false = either side.
function ns.ApplyObserved()
  local observed = ns.Observed
  if not observed then return 0 end
  ns.Quests = ns.Quests or {}
  local added = 0
  for itemID, entries in pairs(observed.questItems or {}) do
    local list = ns.Quests[itemID]
    if not list then list = {}; ns.Quests[itemID] = list end
    for _, e in ipairs(entries) do
      local present = false
      for _, have in ipairs(list) do if have[1] == e[1] then present = true; break end end
      if not present then
        table.insert(list, { e[1], e[2], "objective", false, false, 0, false })
        added = added + 1
      end
    end
  end
  known = nil -- the known-quest set must include what was just added
  return added
end
ns.ApplyObserved()

------------------------------------------------------------------------------
-- Counts, slash commands, events
------------------------------------------------------------------------------
local function count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end

function ns.CollectedCounts()
  local c = store()
  if not c then return nil end
  return { items = count(c.items), quests = count(c.quests), npcs = count(c.npcs), loot = count(c.loot),
           vendors = count(c.vendors), talents = count(c.talents), reports = #c.reports }
end

function ns.CollectedSummary()
  local n = ns.CollectedCounts()
  if not n then return "nothing recorded yet (settings not loaded)" end
  return ("recorded so far: %d items, %d quests, %d NPCs, %d loot sources, %d vendors, %d characters' talents, %d reports"):format(
    n.items, n.quests, n.npcs, n.loot, n.vendors, n.talents, n.reports)
end

------------------------------------------------------------------------------
-- /fb collect check: is recording working on this client, right now?
------------------------------------------------------------------------------
local function resolve(path)
  local v = _G
  for part in path:gmatch("[^%.]+") do
    if type(v) ~= "table" then return nil end
    v = v[part]
  end
  return v
end

-- Each group: what it records, and the client functions it needs (any one of an "a|b" pair is enough).
ns.COLLECT_APIS = {
  { "items", { "TooltipDataProcessor.AddTooltipPostCall", "C_Item.GetItemInfo" } },
  { "item stats", { "C_Item.GetItemStats|GetItemStats" } },
  { "quests", { "GetQuestID", "GetTitleText", "C_QuestLog.GetQuestObjectives" } },
  { "quest givers", { "UnitGUID", "UnitName" } },
  { "quest XP and rewards", { "GetRewardXP", "GetRewardMoney", "GetNumQuestRewards", "GetQuestItemLink" } },
  { "shareable flag", { "C_QuestLog.IsPushableQuest" } },
  { "positions", { "C_Map.GetBestMapForUnit", "C_Map.GetPlayerMapPosition" } },
  { "loot sources", { "GetNumLootItems", "GetLootSlotLink", "GetLootSourceInfo|UnitIsDead" } },
  { "vendors", { "GetMerchantNumItems", "GetMerchantItemLink", "C_MerchantFrame.GetItemInfo|GetMerchantItemInfo" } },
  -- Classic talent functions (Era) or the trait tree (Forever); each "a|b" pair is one path or the other.
  { "talent order", { "GetNumTalentTabs|C_Traits.GetTreeNodes", "GetTalentInfo|C_Traits.GetNodeInfo", "GetNumTalents|C_Traits.GetConfigInfo" } },
}

function ns.MissingCollectAPIs()
  local missing = {}
  for _, group in ipairs(ns.COLLECT_APIS) do
    local absent = {}
    for _, need in ipairs(group[2]) do
      local found = false
      for alt in need:gmatch("[^|]+") do
        if type(resolve(alt)) == "function" then found = true end
      end
      if not found then table.insert(absent, need) end
    end
    if #absent > 0 then table.insert(missing, { what = group[1], apis = absent }) end
  end
  return missing
end

local function latest(t, fields)
  local bestKey, bestTime
  for key, rec in pairs(t or {}) do
    local stamp = 0
    for _, f in ipairs(fields) do stamp = math.max(stamp, tonumber(rec[f]) or 0) end
    if not bestTime or stamp > bestTime then bestKey, bestTime = key, stamp end
  end
  return bestKey
end

local function anyKey(t) return (next(t or {})) end

local function yesno(v) if v == nil then return "?" end return v and "yes" or "no" end

-- Returns the lines to print, and a result: "working", "problems" or "untested".
function ns.CollectCheck()
  local lines, problems, untested = {}, {}, {}
  local function add(s) table.insert(lines, s) end
  local client = ns.ClientInfo() or {}
  add(("client %s build %s, interface %s. Recording is %s."):format(tostring(client.version), tostring(client.build),
    tostring(client.interface), ns.IsFeatureEnabled("collect") and "ON" or "OFF"))
  if not ns.IsFeatureEnabled("collect") then table.insert(problems, "recording is off (/fb collect on)") end
  local c = store()
  if not c then
    add("RESULT: settings are not loaded, so nothing can be recorded. Is the addon folder named ForeverBuddy?")
    return lines, "problems"
  end
  if ns.savedLoaded then
    add("saved file: loaded at login with " .. tostring(ns.savedSummary) .. ".")
  else
    add("saved file: NOT loaded at login. If you had settings or recorded data before, the game is")
    add("saved file: not reading WTF/Account/<account>/SavedVariables/ForeverBuddy.lua. Everything starts fresh each time.")
    table.insert(problems, "the saved file was not loaded at login")
  end

  local missing = ns.MissingCollectAPIs()
  if #missing == 0 then
    add("APIs: everything the recorder uses exists on this client.")
  else
    for _, m in ipairs(missing) do
      add(("APIs: MISSING %s, so %s will not be recorded."):format((table.concat(m.apis, ", "):gsub("|", " or ")), m.what))
      if m.what ~= "talent order" and m.what ~= "shareable flag" then table.insert(problems, "no " .. m.what) end
    end
  end

  local itemID = ns.collectLast.item or latest(c.items, { "seen" })
  local item = itemID and c.items[itemID]
  if item then
    add(("item OK: %s (%s), stats %s, sell price %s."):format(tostring(item.name), tostring(itemID), item.stats and "yes" or "none", tostring(item.sell)))
  else
    add("item: nothing yet. Hover any item in your bags.")
    table.insert(untested, "items")
  end

  local questID = ns.collectLast.quest or latest(c.quests, { "offered", "accepted", "done" })
  local q = questID and c.quests[questID]
  if q then
    local issues = {}
    if not q.title then table.insert(issues, "no title") end
    if not q.accepted then table.insert(issues, "not accepted yet") end
    if q.accepted and not q.level then table.insert(issues, "no level") end
    if not (q.where and q.where.zone) then table.insert(issues, "no place") end
    local giver = q.giver and ("%s (%s%s)"):format(tostring(q.giver.name), q.giver.object and "object " or "", tostring(q.giver.id)) or "none"
    local place = q.where and ("%s %s, %s"):format(tostring(q.where.zone), tostring(q.where.x), tostring(q.where.y)) or "none"
    add(("quest %s: %s (%s): giver %s at %s, level %s, xp %s, shareable %s, %d objectives, handed in %s."):format(
      #issues == 0 and "OK" or "PROBLEM", tostring(q.title), tostring(questID), giver, place, tostring(q.level), tostring(q.xp),
      yesno(q.shareable), q.objectives and #q.objectives or 0, q.done and "yes" or "not yet"))
    if not q.giver then add("quest note: no giver recorded. That is expected only if the quest started from an item.") end
    for _, i in ipairs(issues) do
      if i ~= "not accepted yet" then table.insert(problems, "quest " .. i) end
    end
    if not q.accepted then table.insert(untested, "accepting a quest") end
  else
    add("quest: nothing yet. Talk to a quest giver and accept a quest.")
    table.insert(untested, "quests")
  end

  local lootKey = ns.collectLast.loot or anyKey(c.loot)
  if lootKey then
    local n = 0
    for _ in pairs(c.loot[lootKey].items) do n = n + 1 end
    add(("loot OK: %d item%s from %s%s."):format(n, n == 1 and "" or "s", lootKey,
      c.loot[lootKey].fromTarget and " (credited to the dead mob you looted, this client has no loot-source function)" or ""))
  else
    add("loot: nothing yet. Kill a mob and loot it.")
    table.insert(untested, "loot")
  end

  local vendorID = ns.collectLast.vendor or anyKey(c.vendors)
  if vendorID then
    local v, n = c.vendors[vendorID], 0
    for _ in pairs(v.items) do n = n + 1 end
    add(("vendor OK: %s (%s), %d items, repairs %s."):format(tostring(v.name), tostring(vendorID), n, yesno(v.repair)))
  else
    add("vendor: nothing yet. Open any vendor.")
    table.insert(untested, "vendors")
  end

  local t = c.talents[ns.CharacterKey()]
  if t and t.tabs then
    local n = 0
    for _, tab in ipairs(t.tabs) do for _ in pairs(tab.talents) do n = n + 1 end end
    add(("talents OK: %d trees, %d talents read, %d points logged."):format(#t.tabs, n, #(t.order or {})))
  else
    add("talents: nothing read yet. They are read at login and whenever a point is spent; below level 10 there is nothing to read.")
  end

  local errorCount = 0
  for where, e in pairs(c.errors) do
    errorCount = errorCount + 1
    if errorCount <= 3 then add(("ERROR in %s (x%d): %s"):format(where, e.count, tostring(e.msg))) end
    table.insert(problems, "errors in " .. where)
  end
  if errorCount == 0 then add("errors: none.") end

  local result
  if #problems > 0 then
    result = "problems"
    add("RESULT: PROBLEMS: " .. table.concat(problems, "; ") .. ". Screenshot these lines and send them.")
  elseif #untested == 4 then
    result = "untested"
    add("RESULT: nothing recorded yet. Hover an item and accept a quest, then run /fb collect check again.")
  else
    result = "working"
    add("RESULT: WORKING." .. (#untested > 0 and (" Not tested yet: " .. table.concat(untested, ", ") .. ".") or " Everything tested."))
  end
  return lines, result
end

ns.SlashHandlers.collect = function(rest)
  rest = (rest or ""):match("^%s*(.-)%s*$")
  if rest == "on" or rest == "off" then
    ns.SetFeatureEnabled("collect", rest == "on")
    ns.Print("data recording " .. (rest == "on" and "on" or "off"))
    return
  end
  if rest == "stats" then
    ns.Print(ns.CollectedSummary())
    return
  end
  if rest == "check" then
    for _, line in ipairs((ns.CollectCheck())) do ns.Print("check: " .. line) end
    return
  end
  for _, line in ipairs(ns.COLLECT_EXPLAINER) do ns.Print(line) end
  ns.Print(("It is currently %s. %s"):format(ns.IsFeatureEnabled("collect") and "ON" or "OFF", ns.CollectedSummary()))
end

ns.SlashHandlers.report = function(rest)
  rest = (rest or ""):match("^%s*(.-)%s*$")
  if rest == "" then
    ns.Print("usage: /fb report <what is wrong>  (target the NPC or hover the item first; the place, your quests and the target are saved with it)")
    return
  end
  local r = ns.CollectReport(rest)
  if not r then
    ns.Print("settings are not loaded yet")
    return
  end
  local bits = {}
  if r.target then table.insert(bits, "target " .. tostring(r.target.name)) end
  if r.item then table.insert(bits, "item " .. r.item) end
  if r.where and r.where.zone then table.insert(bits, r.where.zone) end
  ns.Print(("report saved%s. Thank you."):format(#bits > 0 and (" with " .. table.concat(bits, ", ")) or ""))
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
  local ok, err = pcall(ns.CollectItem, tooltip, data)
  if not ok then ns.CollectError("item tooltip", err) end
end)
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
  local ok, err = pcall(ns.CollectUnit, tooltip, data)
  if not ok then ns.CollectError("unit tooltip", err) end
end)

local events = CreateFrame("Frame")
local handlers = {
  QUEST_DETAIL = function() ns.CollectQuestDetail() end,
  GOSSIP_SHOW = function() ns.RememberQuestNpc() end,
  QUEST_GREETING = function() ns.RememberQuestNpc() end,
  QUEST_PROGRESS = function() ns.RememberQuestNpc() end,
  QUEST_ACCEPTED = function(a, b) ns.CollectQuestAccepted(type(b) == "number" and b or a) end, -- Classic passes (logIndex, questID); Mainline passes (questID)
  QUEST_COMPLETE = function() ns.CollectQuestComplete() end,
  QUEST_TURNED_IN = function(questID, xpReward, moneyReward) ns.CollectQuestTurnedIn(questID, xpReward, moneyReward) end,
  LOOT_OPENED = function(_, isFromItem) ns.CollectLoot(isFromItem) end,
  MERCHANT_SHOW = function() ns.CollectVendor() end,
  PLAYER_ENTERING_WORLD = function() ns.CollectTalents() end,
  CHARACTER_POINTS_CHANGED = function() ns.CollectTalents() end,
  PLAYER_TALENT_UPDATE = function() ns.CollectTalents() end,
  TRAIT_CONFIG_UPDATED = function() ns.CollectTalents() end,
  ACTIVE_COMBAT_CONFIG_CHANGED = function() ns.CollectTalents() end,
}
for event in pairs(handlers) do events:RegisterEvent(event) end
events:SetScript("OnEvent", function(_, event, ...)
  local ok, err = pcall(handlers[event], ...)
  if not ok then ns.CollectError(event, err) end
end)
