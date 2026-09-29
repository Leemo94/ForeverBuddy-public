local ADDON, ns = ...

-- Level ranges written over every zone on a continent map. The game shows the range for the one
-- zone under your cursor; this keeps them all on screen, so a glance answers where to go next.
-- The numbers are the client's own (C_Map.GetMapLevels), so Forever's new zones are included.

ns.RegisterFeature({
  key = "maplevels",
  name = "Zone levels on the map",
  desc = "Writes each zone's level range over it on the continent map. The game only shows the zone under your cursor.",
  default = true,
})

local labels = {}
local overlay

-- Forever ships no level tuning for zones: every zone's ContentTuningID is 0 in this build, so
-- the client's own GetMapLevels answers nothing and Blizzard's map label shows no range. Our own
-- ranges, worked out from where quests of each level are, stand in for it.
local byName

local function ZoneLevelsByName(name)
  if not byName then
    byName = {}
    for _, z in ipairs(ns.Zones or {}) do
      byName[z.name:lower()] = z
    end
  end
  return name and byName[name:lower()] or nil
end
ns.ZoneLevelsByName = ZoneLevelsByName

-- min, max, source for a map, or nil when nothing knows it.
function ns.MapLevels(mapID)
  if C_Map and C_Map.GetMapLevels then
    local ok, minLevel, maxLevel = pcall(C_Map.GetMapLevels, mapID)
    if ok and minLevel and minLevel > 0 then
      if not maxLevel or maxLevel <= 0 then maxLevel = minLevel end
      return minLevel, maxLevel, "client"
    end
  end
  local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
  local zone = info and ZoneLevelsByName(info.name)
  if zone then return zone.level[1], zone.level[2], zone.source or "quests" end
  return nil
end

function ns.LevelRangeText(minLevel, maxLevel)
  if minLevel == maxLevel then return tostring(minLevel) end
  return ("%d-%d"):format(minLevel, maxLevel)
end

-- Red when it is above you, grey when you have outgrown it, yellow while it suits you.
function ns.LevelRangeColor(minLevel, maxLevel, playerLevel)
  if playerLevel < minLevel then return ns.COLORS.keep end
  if playerLevel > maxLevel + 2 then return ns.COLORS.done end
  return ns.COLORS.available
end

-- Where to write a zone's range. The middle of its rectangle is usually right, but a rectangle
-- takes in everything the zone reaches: Feralas' takes in the sea and the isles west of it, and
-- a long zone like Stranglethorn is thin where its middle falls. Where the client can say which
-- zone a point belongs to, we sample the rectangle and take the point furthest from anything
-- that is not this zone, which is the middle of its widest part.
local GRID = 11
local labelPoints = {}

-- true, false, or nil when this client cannot answer at all (then the plain middle stands).
local function BelongsTo(parentMapID, mapID, x, y)
  if not (C_Map and C_Map.GetMapInfoAtPosition) then return nil end
  local ok, info = pcall(C_Map.GetMapInfoAtPosition, parentMapID, x, y)
  if not ok then return nil end
  if type(info) ~= "table" then return false end -- open water, or the continent itself
  return info.mapID == mapID
end

function ns.ZoneLabelPoint(parentMapID, mapID, left, right, top, bottom)
  local cx, cy = (left + right) / 2, (top + bottom) / 2
  if BelongsTo(parentMapID, mapID, cx, cy) ~= false then return cx, cy end
  local inside, outside = {}, {}
  for i = 1, GRID do
    for j = 1, GRID do
      local x = left + (right - left) * (i - 0.5) / GRID
      local y = top + (bottom - top) * (j - 0.5) / GRID
      table.insert(BelongsTo(parentMapID, mapID, x, y) and inside or outside, { x, y })
    end
  end
  if #inside == 0 then return cx, cy end
  local best, bestScore
  for _, point in ipairs(inside) do
    -- How far this point is from anything that is not the zone. The sides of the rectangle
    -- count: it is the zone's own bounding box, so the zone ends at each of them.
    local depth = math.min(point[1] - left, right - point[1], point[2] - top, bottom - point[2])
    for _, other in ipairs(outside) do
      local dx, dy = point[1] - other[1], point[2] - other[2]
      local distance = math.sqrt(dx * dx + dy * dy)
      if distance < depth then depth = distance end
    end
    -- Two equally deep points: the one nearer the middle of the rectangle wins.
    local dx, dy = point[1] - cx, point[2] - cy
    local score = depth - 0.001 * math.sqrt(dx * dx + dy * dy)
    if not bestScore or score > bestScore then best, bestScore = point, score end
  end
  return best[1], best[2]
