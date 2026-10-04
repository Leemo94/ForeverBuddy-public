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

-- The look ------------------------------------------------------------------
-- Warm brown panels with a gold-brown edge, headings in gold over a rule, and text big enough
-- to read across a room. It is how the game draws its own journals, and the point is that
-- nothing on our screens should look like it came from somewhere else.
ns.SKIN = {
  panel      = { 0.09,  0.07,  0.045, 0.92 },
  inner      = { 0.135, 0.105, 0.065, 0.92 },
  row        = { 0.17,  0.13,  0.08,  0.55 },
  selected   = { 0.30,  0.23,  0.12,  1    },
  border     = { 0.40,  0.32,  0.18,  1    },
  borderLit  = { 0.76,  0.61,  0.30,  1    },
  gold       = { 1,     0.82,  0      },
  body       = { 0.91,  0.86,  0.75   },
  muted      = { 0.60,  0.56,  0.47   },
}

-- A bordered panel: a fill and four one-pixel edges, which every client can draw. Backdrops
-- come and go between versions; four textures do not.
--
-- It is a frame, not a texture, so it draws over everything on its parent whatever layer that
-- parent's bits are on. Put it behind anything of the parent's it should not cover, with
-- SetFrameLevel one below the parent's.
function ns.Panel(parent, fill)
  local frame = CreateFrame("Frame", nil, parent)
  frame.bg = frame:CreateTexture(nil, "BACKGROUND")
  frame.bg:SetAllPoints()
  frame.bg:SetColorTexture(unpack(fill or ns.SKIN.panel))
  frame.edges = {}
  for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
    local edge = frame:CreateTexture(nil, "BORDER")
    edge:SetColorTexture(unpack(ns.SKIN.border))
    if side == "TOP" or side == "BOTTOM" then
      edge:SetHeight(1)
      edge:SetPoint(side .. "LEFT")
      edge:SetPoint(side .. "RIGHT")
    else
      edge:SetWidth(1)
      edge:SetPoint("TOP" .. side)
      edge:SetPoint("BOTTOM" .. side)
    end
    frame.edges[side] = edge
  end
  function frame:SetEdgeColor(colour)
    for _, edge in pairs(self.edges) do edge:SetColorTexture(unpack(colour)) end
  end
  function frame:SetFill(colour)
    self.bg:SetColorTexture(unpack(colour))
  end
  return frame
end

-- The client's own font at whatever size we ask for, so nothing is hard-coded to a file that
-- may not exist on a given build.
function ns.SetFontSize(fontString, size, outline)
  local base = rawget(_G, "GameFontNormal")
  if not (base and base.GetFont and fontString and fontString.SetFont) then return fontString end
  local file, _, flags = base:GetFont()
  if file then pcall(fontString.SetFont, fontString, file, size, outline or flags) end
  return fontString
end

-- A gold heading with a rule under it, the way every panel in the game separates its sections.
function ns.Heading(parent, text, size)
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  ns.SetFontSize(label, size or 15)
  label:SetTextColor(unpack(ns.SKIN.gold))
  if text then label:SetText(text) end
  local rule = parent:CreateTexture(nil, "ARTWORK")
  rule:SetHeight(1)
  rule:SetColorTexture(unpack(ns.SKIN.border))
  label.rule = rule
  return label
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
