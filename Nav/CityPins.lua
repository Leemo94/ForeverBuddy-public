local ADDON, ns = ...

-- Trainers and services on a city map. Open Orgrimmar and every class trainer, profession
-- trainer, bank, auction house and flight master is on it, each kind its own switch in the
-- corner of the map. Positions are Classic's; anything our own records have seen somewhere
-- else is marked on the pin's tooltip.

ns.RegisterFeature({
  key = "citypins",
  name = "City trainers on the map",
  desc = "Marks class and profession trainers, banks, auction houses and the flight master on a city map. Each kind has its own switch in the corner of the map.",
  default = true,
})

local PIN_SIZE, DOT_SIZE = 16, 20
local pins, panel = {}, nil

local byMap
local function CityForMap(mapID)
  if not byMap then
    byMap = {}
    for _, city in ipairs(ns.Cities or {}) do
      if city.map and city.map > 0 then byMap[city.map] = city end
    end
  end
  return mapID and byMap[mapID] or nil
end
ns.CityForMap = CityForMap

-- Trainers a player has recorded that the Classic data never had, or has somewhere else.
-- Forever moved Einris Brightspear, the hunter trainer, out of Ironforge and into Stormwind's
-- Dwarven District, and no Classic source knows that; our own records do.
local CLASS_NAME_OF = {
  WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
  SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}

local recorded

function ns.RecordedTrainers(mapID)
  local observed = ns.Observed
  if not (observed and observed.trainers and observed.npcs) then return {} end
  if not recorded or recorded.source ~= observed.trainers then
    recorded = { source = observed.trainers, byMap = {} }
    for id, trainer in pairs(observed.trainers) do
      local npc = observed.npcs[id]
      if npc and npc.map and npc.x and npc.y then
        local tag = CLASS_NAME_OF[trainer.class or ""]
        local list = recorded.byMap[npc.map] or {}
        table.insert(list, { id = id, kind = tag and "class" or "profession", name = npc.name or trainer.name,
                             sub = tag and (tag .. " Trainer") or "Trainer", tag = tag,
                             x = npc.x, y = npc.y, recorded = true })
        recorded.byMap[npc.map] = list
      end
    end
  end
  return (mapID and recorded.byMap[mapID]) or {}
end

-- Every point of a city that the switches are currently showing: its kind must be on, and so
-- must its own class or profession. Recorded trainers join the list unless the city data
-- already holds that NPC.
function ns.CityPoints(city)
  local out, have = {}, {}
  for _, point in ipairs(city.points or {}) do
    have[point.id] = true
    if ns.PinEnabled(point.kind) and ns.TagEnabled(point.tag) then table.insert(out, point) end
  end
  for _, point in ipairs(ns.RecordedTrainers(city.map)) do
    if not have[point.id] and ns.PinEnabled(point.kind) and ns.TagEnabled(point.tag) then
      table.insert(out, point)
    end
  end
  return out
end

local function Canvas()
  local container = WorldMapFrame and WorldMapFrame.ScrollContainer
  return container and container.Child or container or WorldMapFrame
end

local function PinTooltip(pin)
  local point = pin.point
  if not point then return nil end
  GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
  GameTooltip:ClearLines()
  GameTooltip:AddLine(point.name)
  local def = ns.pinIndex[point.kind]
  GameTooltip:AddLine(point.sub ~= "" and point.sub or (def and def.name) or point.kind, 0.8, 0.8, 0.8, true)
  GameTooltip:AddLine(("%.1f, %.1f"):format(point.x, point.y), 0.6, 0.6, 0.6)
  if point.recorded then
    GameTooltip:AddLine("Recorded here in Forever", 0.25, 0.85, 0.35, true)
  else
    local seen = ns.Observed and ns.Observed.npcs and ns.Observed.npcs[point.id]
    if seen and seen.x and (math.abs(seen.x - point.x) > 2 or math.abs(seen.y - point.y) > 2) then
      GameTooltip:AddLine(("Seen in Forever at %.1f, %.1f"):format(seen.x, seen.y), 1, 0.82, 0, true)
    end
  end
  GameTooltip:Show()
  return point.name
