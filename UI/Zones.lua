local ADDON, ns = ...

-- Where to level: bands of five levels down the left, and the one you are in opened on the
-- right, with the zones to quest in and the dungeons to run in them. The shape is Blizzard's
-- own quest log, so nobody has to be taught it, and the colours are the game's own quest
-- difficulty colours, which every player reads without being told: yellow is now, grey is
-- behind you, red is too soon.

local BAND = 5
-- Thirteen cards have to fit between the advice panel and the bottom of the window without a
-- scrollbar of their own: 6 + 13 x (32 + 3) - 3 = 458, against the 488 the page leaves.
local RAIL_W, RAIL_ROW_H, RAIL_GAP = 170, 32, 3
local ROW_H, HEAD_H = 24, 30
local DETAIL_X = RAIL_W + 18
local COL_LEVELS, COL_WHERE, COL_LAST = 300, 380, 520
local TOP = -84

-- Shared with the tests, which check the rail still fits when somebody changes a font.
ns.RAIL_METRICS = { width = RAIL_W, height = RAIL_ROW_H, gap = RAIL_GAP, top = TOP, pad = 6 }

local DUNGEON_ICON = "Interface\\LFGFrame\\LFGIcon-Dungeon"
local FACTION_ICON = {
  Alliance = "Interface\\TargetingFrame\\UI-PVP-Alliance",
  Horde = "Interface\\TargetingFrame\\UI-PVP-Horde",
}

-- The continents, found by walking up from wherever the player is, with the usual two as a
-- fallback so the list still fills in before you have moved.
function ns.ContinentMaps()
  local found, order = {}, {}
  local function add(id)
    if id and not found[id] then
      found[id] = true
      table.insert(order, id)
    end
  end
  if C_Map and C_Map.GetMapInfo and C_Map.GetBestMapForUnit then
    local mapID = C_Map.GetBestMapForUnit("player")
    local guard = 0
    while mapID and guard < 10 do
      guard = guard + 1
      local info = C_Map.GetMapInfo(mapID)
      if not info then break end
      if info.mapType == (Enum.UIMapType and Enum.UIMapType.Continent) then add(mapID) break end
      mapID = info.parentMapID
    end
  end
  for _, id in ipairs({ 1414, 1415 }) do add(id) end -- Kalimdor, Eastern Kingdoms
  return order
end

-- The map a named zone sits on. GetMapChildrenInfo with no type wanted also turns up the ones
-- that are not plain zones, which is how Blackrock Mountain is found.
function ns.FindZoneMap(name)
  if not (C_Map and C_Map.GetMapChildrenInfo and name) then return nil end
  local wanted = name:lower()
  for _, continent in ipairs(ns.ContinentMaps()) do
    for _, child in ipairs(C_Map.GetMapChildrenInfo(continent) or {}) do
      if child.name and child.name:lower() == wanted then return child.mapID, continent end
    end
  end
  return nil
end

-- Every zone we know, grouped by continent: the client's own map tree first, then anything in
-- our data it did not hand us, so Blackrock Mountain joins Eastern Kingdoms like the rest.
function ns.ZoneList()
  local order, groups, seen = {}, {}, {}
  local function group(name)
    local g = groups[name]
    if not g then
      g = { continent = name, zones = {} }
      groups[name] = g
      table.insert(order, g)
    end
    return g
  end
  for _, continent in ipairs(ns.ContinentMaps()) do
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(continent)
    local zones = ns.ZonesOnMap(continent)
    if #zones > 0 then
      local g = group((info and info.name) or ("Map " .. continent))
      for _, z in ipairs(zones) do
        seen[z.name:lower()] = true
        table.insert(g.zones, z)
      end
    end
  end
  for _, z in ipairs(ns.Zones or {}) do
    if not seen[z.name:lower()] then
      local mapID, parent = ns.FindZoneMap(z.name)
      table.insert(group(z.continent or "?").zones,
        { name = z.name, min = z.level[1], max = z.level[2], source = z.source or "quests", continent = z.continent,
          mapID = mapID, parent = parent, faction = z.faction or nil, leaning = z.leaning == true,
          alliance = z.alliance or 0, horde = z.horde or 0, quests = z.quests or 0 })
    end
  end
  for _, g in ipairs(order) do
    table.sort(g.zones, function(a, b)
      if a.min ~= b.min then return a.min < b.min end
      if a.max ~= b.max then return a.max < b.max end
      return a.name < b.name
    end)
  end
  return order
