local _, ns = ...

-- The player's normalized position on a map (0..1), or nil where the client hides it (instances).
-- Lives here because the arrow needs it; the coordinate display itself was dropped once
-- Forever's own interface started showing coordinates.
function ns.PlayerMapXY(mapID)
  if not (C_Map and C_Map.GetPlayerMapPosition) then return nil end
  mapID = mapID or (C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
  if not mapID then return nil end
  local pos = C_Map.GetPlayerMapPosition(mapID, "player")
  if not pos then return nil end
  local x, y = pos:GetXY()
  if not x or not y or (x == 0 and y == 0) then return nil end
  return x, y
end

-- A directional arrow to a place on a map, with the distance. Uses TomTom's arrow when that
-- addon is loaded, otherwise a small movable HUD of our own. Map coordinates are the usual
-- percentages (0-100) on a uiMapID, as the dungeon data and the collector store them.

local ARROW_TEXTURE = "Interface\\Minimap\\ROTATING-MINIMAPGUIDEARROW"
local active, arrow

-- Angle to rotate an up-pointing arrow so it points at the target, given world positions
-- (x north, y west, as C_Map.GetWorldPosFromMapPos returns them) and the player's facing
-- (radians counterclockwise from north, as GetPlayerFacing returns it).
function ns.ArrowAngle(px, py, tx, ty, facing)
  local bearing = math.atan2(ty - py, tx - px)
  return bearing - (facing or 0)
end

function ns.WorldPos(mapID, x, y)
  if not (C_Map and C_Map.GetWorldPosFromMapPos) then return nil end
  local vector = CreateVector2D and CreateVector2D(x, y) or { x = x, y = y }
  local continent, pos = C_Map.GetWorldPosFromMapPos(mapID, vector)
  if not pos then return nil end
  return continent, pos.x, pos.y
end

function ns.ActiveWaypoint() return active end

-- { distance = yards, angle = radians } or nil plus a reason.
function ns.WaypointStatus()
  if not active then return nil, "no waypoint" end
  local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  local px, py = ns.PlayerMapXY(mapID)
  if not px then return nil, "your position is hidden here" end
  local pc, pwx, pwy = ns.WorldPos(mapID, px, py)
  local tc, twx, twy = ns.WorldPos(active.map, active.x / 100, active.y / 100)
  if not pwx or not twx then return nil, "no route" end
  if pc ~= tc then return nil, "on another continent" end
  local distance = math.sqrt((twx - pwx) ^ 2 + (twy - pwy) ^ 2)
  local angle = ns.ArrowAngle(pwx, pwy, twx, twy, GetPlayerFacing and GetPlayerFacing() or 0)
  return { distance = distance, angle = angle }
end

local function BuildArrow()
  local f = CreateFrame("Frame", "ForeverBuddyArrow", UIParent)
  f:SetSize(140, 96)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 220)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetFrameStrata("MEDIUM")
  f.tex = f:CreateTexture(nil, "OVERLAY")
  f.tex:SetSize(56, 42)
  f.tex:SetPoint("TOP", f, "TOP", 0, -4)
  f.tex:SetTexture(ARROW_TEXTURE)
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.title:SetPoint("TOP", f.tex, "BOTTOM", 0, -4)
  f.title:SetWidth(140)
  f.dist = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.dist:SetPoint("TOP", f.title, "BOTTOM", 0, -2)
  f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 12, 12)
  f.close:SetScript("OnClick", function() ns.ClearWaypoint() end)
  local acc = 0
  f:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + (elapsed or 0)
    if acc < 0.05 then return end
    acc = 0
    ns.UpdateArrow()
  end)
  f:Hide()
  return f
end

function ns.UpdateArrow()
  if not arrow or not active then return nil end
  local status, why = ns.WaypointStatus()
  if not status then
    arrow.tex:SetRotation(0)
    arrow.dist:SetText(why)
    return why
  end
  arrow.tex:SetRotation(status.angle)
  arrow.dist:SetText(status.distance < 10 and "you are here" or ("%d yd"):format(status.distance))
  return status
end

function ns.SetWaypoint(mapID, x, y, title)
  if not mapID or not x or not y then return nil end
  active = { map = mapID, x = x, y = y, title = title or "" }
  if TomTom and TomTom.AddWaypoint then
    local ok = pcall(TomTom.AddWaypoint, TomTom, mapID, x / 100, y / 100, { title = title, crazy = true, persistent = false, from = "ForeverBuddy" })
    if ok then
      active.tomtom = true
      if arrow then arrow:Hide() end
      return active
    end
  end
  arrow = arrow or BuildArrow()
  arrow.title:SetText(active.title)
  arrow:Show()
  ns.UpdateArrow()
  return active
end

function ns.ClearWaypoint()
  active = nil
  if arrow then arrow:Hide() end
end

ns.SlashHandlers.arrow = function(rest)
  rest = (rest or ""):match("^%s*(.-)%s*$")
  if rest == "clear" or rest == "off" then
    ns.ClearWaypoint()
    ns.Print("arrow cleared")
    return
  end
  if not active then
    ns.Print("no arrow set. Click a quest in /fb dungeon to get one; /fb arrow clear removes it.")
    return
  end
  local status, why = ns.WaypointStatus()
  ns.Print(("arrow: %s, %s"):format(active.title, status and ("%d yd away"):format(status.distance) or why))
end
