local ADDON, ns = ...

-- "I want five of these: what do I actually have to go and get?"
--
-- Walks a recipe down to the things nobody can craft, counting what you already hold on the way
-- so a Mithril Tube in your bank stops that whole branch. The panel on the profession window is
-- a view of what this works out; /fb craft prints the same thing into chat.

local MAX_DEPTH = 8 -- nothing in the game nests anywhere near this deep; it is a cycle guard

function ns.CraftingRecipe(itemID)
  local row = itemID and (ns.Crafting or {})[itemID]
  if not row then return nil end
  return { spell = row[1], name = row[2], profession = row[3], skill = row[4], makes = row[5] or 1,
           reagents = row[6] or {} }
end

-- How many of an item you hold. Bags always; the bank and the reagent bank when the client
-- will say, which it does not always do until the bank has been opened once.
function ns.ItemOnHand(itemID, includeBank)
  if not itemID then return 0 end
  local get = (C_Item and C_Item.GetItemCount) or rawget(_G, "GetItemCount")
  if not get then return 0 end
  local ok, count = pcall(get, itemID, includeBank and true or false, false, includeBank and true or false,
                          includeBank and true or false)
  if not ok then
    ok, count = pcall(get, itemID, includeBank and true or false)
  end
  return (ok and tonumber(count)) or 0
end

-- The deepest a thing sits below the target, so that everything which needs an item has had its
-- say before we work out how many of that item to make. Mithril Bars are wanted by the gun
-- itself and by the tube inside it; count them once, after both.
-- Whether we take a reagent apart or put it on the shopping list. The rule is the one a
-- crafter already uses without thinking: break down what you can make at this window, and buy
-- the rest. A Whirring Bronze Gizmo is Engineering, so an engineer makes it; a Bronze Bar is
-- Mining and a Heavy Leather is Leatherworking, so both are things you go and get. Passing no
-- profession expands everything, which is what /fb craft does.
local function Expands(itemID, opts, isTarget)
  if opts.collapsed and opts.collapsed[itemID] then return nil end
  local recipe = ns.CraftingRecipe(itemID)
  if not recipe then return nil end
  if isTarget or opts.expandEverything or not opts.profession then return recipe end
  return recipe.profession == opts.profession and recipe or nil
end
ns.CraftingExpands = Expands

local function depths(itemID, opts, depth, out, isTarget)
  out = out or {}
  depth = depth or 0
  if depth > MAX_DEPTH then return out end
  if (out[itemID] or -1) >= depth then return out end
  out[itemID] = depth
  local recipe = Expands(itemID, opts, isTarget)
  if not recipe then return out end
  for _, pair in ipairs(recipe.reagents) do
    depths(pair[1], opts, depth + 1, out)
  end
  return out
end

-- Which professions this character actually has, so a breakdown is only offered when they
-- could do it. An engineer who mines wants to know that thirty bronze bars is fifteen smelts;
-- an engineer who has never skinned anything does not want a tanning lesson under Heavy
-- Leather. A client that will not say means we hide nothing.
local professions, professionsFor

-- The tests change character between runs; the game does not.
function ns.ClearProfessionCache()
  professions, professionsFor = nil, nil
end

function ns.PlayerProfessions()
  local who = (UnitName and UnitName("player")) or "?"
  if professions and professionsFor == who then return professions end
  local get, info = rawget(_G, "GetProfessions"), rawget(_G, "GetProfessionInfo")
  if not (get and info) then return nil end
  local ok, first, second, archaeology, fishing, cooking, firstAid = pcall(get)
  if not ok then return nil end
  local found = {}
  for _, index in ipairs({ first, second, archaeology, fishing, cooking, firstAid }) do
    local okInfo, name = pcall(info, index)
    if okInfo and name then found[name] = true end
  end
  -- Nothing at all means the client has not filled this in yet, not that the character has no
  -- professions: treat it as "cannot tell" and hide nothing.
  if next(found) == nil then return nil end
  professions, professionsFor = found, who
  return found
end