end

-- Blizzard's own pins, the quest ! and ? above all, are handed frame levels in the hundreds by
-- the map's pin manager. Ours sit just above the map art and below every one of them, so a
-- trainer dot never covers a quest giver and never takes the mouse-over off one.
local PIN_LEVEL_ABOVE_MAP = 2

-- The pins themselves, for the tests.
function ns.CityPinFrames()
  return pins
end

function ns.CityPinFrameLevel(canvas)
  local base = canvas and canvas.GetFrameLevel and canvas:GetFrameLevel()
  return (type(base) == "number" and base or 1) + PIN_LEVEL_ABOVE_MAP
end

local function BuildPin(parent, index)
  local pin = CreateFrame("Button", nil, parent)
  pin:SetSize(DOT_SIZE, DOT_SIZE)
  pin.dot = pin:CreateTexture(nil, "BACKGROUND")
  pin.dot:SetAllPoints()
  pin.icon = pin:CreateTexture(nil, "ARTWORK")
  pin.icon:SetSize(PIN_SIZE, PIN_SIZE)
  pin.icon:SetPoint("CENTER")
  pin:SetScript("OnEnter", function(self) PinTooltip(self) end)
  pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
  pins[index] = pin
  return pin
end

------------------------------------------------------------------------------
-- Which trainer is which: a class wears its own class icon, a profession its trade icon
------------------------------------------------------------------------------
local CLASS_SHEET = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local CLASS_OF_TAG = {
  Warrior = "WARRIOR", Paladin = "PALADIN", Hunter = "HUNTER", Rogue = "ROGUE", Priest = "PRIEST",
  Shaman = "SHAMAN", Mage = "MAGE", Warlock = "WARLOCK", Druid = "DRUID",
  ["Mage portals"] = "MAGE",
}
local PROFESSION_ICON = {
  Alchemy = "Trade_Alchemy", Blacksmithing = "Trade_BlackSmithing", Enchanting = "Trade_Engraving",
  Engineering = "Trade_Engineering", Herbalism = "Trade_Herbalism", Leatherworking = "Trade_LeatherWorking",
  Mining = "Trade_Mining", Tailoring = "Trade_Tailoring", Cooking = "INV_Misc_Food_15",
  ["First Aid"] = "Spell_Holy_SealOfSacrifice", Fishing = "Trade_Fishing", Poisons = "Trade_BrewPoison",
}

-- texture, and the corner of the class sheet to crop to when it is a class.
function ns.PinArt(kind, tag)
  if kind == "class" then
    local token = CLASS_OF_TAG[tag]
    local coords = token and rawget(_G, "CLASS_ICON_TCOORDS")
    if coords and coords[token] then return CLASS_SHEET, coords[token] end
  elseif kind == "profession" then
    local icon = PROFESSION_ICON[tag]
    if icon then return "Interface\\Icons\\" .. icon, nil end
  end
  local def = ns.pinIndex[kind]
  return def and def.icon or nil, nil
end

-- The classes or professions a city actually trains, in the order they should be listed.
function ns.CityTags(city, kind)
  local seen, out = {}, {}
  local points = {}
  for _, point in ipairs(city.points or {}) do table.insert(points, point) end
  for _, point in ipairs(ns.RecordedTrainers(city.map)) do table.insert(points, point) end
  for _, point in ipairs(points) do
    if point.kind == kind and point.tag and not seen[point.tag] then
      seen[point.tag] = true
      table.insert(out, point.tag)
    end
  end

  table.sort(out)
  return out
end

------------------------------------------------------------------------------
-- The switches, in the corner of the map
------------------------------------------------------------------------------
local PANEL_W, ROW_H = 196, 19
local WITH_TAGS = { class = true, profession = true }

