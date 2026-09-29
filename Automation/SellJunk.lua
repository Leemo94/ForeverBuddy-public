local ADDON, ns = ...

ns.RegisterFeature({
  key = "selljunk",
  name = "Sell junk",
  desc = "Sells grey (poor quality) items automatically when you open a vendor. /fb junk keep [item] protects one, /fb junk sell [item] always sells one.",
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
    rules.keep[id] = nil; rules.sell[id] = nil
    if action == "keep" then rules.keep[id] = true elseif action == "sell" then rules.sell[id] = true end
    local name = (C_Item.GetItemInfo(id)) or ("item " .. id)
    ns.Print(action == "keep" and (name .. " will never be sold") or action == "sell" and (name .. " will always be sold") or (name .. " follows the normal rules again"))
    return
  end
  ns.Print("usage: /fb junk keep|sell|clear <shift-click an item>, /fb junk list")
end