-- `crafts` is how many times you press Create, not how many items you end up with: two of
-- Thorium Shells is two batches and four hundred shells. That is what the quantity box on the
-- profession window means, and anything else surprises somebody making ammunition.
--
-- opts: { includeBank, profession, expandEverything, collapsed = { [itemID] = true },
--         ignoreInventory }
-- Returns { target, crafts, produced, steps, base, direct }, steps in the order you would
-- actually make them, deepest first, and base everything you have to go and find.
function ns.CraftingPlan(itemID, crafts, opts)
  opts = opts or {}
  crafts = math.max(1, math.floor(tonumber(crafts) or 1))
  local target = ns.CraftingRecipe(itemID)
  if not target then return nil end

  local order = {}
  for item, depth in pairs(depths(itemID, opts, 0, nil, true)) do
    table.insert(order, { item = item, depth = depth })
  end
  table.sort(order, function(a, b)
    if a.depth ~= b.depth then return a.depth < b.depth end
    return a.item < b.item
  end)

  local produced = crafts * target.makes
  local need, held, steps, base = { [itemID] = produced }, {}, {}, {}
  for _, entry in ipairs(order) do
    local item = entry.item
    local wanted = need[item] or 0
    if wanted > 0 then
      -- What you own is spent on the highest thing that wants it, which is why this runs in
      -- one pass from the top rather than being subtracted branch by branch.
      -- What you already hold counts against the reagents, never against the thing you asked
      -- for: "make me two" is an instruction, not a target to fill up to.
      local have = 0
      if not opts.ignoreInventory and item ~= itemID then
        held[item] = held[item] or ns.ItemOnHand(item, opts.includeBank)
        have = math.min(held[item], wanted)
        held[item] = held[item] - have
      end
      local short = wanted - have
      local recipe = Expands(item, opts, item == itemID)
      if short > 0 and recipe then
        local crafts = math.ceil(short / recipe.makes)
        table.insert(steps, { item = item, name = recipe.name, profession = recipe.profession,
                              skill = recipe.skill, crafts = crafts, makes = recipe.makes,
                              produced = crafts * recipe.makes, need = wanted, have = have,
                              depth = entry.depth, spell = recipe.spell })
        for _, pair in ipairs(recipe.reagents) do
          need[pair[1]] = (need[pair[1]] or 0) + pair[2] * crafts
        end
      else
        -- A shopping item that could be made, if you had that profession or wanted the detour:
        -- say what it would take, which is how somebody sees that 30 bronze bars is 15 smelts.
        -- Only worth offering when you are short of it and could actually make it yourself.
        local hint
        local makeable = short > 0 and ns.CraftingRecipe(item) or nil
        local mine = ns.PlayerProfessions()
        if makeable and mine and not mine[makeable.profession] then makeable = nil end
        if makeable then
          local crafts = math.ceil(short / makeable.makes)
          hint = { profession = makeable.profession, skill = makeable.skill, crafts = crafts,
                   makes = makeable.makes, reagents = {} }
          for _, pair in ipairs(makeable.reagents) do
            table.insert(hint.reagents, { item = pair[1], count = pair[2] * crafts })
          end
        end
        table.insert(base, { item = item, need = wanted, have = have, short = short,
                             depth = entry.depth, hint = hint })
      end
    end
  end

  -- Deepest first: smelt the bars before you build the tube.
  table.sort(steps, function(a, b)
    if a.depth ~= b.depth then return a.depth > b.depth end
    return a.item < b.item
  end)
  -- Everything the recipe eats, not only what you are short of: a shopping list that hides the
  -- thirty bronze bars because they happen to be in your bank is not a list of anything.
  table.sort(base, function(a, b)
    local aShort, bShort = a.short > 0, b.short > 0
    if aShort ~= bShort then return aShort end
    if a.short ~= b.short then return a.short > b.short end
    return a.item < b.item
  end)
  -- What the recipe itself asks for, times how many you want: the panel shows this above the
  -- broken-down list, because it is what the window in front of you is talking about.
  local direct = {}
  for _, pair in ipairs(target.reagents) do
    table.insert(direct, { item = pair[1], need = pair[2] * crafts,
                           have = opts.ignoreInventory and 0 or ns.ItemOnHand(pair[1], opts.includeBank) })
  end

  return { target = itemID, crafts = crafts, produced = produced, makes = target.makes,
           steps = steps, base = base, direct = direct,
           profession = target.profession, skill = target.skill, name = target.name }
end

-- A step is an instruction: press Create this many times. How many items fall out is a different
-- number the moment a recipe makes a batch, and printing that one in the count column is how a
-- plan for two Gyrochronatoms came to say "Gold Power Core x3" when one press of it was the
-- whole job. The count is what you type into the quantity box; the batch goes in the hint.
function ns.CraftStepCount(step)
  return ("x%d"):format(step.crafts)
