local ADDON, ns = ...

-- SHELVED for the first release. The warning does not appear on Forever's delete confirmation.
-- The code and its tests are untouched: turning SHIPPING back on is the whole job.
local SHIPPING = false

if SHIPPING then
  ns.RegisterFeature({
    key = "deletewarn",
    name = "Delete warnings",
    desc = "When you destroy an item a quest still needs, the confirmation says which quest.",
    default = true,
  })
end

local DELETE_DIALOGS = { DELETE_ITEM = true, DELETE_GOOD_ITEM = true, DELETE_QUEST_ITEM = true, DELETE_GOOD_QUEST_ITEM = true }

-- Returns the warning text for an item link, or nil when nothing still needs it.
function ns.DeleteWarning(link)
  local itemID = tonumber(type(link) == "string" and link:match("item:(%d+)") or nil)
  if not itemID then return nil end
  local name = C_Item.GetItemInfo(itemID)
  local quests = ns.CollectQuests(itemID, name)
  local verdict = ns.GetVerdict(quests, ns.Recipes[itemID])
  if verdict and verdict:sub(1, 4) == "KEEP" then return "ForeverBuddy: " .. verdict end
  return nil
end

local function OnPopupShown(which, link)
  if not DELETE_DIALOGS[which] or not ns.IsFeatureEnabled("deletewarn") then return end
  local warning = ns.DeleteWarning(link)
  if not warning then return end
  local dialog = StaticPopup_FindVisible(which)
  if not dialog or not dialog.text then return end
  local current = dialog.text:GetText() or ""
  if current:find(warning, 1, true) then return end
  dialog.text:SetText(current .. "\n\n|cffff8a1f" .. warning .. "|r")
  if StaticPopup_Resize then StaticPopup_Resize(dialog, which) end
end

function ns.HookDeleteWarning()
  hooksecurefunc("StaticPopup_Show", OnPopupShown)
  return true
end

if SHIPPING then ns.HookDeleteWarning() end
