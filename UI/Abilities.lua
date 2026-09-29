local ADDON, ns = ...

-- What your class can learn now, and everything it learns after that, to 60. The levels are
-- Forever's own, which is why Hammer of Justice sits at 24 here and at 20 in Classic.

local ROW_H, HEAD_H = 18, 22

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

local function Known(spellID)
  local check = rawget(_G, "IsSpellKnown")
  if not check then return false end
  local ok, known = pcall(check, spellID)
  return (ok and known) and true or false
end
ns.SpellKnown = Known

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

-- Two lists: what this character could learn at once, and the ladder above their level.
-- Some abilities belong to one race: an Undead priest trains Touch of Weakness and is never
-- offered Starshards. Looking at your own class, we only show what you could actually learn.
function ns.RaceAllows(races, raceFile)
  if not races or races == "" or races == false then return true end
  if not raceFile then return true end
  return (("," .. races .. ","):find("," .. raceFile .. ",", 1, true)) ~= nil
end

function ns.AbilityPlan(classToken, level, raceFile)
  local list = (ns.Abilities or {})[classToken] or {}
  local ready, later = {}, {}
  for _, row in ipairs(list) do
    if ns.RaceAllows(row[7], raceFile) then
      local spell = { id = row[1], name = row[2], level = row[3], rank = row[4], icon = row[5],
                      trained = row[6] == true, races = row[7] or false }
      if spell.level <= level then
        if not Known(spell.id) then table.insert(ready, spell) end
      else
        table.insert(later, spell)
      end
    end
  end
  return ready, later
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

local function Spell(page, index, y, spell, showLevel)
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
  -- What a trainer charges beats a level number: it is the thing you are about to pay.
  local trainer = ns.TrainerFor(spell.id)
  local cost = trainer and ns.CostText(trainer.cost)
  row.note:SetText(cost or (showLevel and ("level %d"):format(spell.level)) or "")
  row:Show()
  return row
end

local function Build(page)
  page.heading = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  page.heading:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -6)
  page.subheading = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  page.subheading:SetPoint("TOPLEFT", page.heading, "BOTTOMLEFT", 0, -4)
  page.list = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
  page.list:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -48)
  page.list:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -26, 8)
  page.content = CreateFrame("Frame", nil, page.list)
  page.content:SetSize(ns.PAGE_WIDTH - 40, 10)
  page.list:SetScrollChild(page.content)
  page.rows = {}
  return page
end

local function Refresh(page, classToken)
  local token = ns.ClassToken(classToken) or select(2, UnitClass("player"))
  local level = UnitLevel("player") or 1
  local mine = token == select(2, UnitClass("player"))
  page.classToken = token
  page.heading:SetText((CLASS_NAME[token] or token) .. " abilities")

  -- Another class is browsed whole; your own is narrowed to what your race can train.
  local raceFile = mine and select(2, UnitRace("player")) or nil
  local ready, later = ns.AbilityPlan(token, mine and level or 0, raceFile)
  local used, y = 0, 0
  used = used + 1
  Header(page, used, y, mine and ("Ready to learn at level %d"):format(level) or "From level 1")
  y = y - HEAD_H
  if #ready == 0 then
    used = used + 1
    local row = Row(page, used)
    row.spellID = nil
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", page.content, "TOPLEFT", 16, y)
    row.icon:Hide()
    row.text:SetPoint("LEFT", row, "LEFT", 16, 0)
    row.text:SetText("Nothing new for you at this level.")
    row.text:SetTextColor(0.6, 0.6, 0.6)
    row.note:SetText("")
    row:Show()
    y = y - ROW_H
  end
  for _, spell in ipairs(ready) do
    used = used + 1
    Spell(page, used, y, spell, true)
    y = y - ROW_H
  end

  local level_ = nil
  for _, spell in ipairs(later) do
    if spell.level ~= level_ then
      level_ = spell.level
      y = y - 6
      used = used + 1
      Header(page, used, y, ("Level %d"):format(spell.level))
      y = y - HEAD_H
    end
    used = used + 1
    Spell(page, used, y, spell, false)
    y = y - ROW_H
  end
  for i = used + 1, #page.rows do page.rows[i]:Hide() end
  page.content:SetHeight(math.max(10, -y + 20))

  local nextLevel = later[1] and later[1].level
  page.subheading:SetText(("%d to learn now, %s. Ability levels come from the Forever client, and sometimes differ from Classic."):format(
    #ready, nextLevel and ("next at level %d"):format(nextLevel) or "nothing further to come"))
  page.shownRows = used
  page.readyCount = #ready
  return ready, later
end

ns.RegisterScreen({
  key = "abilities",
  name = "Abilities",
  icon = "Interface\\Icons\\INV_Misc_Book_09",
  build = Build,
  refresh = Refresh,
})

ns.SlashHandlers.abilities = function(rest)
  local token = ns.ClassToken(rest)
  if rest ~= "" and not token then
    ns.Print("no class called " .. rest .. ". Try /fb abilities paladin, or /fb abilities for your own.")
    return nil
  end
  ns.ShowWindow("abilities", token)
  return token
end
ns.SlashHandlers.spells = ns.SlashHandlers.abilities
