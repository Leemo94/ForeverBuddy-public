local _, ns = ...

-- The data and rules behind the dungeon journal: which quests belong to a dungeon, whether they
-- can be shared, and where an arrow should point. The window itself is UI/Journal.lua.
-- Data from Data/Dungeons.lua (tools/build_dungeons.py); quest status is live from the quest log.

ns.Dungeons = ns.Dungeons or {}

ns.SHARE_TEXT = { yes = "Shareable", chain = "Not shareable (chain)", single = "Not shareable" }

local CLASS_NAMES = {
  [1] = "Warrior", [2] = "Paladin", [4] = "Hunter", [8] = "Rogue", [16] = "Priest",
  [64] = "Shaman", [128] = "Mage", [256] = "Warlock", [1024] = "Druid",
}
local CLASS_ORDER = { 1, 2, 4, 8, 16, 64, 128, 256, 1024 }

function ns.ClassListText(mask)
  local names = {}
  for _, b in ipairs(CLASS_ORDER) do
    if bit.band(mask, b) ~= 0 then table.insert(names, CLASS_NAMES[b]) end
  end
  return table.concat(names, "/")
end

-- Faction and class limits against this character.
function ns.CanTakeQuest(q)
  local mine = UnitFactionGroup("player")
  if q.faction and mine and q.faction ~= mine then return false end
  if q.classes and q.classes ~= 0 then
    local _, token = UnitClass("player")
    local classBit = ns.CLASS_BITS[token]
    if classBit and bit.band(q.classes, classBit) == 0 then return false end
  end
  return true
end

-- The shipped share flag comes from Classic data and Forever changes some of them. Trust the
-- client for a quest in your log, then what players have recorded, then the shipped flag.
function ns.QuestShareText(q)
  local shareable
  if q.id and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(q.id) and C_QuestLog.IsPushableQuest then
    local ok, live = pcall(C_QuestLog.IsPushableQuest, q.id)
    if ok and type(live) == "boolean" then shareable = live end
  end
  if shareable == nil then
    local observed = ns.Observed and ns.Observed.quests and ns.Observed.quests[q.id]
    if observed and type(observed.shareable) == "boolean" then shareable = observed.shareable end
  end
  if shareable == nil then return ns.SHARE_TEXT[q.share] or ns.SHARE_TEXT.single end
  if shareable then return ns.SHARE_TEXT.yes end
  return q.share == "chain" and ns.SHARE_TEXT.chain or ns.SHARE_TEXT.single
end

function ns.DungeonQuestStatus(q)
  return (ns.GetQuestStatus(q.id, q.repeatable, nil))
end

local function normalize(s) return (tostring(s or ""):lower():gsub("[^%a]", "")) end

-- Matches a key, an alias, or part of the name: "rfc", "ragefire", "dead", "Scarlet Monastery".
function ns.FindDungeon(text)
  local want = normalize(text)
  if want == "" then return nil end
  for _, d in ipairs(ns.Dungeons) do
    if d.key == want then return d end
    for _, a in ipairs(d.aliases or {}) do
      if normalize(a) == want then return d end
    end
  end
  for _, d in ipairs(ns.Dungeons) do
    if normalize(d.name):find(want, 1, true) then return d end
  end
  return nil
end

local function distance(d, level)
  local lo, hi = d.level[1], d.level[2]
  return (level < lo and lo - level) or (level > hi and level - hi) or 0
end

local function open_to(d, faction)
  return not d.faction or not faction or d.faction == faction
end

-- The dungeon whose level band fits best; ties go to the band centred nearest the level.
function ns.DungeonForLevel(level, faction)
  local best, bestDist, bestCentre
  for _, d in ipairs(ns.Dungeons) do
    if open_to(d, faction) then
      local dist = distance(d, level)
      local centre = math.abs((d.level[1] + d.level[2]) / 2 - level)
      if not best or dist < bestDist or (dist == bestDist and centre < bestCentre) then
        best, bestDist, bestCentre = d, dist, centre
      end
    end
  end
  return best
end

-- Every dungeon within two levels of the band, in list order.
function ns.DungeonsForLevel(level, faction)
  local out = {}
  for _, d in ipairs(ns.Dungeons) do
    if open_to(d, faction) and distance(d, level) <= 2 then table.insert(out, d) end
  end
  return out
end

function ns.PlaceText(p)
  if not p then return nil end
  if p.kind == "item" then return "item: " .. p.name end
  local s = p.name
  if p.where then
    s = s .. ", " .. p.where
    if p.x and p.y then s = s .. (" (%.1f, %.1f)"):format(p.x, p.y) end
  end
  return s
