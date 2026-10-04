local ADDON, ns = ...

ns.RegisterFeature({
  key = "selljunk",
  name = "Sell junk",
  desc = "Sells grey (poor quality) items automatically when you open a vendor. Ctrl + right click an item in your bags to add it to the list, or to protect a grey one.",
  default = true,
})

ns.RegisterFeature({
  key = "sellunusable",
  name = "Sell unusable soulbound gear",
  desc = "Also sells soulbound uncommon and rare armour or weapons your class cannot use, unless a quest still needs them or they are on your keep list.",
  default = false,
})

local function Rules()
  if not ns.db then return nil end
  ns.db.junk = ns.db.junk or { keep = {}, sell = {} }
  ns.db.junk.keep = ns.db.junk.keep or {}
  ns.db.junk.sell = ns.db.junk.sell or {}
  return ns.db.junk
end

-- Lists an item as "keep" or "sell", or takes it off both with nil. Saved straight away: the
-- beta client does not read our file back at login, so the settings fallback carries them.
function ns.SetJunkRule(itemID, rule)
  local rules = Rules()
  if not (rules and itemID) then return nil end
  rules.keep[itemID], rules.sell[itemID] = nil, nil
  if rule == "keep" then rules.keep[itemID] = true
  elseif rule == "sell" then rules.sell[itemID] = true end
  ns.SaveSettingsFallback()
  return rule
end

-- "keep", "sell", or nil for an item the player has listed.
function ns.JunkRule(itemID)
  local rules = Rules()
  if not rules then return nil end
  if rules.keep[itemID] then return "keep" end
  if rules.sell[itemID] then return "sell" end
  return nil
end

local function IsUnusableGear(bag, slot, info)
  if not (info.isBound and (info.quality == 2 or info.quality == 3)) then return false end
  local _, _, _, equipLoc, _, classID = C_Item.GetItemInfoInstant(info.itemID)
  if not ((classID == 2 or classID == 4) and ns.EQUIP_SLOTS[equipLoc]) then return false end
  if not ns.IsBagItemUsable or ns.IsBagItemUsable(bag, slot) then return false end
  if ns.CollectQuests and ns.GetVerdict then
    local name = C_Item.GetItemInfo(info.itemID)
    local verdict = ns.GetVerdict(ns.CollectQuests(info.itemID, name), ns.Recipes[info.itemID])
    if verdict and verdict:sub(1, 4) == "KEEP" then return false end
  end
  return true
end

-- Why a bag slot would be sold: "junk", "listed", "unusable", or nil to keep it.
function ns.SellReason(bag, slot, info)
  if not info or not info.itemID or info.hasNoValue or info.isLocked then return nil end
  local rule = ns.JunkRule(info.itemID)
  if rule == "keep" then return nil end
  if rule == "sell" then return "listed" end
  if info.quality == Enum.ItemQuality.Poor then return "junk" end
  if ns.IsFeatureEnabled("sellunusable") and IsUnusableGear(bag, slot, info) then return "unusable" end
  return nil
end

