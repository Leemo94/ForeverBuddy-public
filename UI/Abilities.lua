local ADDON, ns = ...

-- Every ability a class learns, level 1 to 60. The levels are Forever's own, which is why
-- Hammer of Justice sits at 24 here and at 20 in Classic.

local ROW_H, HEAD_H = 18, 22

local Refresh -- defined below; the search box redraws through it without leaving the screen

local CLASS_NAME = {
  WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
  SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}

function ns.ClassToken(word)
  if not word or word == "" then return nil end
  local wanted = word:upper()
  for token in pairs(CLASS_NAME) do
    if token == wanted then return token end
  end
  return nil
end

-- Who teaches a spell and what they charge, from the trainer lists players have recorded.
local bySpell, builtFrom

function ns.TrainerFor(spellID)
  local source = (ns.Observed and ns.Observed.trainers) or false
  if not bySpell or builtFrom ~= source then
    bySpell, builtFrom = {}, source
    for _, trainer in pairs(source or {}) do
      for _, service in ipairs(trainer.services or {}) do
        if service.spell and not bySpell[service.spell] then
          bySpell[service.spell] = { name = trainer.name, cost = service.cost, level = service.level }
        end
      end
    end
  end
  return spellID and bySpell[spellID] or nil
end

function ns.CostText(copper)
  if not copper or copper <= 0 then return nil end
  local get = rawget(_G, "GetMoneyString")
  if get then
    local ok, text = pcall(get, copper, true)
    if ok and text then return text end
  end
  return ("%dc"):format(copper)
end

-- Some abilities belong to one race: an Undead priest trains Touch of Weakness and is never
-- offered Starshards. Looking at your own class, we only show what you could actually learn.
function ns.RaceAllows(races, raceFile)
  if not races or races == "" or races == false then return true end
  if not raceFile then return true end
  return (("," .. races .. ","):find("," .. raceFile .. ",", 1, true)) ~= nil
end

-- The whole ladder, level 1 to 60, in level order. This deliberately does not read your own
-- level or what you have already trained: the narrower "ready to learn now" list did not
-- notice a level-up or a freshly bought rank, so it went stale in front of you. A full ladder
-- is always right. The live version comes back when it can refresh itself properly.
function ns.AbilityLadder(classToken, raceFile)
  local list = (ns.Abilities or {})[classToken] or {}
  local out = {}
  for _, row in ipairs(list) do
    if ns.RaceAllows(row[7], raceFile) then
      table.insert(out, { id = row[1], name = row[2], level = row[3], rank = row[4], icon = row[5],
                          trained = row[6] == true, races = row[7] or false, talent = row[8] == true })
    end
  end
  table.sort(out, function(a, b)
    if a.level ~= b.level then return a.level < b.level end
    if a.name ~= b.name then return a.name < b.name end
    return a.rank < b.rank
  end)
  return out
end

------------------------------------------------------------------------------
local function RowTooltip(row)
  if not row.spellID then return nil end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  if not pcall(GameTooltip.SetSpellByID, GameTooltip, row.spellID) then
    pcall(GameTooltip.SetHyperlink, GameTooltip, "spell:" .. row.spellID)
  end
  -- The price is the useful part. Which trainer taught the player who recorded it is not.
  local trainer = ns.TrainerFor(row.spellID)
  if trainer then
    local cost = ns.CostText(trainer.cost)
    GameTooltip:AddLine(cost and ("Taught by a class trainer for %s"):format(cost)
      or "Taught by a class trainer", 0.25, 0.85, 0.35, true)
  end
  GameTooltip:Show()
  return row.spellID
end