end

-- Every child zone of a map that has a level range and a place on it.
function ns.ZonesOnMap(mapID)
  if not (C_Map and C_Map.GetMapChildrenInfo) then return {} end
  local out = {}
  for _, child in ipairs(C_Map.GetMapChildrenInfo(mapID, Enum.UIMapType and Enum.UIMapType.Zone) or {}) do
    local minLevel, maxLevel, source = ns.MapLevels(child.mapID)
    if minLevel then
      local left, right, top, bottom = C_Map.GetMapRectOnMap(child.mapID, mapID)
      local zone = { mapID = child.mapID, parent = mapID, name = child.name, min = minLevel, max = maxLevel, source = source }
      if left and right and top and bottom then
        local key = mapID .. ":" .. child.mapID
        local cached = labelPoints[key]
        if not cached then
          local x, y = ns.ZoneLabelPoint(mapID, child.mapID, left, right, top, bottom)
          cached = { x, y }
          labelPoints[key] = cached
        end
        zone.x, zone.y = cached[1], cached[2]
      end
      table.insert(out, zone)
    end
  end
  table.sort(out, function(a, b) return a.min < b.min or (a.min == b.min and a.name < b.name) end)
  return out
end

local function Canvas()
  local container = WorldMapFrame and WorldMapFrame.ScrollContainer
  return container and container.Child or container or WorldMapFrame
end

function ns.UpdateMapLevels()
  local canvas = Canvas()
  if not canvas then return nil end
  overlay = overlay or CreateFrame("Frame", "ForeverBuddyMapLevels", canvas)
  overlay:SetAllPoints(canvas)
  overlay:SetFrameStrata("HIGH")
  if not ns.IsFeatureEnabled("maplevels") or not (WorldMapFrame and WorldMapFrame:IsShown()) then
    for _, label in ipairs(labels) do label:Hide() end
    return nil
  end
  local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
  local zones = mapID and ns.ZonesOnMap(mapID) or {}
  local width, height = canvas:GetWidth() or 0, canvas:GetHeight() or 0
  local playerLevel = UnitLevel("player") or 1
  local placed = 0
  for i, zone in ipairs(zones) do
    if not zone.x then break end
    placed = i
    local label = labels[i]
    if not label then
      label = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      label:SetShadowOffset(1, -1)
      labels[i] = label
    end
    label:ClearAllPoints()
    label:SetPoint("CENTER", canvas, "TOPLEFT", zone.x * width, -zone.y * height)
    label:SetText(ns.LevelRangeText(zone.min, zone.max))
    local c = ns.LevelRangeColor(zone.min, zone.max, playerLevel)
    label:SetTextColor(c[1], c[2], c[3])
    label:Show()
  end
  for i = placed + 1, #labels do labels[i]:Hide() end
  ns.shownMapLevels = placed
  return placed
end

------------------------------------------------------------------------------
-- Show me that zone: the continent map, with the zone itself lit up on it.
--
-- SHELVED for the first release. The client hands back highlight art that paints a grey sheet
-- over the map instead of the zone's shape, and the box fallback is no better. Clicking a zone
-- still opens the continent map at it, which is the useful half. Turning this back on is the
-- whole job once the art behaves.
------------------------------------------------------------------------------
local SHIPPING = false
local highlight

local function HighlightFrame(canvas)
  if not highlight then
    highlight = CreateFrame("Frame", "ForeverBuddyZoneHighlight", canvas)
    highlight.shape = highlight:CreateTexture(nil, "ARTWORK")
    highlight.edges = {}
    for i = 1, 4 do
      local edge = highlight:CreateTexture(nil, "OVERLAY")
      edge:SetColorTexture(1, 0.82, 0, 0.9)
      highlight.edges[i] = edge
    end
  end
  highlight:SetParent(canvas)
  highlight:SetAllPoints(canvas)
  highlight:SetFrameStrata("HIGH")
  return highlight
end