end

-- The same zones in one flat list, lowest first, each carrying its continent's name.
function ns.AllZones()
  local out = {}
  for _, group in ipairs(ns.ZoneList()) do
    for _, zone in ipairs(group.zones) do
      zone.continent = zone.continent or group.continent
      table.insert(out, zone)
    end
  end
  table.sort(out, function(a, b)
    if a.min ~= b.min then return a.min < b.min end
    return a.name < b.name
  end)
  return out
end

------------------------------------------------------------------------------
-- The bands
------------------------------------------------------------------------------

-- A zone wholly one side's is no use to the other: nothing stops a Night Elf questing in
-- Durotar, but there is nothing there for them. One that only leans stays on both lists.
local function ZoneOpenTo(zone, faction)
  if not (zone.faction and faction) then return true end
  if zone.leaning then return true end
  return zone.faction == faction
end
ns.ZoneOpenTo = ZoneOpenTo

-- { { lo, hi, zones = {}, dungeons = {} }, ... } in level order, and last of all the dungeons
-- Forever has built but not tuned, which have no level to sit at.
function ns.LevelBands(faction)
  local zones, bands = ns.AllZones(), {}
  for lo = 1, 60, BAND do
    local hi = math.min(lo + BAND - 1, 60)
    local band = { lo = lo, hi = hi, zones = {}, dungeons = {} }
    for _, zone in ipairs(zones) do
      if zone.min <= hi and zone.max >= lo and ZoneOpenTo(zone, faction) then
        table.insert(band.zones, zone)
      end
    end
    for _, dungeon in ipairs(ns.Dungeons or {}) do
      local dlo, dhi = ns.DungeonLevels(dungeon)
      if dlo and dlo <= hi and (dhi or dlo) >= lo then table.insert(band.dungeons, dungeon) end
    end
    table.insert(bands, band)
  end
  local untuned = {}
  for _, dungeon in ipairs(ns.Dungeons or {}) do
    if not ns.DungeonLevels(dungeon) then table.insert(untuned, dungeon) end
  end
  if #untuned > 0 then
    table.insert(bands, { lo = false, hi = false, zones = {}, dungeons = untuned })
  end
  return bands
end

function ns.BandIndexFor(bands, level)
  for index, band in ipairs(bands) do
    if band.lo and level >= band.lo and level <= band.hi then return index end
  end
  return 1
end

-- The game's own quest difficulty colours, which is the whole trick: a player already knows
-- what yellow and grey mean, and never had to be told.
function ns.DifficultyColor(lo, hi, level)
  if not lo then return ns.DIFFICULTY.grey end
  hi = hi or lo
  if level < lo - 4 then return ns.DIFFICULTY.red end
  if level < lo then return ns.DIFFICULTY.orange end
  if level <= hi - 3 then return ns.DIFFICULTY.yellow end
  if level <= hi then return ns.DIFFICULTY.green end
  return ns.DIFFICULTY.grey
end

