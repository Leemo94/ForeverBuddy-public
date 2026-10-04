local ADDON, ns = ...

-- Two windows. The options checklist (/fb) lists every feature with a checkbox.
-- The guided setup (/fb setup, and automatically on first install) walks through them page by page.
-- Loads last so every feature is registered.

function ns.AddonVersion()
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local ok, version = pcall(get, ADDON, "Version")
  return (ok and version) or "?"
end

------------------------------------------------------------------------------
-- The options checklist now lives in the main window (UI/Settings.lua)
------------------------------------------------------------------------------
function ns.ShowOptions()
  return ns.ShowWindow("settings")
end

-- /fb opens the welcome page now, so the checklist needs a word of its own.
ns.SlashHandlers.settings = function() return ns.ShowOptions() end
ns.SlashHandlers.options = ns.SlashHandlers.settings

-- Called by the Done button. This must NOT mark the guided setup as done: someone who opens
-- the settings before the guide has run should still be shown the guide on their next login.
function ns.CloseOptions(fromButton)
  if ns.db then ns.db.optionsSeen = true end
  ns.SaveSettingsFallback()
  if fromButton then
    ns.Print("settings saved")
    ns.HideWindow()
  end
end

------------------------------------------------------------------------------
-- Guided setup
------------------------------------------------------------------------------
local SETUP_NAME = "ForeverBuddySetupFrame"
local SETUP_WIDTH, SETUP_HEIGHT = 560, 360
local DEMO_ITEM = "item:769" -- Chunk of Boar Meat: two quests and a recipe in the shipped data
local setup

ns.SETUP_PAGES = {
  {
    title = "Welcome to ForeverBuddy",
    body = "ForeverBuddy is a set of small helpers, and each one is a switch. This takes about thirty seconds and shows what every helper does.\n\nYou can skip it and turn things on later with /fb.",
  },
  {
    title = "Item uses on tooltips",
    body = "Hover an item and its tooltip tells you what it is for: the quests that need it, the recipes that use it, and whether to keep it.\n\nHere is the real thing for a Chunk of Boar Meat. Hold Shift on any tooltip to see the full lists.",
    features = { "usedfor", "appearance" },
    demo = "tooltip",
  },
  {
    title = "At the vendor",
    body = "Open a vendor and, if you want, your gear is repaired and your grey junk is sold. Each one prints a single line in chat, like:\n\n|cff33ff99ForeverBuddy|r: repaired for 12s 40c\n|cff33ff99ForeverBuddy|r: sold 6 junk items for 1s 8c\n\nCtrl + right click anything in your bags to add it to the sell list, or to protect a grey you want to keep. Clicking it again takes it off.",
    features = { "autorepair", "selljunk", "sellunusable" },
  },
  {
    title = "Quests",
    body = "With this on, quests are accepted and handed in without clicking through the text. Hold Shift while talking to a quest giver to do it by hand.\n\nQuests that cost money are always left alone, and when there is a reward to choose between, the choice stays yours.",
    features = { "autoquest" },
  },
  {
    title = "Help improve the data",
    body = "Forever is new and its data is partly hidden, so ForeverBuddy can record what the game shows YOU into its own saved-variables file: items you hover, quests you accept or hand in and who gave them where, what drops from what, what vendors sell, and where your talent points go.\n\nThat is all. It never records chat, keystrokes, other players, account details, or anything from combat, and it never sends anything anywhere. The file stays on your computer until you choose to share it. /fb collect explains this again any time.",
    features = { "collect" },
  },
  {
    title = "All set",
    summary = true,
  },
}

