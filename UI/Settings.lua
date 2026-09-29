local ADDON, ns = ...

-- The settings screen: every feature with a checkbox, in the order the modules registered them.

local COLUMN_WIDTH, ROW_HEIGHT = 420, 48

local function Build(page)
  page.heading = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  page.heading:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -6)
  page.heading:SetText("Settings")
  page.intro = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  page.intro:SetPoint("TOPLEFT", page.heading, "BOTTOMLEFT", 0, -4)
  page.intro:SetText("Tick the features you want. /fb setup walks you through them.")

  local rowsPerColumn = math.ceil(#ns.features / 2)
  page.rows = {}
  for i, def in ipairs(ns.features) do
    local column = math.floor((i - 1) / rowsPerColumn)
    local x = 4 + column * COLUMN_WIDTH
    local y = -44 - ((i - 1) % rowsPerColumn) * ROW_HEIGHT
    local row = { def = def }
    row.check = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    row.check:SetSize(24, 24)
    row.check:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
    row.check.featureKey = def.key
    row.check:SetScript("OnClick", function(self)
      ns.SetFeatureEnabled(def.key, self:GetChecked() and true or false)
    end)
    row.name = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", page, "TOPLEFT", x + 28, y - 4)
    row.name:SetText(def.name)
    row.desc = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.desc:SetPoint("TOPLEFT", page, "TOPLEFT", x + 28, y - 19)
    row.desc:SetWidth(COLUMN_WIDTH - 40)
    row.desc:SetJustifyH("LEFT")
    row.desc:SetText(def.desc or "")
    page.rows[i] = row
  end

  page.done = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
  page.done:SetSize(110, 24)
  page.done:SetPoint("BOTTOM", page, "BOTTOM", 0, 10)
  page.done:SetText("Done")
  page.done:SetScript("OnClick", function() ns.CloseOptions(true) end)
  return page
end

local function Refresh(page)
  for _, row in ipairs(page.rows) do
    row.check:SetChecked(ns.IsFeatureEnabled(row.def.key))
  end
  return page.rows
end

ns.RegisterScreen({
  key = "settings",
  name = "Settings",
  icon = "Interface\\Icons\\Trade_Engineering",
  build = Build,
  refresh = Refresh,
})