-- The zone's own shape, the art the game lights up when your cursor crosses a zone.
local function ShapeHighlight(frame, mapID, zoneMapID, x, y, width, height)
  if not (C_Map and C_Map.GetMapHighlightInfoAtPosition) then return false end
  local ok, fileDataID, _, percentX, percentY, coordX, coordY, childX, childY =
    pcall(C_Map.GetMapHighlightInfoAtPosition, mapID, x, y)
  if not (ok and type(fileDataID) == "number" and fileDataID > 0 and percentX and percentX > 0) then return false end
  frame.shape:SetTexture(fileDataID)
  frame.shape:SetTexCoord(0, coordX or 1, 0, coordY or 1)
  frame.shape:SetVertexColor(1, 0.82, 0, 0.55)
  frame.shape:SetSize(percentX * width, percentY * height)
  frame.shape:ClearAllPoints()
  frame.shape:SetPoint("TOPLEFT", frame, "TOPLEFT", (childX or 0) * width, -(childY or 0) * height)
  frame.shape:Show()
  return true
end

-- Failing that, a box around the zone: less pretty, but it still says where to look.
local function BoxHighlight(frame, left, right, top, bottom, width, height)
  local x1, x2 = left * width, right * width
  local y1, y2 = -top * height, -bottom * height
  local size = { { x2 - x1, 2, x1, y1 }, { x2 - x1, 2, x1, y2 + 2 },
                 { 2, y1 - y2, x1, y1 }, { 2, y1 - y2, x2 - 2, y1 } }
  for i, edge in ipairs(frame.edges) do
    local w, h, ex, ey = size[i][1], size[i][2], size[i][3], size[i][4]
    edge:SetSize(math.max(1, w), math.max(1, h))
    edge:ClearAllPoints()
    edge:SetPoint("TOPLEFT", frame, "TOPLEFT", ex, ey)
    edge:Show()
  end
end

-- Light this zone up the next time its continent is on screen. Same zone again clears it.
function ns.HighlightZone(continentMapID, zoneMapID)
  if not SHIPPING then return nil end
  if ns.highlightZone == zoneMapID and ns.highlightMap == continentMapID then
    ns.highlightZone, ns.highlightMap = nil, nil
  else
    ns.highlightZone, ns.highlightMap = zoneMapID, continentMapID
  end
  return ns.UpdateZoneHighlight()
end

function ns.UpdateZoneHighlight()
  if not SHIPPING then return nil end
  local canvas = Canvas()
  if not canvas then return nil end
  local frame = HighlightFrame(canvas)
  local mapID = WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
  local zoneMapID = ns.highlightZone
  if not zoneMapID or mapID ~= ns.highlightMap or not (WorldMapFrame and WorldMapFrame:IsShown()) then
    frame:Hide()
    return nil
  end
  local left, right, top, bottom = C_Map.GetMapRectOnMap(zoneMapID, mapID)
  if not (left and right and top and bottom) then
    frame:Hide()
    return nil
  end
  local width, height = canvas:GetWidth() or 0, canvas:GetHeight() or 0
  local x, y = ns.ZoneLabelPoint(mapID, zoneMapID, left, right, top, bottom)
  frame:Show()
  local shaped = ShapeHighlight(frame, mapID, zoneMapID, x, y, width, height)
  frame.shape:SetShown(shaped)
  if shaped then
    for _, edge in ipairs(frame.edges) do edge:Hide() end
  else
    BoxHighlight(frame, left, right, top, bottom, width, height)
  end
  ns.highlightShaped = shaped
  return zoneMapID
end

local function Hook()
  if not WorldMapFrame or ns.mapLevelsHooked then return false end
  ns.mapLevelsHooked = true
  WorldMapFrame:HookScript("OnShow", ns.UpdateMapLevels)
  WorldMapFrame:HookScript("OnShow", ns.UpdateZoneHighlight)
  if WorldMapFrame.OnMapChanged then
    hooksecurefunc(WorldMapFrame, "OnMapChanged", ns.UpdateMapLevels)
    hooksecurefunc(WorldMapFrame, "OnMapChanged", ns.UpdateZoneHighlight)
  end
  if EventRegistry and EventRegistry.RegisterCallback then
    pcall(EventRegistry.RegisterCallback, EventRegistry, "WorldMapOnMapChanged", ns.UpdateMapLevels, ns)
    pcall(EventRegistry.RegisterCallback, EventRegistry, "WorldMapOnMapChanged", ns.UpdateZoneHighlight, ns)
  end
  return true
end

Hook()
local waiter = CreateFrame("Frame")
waiter:RegisterEvent("PLAYER_ENTERING_WORLD")
waiter:SetScript("OnEvent", function(self)
  if Hook() then self:UnregisterEvent("PLAYER_ENTERING_WORLD") end
  ns.UpdateMapLevels()
end)
