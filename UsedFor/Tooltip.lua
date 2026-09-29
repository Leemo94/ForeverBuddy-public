local ADDON, ns = ...

ns.RegisterFeature({
  key = "usedfor",
  name = "Item uses on tooltips",
  desc = "Shows which quests and recipes an item is used for, and whether to keep it or vendor it.",
  default = true,
})

local MAX_QUESTS = 6
local MAX_RECIPES_PER_PROFESSION = 4

local function AddLine(tooltip, text, colorKey)
  local c = ns.COLORS[colorKey] or ns.COLORS.white
  tooltip:AddLine(text, c[1], c[2], c[3])
end

function ns.FactionName(factionID)
  local name
  if C_Reputation and C_Reputation.GetFactionDataByID then
    local data = C_Reputation.GetFactionDataByID(factionID)
    name = data and data.name
  elseif GetFactionInfoByID then
    name = GetFactionInfoByID(factionID)
  end
  return name or ("faction " .. tostring(factionID))
end

-- "+150 Stormwind, +350 Ironforge" for a quest's reputation rewards, or nil.
function ns.RepText(rep)
  if type(rep) ~= "table" or #rep == 0 then return nil end
  local parts = {}
  for _, pair in ipairs(rep) do
    table.insert(parts, ("%+d %s"):format(pair[2], ns.FactionName(pair[1])))
  end
  return table.concat(parts, ", ")
end

-- q = collected quest { name, status, have, need, rep }
function ns.QuestLineText(q)
  local text = "Quest: " .. q.name
  if q.status == "active" and q.have and q.need then
    text = text .. (" (%d/%d)"):format(q.have, q.need)
  elseif q.status == "repeatable" then
    local rep = ns.RepText(q.rep)
    text = text .. (rep and (" (repeatable, %s per turn-in)"):format(rep) or " (repeatable)")
  elseif q.status == "done" then
    text = text .. " (done)"
  end
  return text
end

-- r = recipe entry { recipeName, professionName, craftedItemID, craftedItemName, reagentCount }
function ns.RecipeLineText(r)
  local text = r[2] .. ": " .. r[1]
  if r[4] and r[4] ~= "" and r[4] ~= r[1] then
    text = text .. " -> " .. r[4]
  end
  return text
end

-- quests: sorted output of ns.CollectQuests; recipes: ns.Recipes[itemID] or nil (sorted by profession, name)
function ns.RenderBlock(tooltip, quests, recipes, showAll)
  local verdict, colorKey = ns.GetVerdict(quests, recipes)
  tooltip:AddLine(" ")
  if verdict then AddLine(tooltip, verdict, colorKey) end

  local questLimit = showAll and #quests or math.min(#quests, MAX_QUESTS)
  for i = 1, questLimit do
    AddLine(tooltip, ns.QuestLineText(quests[i]), quests[i].status)
  end
  if #quests > questLimit then
    AddLine(tooltip, ("+%d more quests"):format(#quests - questLimit), "grey")
  end

  recipes = recipes or {}
  local i, n = 1, #recipes
  while i <= n do
    local profession = recipes[i][2]
    local j = i
    while j <= n and recipes[j][2] == profession do j = j + 1 end
    local count = j - i
    local shown = showAll and count or math.min(count, MAX_RECIPES_PER_PROFESSION)
    for k = i, i + shown - 1 do
      AddLine(tooltip, ns.RecipeLineText(recipes[k]), "white")
    end
    if count > shown then
      AddLine(tooltip, ("+%d more %s recipes"):format(count - shown, profession), "grey")
    end
    i = j
  end
  tooltip:Show()
end

local function HandleItemTooltip(tooltip, data)
  if not ns.IsFeatureEnabled("usedfor") then return end
  if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
  if tooltip:IsForbidden() then return end
  local itemID = data and data.id
  if not itemID and TooltipUtil and TooltipUtil.GetDisplayedItem then
    local _, _, displayedID = TooltipUtil.GetDisplayedItem(tooltip)
    itemID = displayedID
  end
  if not itemID then return end

  local itemName = C_Item.GetItemInfo(itemID)
  if not itemName then
    C_Item.RequestLoadItemDataByID(itemID)
    local titleLine = _G[tooltip:GetName() .. "TextLeft1"]
    itemName = titleLine and titleLine:GetText()
  end

  local recipes = ns.Recipes[itemID]
  local quests = ns.CollectQuests(itemID, itemName)
  if (recipes == nil or #recipes == 0) and #quests == 0 then return end
  ns.RenderBlock(tooltip, quests, recipes, IsShiftKeyDown())
end

local reported = false
function ns.OnItemTooltip(tooltip, data)
  local ok, err = pcall(HandleItemTooltip, tooltip, data)
  if not ok and not reported then
    reported = true
    ns.Print("tooltip error (reported once per session): " .. tostring(err))
  end
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, ns.OnItemTooltip)