-- The sentence somebody came here for: "At 24: quest in Ashenvale or Stonetalon Mountains, run
-- Shadowfang Keep (22-30). Next dungeon: Excavation Site: Wetlands at 26."
function ns.LevellingAdvice(level, faction)
  local function centre(lo, hi) return math.abs((lo + (hi or lo)) / 2 - level) end
  local here = {}
  for _, zone in ipairs(ns.AllZones()) do
    if zone.min <= level and level <= zone.max and ZoneOpenTo(zone, faction) then
      table.insert(here, zone)
    end
  end
  table.sort(here, function(a, b)
    local ca, cb = centre(a.min, a.max), centre(b.min, b.max)
    if ca ~= cb then return ca < cb end
    return (a.quests or 0) > (b.quests or 0)
  end)

  local runs, nextUp
  for _, dungeon in ipairs(ns.Dungeons or {}) do
    local lo, hi = ns.DungeonLevels(dungeon)
    if lo and lo - 2 <= level and level <= (hi or lo) then
      if not runs or centre(lo, hi) < centre(ns.DungeonLevels(runs)) then runs = dungeon end
    elseif lo and lo > level then
      if not nextUp or lo < (ns.DungeonLevels(nextUp)) then nextUp = dungeon end
    end
  end

  local parts = {}
  if here[1] then
    table.insert(parts, here[2] and ("quest in %s or %s"):format(here[1].name, here[2].name)
      or ("quest in %s"):format(here[1].name))
  end
  if runs then
    table.insert(parts, ("run %s (%s)"):format(runs.name, ns.DungeonLevelText(runs, "bare")))
  end
  if #parts == 0 then return ("At %d there is nothing in the data for you yet."):format(level) end
  local text = ("At %d: %s."):format(level, table.concat(parts, ", "))
  if nextUp then
    text = text .. (" Next dungeon: %s at %d."):format(nextUp.name, (ns.DungeonLevels(nextUp)))
  end
  return text
end

------------------------------------------------------------------------------
-- The screen
------------------------------------------------------------------------------

-- Each band is its own little card, like the boss list in the game's dungeon journal: a brown
-- fill, an edge that lights up when it is the one you are looking at, and two lines of text.
local function RailButton(page, index)
  local button = page.rail[index]
  if button then return button end
  button = CreateFrame("Button", nil, page.railPanel)
  button:SetSize(RAIL_W - 12, RAIL_ROW_H)
  button:SetPoint("TOPLEFT", page.railPanel, "TOPLEFT", 6, -6 - (index - 1) * (RAIL_ROW_H + RAIL_GAP))
  button.panel = ns.Panel(button, ns.SKIN.row)
  button.panel:SetAllPoints()
  -- A panel is a frame of its own, and a child frame draws over every layer of its parent, so
  -- the card's own title sat underneath this fill. An unselected card hid it only partly, the
  -- fill being 55% opaque; the selected one is solid, and swallowed the label whole. One level
  -- down puts the background back behind the text that describes it.
  button.panel:SetFrameLevel(math.max(0, (button:GetFrameLevel() or 1) - 1))
  button.title = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ns.SetFontSize(button.title, 13)
  button.title:SetPoint("TOPLEFT", button, "TOPLEFT", 9, -5)
  button.count = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  ns.SetFontSize(button.count, 11)
  button.count:SetPoint("TOPLEFT", button.title, "BOTTOMLEFT", 0, -2)
  button.count:SetTextColor(unpack(ns.SKIN.muted))
  -- Kept so the tests and anything else that asks can still see which band is open.
  button.mark = button:CreateTexture(nil, "ARTWORK")
  button.mark:SetSize(3, RAIL_ROW_H - 10)
  button.mark:SetPoint("LEFT", button, "LEFT", 2, 0)
  button.mark:SetColorTexture(unpack(ns.SKIN.gold))
  button.mark:Hide()
  button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  button:SetScript("OnClick", function(self) ns.SelectBand(page, self.index) end)
  page.rail[index] = button
  return button
end

function ns.MarkRailButton(button, selected)
  if selected then
    button.panel:SetFill(ns.SKIN.selected)
    button.panel:SetEdgeColor(ns.SKIN.borderLit)
    button.mark:Show()
  else
    button.panel:SetFill(ns.SKIN.row)
    button.panel:SetEdgeColor(ns.SKIN.border)
    button.mark:Hide()
  end
  return selected and true or false
end

