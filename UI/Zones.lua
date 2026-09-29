local ADDON, ns = ...

-- The zones screen: everywhere you can level, ordered by level, with the ranges the client
-- itself reports. No map, just the list, so "you are 20, go here" takes one glance.

local COLUMN_WIDTH, ROW_HEIGHT, MAX_ROWS = 300, 15, 30

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

-- Open the continent map with this zone lit up on it.
function ns.ShowZoneOnMap(zone)
  if not (zone and zone.mapID and zone.parent) then
    ns.Print(("no map for %s"):format(zone and zone.name or "that zone"))
    return nil
  end
  if WorldMapFrame then
    if not WorldMapFrame:IsShown() then
      if ToggleWorldMap then pcall(ToggleWorldMap) else pcall(WorldMapFrame.Show, WorldMapFrame) end
    end
    if WorldMapFrame.SetMapID then pcall(WorldMapFrame.SetMapID, WorldMapFrame, zone.parent) end
  end
  ns.HideWindow()
  local lit = ns.HighlightZone and ns.HighlightZone(zone.parent, zone.mapID)
  ns.Print(("%s, level %s"):format(zone.name, ns.LevelRangeText(zone.min, zone.max)))
  return lit
end

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
  -- Whatever the client's map tree did not hand us joins the continent it belongs to rather than
  -- standing in a column of its own: Blackrock Mountain is Eastern Kingdoms like the rest.
  for _, z in ipairs(ns.Zones or {}) do
    if not seen[z.name:lower()] then
      local mapID, parent = ns.FindZoneMap(z.name)
      table.insert(group(z.continent or "?").zones,
        { name = z.name, min = z.level[1], max = z.level[2], source = z.source or "quests", continent = z.continent,
          mapID = mapID, parent = parent })
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

local function Build(page)
  page.heading = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  page.heading:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -6)
  page.heading:SetText("Where to level")
  page.subheading = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  page.subheading:SetPoint("TOPLEFT", page.heading, "BOTTOMLEFT", 0, -4)
  page.columns = {}
  return page
end

local function Column(page, index)
  local column = page.columns[index]
  if column then return column end
  column = { rows = {} }
  column.title = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  column.title:SetPoint("TOPLEFT", page, "TOPLEFT", 4 + (index - 1) * COLUMN_WIDTH, -46)
  page.columns[index] = column
  return column
end

local function Refresh(page)
  local playerLevel = UnitLevel("player") or 1
  local lists = ns.ZoneList()
  page.subheading:SetText(("You are level %d. Yellow suits you now, orange is ahead, grey is behind. Click a zone to see it on the map."):format(playerLevel))
  local shown = 0
  for index, list in ipairs(lists) do
    local column = Column(page, index)
    column.title:SetText(list.continent)
    column.title:Show()
    for i, zone in ipairs(list.zones) do
      local row = column.rows[i]
      if not row then
        row = CreateFrame("Button", nil, page)
        row:SetSize(COLUMN_WIDTH - 16, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", column.title, "BOTTOMLEFT", 0, -((i - 1) * ROW_HEIGHT) - 6)
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWidth(COLUMN_WIDTH - 16)
        row:SetFontString(row.label)
        row:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        row:SetScript("OnClick", function(self) ns.ShowZoneOnMap(self.zone) end)
        column.rows[i] = row
      end
      row.zone = zone
      row:SetText(("%s  %s"):format(ns.LevelRangeText(zone.min, zone.max), zone.name))
      local c = ns.LevelRangeColor(zone.min, zone.max, playerLevel)
      row.label:SetTextColor(c[1], c[2], c[3])
      row:Show()
      shown = shown + 1
    end
    for i = #list.zones + 1, #column.rows do column.rows[i]:Hide() end
  end
  for index = #lists + 1, #page.columns do
    page.columns[index].title:Hide()
    for _, row in ipairs(page.columns[index].rows) do row:Hide() end
  end
  if shown == 0 then
    page.subheading:SetText("The client has not told us any zone level ranges yet. Open the world map once, then come back.")
  end
  page.shownZones = shown
  return shown
end

ns.RegisterScreen({
  key = "zones",
  name = "Where to level",
  icon = "Interface\\Icons\\INV_Misc_Map_01",
  build = Build,
  refresh = Refresh,
})