local function PanelRow(panel, index)
  local row = panel.rows[index]
  if row then return row end
  row = CreateFrame("Frame", nil, panel)
  row:SetSize(PANEL_W - 12, ROW_H)
  row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
  row.check:SetSize(18, 18)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(14, 14)
  row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.label:SetJustifyH("LEFT")
  row.expand = CreateFrame("Button", nil, row)
  row.expand:SetSize(18, 18)
  row.expand:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  row.expand.label = row.expand:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.expand.label:SetAllPoints()
  row.all = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.all:SetSize(40, 16)
  row.none = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.none:SetSize(48, 16)
  panel.rows[index] = row
  return row
end

local function LayOut(row, y, indent)
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", row:GetParent(), "TOPLEFT", 8 + indent, y)
  row.check:ClearAllPoints()
  row.check:SetPoint("LEFT", row, "LEFT", 0, 0)
  row.icon:ClearAllPoints()
  row.icon:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
  row.label:ClearAllPoints()
  row.label:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
  row.label:SetWidth(PANEL_W - 60 - indent)
  row:Show()
end

local function KindRow(panel, index, y, def)
  local row = PanelRow(panel, index)
  LayOut(row, y, 0)
  row.check:Show()
  row.check:SetChecked(ns.PinEnabled(def.key))
  row.check.pinKey = def.key
  row.check:SetScript("OnClick", function(self)
    ns.SetPinEnabled(def.key, self:GetChecked() and true or false)
    ns.UpdateCityPins()
  end)
  row.icon:SetTexture(def.icon)
  row.icon:SetTexCoord(0, 1, 0, 1)
  row.icon:Show()
  row.label:SetText(def.name)
  row.all:Hide()
  row.none:Hide()
  if WITH_TAGS[def.key] then
    row.expand.label:SetText(panel.open[def.key] and "-" or "+")
    row.expand:SetScript("OnClick", function()
      panel.open[def.key] = not panel.open[def.key]
      ns.UpdateCityPins()
    end)
    row.expand:Show()
  else
    row.expand:Hide()
  end
  return row
end

local function TagRow(panel, index, y, kind, tag)
  local row = PanelRow(panel, index)
  LayOut(row, y, 16)
  row.check:Show()
  row.check:SetChecked(ns.TagEnabled(tag))
  row.check.pinKey = nil
  row.check.pinTag = tag
  row.check:SetScript("OnClick", function(self)
    ns.SetTagEnabled(tag, self:GetChecked() and true or false)
    ns.UpdateCityPins()
  end)
  local texture, coords = ns.PinArt(kind, tag)
  row.icon:SetTexture(texture)
  if coords then row.icon:SetTexCoord(unpack(coords)) else row.icon:SetTexCoord(0, 1, 0, 1) end
  row.icon:Show()
  row.label:SetText(tag)
  row.expand:Hide()
  row.all:Hide()
  row.none:Hide()
  return row
end

local function AllNoneRow(panel, index, y, kind, tags)
  local row = PanelRow(panel, index)
  LayOut(row, y, 16)
  row.check:Hide()
  row.icon:Hide()
  row.label:SetText("")
  row.expand:Hide()
  local function set(on)
    for _, tag in ipairs(tags) do ns.SetTagEnabled(tag, on) end
    ns.UpdateCityPins()
  end
  row.all:ClearAllPoints()
  row.all:SetPoint("LEFT", row, "LEFT", 0, 0)
  row.all:SetText("All")
  row.all:SetScript("OnClick", function() set(true) end)
  row.all:Show()
  row.none:ClearAllPoints()
  row.none:SetPoint("LEFT", row.all, "RIGHT", 4, 0)
  row.none:SetText("None")
  row.none:SetScript("OnClick", function() set(false) end)
  row.none:Show()
  return row
end

local function BuildPanel(canvas)
  if not panel then
    panel = CreateFrame("Frame", "ForeverBuddyCityPins", canvas)
    panel:SetPoint("TOPLEFT", canvas, "TOPLEFT", 12, -12)
    panel.bg = panel:CreateTexture(nil, "BACKGROUND")
    panel.bg:SetAllPoints()
    panel.bg:SetColorTexture(0, 0, 0, 0.7)
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
    panel.rows = {}
    panel.open = {}
  end
  panel:SetParent(canvas)
  panel:SetFrameStrata("HIGH")
  return panel