end

-- "Hidden Enemies (2 parts) from Thrall, Orgrimmar (32, 38), then ..." with same-named parts collapsed.
function ns.ChainText(pre)
  if not pre or #pre == 0 then return nil end
  local parts, i = {}, 1
  while i <= #pre do
    local j = i
    while j < #pre and pre[j + 1].name == pre[i].name do j = j + 1 end
    local label = pre[i].name
    if j > i then label = ("%s (%d parts)"):format(label, j - i + 1) end
    local from = ns.PlaceText(pre[i].giver)
    if from then label = label .. " from " .. from end
    table.insert(parts, label)
    i = j + 1
  end
  return table.concat(parts, ", then ")
end

local STATUS_WORD = { active = "in your log", done = "done", repeatable = "repeatable" }

-- Returns the title line and an array of detail lines for one quest row.
function ns.DungeonQuestLines(q, status)
  local title = ("[%d] %s"):format(q.level, q.name)
  if q.classes and q.classes ~= 0 then title = title .. (" (%s)"):format(ns.ClassListText(q.classes)) end
  if STATUS_WORD[status] then title = title .. " - " .. STATUS_WORD[status] end
  local details = { ns.QuestShareText(q) }
  if q.giver and q.giver.kind == "item" then
    table.insert(details, "Starts from " .. ns.PlaceText(q.giver))
  elseif q.giver then
    table.insert(details, "Pick up: " .. ns.PlaceText(q.giver))
  end
  local chain = ns.ChainText(q.pre)
  if chain then table.insert(details, "Before it: " .. chain) end
  if q.turnin and q.giver and (q.turnin.name ~= q.giver.name or q.turnin.where ~= q.giver.where) then
    table.insert(details, "Turn in: " .. ns.PlaceText(q.turnin))
  elseif q.turnin and not q.giver then
    table.insert(details, "Turn in: " .. ns.PlaceText(q.turnin))
  end
  return title, details
end

-- Where the arrow should point for a quest row: the earliest prerequisite still to do, the
-- turn-in when the quest is already in the log, otherwise the giver.
function ns.DungeonQuestTarget(q, status)
  for _, step in ipairs(q.pre or {}) do
    if not C_QuestLog.IsQuestFlaggedCompleted(step.id) and not C_QuestLog.IsOnQuest(step.id) then
      local g = step.giver
      if g and g.kind ~= "item" and g.map and g.x and g.y then
        return g.map, g.x, g.y, ("%s (needed first): %s"):format(step.name, g.name)
      end
      return nil, ("%s comes first, and its giver has no known place"):format(step.name)
    end
  end
  local p = status == "active" and q.turnin or q.giver
  if not p then return nil, "no known place for this quest" end
  if p.kind == "item" then return nil, "it starts from an item: " .. p.name end
  if not (p.map and p.x and p.y) then return nil, ("%s has no known position"):format(p.name) end
  return p.map, p.x, p.y, ("%s: %s%s"):format(q.name, status == "active" and "hand in to " or "", p.name)
end

function ns.DungeonRowClicked(row)
  if not row or not row.quest then return nil end
  local mapID, x, y, title = ns.DungeonQuestTarget(row.quest, row.status)
  if not mapID then
    ns.Print(x)
    return nil
  end
  ns.SetWaypoint(mapID, x, y, title)
  ns.Print("arrow set: " .. title)
  return title
end

ns.SlashHandlers.dungeon = function(rest)
  rest = (rest or ""):match("^%s*(.-)%s*$")
  local faction, level = UnitFactionGroup("player"), UnitLevel("player")
  if rest == "list" then
    local list = ns.DungeonsForLevel(level, faction)
    if #list == 0 then
      ns.Print(("no dungeon fits level %d"):format(level))
      return
    end
    ns.Print(("Dungeons around level %d:"):format(level))
    for _, d in ipairs(list) do
      local mine = 0
      for _, q in ipairs(d.quests) do if ns.CanTakeQuest(q) then mine = mine + 1 end end
      ns.Print(("  %s %d-%d, %d quests you can take (/fb dungeon %s)"):format(d.name, d.level[1], d.level[2], mine, d.aliases[1] or d.key))
    end
    return
  end
  local d
  if rest ~= "" then
    d = ns.FindDungeon(rest)
    if not d then
      ns.Print(("no dungeon called '%s'. /fb dungeon list shows the ones for your level."):format(rest))
      return
    end
  else
    d = ns.DungeonForLevel(level, faction)
  end
  ns.ShowWindow("journal", d)
end
