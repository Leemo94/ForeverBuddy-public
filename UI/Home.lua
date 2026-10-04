local ADDON, ns = ...

-- The welcome page: what each icon down the left does, in the order they sit there.

local SECTIONS = {
  -- The Dungeon Journal's section is shelved with the screen itself; "Where to level" is
  -- growing to answer the same question, and will say which dungeon to run as well as where
  -- to quest.
  {
    screen = "zones",
    title = "Where to level",
    body = "Where to quest at your level, and which dungeon to run.",
    icon = "Interface\\Icons\\INV_Misc_Map_01",
  },
  {
    screen = "abilities",
    title = "Abilities",
    body = "See what level you learn class abilities at the trainer.",
    icon = "Interface\\Icons\\INV_Misc_Book_09",
  },
  -- No screen of its own: the shopping list lives on Blizzard's profession window, next to the
  -- recipe you picked, so there is nothing here to open.
  {
    title = "Professions",
    body = "Open a profession, pick what to make and press Shopping list: it breaks the recipe\n"
      .. "down to base materials and counts what is already in your bags and bank.",
    icon = "Interface\\Minimap\\Tracking\\Profession",
  },
  {
    title = "City map improvements",
    body = "Toggle the locations of class trainers, profession trainers, weapon masters, the auction\n"
      .. "house, the bank and the flight master in capital cities.",
    icon = "Interface\\Minimap\\Tracking\\Class",
  },
  {
    screen = "settings",
    title = "Settings",
    body = "Toggle quality of life improvements such as auto accept quests, hide Lua errors\n"
      .. "and auto sell junk items.",
    icon = "Interface\\Icons\\INV_Misc_Gear_01",
  },
}

local CAVEAT = "This addon is based on data from the WoW: Forever beta and may not be complete. "
  .. "It will be added to frequently as new data is available."

local function Build(page)
  page.heading = page:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  page.heading:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -8)
  page.heading:SetText("Welcome to ForeverBuddy")

  page.version = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  page.version:SetPoint("TOPLEFT", page.heading, "BOTTOMLEFT", 2, -6)

  page.sections = {}
  local y = -74
  for i, section in ipairs(SECTIONS) do
    local row = CreateFrame("Button", nil, page)
    row:SetPoint("TOPLEFT", page, "TOPLEFT", 4, y)
    row:SetSize(ns.PAGE_WIDTH - 20, 52)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
    row.icon:SetTexture(section.icon)
    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -2)
    row.title:SetText(section.title)
    row.body = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.body:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
    row.body:SetWidth(ns.PAGE_WIDTH - 60)
    row.body:SetJustifyH("LEFT")
    row.body:SetJustifyV("TOP")
    row.body:SetText(section.body)
    if section.screen then
      row:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
      row:SetScript("OnClick", function() ns.SelectScreen(section.screen) end)
    end
    row.section = section
    page.sections[i] = row
    y = y - 56
  end

  page.caveat = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  page.caveat:SetPoint("TOPLEFT", page, "TOPLEFT", 6, y - 10)
  page.caveat:SetWidth(ns.PAGE_WIDTH - 40)
  page.caveat:SetJustifyH("LEFT")
  page.caveat:SetTextColor(0.8, 0.7, 0.4)
  page.caveat:SetText(CAVEAT)

  -- Made by, with the game's own chat bubble standing in for a Discord mark.
  page.madeIcon = page:CreateTexture(nil, "ARTWORK")
  page.madeIcon:SetSize(16, 16)
  page.madeIcon:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 6, 26)
  page.madeIcon:SetTexture("Interface\\FriendsFrame\\UI-Toast-ChatInviteIcon")
  page.made = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  page.made:SetPoint("LEFT", page.madeIcon, "RIGHT", 4, 0)
  page.made:SetText("Made by Leemo")

  return page
end

local function Refresh(page)
  local version = ns.AddonVersion and ns.AddonVersion() or "?"
  local newer = ns.NewerVersion and ns.NewerVersion()
  if newer then
    -- Somebody in your guild or group is running a higher version than this one.
    page.version:SetText(("|cffff8000Version %s. Version %s is out, update when you can.|r"):format(version, newer))
  else
    page.version:SetText(("Version %s. Everything here is a switch: the cog on the left turns anything off."):format(version))
  end
end

ns.RegisterScreen({
  key = "home",
  name = "Welcome",
  icon = ns.LOGO,
  build = Build,
  refresh = Refresh,
})