end

-- Draws the switch list for this city and returns how many rows it used.
local function FillPanel(frame, city)
  local used, y = 0, -24
  for _, def in ipairs(ns.PIN_KINDS) do
    used = used + 1
    KindRow(frame, used, y, def)
    y = y - ROW_H
    if WITH_TAGS[def.key] and frame.open[def.key] then
      local tags = ns.CityTags(city, def.key)
      if #tags > 0 then
        used = used + 1
        AllNoneRow(frame, used, y, def.key, tags)
        y = y - ROW_H
        for _, tag in ipairs(tags) do
          used = used + 1
          TagRow(frame, used, y, def.key, tag)
          y = y - ROW_H
        end
      end
    end
  end
  for i = used + 1, #frame.rows do frame.rows[i]:Hide() end
  frame:SetSize(PANEL_W, -y + 8)
  frame.checks = {}
  for i = 1, used do
    local check = frame.rows[i].check
    if check.pinKey then table.insert(frame.checks, check) end
  end
  frame.shownRows = used
  return used
end

------------------------------------------------------------------------------
function ns.UpdateCityPins()
  local canvas = Canvas()
  if not canvas then return nil end
  local mapID = WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
  local city = CityForMap(mapID)
  local on = ns.IsFeatureEnabled("citypins") and city and WorldMapFrame and WorldMapFrame:IsShown()
  if not on then
    for _, pin in ipairs(pins) do pin:Hide() end
    if panel then panel:Hide() end
    ns.shownCityPins = nil
    return nil
  end

  local frame = BuildPanel(canvas)
  frame.title:SetText(city.name)
  FillPanel(frame, city)
  frame:Show()

  local width, height = canvas:GetWidth() or 0, canvas:GetHeight() or 0
  local level = ns.CityPinFrameLevel(canvas)
  local shown = 0
  for _, point in ipairs(ns.CityPoints(city)) do
    shown = shown + 1
    local pin = pins[shown] or BuildPin(canvas, shown)
    pin.point = point
    local def = ns.pinIndex[point.kind]
    pin.dot:SetColorTexture(def.color[1], def.color[2], def.color[3], 0.9)
    local texture, coords = ns.PinArt(point.kind, point.tag)
    pin.icon:SetTexture(texture)
    if coords then pin.icon:SetTexCoord(unpack(coords)) else pin.icon:SetTexCoord(0, 1, 0, 1) end
    pin:ClearAllPoints()
    pin:SetPoint("CENTER", canvas, "TOPLEFT", point.x / 100 * width, -point.y / 100 * height)
    pin:SetFrameStrata(canvas:GetFrameStrata() or "MEDIUM")
    pin:SetFrameLevel(level)
    pin:Show()
  end
  for i = shown + 1, #pins do pins[i]:Hide() end
  ns.shownCityPins = shown
  return shown
end

local function Hook()
  if not WorldMapFrame or ns.cityPinsHooked then return false end
  ns.cityPinsHooked = true
  WorldMapFrame:HookScript("OnShow", ns.UpdateCityPins)
  if WorldMapFrame.OnMapChanged then
    hooksecurefunc(WorldMapFrame, "OnMapChanged", ns.UpdateCityPins)
  end
  if EventRegistry and EventRegistry.RegisterCallback then
    pcall(EventRegistry.RegisterCallback, EventRegistry, "WorldMapOnMapChanged", ns.UpdateCityPins, ns)
  end
  return true
end

Hook()
local waiter = CreateFrame("Frame")
waiter:RegisterEvent("PLAYER_ENTERING_WORLD")
waiter:SetScript("OnEvent", function(self)
  if Hook() then self:UnregisterEvent("PLAYER_ENTERING_WORLD") end
  ns.UpdateCityPins()
end)