StaticPopupDialogs.FOREVERBUDDY_EQUIP_DEMO = {
  text = "ForeverBuddy: equip %s?\nIt replaces %s.\n\n(This is a preview from the setup.)",
  button1 = "Equip",
  button2 = "Keep",
  OnAccept = function() ns.Print("in the real prompt, Equip puts the item on") end,
  OnCancel = function() ns.Print("in the real prompt, Keep silences that item for the session") end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

local function ShowTooltipDemo(frame)
  GameTooltip:SetOwner(frame, "ANCHOR_NONE")
  GameTooltip:ClearAllPoints()
  GameTooltip:SetPoint("TOPLEFT", frame, "TOPRIGHT", 12, -40)
  GameTooltip:SetHyperlink(DEMO_ITEM)
  GameTooltip:Show()
end

local function HideTooltipDemo()
  GameTooltip:Hide()
end

local function FeatureCheck(page, key, y)
  local def = ns.featureIndex[key]
  local check = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
  check:SetSize(26, 26)
  check:SetPoint("TOPLEFT", page, "TOPLEFT", 0, y)
  check.featureKey = key
  check:SetScript("OnClick", function(self)
    ns.SetFeatureEnabled(key, self:GetChecked() and true or false)
  end)
  local label = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("LEFT", check, "RIGHT", 4, 0)
  label:SetText(def and def.name or key)
  return check
end

function ns.SetupSummary()
  local on, off = {}, {}
  for _, def in ipairs(ns.features) do
    table.insert(ns.IsFeatureEnabled(def.key) and on or off, def.name)
  end
  return ("On: %s\nOff: %s\n\nAlso: /fb dungeon lists every quest for a dungeon, and /fb zones says where to quest at your level.\nType /fb settings any time to change these, or /fb setup to see this again."):format(
    #on > 0 and table.concat(on, ", ") or "nothing",
    #off > 0 and table.concat(off, ", ") or "nothing")
end

local function BuildSetupFrame()
  local f = CreateFrame("Frame", SETUP_NAME, UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(SETUP_WIDTH, SETUP_HEIGHT)
  f:SetPoint("CENTER", UIParent, "CENTER", -120, 40)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetScript("OnHide", function()
    HideTooltipDemo()
    ns.FinishSetup(false)
  end)
  f:Hide()
  tinsert(UISpecialFrames, SETUP_NAME)

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.title:SetPoint("TOP", f, "TOP", 0, -6)
  f.title:SetText("ForeverBuddy setup")

  f.counter = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.counter:SetPoint("TOPRIGHT", f, "TOPRIGHT", -36, -9)

  f.pages = {}
  for i, def in ipairs(ns.SETUP_PAGES) do
    local page = CreateFrame("Frame", nil, f)
    page:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -36)
    page:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 48)
    page.def = def
    page.heading = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    page.heading:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -4)
    page.heading:SetText(def.title)
    page.body = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    page.body:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -34)
    page.body:SetWidth(SETUP_WIDTH - 72)
    page.body:SetJustifyH("LEFT")
    page.body:SetJustifyV("TOP")
    page.body:SetText(def.body or "")
    page.checks = {}
    local y = -190
    for _, key in ipairs(def.features or {}) do
      if ns.featureIndex[key] then -- some features only exist on some clients (e.g. appearance)
        table.insert(page.checks, FeatureCheck(page, key, y))
        y = y - 30
      end
    end
    if def.demo == "popup" then
      page.demoButton = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
      page.demoButton:SetSize(110, 24)
      page.demoButton:SetPoint("TOPLEFT", page, "TOPLEFT", 220, -190)
      page.demoButton:SetText("Show me")
      page.demoButton:SetScript("OnClick", function()
        StaticPopup_Show("FOREVERBUDDY_EQUIP_DEMO", "|cff1eff00[Fine Leather Vest]|r", "|cffffffff[Ragged Vest]|r")
      end)
    end
    page:Hide()
    f.pages[i] = page
  end

  f.back = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.back:SetSize(90, 24)
  f.back:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 14)
  f.back:SetText("Back")
  f.back:SetScript("OnClick", function() ns.SetupPage(f.index - 1) end)

  f.next = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.next:SetSize(90, 24)
  f.next:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 14)
  f.next:SetScript("OnClick", function()
    if f.index >= #f.pages then ns.FinishSetup(true) else ns.SetupPage(f.index + 1) end
  end)

  f.skip = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.skip:SetSize(90, 24)
  f.skip:SetPoint("RIGHT", f.next, "LEFT", -8, 0)
  f.skip:SetText("Skip")
  f.skip:SetScript("OnClick", function() f:Hide() end)
  return f
end

function ns.SetupPage(index)
  local f = setup
  index = math.max(1, math.min(#f.pages, index))
  local previous = f.index and f.pages[f.index]
  if previous then
    previous:Hide()
    if previous.def.demo == "tooltip" then HideTooltipDemo() end
  end
  f.index = index
  local page = f.pages[index]
  for _, check in ipairs(page.checks) do
    check:SetChecked(ns.IsFeatureEnabled(check.featureKey))
  end
  if page.def.summary then page.body:SetText(ns.SetupSummary()) end
  page:Show()
  if page.def.demo == "tooltip" then ShowTooltipDemo(f) end
  f.counter:SetText(("%d of %d"):format(index, #f.pages))
  if index == 1 then f.back:Disable() else f.back:Enable() end
  f.next:SetText(index == #f.pages and "Finish" or "Next")
  f.skip:SetShown(index < #f.pages)
  return page
end

function ns.ShowSetup()
  setup = setup or BuildSetupFrame()
  ns.SetupPage(1)
  setup:Show()
  return setup
end

-- Called by Finish (fromButton = true) and by the frame's OnHide (false).
function ns.FinishSetup(fromButton)
  if ns.db then ns.db.setupDone = true end
  ns.SaveSettingsFallback()
  if fromButton then
    ns.Print("setup complete, /fb for options")
    setup:Hide()
  end
end

------------------------------------------------------------------------------
-- First install, version notice, Settings menu entry
------------------------------------------------------------------------------
-- Everything that happens the first time you land in the world, in one place so a test can ask
-- for it directly: the event itself only ever fires once a session.
function ns.OnEnteringWorld()
  if not ns.db then return end
  if ns.restoredSettings then
    ns.Print(("your saved file did not load this login, so %d switch%s and the setup state were restored from the game's settings file."):format(
      ns.restoredSettings, ns.restoredSettings == 1 and "" or "es"))
  end
  local version = ns.AddonVersion()
  if ns.db.seenVersion ~= version then
    ns.db.seenVersion = version
    ns.Print(("v%s loaded. /fb for options, /fb setup for the guided setup."):format(version))
  end
  if not ns.db.setupDone then
    C_Timer.After(2, function()
      local ok, err = pcall(ns.ShowSetup)
      if not ok then
        ns.Print("the setup guide could not open: " .. tostring(err))
        ns.Print("everything else still works. /fb lists every feature, /fb setup tries the guide again.")
      end
    end)
  end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_ENTERING_WORLD")
  ns.OnEnteringWorld()
end)

if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
  pcall(function()
    local panel = CreateFrame("Frame")
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(220, 24)
    button:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    button:SetText("Open ForeverBuddy options")
    button:SetScript("OnClick", function() ns.ShowOptions() end)
    local category = Settings.RegisterCanvasLayoutCategory(panel, "ForeverBuddy")
    Settings.RegisterAddOnCategory(category)
  end)
end
