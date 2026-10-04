local ADDON, ns = ...

-- A button on the minimap, the same 31x31 as every other addon's so it sits in the ring with
-- them. Left click opens the window, right click the settings, and dragging moves it around
-- the edge. Where it ends up is kept with the switches, because the beta client does not read
-- our saved file back at login.

local SIZE, ICON_SIZE = 31, 18
local DEFAULT_ANGLE = 205 -- lower left, out of the way of the clock and the tracking button

ns.MINIMAP_ICON = ns.LOGO

local button

-- Far enough out to clear the minimap ring, whatever size this client draws it.
local function Radius()
  local width = Minimap and Minimap.GetWidth and Minimap:GetWidth()
  if type(width) == "number" and width > 0 then return width / 2 + 10 end
  return 80
end

local function Place(angle)
  if not (button and Minimap) then return nil end
  local rad = math.rad(angle)
  local r = Radius()
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * r, math.sin(rad) * r)
  return angle
end

function ns.MinimapAngle()
  local saved = ns.db and tonumber(ns.db.minimapAngle)
  return saved or DEFAULT_ANGLE
end

-- save = false while a drag is in progress: the button follows the cursor and the position is
-- written once, on drop, rather than on every frame.
function ns.SetMinimapAngle(angle, save)
  angle = (tonumber(angle) or DEFAULT_ANGLE) % 360
  if ns.db then ns.db.minimapAngle = angle end
  if save ~= false then ns.SaveSettingsFallback() end
  Place(angle)
  return angle
end

-- Where the cursor is, as an angle around the minimap centre. nil on a client that will not say.
function ns.MinimapCursorAngle()
  local get = rawget(_G, "GetCursorPosition")
  if not (Minimap and get and Minimap.GetCenter) then return nil end
  local mx, my = Minimap:GetCenter()
  local scale = Minimap.GetEffectiveScale and Minimap:GetEffectiveScale()
  local px, py = get()
  if type(mx) ~= "number" or type(my) ~= "number" then return nil end
  if type(px) ~= "number" or type(py) ~= "number" then return nil end
  if type(scale) ~= "number" or scale == 0 then scale = 1 end
  return math.deg(math.atan2(py / scale - my, px / scale - mx))
end

-- Left click opens the welcome page, or closes the window if it is already open.
function ns.ToggleWindow()
  local frame = ns.Window and ns.Window()
  if frame and frame:IsShown() then
    ns.HideWindow()
    return false
  end
  ns.ShowWindow("home")
  return true
end

local function OnDragUpdate(self)
  local angle = ns.MinimapCursorAngle()
  if angle then ns.SetMinimapAngle(angle, false) end
end

local function Build()
  if not (Minimap and CreateFrame) then return nil end
  local b = CreateFrame("Button", "ForeverBuddyMinimapButton", Minimap)
  b:SetSize(SIZE, SIZE)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetMovable(true)

  b.background = b:CreateTexture(nil, "BACKGROUND")
  b.background:SetSize(20, 20)
  b.background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  b.background:SetPoint("TOPLEFT", 7, -5)

  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(ICON_SIZE, ICON_SIZE)
  b.icon:SetPoint("TOPLEFT", 7, -6)
  b.icon:SetTexture(ns.MINIMAP_ICON)

  b.border = b:CreateTexture(nil, "OVERLAY")
  b.border:SetSize(53, 53)
  b.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  b.border:SetPoint("TOPLEFT")

  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  b:SetScript("OnClick", function(self, mouseButton)
    if mouseButton == "RightButton" then
      ns.ShowWindow("settings")
    else
      ns.ToggleWindow()
    end
  end)
  b:SetScript("OnDragStart", function(self)
    self.dragging = true
    self:SetScript("OnUpdate", OnDragUpdate)
  end)
  b:SetScript("OnDragStop", function(self)
    self.dragging = nil
    self:SetScript("OnUpdate", nil)
    ns.SetMinimapAngle(ns.MinimapAngle()) -- the same spot, written down this time
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("ForeverBuddy")
    GameTooltip:AddLine("Left click to open it, right click for the settings.", 1, 1, 1)
    GameTooltip:AddLine("Drag to move this button around the minimap.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

function ns.MinimapButton()
  button = button or Build()
  return button
end

-- true when the button is up, false when it is hidden, nil on a client with no minimap to sit on.
function ns.ApplyMinimapButton(enabled)
  if enabled == nil then enabled = ns.IsFeatureEnabled("minimapbutton") end
  local b = ns.MinimapButton()
  if not b then return nil end
  Place(ns.MinimapAngle())
  if enabled then b:Show() else b:Hide() end
  return enabled and true or false
end

ns.RegisterFeature({
  key = "minimapbutton",
  name = "Minimap button",
  desc = "A ForeverBuddy button on the minimap. Left click opens the window, right click the settings, and you can drag it around the edge.",
  default = true,
  apply = function(enabled) ns.ApplyMinimapButton(enabled) end,
})

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_LOGIN")
  ns.ApplyMinimapButton()
end)
