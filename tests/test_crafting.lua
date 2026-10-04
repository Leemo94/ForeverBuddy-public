package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Stub = require("wow_stub")
local ns = Stub.LoadAddon({ "Core.lua", "UI/Window.lua", "Craft/Plan.lua", "Craft/Panel.lua" })
local printed = {}
ns.Print = function(msg) table.insert(printed, msg) end

-- The Gnomish Net-o-Matic Projector, which is the shape of the problem: a reagent wanted by two
-- branches at once (Mithril Bar, by the gun and by the tube inside it), a step in another
-- profession (smelting), and a step that makes two hundred at a time (the slugs).
local NET, TUBE, BAR, ORE, POWDER, STONE, SILK, SHADOW = 10720, 10559, 3860, 3858, 10505, 7912, 4337, 10285
local SLUGS, BOLT = 10512, 10559

local function world()
  Stub.reset(); printed = {}
  ns.db = { features = {} }
  Stub.items = {
    [NET] = { name = "Gnomish Net-o-Matic Projector" }, [TUBE] = { name = "Mithril Tube" },
    [BAR] = { name = "Mithril Bar" }, [ORE] = { name = "Mithril Ore" },
    [POWDER] = { name = "Solid Blasting Powder" }, [STONE] = { name = "Solid Stone" },
    [SILK] = { name = "Thick Spider's Silk" }, [SHADOW] = { name = "Shadow Silk" },
    [SLUGS] = { name = "Hi-Impact Mithril Slugs" },
  }
  ns.Crafting = {
    [NET] = { 12902, "Gnomish Net-o-Matic Projector", "Engineering", 230, 1,
              { { BAR, 4 }, { SILK, 4 }, { SHADOW, 2 }, { POWDER, 2 }, { TUBE, 1 } } },
    [TUBE] = { 3967, "Mithril Tube", "Engineering", 195, 1, { { BAR, 3 } } },
    [BAR] = { 10097, "Smelt Mithril", "Mining", 175, 1, { { ORE, 1 } } },
    [POWDER] = { 12585, "Solid Blasting Powder", "Engineering", 190, 1, { { STONE, 2 } } },
    [SLUGS] = { 12596, "Hi-Impact Mithril Slugs", "Engineering", 215, 200, { { BAR, 1 }, { POWDER, 1 } } },
  }
  Stub.bags = {}
end

-- What the player is carrying, which is all GetItemCount answers from.
local function carrying(counts)
  Stub.bags[0] = {}
  for item, n in pairs(counts) do
    table.insert(Stub.bags[0], { itemID = item, stackCount = n, quality = 1 })
  end
end