end

function ns.CraftStepHint(step)
  local where = ("%s %d"):format(step.profession, step.skill)
  if (step.makes or 1) <= 1 then return where end
  return ("%s - %d a craft, %d in all"):format(where, step.makes, step.produced)
end

-- Chat version, which is also the quickest way to see whether the sums are right.
function ns.CraftingPlanText(plan)
  if not plan then return nil end
  local lines = {}
  table.insert(lines, plan.makes > 1
    and ("%d x %s, %d in all (%s %d)"):format(plan.crafts, plan.name, plan.produced, plan.profession, plan.skill)
    or ("%d x %s (%s %d)"):format(plan.crafts, plan.name, plan.profession, plan.skill))
  local missing = 0
  if #plan.base > 0 then
    table.insert(lines, "you need:")
    for _, row in ipairs(plan.base) do
      local name = ns.CraftItemName(row.item)
      if row.short <= 0 then
        table.insert(lines, ("  %s x%d (you have them)"):format(name, row.need))
      elseif row.have > 0 then
        missing = missing + 1
        table.insert(lines, ("  %s x%d (you have %d, need %d more)"):format(name, row.need, row.have, row.short))
      else
        missing = missing + 1
        table.insert(lines, ("  %s x%d"):format(name, row.need))
      end
    end
    if missing == 0 then table.insert(lines, "which you already have, all of it.") end
  else
    table.insert(lines, "you already have everything.")
  end
  if #plan.steps > 1 then
    table.insert(lines, "then make, in order:")
    for _, step in ipairs(plan.steps) do
      table.insert(lines, ("  %s %s (%s)"):format(step.name, ns.CraftStepCount(step), ns.CraftStepHint(step)))
    end
  end
  return lines
end

-- Finding a recipe by what somebody typed, or by a link they shift-clicked in.
function ns.FindCraftable(text)
  if not text or text == "" then return nil end
  local linked = tonumber(text:match("item:(%d+)"))
  if linked and ns.CraftingRecipe(linked) then return linked end
  local id = tonumber(text:match("^%s*(%d+)%s*$"))
  if id and ns.CraftingRecipe(id) then return id end
  local wanted = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
  local best
  for item, row in pairs(ns.Crafting or {}) do
    local name = (row[2] or ""):lower()
    if name == wanted then return item end
    if name:find(wanted, 1, true) and (not best or #name < #((ns.Crafting[best] or {})[2] or "")) then
      best = item
    end
  end
  return best
end

-- The client only knows an item it has seen. Ask it to fetch the rest, the same way the quest
-- scanner does, so a list stops saying "item 2934" the moment the answer lands.
function ns.CraftItemName(itemID)
  local name = ns.ItemName(itemID)
  if name and not name:find("^item %d") then return name end
  local request = C_Item and C_Item.RequestLoadItemDataByID
  if request then pcall(request, itemID) end
  return name
end

ns.SlashHandlers.craft = function(rest)
  rest = (rest or ""):match("^%s*(.-)%s*$")
  -- "/fb craft repair bot 5 all" takes every branch apart, including the professions you would
  -- normally just go and buy from.
  local everything = rest:match("%s+all$") ~= nil
  rest = rest:gsub("%s+all$", "")
  local crafts = tonumber(rest:match("%s(%d+)$")) or 1
  local name = rest:gsub("%s+%d+$", "")
  if name == "" then
    ns.Print("usage: /fb craft <item> [how many times] [all], e.g. /fb craft net-o-matic 5")
    return nil
  end
  local item = ns.FindCraftable(name)
  if not item then
    ns.Print(("nothing craftable called '%s'"):format(name))
    return nil
  end
  -- The same rule the panel uses: break down what this profession makes, and treat everything
  -- else as something you go and get. Nobody asking for a Repair Bot wants to be told how much
  -- Light Leather it takes to tan their way to a Heavy Leather.
  local recipe = ns.CraftingRecipe(item)
  local plan = ns.CraftingPlan(item, crafts, {
    includeBank = true,
    profession = (not everything) and recipe.profession or nil,
    expandEverything = everything,
  })
  for _, line in ipairs(ns.CraftingPlanText(plan) or {}) do ns.Print(line) end
  return plan
end
