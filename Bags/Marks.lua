local ADDON, ns = ...

-- Markers on bag icons: quest (a quest still needs it), junk (will be sold), upgrade (beats what
-- you wear), plus item level on gear.
--
-- SHELVED for the first release: the markers do not appear in the Forever beta. The working
-- parts are all still here and tested, so turning SHIPPING back on is the whole job once the
-- bag frames behave. Nothing registers while it is off, so no switch is offered for something
-- that would do nothing.
local SHIPPING = false

if SHIPPING then
  ns.RegisterFeature({
    key = "bagmarks",
    name = "Bag icon markers",
    desc = "Marks bag icons: quest mark on items a quest still needs, coin on junk that will be sold, green arrow on gear that beats what you wear, item level on gear.",
    default = true,
  })
end

ns.BAG_MARK_ICONS = {
  keep = "Interface\\GossipFrame\\ActiveQuestIcon",
  junk = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
  upgrade = "Interface\\Buttons\\UI-MicroStream-Green",
}

local function IsGear(classID, equipLoc)
  return (classID == 2 or classID == 4) and ns.EQUIP_SLOTS[equipLoc] ~= nil
end

-- Returns markKind|nil, itemLevel|nil for a bag slot's item info.
function ns.BagMarkFor(bag, slot, info)
  if not info or not info.itemID then return nil end
  local itemID = info.itemID
  local kind
  local sellReason = ns.SellReason and ns.SellReason(bag, slot, info)
  if sellReason then kind = "junk" end
  local name, link, quality, itemLevel, _, _, _, _, equipLoc, _, _, classID = C_Item.GetItemInfo(itemID)
  if ns.IsFeatureEnabled("usedfor") and ns.CollectQuests and ns.GetVerdict then
    local verdict = ns.GetVerdict(ns.CollectQuests(itemID, name), ns.Recipes[itemID])
    if verdict and verdict:sub(1, 4) == "KEEP" then kind = "keep" end
  end
  local ilvl
  if IsGear(classID, equipLoc) and (quality or 0) >= 2 then
    ilvl = itemLevel
    if kind == nil and ns.IsFeatureEnabled("itemscore") and ns.PlayerSpecKey then
      local specKey = ns.PlayerSpecKey()
      local spec = specKey and ns.Weights[specKey]
      if spec then
        local score = ns.ScoreItem(spec, itemID, link)
        local equipped = score and ns.EquippedScore(spec, equipLoc)
        if score and equipped and score > equipped then kind = "upgrade" end
      end
    end
  end
  return kind, ilvl
end

local overlays = setmetatable({}, { __mode = "k" }) -- button -> overlay, without touching Blizzard's button fields

function ns.BagOverlay(button)
  return overlays[button]
end

local function Overlay(button)
  if overlays[button] then return overlays[button] end
  local mark = {}
  mark.icon = button:CreateTexture(nil, "OVERLAY")
  mark.icon:SetSize(14, 14)
  mark.icon:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
  mark.icon:Hide()
  mark.text = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  mark.text:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
  mark.text:Hide()
  overlays[button] = mark
  return mark
end

function ns.ApplyBagMark(button, bag, slot)
  local mark = Overlay(button)
  if not ns.IsFeatureEnabled("bagmarks") then
    mark.icon:Hide(); mark.text:Hide()
    return nil
  end
  local info = C_Container.GetContainerItemInfo(bag, slot)
  local kind, ilvl = ns.BagMarkFor(bag, slot, info)
  if kind then
    mark.icon:SetTexture(ns.BAG_MARK_ICONS[kind])
    mark.icon:Show()
  else
    mark.icon:Hide()
  end
  if ilvl then
    mark.text:SetText(tostring(ilvl))
    mark.text:Show()
  else
    mark.text:Hide()
  end
  return kind, ilvl
end

local function ButtonsOf(frame)
  if type(rawget(frame, "EnumerateValidItems")) == "function" then -- Mainline (Forever) container frames
    local buttons = {}
    for _, button in frame:EnumerateValidItems() do table.insert(buttons, button) end
    return buttons
  end
  if frame.Items then return frame.Items end
  local buttons, name = {}, frame:GetName()
  for i = 1, (frame.size or 0) do
    local button = name and _G[name .. "Item" .. i]
    if button then table.insert(buttons, button) end
  end
  return buttons
end

function ns.UpdateContainerMarks(frame)
  local bag = frame:GetID()
  for _, button in ipairs(ButtonsOf(frame)) do
    ns.ApplyBagMark(button, bag, button:GetID())
  end
end

local function SafeUpdate(frame)
  local ok, err = pcall(ns.UpdateContainerMarks, frame)
  if not ok and not ns.bagMarkErrorReported then
    ns.bagMarkErrorReported = true
    ns.Print("bag marker error (reported once per session): " .. tostring(err))
  end
end

-- Nothing of the game's is touched while this is shelved.
function ns.HookBagFrames()
  if ContainerFrame_Update then
    hooksecurefunc("ContainerFrame_Update", SafeUpdate) -- Classic bag frames
    return "ContainerFrame_Update"
  elseif ContainerFrameMixin and ContainerFrameMixin.UpdateItems then
    hooksecurefunc(ContainerFrameMixin, "UpdateItems", SafeUpdate) -- Mainline and Forever, combined bags included
    return "ContainerFrameMixin"
  end
  return nil
end

if SHIPPING then ns.HookBagFrames() end