T.run("a recipe reads back with everything the list needs", function()
  world()
  local recipe = ns.CraftingRecipe(NET)
  T.eq(recipe.name, "Gnomish Net-o-Matic Projector")
  T.eq(recipe.profession, "Engineering")
  T.eq(recipe.skill, 230)
  T.eq(recipe.makes, 1)
  T.eq(#recipe.reagents, 5)
  T.eq(ns.CraftingRecipe(ORE), nil, "ore is dug up, not made")
  T.eq(ns.CraftingRecipe(nil), nil)
end)

T.run("one of them comes down to ore, silk, stone and shadow silk", function()
  world()
  local plan = ns.CraftingPlan(NET, 1, { ignoreInventory = true })
  local base = {}
  for _, row in ipairs(plan.base) do base[row.item] = row.short end
  T.eq(base[ORE], 7, "four bars for the gun and three for the tube")
  T.eq(base[SILK], 4)
  T.eq(base[STONE], 4, "two powders at two stone each")
  T.eq(base[SHADOW], 2)
  T.eq(base[BAR], nil, "bars are made, not found")
end)

T.run("five of them is five times everything", function()
  world()
  local plan = ns.CraftingPlan(NET, 5, { ignoreInventory = true })
  local base = {}
  for _, row in ipairs(plan.base) do base[row.item] = row.short end
  T.eq(base[ORE], 35); T.eq(base[SILK], 20); T.eq(base[STONE], 20); T.eq(base[SHADOW], 10)
end)

T.run("the steps come back in the order you would make them", function()
  world()
  local plan = ns.CraftingPlan(NET, 1, { ignoreInventory = true })
  local names = {}
  for _, step in ipairs(plan.steps) do table.insert(names, step.name) end
  T.eq(names[1], "Smelt Mithril", "the bars before anything that needs them")
  T.eq(names[#names], "Gnomish Net-o-Matic Projector", "and the gun last")
  T.eq(plan.steps[1].crafts, 7, "seven bars in one go, not four and then three")
end)

T.run("what you already have stops a branch, counted once from the top", function()
  world()
  carrying({ [TUBE] = 1 })
  local plan = ns.CraftingPlan(NET, 1)
  local base = {}
  for _, row in ipairs(plan.base) do base[row.item] = row.short end
  T.eq(base[ORE], 4, "the tube's three bars are no longer wanted")
  local names = {}
  for _, step in ipairs(plan.steps) do names[step.name] = true end
  T.eq(names["Mithril Tube"], nil, "and the tube itself is not on the list")
end)

T.run("a reagent two branches want is shared out, not spent twice", function()
  world()
  carrying({ [BAR] = 5 })
  local plan = ns.CraftingPlan(NET, 1)
  local base = {}
  for _, row in ipairs(plan.base) do base[row.item] = row.short end
  T.eq(base[ORE], 2, "seven bars wanted, five held, so two more to smelt")
  for _, step in ipairs(plan.steps) do
    if step.name == "Smelt Mithril" then T.eq(step.crafts, 2) end
  end
end)

T.run("the list is the whole bill, with what you hold marked off", function()
  world()
  carrying({ [BAR] = 7, [SILK] = 4, [SHADOW] = 2, [POWDER] = 2, [TUBE] = 1 })
  local plan = ns.CraftingPlan(NET, 1)
  local base = {}
  for _, row in ipairs(plan.base) do base[row.item] = row end
  T.eq(base[BAR].need, 4, "the bars are still on the list")
  T.eq(base[BAR].short, 0, "with nothing left to find")
  T.eq(base[SILK].short, 0)
  T.eq(#plan.steps, 1, "and there is nothing to make but the gun")
  local lines = table.concat(ns.CraftingPlanText(plan), "\n")
  T.truthy(lines:find("you have them", 1, true), lines)
  T.truthy(lines:find("which you already have, all of it.", 1, true), lines)
end)

T.run("what you are short of comes first", function()
  world()
  carrying({ [SILK] = 4, [SHADOW] = 2 })
  local plan = ns.CraftingPlan(NET, 1)
  T.truthy(plan.base[1].short > 0, "something missing is at the top")
  T.eq(plan.base[#plan.base].short, 0, "and something covered is at the bottom")
end)

T.run("the quantity is how many times you press Create, not how many you end up with", function()
  world()
  local plan = ns.CraftingPlan(SLUGS, 1, { ignoreInventory = true })
  T.eq(plan.crafts, 1); T.eq(plan.produced, 200, "one press makes two hundred")
  local base = {}
  for _, row in ipairs(plan.base) do base[row.item] = row.short end
  T.eq(base[ORE], 1); T.eq(base[STONE], 2)

  plan = ns.CraftingPlan(SLUGS, 2, { ignoreInventory = true })
  T.eq(plan.produced, 400)
  T.eq(plan.steps[#plan.steps].crafts, 2)
  base = {}
  for _, row in ipairs(plan.base) do base[row.item] = row.short end
  T.eq(base[ORE], 2, "twice the reagents, not two hundred times")
  T.eq(base[STONE], 4)
end)

T.run("what you hold counts against the reagents, never against what you asked to make", function()
  world()
  carrying({ [NET] = 3, [BAR] = 2 })
  local plan = ns.CraftingPlan(NET, 1)
  T.eq(plan.crafts, 1, "you asked for one, you get a list for one")
  local base = {}
  for _, row in ipairs(plan.base) do base[row.item] = row.short end
  T.eq(base[ORE], 5, "seven bars wanted, two held")
end)

T.run("a branch you would rather buy is left alone", function()
  world()
  local plan = ns.CraftingPlan(NET, 1, { ignoreInventory = true, collapsed = { [TUBE] = true } })
  local base = {}
  for _, row in ipairs(plan.base) do base[row.item] = row.short end
  T.eq(base[TUBE], 1, "the tube is on the shopping list itself")
  T.eq(base[ORE], 4, "and only the gun's own bars are smelted")
end)

T.run("the chat version says what to get and what to make", function()
  world()
  carrying({ [ORE] = 3 })
  local lines = table.concat(ns.CraftingPlanText(ns.CraftingPlan(NET, 1)), "\n")
  T.truthy(lines:find("1 x Gnomish Net-o-Matic Projector (Engineering 230)", 1, true), lines)
  T.truthy(table.concat(ns.CraftingPlanText(ns.CraftingPlan(SLUGS, 2, { ignoreInventory = true })), "\n")
    :find("2 x Hi-Impact Mithril Slugs, 400 in all", 1, true), "a batch recipe says what it comes to")
  T.truthy(lines:find("Mithril Ore x7 (you have 3, need 4 more)", 1, true), lines)
  T.truthy(lines:find("Smelt Mithril x7", 1, true), lines)
end)

T.run("/fb craft takes a name, a count and a link, and says so when it knows nothing", function()
  world()
  local plan = ns.SlashHandlers.craft("net-o-matic 5")
  T.truthy(plan); T.eq(plan.crafts, 5); T.eq(plan.target, NET)
  T.eq(ns.FindCraftable("Mithril Tube"), TUBE)
  T.eq(ns.FindCraftable("|cff1eff00|Hitem:10559::::::::15:::::|h[Mithril Tube]|h|r"), TUBE)
  T.eq(ns.FindCraftable("10559"), TUBE)
  T.eq(ns.SlashHandlers.craft("a sandwich"), nil)
  T.truthy(printed[#printed]:find("nothing craftable called", 1, true), printed[#printed])
  T.eq(ns.SlashHandlers.craft(""), nil)
  T.truthy(printed[#printed]:find("usage: /fb craft", 1, true), printed[#printed])
end)

T.run("a recipe that eats its own output does not hang", function()
  world()
  ns.Crafting[BAR] = { 1, "Silly Bar", "Mining", 1, 1, { { BAR, 2 } } }
  local plan = ns.CraftingPlan(NET, 1, { ignoreInventory = true })
  T.truthy(plan, "it comes back at all")
  T.truthy(#plan.steps > 0)
end)

T.run("the panel lists what to buy, then what to make with it", function()
  world()
  local plan = ns.CraftingPlan(NET, 5, { ignoreInventory = true, profession = "Engineering" })
  local frame = ns.CraftPanel()
  local used = ns.FillCraftPanel(frame, plan)
  T.truthy(used > 0)
  T.eq(frame.title:GetText(), "Gnomish Net-o-Matic Projector")
  T.eq(frame.subtitle:GetText(), "Engineering 230")

  local lines = {}
  for i = 1, used do
    local row = frame.rows[i]
    table.insert(lines, ("%s|%s|%s"):format(row.name:GetText(), row.count:GetText(), row.hint:GetText()))
  end
  local text = table.concat(lines, "\n")
  T.truthy(text:find("Shopping", 1, true), text)
  T.truthy(text:find("To make", 1, true), text)
  T.truthy(text:find("Mithril Bar|35|Mining 175: Mithril Ore x35", 1, true),
    "bars are shopping, with what smelting them would take: " .. text)
  T.truthy(text:find("Mithril Tube|x5|Engineering 195", 1, true),
    "and the tube is something to make, not something to buy: " .. text)
  T.eq(text:find("End Mats", 1, true), nil, "the recipe's own list is on Blizzard's window already")
end)

T.run("the quantity box drives it, and bad input does not", function()
  world()
  local frame = ns.CraftPanel()
  frame.qty:SetText("5")
  T.eq(ns.CraftPanelQuantity(), 5)
  frame.qty:SetText("")
  T.eq(ns.CraftPanelQuantity(), 1, "an empty box is one, not nothing")
  frame.qty:SetText("0")
  T.eq(ns.CraftPanelQuantity(), 1)
end)

T.run("a recipe id finds its item, through the client or through our own data", function()
  world()
  T.eq(ns.ItemForRecipe(12902), NET, "the Net-o-Matic's spell")
  T.eq(ns.ItemForRecipe(10097), BAR)
  T.eq(ns.ItemForRecipe(nil), nil)
  T.eq(ns.ItemForRecipe(123456), nil, "a spell that makes nothing we know")
end)

T.run("nothing selected says so instead of drawing an empty list", function()
  world()
  local frame = ns.CraftPanel()
  T.eq(ns.FillCraftPanel(frame, nil), 0)
  T.eq(frame.title:GetText(), "Nothing selected")
end)

T.run("the panel stops where the profession stops, and says what the rest would take", function()
  world()
  -- Heavy Leather is Leatherworking: an engineer buys it, and is never told about Light Leather.
  ns.Crafting[SILK] = { 9999, "Thick Spider's Silk", "Leatherworking", 100, 1, { { STONE, 10 } } }
  local plan = ns.CraftingPlan(NET, 1, { ignoreInventory = true, profession = "Engineering" })
  local base = {}
  for _, row in ipairs(plan.base) do base[row.item] = row end
  T.truthy(base[SILK], "the silk is shopping, not a step")
  T.eq(base[SILK].short, 4)
  T.eq(base[STONE].short, 4, "and its own ten stone each are not added to ours")
  T.truthy(base[SILK].hint, "but it says what making it would take")
  T.eq(ns.HintText(base[SILK].hint), "Leatherworking 100: Solid Stone x40")

  local everything = ns.CraftingPlan(NET, 1, { ignoreInventory = true, expandEverything = true })
  local deep = {}
  for _, row in ipairs(everything.base) do deep[row.item] = row.short end
  T.eq(deep[STONE], 44, "asking for all of it does follow the silk down")
end)

T.run("/fb craft breaks down this profession only, unless asked for all of it", function()
  world()
  ns.Crafting[SILK] = { 9999, "Thick Spider's Silk", "Leatherworking", 100, 1, { { STONE, 10 } } }
  local plan = ns.SlashHandlers.craft("net-o-matic 1")
  local base = {}
  for _, row in ipairs(plan.base) do base[row.item] = row.short end
  T.eq(base[SILK], 4, "silk is bought")
  plan = ns.SlashHandlers.craft("net-o-matic 1 all")
  base = {}
  for _, row in ipairs(plan.base) do base[row.item] = row.short end
  T.eq(base[SILK], nil, "and with 'all' it is made")
  T.eq(base[STONE], 44)
end)

-- Lee: "the shopping list button doesn't appear sometimes until you click another profession
-- then go back". Choosing a recipe fires no event, so nothing recomputed the button.
T.run("choosing a recipe shows the button without any event firing", function()
  world()
  local page = Stub.NewMock("Frame", "FBTestCraftingPage2")
  page.SchematicForm = Stub.NewMock("Frame", "FBTestSchematicForm2")
  _G.ProfessionsFrame = Stub.NewMock("Frame", "ProfessionsFrame")
  _G.ProfessionsFrame.CraftingPage = page
  _G.ProfessionsFrame:Show()
  local selected = nil
  page.SchematicForm.GetRecipeInfo = function() return selected and { recipeID = selected } or nil end

  -- The window opens before Blizzard has restored the recipe you had open last.
  local made = ns.CraftButton()
  ns.UpdateCraftButton()
  T.eq(made:IsShown(), false, "nothing is selected yet")

  -- Blizzard restores it. No event we listen to is fired.
  selected = 12902
  T.eq(ns.PollCraftButton(), true, "a look at what is selected is all it takes")
  T.eq(made:IsShown(), true, "and the button is there without switching profession and back")

  -- Closing the window stops it looking at all.
  _G.ProfessionsFrame:Hide()
  T.eq(ns.PollCraftButton(), nil, "nothing to do while the window is shut")
  _G.ProfessionsFrame = nil
end)

T.run("the button is only there when a recipe is open", function()
  world()
  -- Blizzard's window, roughly: a crafting page with a recipe pane on it.
  local page = Stub.NewMock("Frame", "FBTestCraftingPage")
  page.SchematicForm = Stub.NewMock("Frame", "FBTestSchematicForm")
  _G.ProfessionsFrame = Stub.NewMock("Frame", "ProfessionsFrame")
  _G.ProfessionsFrame.CraftingPage = page
  local selected = nil
  page.SchematicForm.GetRecipeInfo = function() return selected and { recipeID = selected } or nil end

  local made = ns.CraftButton()
  T.truthy(made, "it is built on the crafting page, not on the window")
  selected = 12902
  T.eq(ns.UpdateCraftButton(), true)
  T.eq(made:IsShown(), true)
  selected = nil
  T.eq(ns.UpdateCraftButton(), false)
  T.eq(made:IsShown(), false, "nothing selected, nothing to shop for")
  _G.ProfessionsFrame = nil
end)

T.run("a breakdown is only offered for a profession you have", function()
  world()
  Stub.professions = { "Engineering", "Mining" }
  local plan = ns.CraftingPlan(NET, 1, { ignoreInventory = true, profession = "Engineering" })
  local base = {}
  for _, row in ipairs(plan.base) do base[row.item] = row end
  T.truthy(base[BAR].hint, "an engineer who mines is told that bars are smelted")
  T.eq(base[BAR].hint.profession, "Mining")

  -- The same character without Mining is told nothing about smelting.
  Stub.professions = { "Engineering", "Tailoring" }
  ns.ClearProfessionCache()
  plan = ns.CraftingPlan(NET, 1, { ignoreInventory = true, profession = "Engineering" })
  base = {}
  for _, row in ipairs(plan.base) do base[row.item] = row end
  T.eq(base[BAR].hint, nil, "bars are simply something to go and get")
  T.eq(base[BAR].short, 7, "and the list is otherwise the same")

  -- A client that will not say hides nothing.
  Stub.professions = nil
  ns.ClearProfessionCache()
  plan = ns.CraftingPlan(NET, 1, { ignoreInventory = true, profession = "Engineering" })
  base = {}
  for _, row in ipairs(plan.base) do base[row.item] = row end
  T.truthy(base[BAR].hint)
end)

-- Lee's Gyrochronatom, which is where this went wrong in game: a Gold Power Core comes three to
-- a craft, so wanting two of them with one already in the bag is a single press. The panel used
-- to print the batch in the count column and tell him to make three.
T.run("a batch recipe counts presses, not what falls out", function()
  Stub.reset()
  ns.db = { features = {} }
  local GYRO, IRON, CORE, GOLD = 4389, 3575, 10558, 3577
  Stub.items = { [GYRO] = { name = "Gyrochronatom" }, [IRON] = { name = "Iron Bar" },
                 [CORE] = { name = "Gold Power Core" }, [GOLD] = { name = "Gold Bar" } }
  ns.Crafting = {
    [GYRO] = { 3961, "Gyrochronatom", "Engineering", 170, 1, { { IRON, 1 }, { CORE, 1 } } },
    [CORE] = { 12584, "Gold Power Core", "Engineering", 150, 3, { { GOLD, 1 } } },
  }
  Stub.bags = { [0] = { [1] = { itemID = CORE, stackCount = 1 } } }
  ns.ClearProfessionCache()

  local plan = ns.CraftingPlan(GYRO, 2, { includeBank = true, profession = "Engineering" })
  local step = {}
  for _, s in ipairs(plan.steps) do step[s.item] = s end
  T.eq(step[CORE].need, 2, "two gyros want two cores")
  T.eq(step[CORE].have, 1, "one of them is already in the bag")
  T.eq(step[CORE].crafts, 1, "and one press covers the one he is short of")
  T.eq(step[CORE].produced, 3, "even though three fall out")
  T.eq(ns.CraftStepCount(step[CORE]), "x1", "the count column is the instruction, not the yield")
  T.truthy(ns.CraftStepHint(step[CORE]):find("3 a craft", 1, true), "the batch is explained in the hint")
  T.truthy(ns.CraftStepHint(step[CORE]):find("Engineering 150", 1, true))

  T.eq(ns.CraftStepCount(step[GYRO]), "x2", "the thing he asked for is still two")
  T.eq(ns.CraftStepHint(step[GYRO]), "Engineering 170", "a recipe that makes one says nothing extra")

  -- Nothing to buy: both reagents are already held, which is what his screenshot showed.
  local base = {}
  for _, row in ipairs(plan.base) do base[row.item] = row end
  T.eq(base[GOLD].need, 1); T.eq(base[GOLD].short, 1, "the gold bar is still wanted, he had none")

  -- And three presses when he is short of seven.
  Stub.bags = {}
  ns.ClearProfessionCache()
  plan = ns.CraftingPlan(GYRO, 7, { profession = "Engineering" })
  for _, s in ipairs(plan.steps) do step[s.item] = s end
  T.eq(step[CORE].crafts, 3, "seven cores is three presses")
  T.eq(ns.CraftStepCount(step[CORE]), "x3")
  T.truthy(ns.CraftStepHint(step[CORE]):find("9 in all", 1, true), "and says you end up with nine")
end)

T.finish()