local function DetailRow(page, index)
  local row = page.rows[index]
  if row then return row end
  row = CreateFrame("Button", nil, page.content)
  row:SetSize(ns.PAGE_WIDTH - DETAIL_X - 42, ROW_H)
  row.stripe = row:CreateTexture(nil, "BACKGROUND")
  row.stripe:SetAllPoints()
  row.stripe:SetColorTexture(unpack(ns.SKIN.row))
  row.stripe:Hide()
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(16, 16)
  row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)
  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ns.SetFontSize(row.name, 14)
  row.name:SetPoint("LEFT", row, "LEFT", 30, 0)
  row.name:SetJustifyH("LEFT")
  row.name:SetWidth(COL_LEVELS - 36)
  row.levels = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ns.SetFontSize(row.levels, 14)
  row.levels:SetPoint("LEFT", row, "LEFT", COL_LEVELS, 0)
  row.where = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  ns.SetFontSize(row.where, 12)
  row.where:SetPoint("LEFT", row, "LEFT", COL_WHERE, 0)
  row.where:SetTextColor(unpack(ns.SKIN.muted))
  row.last = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  ns.SetFontSize(row.last, 12)
  row.last:SetPoint("LEFT", row, "LEFT", COL_LAST, 0)
  row.last:SetTextColor(unpack(ns.SKIN.muted))
  row:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  -- type(), not truthiness: a heading row has no zone, and a frame is free to answer
  -- something unhelpful for a field nobody set.
  -- No click: opening the map without lighting the zone up left people hunting for whatever was
  -- supposed to have happened. It comes back with the highlight, if the highlight ever works.
  row:SetScript("OnEnter", function(self) ns.LevelRowTooltip(self) end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  page.rows[index] = row
  return row
end

function ns.LevelRowTooltip(row)
  local zone = type(row.zone) == "table" and row.zone or nil
  local dungeon = type(row.dungeon) == "table" and row.dungeon or nil
  if not (zone or dungeon) then return nil end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  if zone then
    GameTooltip:AddLine(zone.name)
    GameTooltip:AddLine(("Level %s"):format(ns.LevelRangeText(zone.min, zone.max)), 1, 1, 1)
    local alliance, horde = zone.alliance or 0, zone.horde or 0
    if alliance + horde > 0 then
      local side = zone.faction and (zone.leaning and ("mostly " .. zone.faction) or zone.faction) or "both sides"
      GameTooltip:AddLine(("%d Alliance, %d Horde: %s"):format(alliance, horde, side), 0.6, 0.6, 0.6, true)
    end
  else
    GameTooltip:AddLine(dungeon.name)
    GameTooltip:AddLine(ns.DungeonLevelText(dungeon, "long"), 1, 1, 1)
    if dungeon.faction then
      GameTooltip:AddLine(("The entrance is in %s territory."):format(dungeon.faction), 0.6, 0.6, 0.6, true)
    end
    if not (ns.DungeonLevels(dungeon)) then
      GameTooltip:AddLine("Forever has built this one but not tuned it yet.", 0.6, 0.6, 0.6, true)
    end
  end
  GameTooltip:Show()
  return (zone or dungeon).name
end

local function Header(page, index, y, text, where, last)
  local row = DetailRow(page, index)
  row.zone, row.dungeon = nil, nil
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", page.content, "TOPLEFT", 0, y)
  row:SetHeight(HEAD_H)
  row.stripe:Hide()
  row.icon:Hide()
  ns.SetFontSize(row.name, 15)
  row.name:SetText(text)
  row.name:SetTextColor(unpack(ns.SKIN.gold))
  row.levels:SetText("Levels"); row.levels:SetTextColor(unpack(ns.SKIN.muted))
  ns.SetFontSize(row.levels, 11)
  row.where:SetText(where or "")
  row.last:SetText(last or "")
  -- type(), not truthiness: a frame answers something unhelpful for a field nobody has set.
  if type(row.rule) ~= "table" then
    row.rule = row:CreateTexture(nil, "ARTWORK")
    row.rule:SetHeight(1)
    row.rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 2)
    row.rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 2)
    row.rule:SetColorTexture(unpack(ns.SKIN.border))
  end
  row.rule:Show()
  row:Show()
  return row
end

local function Plain(page, index, y, text)
  local row = DetailRow(page, index)
  row.zone, row.dungeon = nil, nil
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", page.content, "TOPLEFT", 0, y)
  row:SetHeight(ROW_H)
  row.stripe:Hide()
  if type(row.rule) == "table" then row.rule:Hide() end
  row.icon:Hide()
  ns.SetFontSize(row.name, 13)
  row.name:SetWidth(ns.PAGE_WIDTH - DETAIL_X - 60)
  row.name:SetText(text)
  row.name:SetTextColor(0.6, 0.6, 0.6)
  row.levels:SetText(""); row.where:SetText(""); row.last:SetText("")
  row:Show()
  return row
