local ADDON, ns = ...

-- Unique profession names from a recipe list, in order of first appearance.
function ns.ProfessionList(recipes)
  local list, seen = {}, {}
  for _, r in ipairs(recipes or {}) do
    local profession = r[2]
    if profession and profession ~= "" and not seen[profession] then
      seen[profession] = true
      table.insert(list, profession)
    end
  end
  return list
end

-- quests: sorted output of ns.CollectQuests (active > available > repeatable > done).
-- recipes: ns.Recipes[itemID] or nil.
-- Returns text, colourKey (a key of ns.COLORS), or nil when the item has no known use.
function ns.GetVerdict(quests, recipes)
  quests = quests or {}
  local hasRecipes = recipes ~= nil and #recipes > 0
  local needed = {}
  for _, q in ipairs(quests) do
    if q.status ~= "done" then table.insert(needed, q) end
  end
  if #needed > 0 then
    local text = "KEEP: needed for " .. needed[1].name
    if #needed > 1 then text = text .. (" and %d more"):format(#needed - 1) end
    return text, "keep"
  elseif #quests > 0 and hasRecipes then
    local professions = ns.ProfessionList(recipes)
    return "All quests done: still a " .. (professions[1] or "crafting") .. " reagent", "white"
  elseif #quests > 0 then
    return "All quests done: safe to vendor", "grey"
  elseif hasRecipes then
    local professions = ns.ProfessionList(recipes)
    if #professions == 0 then return "Crafting reagent", "white" end
    return "Crafting reagent (" .. table.concat(professions, ", ") .. ")", "white"
  end
  return nil
end