local function BuildRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(ns.PAGE_WIDTH - 40, ROW_H)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(16, 16)
  row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
  row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.text:SetJustifyH("LEFT")
  row.note = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.note:SetPoint("LEFT", row, "LEFT", 300, 0)
  row:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  row:SetScript("OnEnter", function(self) RowTooltip(self) end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return row
end

local function Row(page, index)
  local row = page.rows[index]
  if not row then
    row = BuildRow(page.content)
    page.rows[index] = row
  end
  return row
end

local function Header(page, index, y, text)
  local row = Row(page, index)
  row.spellID = nil
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", page.content, "TOPLEFT", 0, y)
  row.icon:Hide()
  row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
  row.text:SetText(text)
  row.text:SetTextColor(1, 0.82, 0)
  row.note:SetText("")
  row:Show()
  return row
end

local function Spell(page, index, y, spell)
  local row = Row(page, index)
  row.spellID = spell.id
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", page.content, "TOPLEFT", 16, y)
  row.icon:SetTexture(spell.icon ~= "" and ("Interface\\Icons\\" .. spell.icon) or ns.ItemIcon(0))
  row.icon:Show()
  row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.text:SetText(spell.rank > 0 and ("%s (rank %d)"):format(spell.name, spell.rank) or spell.name)
  row.text:SetTextColor(1, 1, 1)
  if spell.races and spell.races ~= "" and spell.races ~= false then
    row.text:SetText(row.text:GetText() .. " |cff9d9d9d(" .. spell.races:gsub(",", ", ") .. ")|r")
  end
  -- A talent is not something you walk in and buy, whatever level it says, so it says so.
  if spell.talent then
    row.text:SetText(row.text:GetText() .. " |cff8080ff(talent)|r")
  end
  -- The level is already the heading above, so the note carries the price instead.
  local trainer = ns.TrainerFor(spell.id)
  local cost = trainer and ns.CostText(trainer.cost)
  row.note:SetText(cost or "")
  row:Show()
  return row
end

local function Build(page)
  page.heading = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  page.heading:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -6)
  page.subheading = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  page.subheading:SetPoint("TOPLEFT", page.heading, "BOTTOMLEFT", 0, -4)
  page.subheading:SetJustifyH("LEFT")
  page.subheading:SetWordWrap(false)

  -- The game's own search box, the one on the profession window, so it looks like it belongs.
  page.search = CreateFrame("EditBox", nil, page, "SearchBoxTemplate")
  page.search:SetSize(200, 20)
  page.search:SetPoint("TOPRIGHT", page, "TOPRIGHT", -28, -10)
  -- The line under the heading runs the width of the page, and the search box sits on top of
  -- its right-hand end: "sometimes differ from Classic" was reading through the box. Stopping
  -- the text at the box is the whole fix, and it stays right when the sentence changes length.
  page.subheading:SetPoint("RIGHT", page.search, "LEFT", -12, 0)
  page.search:SetAutoFocus(false)
  -- Redraw the list in place. Going through SelectScreen would hide the page and show it again,
  -- and hiding a frame takes the keyboard off anything inside it: you got one letter per click.
  page.search:SetScript("OnTextChanged", function(self)
    local instructions = rawget(self, "Instructions")
    if instructions and instructions.SetShown then
      pcall(instructions.SetShown, instructions, (self:GetText() or "") == "")
    end
    Refresh(page, page.classToken)
  end)
  page.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  page.search:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)

  page.list = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
  page.list:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -48)
  page.list:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -26, 8)
  page.content = CreateFrame("Frame", nil, page.list)
  page.content:SetSize(ns.PAGE_WIDTH - 40, 10)
  page.list:SetScrollChild(page.content)
  page.rows = {}
  return page
end

local function Note(page, index, y, text)
  local row = Row(page, index)
  row.spellID = nil
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", page.content, "TOPLEFT", 16, y)
  row.icon:Hide()
  row.text:SetPoint("LEFT", row, "LEFT", 16, 0)
  row.text:SetText(text)
  row.text:SetTextColor(0.6, 0.6, 0.6)
  row.note:SetText("")
  row:Show()
  return row
end