end

local function ZoneRow(page, index, y, zone, level, stripe)
  local row = DetailRow(page, index)
  row.zone, row.dungeon = zone, nil
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", page.content, "TOPLEFT", 0, y)
  row:SetHeight(ROW_H)
  if type(row.rule) == "table" then row.rule:Hide() end
  if stripe then row.stripe:Show() else row.stripe:Hide() end
  ns.SetFontSize(row.name, 14)
  ns.SetFontSize(row.levels, 14)
  row.name:SetWidth(COL_LEVELS - 36)
  local icon = zone.faction and FACTION_ICON[zone.faction]
  if icon then
    row.icon:SetTexture(icon)
    row.icon:SetAlpha(zone.leaning and 0.45 or 1)
    row.icon:Show()
  else
    row.icon:Hide()
  end
  row.name:SetText(zone.name)
  local c = ns.DifficultyColor(zone.min, zone.max, level)
  row.name:SetTextColor(c[1], c[2], c[3])
  row.levels:SetText(ns.LevelRangeText(zone.min, zone.max))
  row.levels:SetTextColor(c[1], c[2], c[3])
  row.where:SetText(zone.continent or "")
  row.last:SetText((zone.quests or 0) > 0 and ("%d quests"):format(zone.quests) or "")
  row:Show()
  return row
end

local function DungeonRow(page, index, y, dungeon, level, stripe)
  local row = DetailRow(page, index)
  row.zone, row.dungeon = nil, dungeon
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", page.content, "TOPLEFT", 0, y)
  row:SetHeight(ROW_H)
  if type(row.rule) == "table" then row.rule:Hide() end
  if stripe then row.stripe:Show() else row.stripe:Hide() end
  ns.SetFontSize(row.name, 14)
  ns.SetFontSize(row.levels, 14)
  row.name:SetWidth(COL_LEVELS - 36)
  row.icon:SetTexture(DUNGEON_ICON)
  row.icon:SetAlpha(1)
  row.icon:Show()
  row.name:SetText(dungeon.name)
  local lo, hi = ns.DungeonLevels(dungeon)
  local c = ns.DifficultyColor(lo, hi, level)
  row.name:SetTextColor(c[1], c[2], c[3])
  row.levels:SetText(ns.DungeonLevelText(dungeon, "bare"))
  row.levels:SetTextColor(c[1], c[2], c[3])
  row.where:SetText(dungeon.faction and (dungeon.faction .. " side") or "both sides")
  row.last:SetText("")
  row:Show()
  return row
end

local function Build(page)
  page.heading = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  ns.SetFontSize(page.heading, 18)
  page.heading:SetPoint("TOPLEFT", page, "TOPLEFT", 6, -6)
  page.heading:SetText("Where to level")
  page.heading:SetTextColor(unpack(ns.SKIN.gold))
  page.subheading = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ns.SetFontSize(page.subheading, 12)
  page.subheading:SetPoint("TOPLEFT", page.heading, "BOTTOMLEFT", 0, -4)
  page.subheading:SetTextColor(unpack(ns.SKIN.muted))

  -- The answer to the question, in its own panel at the top, where the game puts the thing it
  -- most wants you to read.
  page.advicePanel = ns.Panel(page, ns.SKIN.inner)
  page.advicePanel:SetPoint("TOPLEFT", page, "TOPLEFT", 6, -46)
  page.advicePanel:SetPoint("RIGHT", page, "RIGHT", -22, 0)
  page.advicePanel:SetHeight(30)
  page.advice = page.advicePanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ns.SetFontSize(page.advice, 14)
  page.advice:SetPoint("LEFT", page.advicePanel, "LEFT", 12, 0)
  page.advice:SetPoint("RIGHT", page.advicePanel, "RIGHT", -12, 0)
  page.advice:SetJustifyH("LEFT")
  page.advice:SetTextColor(unpack(ns.SKIN.gold))

  page.rail, page.rows = {}, {}
  page.railPanel = ns.Panel(page, ns.SKIN.panel)
  page.railPanel:SetPoint("TOPLEFT", page, "TOPLEFT", 6, TOP)
  page.railPanel:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 6, 8)
  page.railPanel:SetWidth(RAIL_W)

  page.detailPanel = ns.Panel(page, ns.SKIN.panel)
  page.detailPanel:SetPoint("TOPLEFT", page, "TOPLEFT", DETAIL_X, TOP)
  page.detailPanel:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -22, 8)

  page.list = CreateFrame("ScrollFrame", nil, page.detailPanel, "UIPanelScrollFrameTemplate")
  page.list:SetPoint("TOPLEFT", page.detailPanel, "TOPLEFT", 10, -8)
  page.list:SetPoint("BOTTOMRIGHT", page.detailPanel, "BOTTOMRIGHT", -26, 8)
  page.content = CreateFrame("Frame", nil, page.list)
  page.content:SetSize(ns.PAGE_WIDTH - DETAIL_X - 42, 10)
  page.list:SetScrollChild(page.content)
  return page