-- Sells everything SellReason approves. Returns count, total copper, and a per-reason count table.
function ns.SellJunk()
  local count, total, reasons = 0, 0, {}
  for bag = 0, NUM_BAG_SLOTS do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      local reason = ns.SellReason(bag, slot, info)
      if reason then
        local sellPrice = select(11, C_Item.GetItemInfo(info.itemID))
        total = total + (sellPrice or 0) * (info.stackCount or 1)
        count = count + 1
        reasons[reason] = (reasons[reason] or 0) + 1
        C_Container.UseContainerItem(bag, slot)
      end
    end
  end
  return count, total, reasons
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("MERCHANT_SHOW")
frame:SetScript("OnEvent", function()
  if not ns.IsFeatureEnabled("selljunk") then return end
  local count, total, reasons = ns.SellJunk()
  if count > 0 then
    local extra = {}
    if (reasons.unusable or 0) > 0 then table.insert(extra, ("%d unusable"):format(reasons.unusable)) end
    if (reasons.listed or 0) > 0 then table.insert(extra, ("%d listed"):format(reasons.listed)) end
    ns.Print(("sold %d item%s for %s%s"):format(count, count == 1 and "" or "s", GetMoneyString(total, true),
      #extra > 0 and (" (" .. table.concat(extra, ", ") .. ")") or ""))
  end
end)

-- /fb junk keep|sell|clear <item link or id>, /fb junk list ------------------------
local function ParseItem(text)
  local id = tonumber(text:match("item:(%d+)")) or tonumber(text:match("^(%d+)$"))
  return id
end

ns.SlashHandlers.junk = function(rest)
  local rules = Rules()
  if not rules then ns.Print("settings are not loaded yet") return end
  local action, item = (rest or ""):match("^(%S*)%s*(.-)$")
  action = action:lower()
  if action == "list" then
    local keep, sell = {}, {}
    for id in pairs(rules.keep) do table.insert(keep, (C_Item.GetItemInfo(id)) or ("item " .. id)) end
    for id in pairs(rules.sell) do table.insert(sell, (C_Item.GetItemInfo(id)) or ("item " .. id)) end
    table.sort(keep); table.sort(sell)
    ns.Print("keep list: " .. (#keep > 0 and table.concat(keep, ", ") or "empty"))
    ns.Print("always sell: " .. (#sell > 0 and table.concat(sell, ", ") or "empty"))
    return
  end
  local id = ParseItem(item)
  if (action == "keep" or action == "sell" or action == "clear") and id then
    ns.SetJunkRule(id, action ~= "clear" and action or nil)
    local name = (C_Item.GetItemInfo(id)) or ("item " .. id)
    ns.Print(action == "keep" and (name .. " will never be sold") or action == "sell" and (name .. " will always be sold") or (name .. " follows the normal rules again"))
    return
  end
  ns.Print("usage: /fb junk keep|sell|clear <shift-click an item>, /fb junk list")
end

-- Ctrl + right click in your bags -------------------------------------------------
-- Peddler's trick, and the thing people ask for most: flip what happens to an item at the
-- next vendor without typing anything. A grey you want to keep goes on the keep list, anything
-- else goes on the sell list, and a second click takes it off again.

-- Returns the new rule ("keep", "sell" or nil), the item's name, and its id.
function ns.ToggleJunkRule(bag, slot)
  local info = C_Container.GetContainerItemInfo(bag, slot)
  local itemID = info and info.itemID
  if not itemID then return nil end
  local name = (C_Item.GetItemInfo(itemID)) or ("item " .. itemID)
  if ns.JunkRule(itemID) then
    ns.SetJunkRule(itemID, nil)
    return nil, name, itemID
  end
  local rule = (info.quality == Enum.ItemQuality.Poor) and "keep" or "sell"
  ns.SetJunkRule(itemID, rule)
  return rule, name, itemID
end

local function BagSlotOf(button)
  if type(button) ~= "table" then return nil end
  local bag = button.GetBagID and button:GetBagID()
  if bag == nil and button.GetParent then
    local parent = button:GetParent()
    bag = parent and parent.GetID and parent:GetID()
  end
  local slot = button.GetID and button:GetID()
  if type(bag) ~= "number" or type(slot) ~= "number" then return nil end
  return bag, slot
end

function ns.OnBagModifiedClick(button, mouseButton)
  if mouseButton ~= "RightButton" then return nil end
  local ctrl = rawget(_G, "IsControlKeyDown")
  if not (ctrl and ctrl()) then return nil end
  if not ns.IsFeatureEnabled("selljunk") then return nil end
  local bag, slot = BagSlotOf(button)
  if not bag then return nil end

  local info = C_Container.GetContainerItemInfo(bag, slot)
  if not (info and info.itemID) then return nil end
  -- Nothing to list: a vendor will not take something with no sell price.
  if info.hasNoValue and not ns.JunkRule(info.itemID) then
    ns.Print(((C_Item.GetItemInfo(info.itemID)) or "that") .. " has no sell price, so a vendor will not take it.")
    return nil
  end

  local rule, name = ns.ToggleJunkRule(bag, slot)
  if not name then return nil end
  if rule == "sell" then
    ns.Print(name .. " will be sold at the next vendor. Ctrl + right click it again to stop.")
  elseif rule == "keep" then
    ns.Print(name .. " will be kept, not sold with your greys. Ctrl + right click it again to stop.")
  else
    ns.Print(name .. " follows the normal rules again.")
  end
  return rule
end

-- Hooked rather than replaced, so whatever the client does with a modified click still happens.
function ns.HookBagJunkClicks()
  if ns.junkClicksHooked then return false end
  local mixin = rawget(_G, "ContainerFrameItemButtonMixin")
  if type(mixin) == "table" and mixin.OnModifiedClick then
    hooksecurefunc(mixin, "OnModifiedClick", ns.OnBagModifiedClick) -- Mainline and Forever
  elseif rawget(_G, "ContainerFrameItemButton_OnModifiedClick") then
    hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", ns.OnBagModifiedClick) -- Classic
  else
    return false
  end
  ns.junkClicksHooked = true
  return true
end

ns.HookBagJunkClicks()