-- "kidney" finds Kidney Shot, and so does "kidney shot"; spacing and case are nobody's problem
-- but ours. An empty search matches everything.
function ns.AbilityMatches(spell, wanted)
  if not wanted or wanted == "" then return true end
  local name = (spell.name or ""):lower()
  if name:find(wanted, 1, true) then return true end
  -- A rank is worth finding too: "sinister strike 5".
  if spell.rank and spell.rank > 0 then
    local withRank = ("%s %d"):format(name, spell.rank)
    if withRank:find(wanted, 1, true) then return true end
  end
  return false
end

function Refresh(page, classToken)
  local token = ns.ClassToken(classToken) or select(2, UnitClass("player"))
  local mine = token == select(2, UnitClass("player"))
  page.classToken = token
  page.heading:SetText((CLASS_NAME[token] or token) .. " abilities")

  local typed = page.search and page.search:GetText()
  local wanted = (type(typed) == "string" and typed or ""):lower():match("^%s*(.-)%s*$")

  -- Another class is browsed whole; your own is narrowed to what your race can train.
  local raceFile = mine and select(2, UnitRace("player")) or nil
  local all = ns.AbilityLadder(token, raceFile)
  local spells = {}
  for _, spell in ipairs(all) do
    if ns.AbilityMatches(spell, wanted) then table.insert(spells, spell) end
  end
  -- false, not nil: a field set to nil is a field nobody set, and the difference has bitten.
  page.searching = wanted ~= "" and wanted or false
  page.matched = #spells

  local used, y, level = 0, 0, nil
  for _, spell in ipairs(spells) do
    if spell.level ~= level then
      level = spell.level
      if used > 0 then y = y - 6 end
      used = used + 1
      Header(page, used, y, ("Level %d"):format(level))
      y = y - HEAD_H
    end
    used = used + 1
    Spell(page, used, y, spell)
    y = y - ROW_H
  end
  if used == 0 then
    used = used + 1
    Note(page, used, y, page.searching
      and ("Nothing matching \"%s\" in this class's abilities."):format(page.searching)
      or "No abilities are known for this class yet.")
    y = y - ROW_H
  end
  for i = used + 1, #page.rows do page.rows[i]:Hide() end
  page.content:SetHeight(math.max(10, -y + 20))

  local talents = 0
  for _, spell in ipairs(spells) do if spell.talent then talents = talents + 1 end end
  local tail = talents > 0 and (" %d of them are talents, not trainer spells."):format(talents) or ""
  page.subheading:SetText(page.searching
    and ("%d matching \"%s\".%s Clear the box for the whole ladder."):format(#spells, page.searching, tail)
    or ("%d abilities, level 1 to 60.%s Ability levels come from the Forever client, and sometimes differ from Classic."):format(#spells, tail))
  page.shownRows = used
  page.total = #spells
  return spells
end

ns.RegisterScreen({
  key = "abilities",
  name = "Abilities",
  icon = "Interface\\Icons\\INV_Misc_Book_09",
  build = Build,
  refresh = Refresh,
})

-- Opens the screen with the box already filled, so "/fb abilities kidney shot" is the same as
-- typing it up there.
function ns.SearchAbilities(text, classToken)
  local window = ns.ShowWindow("abilities", classToken)
  local page = window.pages.abilities
  if page and page.search then
    page.search:SetText(text or "")
    ns.SelectScreen("abilities", page.classToken)
  end
  return page
end

ns.SlashHandlers.abilities = function(rest)
  rest = (rest or ""):match("^%s*(.-)%s*$")
  local token = ns.ClassToken(rest)
  if token then
    ns.SearchAbilities("", token)
    return token
  end
  -- Anything that is not a class is something to look for: a rogue asking about kidney shot
  -- wants the level, not a lecture about class names.
  if rest ~= "" then
    ns.SearchAbilities(rest)
    return rest
  end
  ns.SearchAbilities("")
  return nil
end
ns.SlashHandlers.spells = ns.SlashHandlers.abilities