end

-- Draws one band on the right. Returns how many rows it used.
function ns.SelectBand(page, index)
  local bands = page.bands or {}
  local band = bands[index]
  if not band then return nil end
  page.band = index
  for i, button in ipairs(page.rail) do
    ns.MarkRailButton(button, i == index)
  end

  local level = UnitLevel("player") or 1
  local used, y = 0, 0
  used = used + 1
  Header(page, used, y, band.lo and ("Levels %d to %d"):format(band.lo, band.hi) or "Not tuned yet",
    band.lo and "Continent" or "", band.lo and "Quests" or "")
  y = y - HEAD_H
  for i, zone in ipairs(band.zones) do
    used = used + 1
    ZoneRow(page, used, y, zone, level, i % 2 == 0)
    y = y - ROW_H
  end
  if #band.zones == 0 and band.lo then
    used = used + 1
    Plain(page, used, y, "No zone of your side's is written down for these levels.")
    y = y - ROW_H
  end

  if #band.dungeons > 0 then
    y = y - 8
    used = used + 1
    Header(page, used, y, "Dungeons", "Side", "")
    y = y - HEAD_H
    for i, dungeon in ipairs(band.dungeons) do
      used = used + 1
      DungeonRow(page, used, y, dungeon, level, i % 2 == 0)
      y = y - ROW_H
    end
  end
  if not band.lo then
    used = used + 1
    y = y - 8
    Plain(page, used, y, "Forever has built these and not given them a level yet.")
    y = y - ROW_H
  end

  for i = used + 1, #page.rows do page.rows[i]:Hide() end
  page.content:SetHeight(math.max(10, -y + 20))
  page.shownRows = used
  return used
end

local function Refresh(page)
  local level = UnitLevel("player") or 1
  local faction = UnitFactionGroup("player")
  page.bands = ns.LevelBands(faction)
  page.subheading:SetText(
    ("You are level %d. Yellow is where you should be now, grey is behind you, red is too soon."):format(level))
  page.advice:SetText(ns.LevellingAdvice(level, faction))

  for index, band in ipairs(page.bands) do
    local button = RailButton(page, index)
    button.index = index
    button.title:SetText(band.lo and ("Level %d-%d"):format(band.lo, band.hi) or "Not tuned yet")
    button.count:SetText(("%d zones, %d dungeons"):format(#band.zones, #band.dungeons))
    local c = band.lo and ns.DifficultyColor(band.lo, band.hi, level) or ns.DIFFICULTY.grey
    button.title:SetTextColor(c[1], c[2], c[3])
    button:Show()
  end
  for index = #page.bands + 1, #page.rail do page.rail[index]:Hide() end

  ns.SelectBand(page, ns.BandIndexFor(page.bands, level))
  page.shownBands = #page.bands
  return page.shownBands
end

ns.RegisterScreen({
  key = "zones",
  name = "Where to level",
  icon = "Interface\\Icons\\INV_Misc_Map_01",
  build = Build,
  refresh = Refresh,
})
