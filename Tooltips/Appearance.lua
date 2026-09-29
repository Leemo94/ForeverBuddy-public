local ADDON, ns = ...

-- "Appearance: collected / not collected" for transmog, only on clients that expose the collection API (Forever, not Era).

local api = C_TransmogCollection
if not (api and api.PlayerHasTransmogByItemInfo) then return end

ns.RegisterFeature({
  key = "appearance",
  name = "Appearance collected",
  desc = "Tooltips of armour and weapons say whether you already have their look in your collection.",
  default = true,
})

local NO_APPEARANCE = { INVTYPE_NECK = true, INVTYPE_FINGER = true, INVTYPE_TRINKET = true, INVTYPE_RELIC = true }

function ns.AppearanceLine(itemID, link)
  local _, _, _, equipLoc, _, classID = C_Item.GetItemInfoInstant(itemID)
  if not ((classID == 2 or classID == 4) and ns.EQUIP_SLOTS[equipLoc] and not NO_APPEARANCE[equipLoc]) then return nil end
  if C_Item.IsDressableItemByID and not C_Item.IsDressableItemByID(itemID) then return nil end
  local has = api.PlayerHasTransmogByItemInfo(link or itemID)
  if has then return "Appearance: collected", "active" end
  return "Appearance: not collected", "available"
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
  if not ns.IsFeatureEnabled("appearance") then return end
  if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
  if tooltip:IsForbidden() then return end
  local itemID = data and data.id
  if not itemID then return end
  local link = select(2, C_Item.GetItemInfo(itemID))
  local text, colorKey = ns.AppearanceLine(itemID, link)
  if text then
    local c = ns.COLORS[colorKey]
    tooltip:AddLine(text, c[1], c[2], c[3])
    tooltip:Show()
  end
end)
