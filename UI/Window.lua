local ADDON, ns = ...

-- One window with a rail of icons down its left edge. Each screen registers itself and owns a
-- page inside the window: the welcome page, the dungeon journal, the settings checklist.

local FRAME_NAME = "ForeverBuddyFrame"
local WIDTH, HEIGHT = 900, 620
local RAIL_X, RAIL_TOP, RAIL_SIZE, RAIL_GAP = 10, -30, 34, 8
local CONTENT_LEFT = RAIL_X + RAIL_SIZE + 12

ns.screens = {}       -- ordered, rail order
ns.screenIndex = {}   -- key -> definition

-- def = { key, name, icon, build(page), refresh(page, ...) }
function ns.RegisterScreen(def)
  assert(type(def.key) == "string" and def.key ~= "", "screen key required")
  assert(not ns.screenIndex[def.key], "duplicate screen " .. def.key)
  table.insert(ns.screens, def)
  ns.screenIndex[def.key] = def
  return def
end

-- Two small helpers the pages share.

-- A scrim over artwork: dark where the text sits on the left, clear on the right so the picture
-- still shows. Falls back to a flat wash on a client without the gradient call.
function ns.DarkenLeft(texture)
  local ok = false
  if texture.SetGradient and CreateColor then
    ok = pcall(texture.SetGradient, texture, "HORIZONTAL", CreateColor(0, 0, 0, 0.92), CreateColor(0, 0, 0, 0.2))
  end
  if not ok then texture:SetColorTexture(0, 0, 0, 0.55) end
  return ok
end

-- Cut a wrapped string off after so many lines instead of letting it grow over its neighbour.
function ns.LimitLines(fontString, lines)
  if not fontString.SetMaxLines then return false end
  return (pcall(fontString.SetMaxLines, fontString, lines))
end

local window

local function BuildWindow()
  local f = CreateFrame("Frame", FRAME_NAME, UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(WIDTH, HEIGHT)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()
  tinsert(UISpecialFrames, FRAME_NAME) -- Escape closes it

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.title:SetPoint("TOP", f, "TOP", 0, -6)
  f.title:SetText("ForeverBuddy")

  f.note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.note:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -9)
  f.note:SetText(ns.DataInfo and ns.DataInfo.build and ("Forever data " .. ns.DataInfo.build) or "")

  f.buttons, f.pages = {}, {}
  for i, def in ipairs(ns.screens) do
    local b = CreateFrame("Button", nil, f)
    b:SetSize(RAIL_SIZE, RAIL_SIZE)
    b:SetPoint("TOPLEFT", f, "TOPLEFT", RAIL_X, RAIL_TOP - (i - 1) * (RAIL_SIZE + RAIL_GAP))
    b:SetNormalTexture(def.icon)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b.screenKey = def.key
    b:SetScript("OnClick", function() ns.SelectScreen(def.key) end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(def.name)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.buttons[i] = b

    local page = CreateFrame("Frame", nil, f)
    page:SetPoint("TOPLEFT", f, "TOPLEFT", CONTENT_LEFT, -30)
    page:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
    page:Hide()
    page.def = def
    if def.build then def.build(page) end
    f.pages[def.key] = page
  end
  return f
end

function ns.Window()
  window = window or BuildWindow()
  return window
end

ns.PAGE_WIDTH = WIDTH - CONTENT_LEFT - 10

-- Switches to a screen, builds it on first use, and passes anything else to its refresh.
function ns.SelectScreen(key, ...)
  local f = ns.Window()
  local def = ns.screenIndex[key] or ns.screens[1]
  if not def then return nil end
  for _, page in pairs(f.pages) do page:Hide() end
  for _, b in ipairs(f.buttons) do
    if b.screenKey == def.key then b:LockHighlight() else b:UnlockHighlight() end
  end
  local page = f.pages[def.key]
  f.current = def.key
  f.title:SetText("ForeverBuddy - " .. def.name)
  page:Show()
  if def.refresh then def.refresh(page, ...) end
  return page
end

function ns.ShowWindow(key, ...)
  local f = ns.Window()
  ns.SelectScreen(key or f.current or (ns.screens[1] and ns.screens[1].key), ...)
  f:Show()
  return f
end

function ns.HideWindow()
  if window then window:Hide() end
end
