local ADDON, ns = ...

-- SHELVED for the first release. It judges an upgrade by the item scores, and those are wrong
-- until the spell power wording is read properly, so it would offer the wrong gear. The code
-- and its tests are untouched: turning SHIPPING back on is the whole job.
local SHIPPING = false

if SHIPPING then
  ns.RegisterFeature({
    key = "autoequip",
    name = "Equip upgrade prompts",
    desc = "When gear you can wear lands in your bags with a higher item level than what you have on, asks whether to equip it. Never equips on its own.",
    default = true,
  })
end

-- ns.EQUIP_SLOTS (Core.lua) maps equip locations to inventory slots.

local SCAN_NAME = "ForeverBuddyScanTooltip"
local scanTip = CreateFrame("GameTooltip", SCAN_NAME, UIParent, "GameTooltipTemplate")

-- Armour a class can wear: the heaviest type, and the lighter ones below it. Plate and mail
-- arrive at level 40. Cloaks and jewellery (the Generic subclass) are worn by everyone.
local ARMOR_GENERIC, ARMOR_CLOTH, ARMOR_LEATHER, ARMOR_MAIL, ARMOR_PLATE, ARMOR_SHIELD = 0, 1, 2, 3, 4, 6
local HEAVIEST_ARMOR = {
  WARRIOR = { early = ARMOR_MAIL, late = ARMOR_PLATE }, PALADIN = { early = ARMOR_MAIL, late = ARMOR_PLATE },
  HUNTER = { early = ARMOR_LEATHER, late = ARMOR_MAIL }, SHAMAN = { early = ARMOR_LEATHER, late = ARMOR_MAIL },
  ROGUE = { early = ARMOR_LEATHER, late = ARMOR_LEATHER }, DRUID = { early = ARMOR_LEATHER, late = ARMOR_LEATHER },
  PRIEST = { early = ARMOR_CLOTH, late = ARMOR_CLOTH }, MAGE = { early = ARMOR_CLOTH, late = ARMOR_CLOTH },
  WARLOCK = { early = ARMOR_CLOTH, late = ARMOR_CLOTH },
}
local ARMOR_LEVEL = 40
local SHIELD_CLASSES = { WARRIOR = true, PALADIN = true, SHAMAN = true }
local RELIC_CLASSES = { [7] = "PALADIN", [8] = "DRUID", [9] = "SHAMAN", [10] = "DEATHKNIGHT" } -- Libram, Idol, Totem, Sigil
local ITEM_CLASS_ARMOR = 4

-- Forever can return "secret" values to addons, e.g. a tooltip line's colour. Never compare those.
local function public(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

-- false only when the character certainly cannot wear this armour: mail on a mage, a shield on a
-- rogue, another class's relic. Anything else (weapons, unknown items) is left to the tooltip check.
function ns.IsArmorWearable(itemID)
  local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
  if classID ~= ITEM_CLASS_ARMOR then return true end
  if equipLoc == "INVTYPE_CLOAK" or subclassID == ARMOR_GENERIC then return true end
  local _, token = UnitClass("player")
  if subclassID == ARMOR_SHIELD then return SHIELD_CLASSES[token] == true end
  if RELIC_CLASSES[subclassID] then return RELIC_CLASSES[subclassID] == token end
  local allowed = HEAVIEST_ARMOR[token]
  if not allowed then return true end
  local heaviest = (UnitLevel("player") or 1) >= ARMOR_LEVEL and allowed.late or allowed.early
  if subclassID >= ARMOR_CLOTH and subclassID <= ARMOR_PLATE then return subclassID <= heaviest end
  return true
end

local declined = {}      -- [itemID] = true, for this session
local waiting = {}       -- [itemID] = true: the server had not sent the item's data yet
local counts = {}        -- [itemID] = how many were in the bags at the last scan
local baselined = false  -- bag updates before the first world entry are ignored
local pending            -- an upgrade found in combat, prompted once combat ends

-- Item level decides; quality breaks ties. nil when the item is not cached.
local function Score(itemID)
  local _, _, quality, itemLevel = C_Item.GetItemInfo(itemID)
  if not itemLevel then return nil end
  return itemLevel * 10 + (quality or 0)
end

-- The slot this equip location would replace: the weakest of its candidate slots. Empty slots score -1.
function ns.WeakestSlot(equipLoc)
  local slots = ns.EQUIP_SLOTS[equipLoc]
  if not slots then return nil end
  local bestSlot, bestItem, bestScore
  for _, slot in ipairs(slots) do
    local current = GetInventoryItemID("player", slot)
    local score = current and Score(current) or -1
    if bestScore == nil or score < bestScore then
      bestSlot, bestItem, bestScore = slot, current, score
    end
  end
  return bestSlot, bestItem, bestScore
end

-- Can the character use this at all: class, level, armour type, weapon skill. Forever answers
-- directly; on clients without that, fall back to the red tooltip text.
function ns.IsBagItemUsable(bag, slot, itemID)
  if itemID and C_PlayerInfo and C_PlayerInfo.CanUseItem then
    local ok, usable = pcall(C_PlayerInfo.CanUseItem, itemID)
    if ok and type(usable) == "boolean" then return usable end
  end
  scanTip:SetOwner(UIParent, "ANCHOR_NONE")
  scanTip:ClearLines()
  scanTip:SetBagItem(bag, slot)
  for i = 2, scanTip:NumLines() do
    local line = _G[SCAN_NAME .. "TextLeft" .. i]
    if line then
      local r, g, b = line:GetTextColor()
      r, g, b = public(r), public(g), public(b)
      if type(r) == "number" and type(g) == "number" and type(b) == "number"
        and r > 0.9 and g < 0.2 and b < 0.2 then return false end
    end
  end
  return true
end

-- The spec score (stat weights) for a new item and for what is worn in that slot, when both can
-- be scored. A priest's staff with spell power beats a higher-damage sword that has none.
local function SpecScores(itemID, link, equipLoc)
  if not (ns.PlayerSpecKey and ns.ScoreItem and ns.EquippedScore and ns.Weights) then return nil end
  local specKey = ns.PlayerSpecKey()
  local spec = specKey and ns.Weights[specKey]
  if not spec then return nil end
  local new = ns.ScoreItem(spec, itemID, link)
  if not new then return nil end
  return new, ns.EquippedScore(spec, equipLoc)
end

-- Returns an upgrade record for the item at bag/slot, or nil.
function ns.FindUpgrade(bag, slot, itemID)
  if declined[itemID] then return nil end
  local _, _, _, equipLoc = C_Item.GetItemInfoInstant(itemID)
  if not ns.EQUIP_SLOTS[equipLoc] then return nil end
  if not ns.IsArmorWearable(itemID) then return nil end
  local name, link, quality, itemLevel = C_Item.GetItemInfo(itemID)
  -- A slow or busy server sends item data late; ask for it and look again when it arrives.
  if not itemLevel then
    waiting[itemID] = true
    if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
    return nil
  end
  if quality == Enum.ItemQuality.Poor then return nil end
  local newScore = itemLevel * 10 + (quality or 0)
  local invSlot, currentID, currentScore = ns.WeakestSlot(equipLoc)
  local newSpecScore, wornSpecScore = SpecScores(itemID, link, equipLoc)
  if newSpecScore and wornSpecScore then
    if newSpecScore <= wornSpecScore then return nil end
  elseif currentScore >= newScore then
    return nil
  end
  if not ns.IsBagItemUsable(bag, slot, itemID) then return nil end
  return { itemID = itemID, name = name, link = link, slot = invSlot, currentID = currentID, bag = bag, bagSlot = slot }
end

StaticPopupDialogs.FOREVERBUDDY_EQUIP = {
  text = "ForeverBuddy: equip %s?\nIt replaces %s.",
  button1 = "Equip",
  button2 = "Keep",
  OnAccept = function(_, data) C_Item.EquipItemByName(data.link, data.slot) end,
  OnCancel = function(_, data) declined[data.itemID] = true end,
  timeout = 0,
  whileDead = false,
  hideOnEscape = true,
  preferredIndex = 3,
}

function ns.PromptEquip(upgrade)
  if InCombatLockdown() then
    pending = upgrade
    return "deferred"
  end
  local replaces = "an empty slot"
  if upgrade.currentID then
    local _, currentLink = C_Item.GetItemInfo(upgrade.currentID)
    replaces = currentLink or "your current item"
  end
  StaticPopup_Show("FOREVERBUDDY_EQUIP", upgrade.link, replaces, upgrade)
  return "prompted"
end

-- Counts every item in the bags and remembers one location per item.
local function ScanBags()
  local found, where = {}, {}
  for bag = 0, NUM_BAG_SLOTS do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID then
        found[info.itemID] = (found[info.itemID] or 0) + 1
        where[info.itemID] = where[info.itemID] or { bag = bag, slot = slot }
      end
    end
  end
  return found, where
end

-- Looks again at everything in the bags, ignoring the "is it new?" counts. Used when item data
-- the server owed us finally arrives.
function ns.RecheckBags()
  if not baselined or not ns.IsFeatureEnabled("autoequip") then return nil end
  local _, where = ScanBags()
  for itemID, loc in pairs(where) do
    local upgrade = ns.FindUpgrade(loc.bag, loc.slot, itemID)
    if upgrade then return ns.PromptEquip(upgrade) end
  end
  return nil
end

function ns.OnBagUpdate()
  if not baselined then return end
  local found, where = ScanBags()
  if ns.IsFeatureEnabled("autoequip") then
    for itemID, n in pairs(found) do
      if n > (counts[itemID] or 0) then
        local loc = where[itemID]
        local upgrade = ns.FindUpgrade(loc.bag, loc.slot, itemID)
        if upgrade then
          counts = found
          return ns.PromptEquip(upgrade)
        end
      end
    end
  end
  counts = found
end

local frame = CreateFrame("Frame")
function ns.HookEquipPrompts()
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("BAG_UPDATE_DELAYED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "PLAYER_ENTERING_WORLD" then
    counts = ScanBags()
    baselined = true
  elseif event == "BAG_UPDATE_DELAYED" then
    ns.OnBagUpdate()
  elseif event == "GET_ITEM_INFO_RECEIVED" then
    if arg1 and waiting[arg1] then
      waiting[arg1] = nil
      ns.RecheckBags()
    end
  elseif event == "PLAYER_REGEN_ENABLED" and pending then
    local upgrade = pending
    pending = nil
    ns.PromptEquip(upgrade)
  end
end)

  return true
end

if SHIPPING then ns.HookEquipPrompts() end
